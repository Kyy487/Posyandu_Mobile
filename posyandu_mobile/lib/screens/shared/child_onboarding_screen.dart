import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/../models/consent.dart';
import '/../services/auth_service.dart';
import '/../services/child_service.dart';
import '/../theme/app_theme.dart';
import '/screens/ibu/home/dashboard_ibu_screen.dart';
import 'login_screen.dart';

class ChildOnboardingScreen extends StatefulWidget {
  const ChildOnboardingScreen({super.key});

  @override
  State<ChildOnboardingScreen> createState() => _ChildOnboardingScreenState();
}

class _ChildOnboardingScreenState extends State<ChildOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nikController = TextEditingController();
  final _nameController = TextEditingController();
  final _birthPlaceController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _birthOrderController = TextEditingController();
  final _birthWeightController = TextEditingController();
  final _birthLengthController = TextEditingController();
  final _headCircumferenceController = TextEditingController();
  final _bukuKiaController = TextEditingController();

  final ChildService _childService = ChildService();

  DateTime? _birthDate;
  String _gender = 'L';
  String _birthStatus = 'normal';
  bool _setuju = false;
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nikController.dispose();
    _nameController.dispose();
    _birthPlaceController.dispose();
    _birthDateController.dispose();
    _birthOrderController.dispose();
    _birthWeightController.dispose();
    _birthLengthController.dispose();
    _headCircumferenceController.dispose();
    _bukuKiaController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      helpText: 'Pilih tanggal lahir anak',
    );

    if (picked == null) return;

    setState(() {
      _birthDate = picked;
      _birthDateController.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    });
  }

  double? _parseDecimal(String text) {
    return double.tryParse(text.trim().replaceAll(',', '.'));
  }

  Future<void> _logout() async {
    final navigator = Navigator.of(context);
    await AuthService().logout();
    if (!mounted) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  String _firstError(Map<String, dynamic> result) {
    final errors = result['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
      if (first != null) return first.toString();
    }
    return result['message']?.toString() ?? 'Gagal menyimpan data anak.';
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    if (!_setuju) {
      setState(() {
        _errorMessage =
            'Centang persetujuan pemrosesan data sebelum menyimpan.';
      });
      return;
    }

    final birthOrder = int.tryParse(_birthOrderController.text.trim());
    final birthWeight = _parseDecimal(_birthWeightController.text);
    final birthLength = _parseDecimal(_birthLengthController.text);
    final headCircumference = _parseDecimal(_headCircumferenceController.text);

    if (birthOrder == null ||
        birthWeight == null ||
        birthLength == null ||
        headCircumference == null ||
        _birthDate == null) {
      setState(() => _errorMessage = 'Lengkapi data kelahiran anak.');
      return;
    }

    setState(() => _loading = true);

    final result = await _childService.completeOnboarding(
      nik: _nikController.text.trim(),
      name: _nameController.text.trim(),
      placeOfBirth: _birthPlaceController.text.trim(),
      dateOfBirth: _birthDateController.text.trim(),
      gender: _gender,
      birthOrder: birthOrder,
      birthWeight: birthWeight,
      birthLength: birthLength,
      birthHeadCircumference: headCircumference,
      birthStatus: _birthStatus,
      bukuKiaId: _bukuKiaController.text.trim(),
      consentType: ConsentTipe.dataProcessing,
      consentDocumentVersion: kConsentDocumentVersion,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DashboardIbuScreen()),
        (route) => false,
      );
      return;
    }

    if (result['status'] == 401) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
      return;
    }

    setState(() {
      _loading = false;
      _errorMessage = _firstError(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lengkapi Data Anak'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Keluar',
            onPressed: _loading ? null : _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F6FD),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.primaryLight),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.child_care, color: AppTheme.primary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Akun Anda sudah disetujui. Lengkapi data satu anak '
                      'untuk mengaktifkan dashboard tumbuh kembang.',
                      style: TextStyle(fontSize: 12.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEF9A9A)),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: AppTheme.danger,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            _label('NIK Anak'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nikController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(16),
              ],
              decoration: InputDecoration(
                hintText: '16 digit angka',
                prefixIcon: const Icon(Icons.badge_outlined),
                suffixText: '${_nikController.text.length}/16',
                suffixStyle: TextStyle(
                  color: _nikController.text.length == 16
                      ? AppTheme.success
                      : AppTheme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onChanged: (_) => setState(() {}),
              validator: (value) {
                final nik = value?.trim() ?? '';
                if (nik.isEmpty) return 'NIK anak wajib diisi';
                if (!RegExp(r'^\d{16}$').hasMatch(nik)) {
                  return 'NIK harus 16 digit angka';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _label('Nama Anak'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Contoh: Budi Santoso',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (value) {
                final name = value?.trim() ?? '';
                if (name.isEmpty) return 'Nama anak wajib diisi';
                if (name.length < 3) return 'Nama terlalu pendek';
                return null;
              },
            ),
            const SizedBox(height: 16),
            _label('Tempat Lahir'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _birthPlaceController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Contoh: Bandung',
                prefixIcon: Icon(Icons.location_city_outlined),
              ),
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? 'Tempat lahir wajib diisi'
                  : null,
            ),
            const SizedBox(height: 16),
            _label('Tanggal Lahir'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _birthDateController,
              readOnly: true,
              onTap: _loading ? null : _pickBirthDate,
              decoration: const InputDecoration(
                hintText: 'YYYY-MM-DD',
                prefixIcon: Icon(Icons.cake_outlined),
                suffixIcon: Icon(Icons.calendar_today_outlined),
              ),
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? 'Tanggal lahir wajib diisi'
                  : null,
            ),
            const SizedBox(height: 16),
            _label('Jenis Kelamin'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.wc)),
              items: const [
                DropdownMenuItem(value: 'L', child: Text('Laki-laki')),
                DropdownMenuItem(value: 'P', child: Text('Perempuan')),
              ],
              onChanged: _loading
                  ? null
                  : (value) => setState(() => _gender = value ?? 'L'),
            ),
            const SizedBox(height: 16),
            _label('Urutan Kelahiran'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _birthOrderController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              decoration: const InputDecoration(
                hintText: 'Contoh: 1',
                prefixIcon: Icon(Icons.format_list_numbered),
              ),
              validator: (value) {
                final order = int.tryParse(value?.trim() ?? '');
                if (order == null) return 'Urutan kelahiran wajib diisi';
                if (order < 1 || order > 20) {
                  return 'Urutan kelahiran harus 1 sampai 20';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _label('Berat Lahir (kg)'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _birthWeightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                hintText: 'Contoh: 3.2',
                prefixIcon: Icon(Icons.monitor_weight_outlined),
              ),
              validator: (value) {
                final weight = _parseDecimal(value ?? '');
                if (weight == null) return 'Berat lahir wajib diisi';
                if (weight < 0.5 || weight > 10) {
                  return 'Berat lahir harus 0,5 sampai 10 kg';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _label('Panjang Lahir (cm)'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _birthLengthController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                hintText: 'Contoh: 49.5',
                prefixIcon: Icon(Icons.straighten),
              ),
              validator: (value) {
                final length = _parseDecimal(value ?? '');
                if (length == null) return 'Panjang lahir wajib diisi';
                if (length < 20 || length > 70) {
                  return 'Panjang lahir harus 20 sampai 70 cm';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _label('Lingkar Kepala Lahir (cm)'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _headCircumferenceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                hintText: 'Contoh: 34',
                prefixIcon: Icon(Icons.circle_outlined),
              ),
              validator: (value) {
                final circumference = _parseDecimal(value ?? '');
                if (circumference == null) {
                  return 'Lingkar kepala wajib diisi';
                }
                if (circumference < 20 || circumference > 60) {
                  return 'Lingkar kepala harus 20 sampai 60 cm';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _label('Kondisi Saat Lahir'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _birthStatus,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.health_and_safety_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'normal', child: Text('Normal')),
                DropdownMenuItem(value: 'premature', child: Text('Prematur')),
              ],
              onChanged: _loading
                  ? null
                  : (value) => setState(() => _birthStatus = value ?? 'normal'),
            ),
            const SizedBox(height: 16),
            _label('ID Buku KIA (opsional)'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _bukuKiaController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: 'Nomor pada buku KIA',
                prefixIcon: Icon(Icons.menu_book_outlined),
              ),
              validator: (value) {
                final id = value?.trim() ?? '';
                if (id.isEmpty) return null;
                if (id.length > 50) return 'ID Buku KIA maksimal 50 karakter';
                return null;
              },
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _setuju,
              onChanged: _loading
                  ? null
                  : (value) => setState(() => _setuju = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Saya setuju data anak diproses',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Data dipakai untuk pencatatan tumbuh kembang dan layanan '
                'Posyandu. Persetujuan bisa dicabut kapan saja.',
                style: TextStyle(fontSize: 11),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('SIMPAN DATA ANAK'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 13,
      color: AppTheme.ink,
    ),
  );
}
