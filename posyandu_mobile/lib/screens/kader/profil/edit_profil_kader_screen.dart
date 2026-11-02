import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '/../../services/auth_service.dart';
import '/../../theme/app_theme.dart';
import '/../../utils/constants.dart';
import 'package:url_launcher/url_launcher.dart';

class EditProfilKaderScreen extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  const EditProfilKaderScreen({super.key, this.initialData});

  @override
  State<EditProfilKaderScreen> createState() => _EditProfilKaderScreenState();
}

class _EditProfilKaderScreenState extends State<EditProfilKaderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = AuthService();
  bool _loading = false;
  bool _loadingData = false;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _instagram = TextEditingController();
  final _facebook = TextEditingController();
  final _address = TextEditingController();

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    if (d != null) {
      _name.text = d['name']?.toString() ?? '';
      _phone.text = d['phone_number']?.toString() ?? '';
      _whatsapp.text = d['whatsapp']?.toString() ?? '';
      _instagram.text = d['instagram']?.toString() ?? '';
      _facebook.text = d['facebook']?.toString() ?? '';
      _address.text = d['address']?.toString() ?? '';
    } else {
      _loadProfile();
    }
  }

  Future<void> _loadProfile() async {
    setState(() => _loadingData = true);
    final p = await _auth.getProfile();
    if (!mounted) return;
    if (p != null) {
      _name.text = p['name']?.toString() ?? '';
      _phone.text = p['phone_number']?.toString() ?? '';
      _whatsapp.text = p['whatsapp']?.toString() ?? '';
      _instagram.text = p['instagram']?.toString() ?? '';
      _facebook.text = p['facebook']?.toString() ?? '';
      _address.text = p['address']?.toString() ?? '';
    }
    setState(() => _loadingData = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final token = await _auth.getToken();
      final body = {
        'name': _name.text.trim(),
        if (_phone.text.trim().isNotEmpty) 'phone_number': _phone.text.trim(),
        if (_whatsapp.text.trim().isNotEmpty) 'whatsapp': _whatsapp.text.trim(),
        if (_instagram.text.trim().isNotEmpty) 'instagram': _instagram.text.trim(),
        if (_facebook.text.trim().isNotEmpty) 'facebook': _facebook.text.trim(),
        if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
      };
      final res = await http.put(
        Uri.parse('${ApiConstants.baseUrl}/profile'),
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil berhasil diperbarui')));
        Navigator.pop(context, true);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal memperbarui profil')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal memperbarui profil')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profil')),
      body: _loadingData
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Nama Lengkap'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Nama wajib diisi' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    decoration: const InputDecoration(labelText: 'No. HP (opsional)'),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _whatsapp,
                    decoration: const InputDecoration(labelText: 'WhatsApp (opsional)', hintText: 'contoh: 628xxx atau link wa.me'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _instagram,
                    decoration: const InputDecoration(labelText: 'Instagram (opsional)', hintText: 'username atau link'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _facebook,
                    decoration: const InputDecoration(labelText: 'Facebook (opsional)', hintText: 'username atau link'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _address,
                    decoration: const InputDecoration(labelText: 'Alamat (opsional)'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _loading ? null : _save,
                    child: Text(_loading ? 'Menyimpan...' : 'Simpan'),
                  )
                ],
              ),
            ),
    );
  }
}
