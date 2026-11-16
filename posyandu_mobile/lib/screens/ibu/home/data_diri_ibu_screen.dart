import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '/../../services/auth_service.dart';
import '/../../utils/constants.dart';

class DataDiriIbuScreen extends StatefulWidget {
  const DataDiriIbuScreen({super.key});

  @override
  State<DataDiriIbuScreen> createState() => _DataDiriIbuScreenState();
}

class _DataDiriIbuScreenState extends State<DataDiriIbuScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = AuthService();
  bool _loading = true;
  bool _saving = false;
  bool _editMode = false;

  Map<String, dynamic> _data = {};

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _instagram = TextEditingController();
  final _facebook = TextEditingController();
  final _address = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final p = await _auth.getProfile();
    if (!mounted) return;
    if (p != null) {
      _data = Map<String, dynamic>.from(p);
      _name.text = _data['name']?.toString() ?? '';
      _phone.text = _data['phone_number']?.toString() ?? '';
      _whatsapp.text = _data['whatsapp']?.toString() ?? '';
      _instagram.text = _data['instagram']?.toString() ?? '';
      _facebook.text = _data['facebook']?.toString() ?? '';
      _address.text = _data['address']?.toString() ?? '';
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
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
        final decoded = jsonDecode(res.body);
        if (decoded['data'] is Map) {
          _data = Map<String, dynamic>.from(decoded['data']);
        } else {
          await _load();
        }
        setState(() => _editMode = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data diri berhasil diperbarui')));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal memperbarui data diri')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal memperbarui data diri')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _val(String? v) {
    if (v == null || v.toString().trim().isEmpty) return 'Belum diisi';
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.pink[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.pink[400],
        title: const Text('Data Diri', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (!_loading && !_editMode)
            TextButton.icon(
              onPressed: () => setState(() => _editMode = true),
              icon: const Icon(Icons.edit, color: Colors.white, size: 18),
              label: const Text('Edit', style: TextStyle(color: Colors.white)),
            ),
          if (_editMode)
            TextButton(
              onPressed: _saving ? null : () => setState(() => _editMode = false),
              child: const Text('Batal', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.pink))
          : _editMode
              ? _buildEdit()
              : _buildView(),
    );
  }

  Widget _buildView() {
    return RefreshIndicator(
      color: Colors.pink,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Data Pribadi'),
          _card([
            _row('Nama Lengkap', _val(_data['name'])),
            _divider(),
            _row('No. HP', _val(_data['phone_number'])),
            _divider(),
            _row('Alamat', _val(_data['address'])),
          ]),
          const SizedBox(height: 16),
          _sectionTitle('Sosial Media'),
          _card([
            _row('WhatsApp', _val(_data['whatsapp'])),
            _divider(),
            _row('Instagram', _val(_data['instagram'])),
            _divider(),
            _row('Facebook', _val(_data['facebook'])),
          ]),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.pink[400]),
            onPressed: () => setState(() => _editMode = true),
            icon: const Icon(Icons.edit),
            label: const Text('Edit Data Diri & Sosial Media'),
          )
        ],
      ),
    );
  }

  Widget _buildEdit() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Data Pribadi'),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Nama Lengkap *'),
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
                    controller: _address,
                    decoration: const InputDecoration(labelText: 'Alamat (opsional)'),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle('Sosial Media (Opsional)'),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextFormField(
                    controller: _whatsapp,
                    decoration: const InputDecoration(labelText: 'WhatsApp', hintText: 'Nomor/Link wa.me'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _instagram,
                    decoration: const InputDecoration(labelText: 'Instagram', hintText: 'Username atau link'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _facebook,
                    decoration: const InputDecoration(labelText: 'Facebook', hintText: 'Username atau link'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.pink[400]),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Menyimpan...' : 'Simpan'),
          )
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(children: children),
    );
  }

  Widget _divider() => Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2));

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}
