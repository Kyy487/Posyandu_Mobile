import 'package:flutter/material.dart';

import '../../models/child.dart';
import '../../services/child_service.dart';

/// Menampilkan form tambah anak dan mengirimnya ke `POST /api/children`.
///
/// Mengembalikan [Child] bila berhasil, atau `null` bila user batal,
/// mengisi form tidak valid, atau server menolak.
Future<Child?> showTambahAnakDialog(
  BuildContext context,
  ChildService service,
) {
  return showDialog<Child>(
    context: context,
    builder: (context) => _TambahAnakDialog(service: service),
  );
}

class _TambahAnakDialog extends StatefulWidget {
  final ChildService service;

  const _TambahAnakDialog({required this.service});

  @override
  State<_TambahAnakDialog> createState() => _TambahAnakDialogState();
}

class _TambahAnakDialogState extends State<_TambahAnakDialog> {
  final _formKey = GlobalKey<FormState>();
  final _namaController = TextEditingController();
  final _nikController = TextEditingController();
  final _tanggalController = TextEditingController();

  String? _gender = 'L';
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _namaController.dispose();
    _nikController.dispose();
    _tanggalController.dispose();
    super.dispose();
  }

  Future<void> _pickTanggalLahir() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      helpText: 'Pilih tanggal lahir anak',
    );
    if (picked == null) return;

    // Format WAJIB YYYY-MM-DD (ISO 8601). PostgreSQL menolak format lain
    // ("26-09-2026" -> SQLSTATE 22008), dan backend memvalidasi dengan
    // date_format:Y-m-d. Tampilannya juga memakai format yang sama supaya
    // yang terlihat persis yang dikirim.
    _tanggalController.text =
        '${picked.year}-${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final hasil = await widget.service.addChild(
      name: _namaController.text.trim(),
      dateOfBirth: _tanggalController.text.trim(),
      gender: _gender!,
      nik: _nikController.text.trim(),
    );

    if (!mounted) return;

    if (hasil['success'] == true && hasil['data'] is Child) {
      Navigator.of(context).pop(hasil['data'] as Child);
      return;
    }

    setState(() {
      _isSubmitting = false;
      _errorMessage =
          hasil['message']?.toString() ?? 'Gagal menyimpan data anak.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Tambah Data Anak',
        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.pink),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _namaController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama Anak',
                  hintText: 'Contoh: Budi Santoso',
                  prefixIcon: Icon(Icons.child_care),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Nama anak wajib diisi';
                  }
                  if (value.trim().length < 3) {
                    return 'Nama terlalu pendek';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tanggalController,
                readOnly: true,
                onTap: _pickTanggalLahir,
                decoration: const InputDecoration(
                  labelText: 'Tanggal Lahir',
                  hintText: 'YYYY-MM-DD',
                  prefixIcon: Icon(Icons.cake_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Tanggal lahir wajib diisi';
                  }
                  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value.trim())) {
                    return 'Format harus YYYY-MM-DD';
                  }
                  if (DateTime.tryParse(value.trim()) == null) {
                    return 'Tanggal tidak valid';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nikController,
                keyboardType: TextInputType.number,
                maxLength: 16,
                decoration: const InputDecoration(
                  labelText: 'NIK (opsional)',
                  hintText: '16 digit, opsional',
                  prefixIcon: Icon(Icons.badge_outlined),
                  counterText: '',
                ),
                validator: (value) {
                  final nik = value?.trim() ?? '';
                  if (nik.isEmpty) return null;
                  if (!RegExp(r'^\d{16}$').hasMatch(nik)) {
                    return 'NIK harus 16 digit angka';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                decoration: const InputDecoration(
                  labelText: 'Jenis Kelamin',
                  prefixIcon: Icon(Icons.wc),
                ),
                items: const [
                  DropdownMenuItem(value: 'L', child: Text('Laki-laki')),
                  DropdownMenuItem(value: 'P', child: Text('Perempuan')),
                ],
                onChanged: (value) => setState(() => _gender = value),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _simpan,
          style: FilledButton.styleFrom(backgroundColor: Colors.pink[400]),
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Simpan'),
        ),
      ],
    );
  }
}
