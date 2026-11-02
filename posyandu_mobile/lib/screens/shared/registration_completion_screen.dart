import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '/../services/auth_service.dart';
import '/../theme/app_theme.dart';
import '/../utils/constants.dart';
import 'pending_approval_screen.dart';

class RegistrationCompletionScreen extends StatefulWidget {
  const RegistrationCompletionScreen({super.key});

  @override
  State<RegistrationCompletionScreen> createState() => _RegistrationCompletionScreenState();
}

class _RegistrationCompletionScreenState extends State<RegistrationCompletionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _birthPlaceController = TextEditingController();
  final _addressController = TextEditingController();
  DateTime? _birthDate;
  String _gender = 'P';
  File? _file;
  String _verificationType = 'kk';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final token = await AuthService().getToken();
    final res = await http.get(
      Uri.parse('${ApiConstants.baseUrl}/registration/status'),
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer ${token ?? ''}'},
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body)['data'];
      setState(() {
        _nameController.text = data['name'] ?? '';
        _phoneController.text = data['phone_number'] ?? '';
        _birthPlaceController.text = data['place_of_birth'] ?? '';
        _addressController.text = data['address'] ?? '';
        _gender = data['gender'] ?? 'P';
        if (data['date_of_birth'] != null) {
          _birthDate = DateTime.tryParse(data['date_of_birth']);
        }
      });
    }
  }

  Future<void> _pickFile() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      setState(() => _file = File(picked.path));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alamat wajib diisi')));
      return;
    }
    setState(() => _loading = true);
    final token = await AuthService().getToken();
    var request = http.MultipartRequest('POST', Uri.parse('${ApiConstants.baseUrl}/registration/complete'));
    request.headers['Authorization'] = 'Bearer ${token ?? ''}';
    request.headers['Accept'] = 'application/json';
    request.fields['name'] = _nameController.text.trim();
    request.fields['phone_number'] = _phoneController.text.trim();
    if (_birthPlaceController.text.trim().isNotEmpty) request.fields['place_of_birth'] = _birthPlaceController.text.trim();
    if (_birthDate != null) request.fields['date_of_birth'] = _birthDate!.toIso8601String().substring(0, 10);
    request.fields['gender'] = _gender;
    request.fields['address'] = _addressController.text.trim();
    request.fields['verification_type'] = _verificationType;
    if (_file != null) {
      request.files.add(await http.MultipartFile.fromPath('verification_file', _file!.path));
    }
    request.fields['_method'] = 'PUT';
    final res = await request.send();
    final body = await res.stream.bytesToString();
    if (res.statusCode == 200) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PendingApprovalScreen()),
        (route) => false,
      );
      return;
    }
    setState(() => _loading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(jsonDecode(body)['message'] ?? 'Gagal')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lengkapi Data Pendaftaran')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: 'Nama Lengkap'), validator: (v) => v!.isEmpty ? 'Wajib' : null),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'No. HP'),
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]')), LengthLimitingTextInputFormatter(16)],
            ),
          TextFormField(controller: _birthPlaceController, decoration: const InputDecoration(labelText: 'Tempat Lahir')),
          ListTile(
            title: Text(_birthDate == null ? 'Tanggal Lahir' : _birthDate!.toIso8601String().substring(0, 10)),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final d = await showDatePicker(context: context, firstDate: DateTime(1950), lastDate: DateTime.now(), initialDate: _birthDate ?? DateTime(1990));
              if (d != null) setState(() => _birthDate = d);
            },
          ),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              items: const [DropdownMenuItem(value: 'L', child: Text('Laki-laki')), DropdownMenuItem(value: 'P', child: Text('Perempuan'))],
              onChanged: (v) => setState(() => _gender = v!),
              decoration: const InputDecoration(labelText: 'Jenis Kelamin'),
            ),
            TextFormField(controller: _addressController, decoration: const InputDecoration(labelText: 'Alamat Lengkap'), maxLines: 3, validator: (v) => v!.isEmpty ? 'Wajib' : null),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _verificationType,
              items: const [
                DropdownMenuItem(value: 'kk', child: Text('Kartu Keluarga (KK)')),
                DropdownMenuItem(value: 'self_photo', child: Text('Foto Diri')),
                DropdownMenuItem(value: 'other', child: Text('Lainnya')),
              ],
              onChanged: (v) => setState(() => _verificationType = v!),
              decoration: const InputDecoration(labelText: 'Jenis Bukti'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _pickFile, icon: const Icon(Icons.upload_file), label: Text(_file == null ? 'Upload Bukti' : 'File dipilih')),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
              child: Text(_loading ? 'Mengirim...' : 'Kirim untuk Persetujuan'),
            ),
          ],
        ),
      ),
    );
  }
}
