import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _nikController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  final _kaderCodeController = TextEditingController();

  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _kaderSectionOpen = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Live validation: konfirmasi password ikut dicek ulang saat password
    // utama berubah, jadi pesannya tidak basi.
    _passwordController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    if (_passwordConfirmController.text.isNotEmpty) setState(() {});
  }

  void _setError(String pesan) {
    setState(() {
      _isLoading = false;
      _errorMessage = pesan;
    });
  }

  Future<void> _handleRegister() async {
    FocusScope.of(context).unfocus();
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final result = await _authService.register(
      name: _nameController.text.trim(),
      nik: _nikController.text.trim(),
      password: _passwordController.text,
      passwordConfirmation: _passwordConfirmController.text,
      // Tidak ada pemilih role. Kode kosong -> akun ibu, kode cadres yang
      // cocok -> akun kader. Server yang memutuskan.
      kaderCode: _kaderCodeController.text.trim(),
    );

    if (!mounted) return;

    if (result['success'] == true) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ?? 'Pendaftaran berhasil',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
      return;
    }

    _setError(_firstError(result));
  }

  /// Mengambil pesan paling spesifik dari respons server.
  String _firstError(Map<String, dynamic> result) {
    final errors = result['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
      if (first != null) return first.toString();
    }
    return result['message']?.toString() ?? 'Pendaftaran gagal.';
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _nameController.dispose();
    _nikController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _kaderCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 40,
                    maxWidth: 460,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTopBar(context),
                      const SizedBox(height: 8),
                      const Text(
                        'Daftar Akun Baru',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ibu cukup mengisi nama dan NIK. Kode kader hanya untuk petugas.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 20),
                      AuthCard(child: _buildForm(context)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          tooltip: 'Kembali ke login',
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.18),
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: _resetForm,
          icon: const Icon(Icons.restart_alt, color: Colors.white),
          tooltip: 'Kosongkan form',
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.18),
          ),
        ),
      ],
    );
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _nameController.clear();
    _nikController.clear();
    _passwordController.clear();
    _passwordConfirmController.clear();
    _kaderCodeController.clear();
    setState(() {
      _errorMessage = null;
      _kaderSectionOpen = false;
      _obscurePassword = true;
      _obscureConfirm = true;
    });
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null) ...[
            AuthBanner(
              message: _errorMessage!,
              onDismiss: () => setState(() => _errorMessage = null),
            ),
            const SizedBox(height: 16),
          ],

          _label('Nama Lengkap'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(
              hintText: 'Contoh: Siti Aminah',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return 'Nama tidak boleh kosong';
              if (v.length < 3) return 'Nama terlalu pendek';
              return null;
            },
          ),
          const SizedBox(height: 16),

          _label('NIK'),
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
              if (nik.isEmpty) return 'NIK tidak boleh kosong';
              if (!RegExp(r'^\d{16}$').hasMatch(nik)) {
                return 'NIK harus 16 digit angka';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          _label('Password'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              hintText: 'Minimal 8 karakter',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: _toggle(
                _obscurePassword,
                () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            onChanged: (_) => setState(() {}),
            validator: (value) => (value == null || value.length < 8)
                ? 'Password minimal 8 karakter'
                : null,
          ),
          const SizedBox(height: 10),
          _PasswordStrength(password: _passwordController.text),
          const SizedBox(height: 16),

          _label('Ulangi Password'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _passwordConfirmController,
            obscureText: _obscureConfirm,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            onFieldSubmitted: (_) => _handleRegister(),
            decoration: InputDecoration(
              hintText: 'Ketik ulang password',
              prefixIcon: const Icon(Icons.lock_reset_outlined),
              suffixIcon: _toggle(
                _obscureConfirm,
                () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
            validator: (value) => value != _passwordController.text
                ? 'Konfirmasi password tidak cocok'
                : null,
          ),
          const SizedBox(height: 20),

          _buildKaderSection(),
          const SizedBox(height: 24),

          FilledButton(
            onPressed: _isLoading ? null : _handleRegister,
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text('DAFTAR'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Dengan mendaftar, data Anda dipakai untuk keperluan monitoring '
            'tumbuh kembang balita di posyandu.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _label(String teks) => Text(
    teks,
    style: const TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 13,
      color: AppTheme.ink,
    ),
  );

  Widget _toggle(bool obscured, VoidCallback onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      ),
      tooltip: obscured ? 'Tampilkan' : 'Sembunyikan',
    );
  }

  /// Section kode kader: disembunyikan secara default agar ibu tidak bingung
  /// dan tidak salah mengisi.
  Widget _buildKaderSection() {
    return Container(
      decoration: BoxDecoration(
        color: _kaderSectionOpen ? const Color(0xFFF1F6FD) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _kaderSectionOpen ? AppTheme.primaryLight : AppTheme.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _kaderSectionOpen = !_kaderSectionOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.vpn_key_outlined,
                    size: 20,
                    color: AppTheme.muted,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Saya petugas posyandu',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _kaderSectionOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _kaderSectionOpen
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Masukkan kode yang Anda terima dari coordinator. '
                          'Kosongkan bagian ini bila Anda ibu.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.muted,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _kaderCodeController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            hintText: 'Kode kader',
                            prefixIcon: Icon(
                              Icons.confirmation_number_outlined,
                            ),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Indikator kekuatan password yang berubah realtime.
///
/// Ini murni untuk membantu user memilih password yang lebih baik - aturan
/// minimum (8 karakter) tetap divalidasi di atas lewat validator.
class _PasswordStrength extends StatelessWidget {
  final String password;

  const _PasswordStrength({required this.password});

  @override
  Widget build(BuildContext context) {
    final level = _hitung(password);

    if (password.isEmpty) {
      return const SizedBox(height: 4);
    }

    final (Color warna, String teks) = switch (level) {
      0 => (AppTheme.danger, 'Lemah - gunakan minimal 8 karakter'),
      1 => (const Color(0xFFF9A825), 'Cukup - tambahkan angka atau simbol'),
      2 => (const Color(0xFF558B2F), 'Bagus'),
      _ => (AppTheme.success, 'Kuat'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (int i = 0; i < 4; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == 3 ? 0 : 4),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 5,
                    decoration: BoxDecoration(
                      color: i < level ? warna : AppTheme.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.shield_outlined, size: 14, color: warna),
            const SizedBox(width: 6),
            // Expanded supaya kalimat panjang tidak meluber di layar sempit.
            Expanded(
              child: Text(
                teks,
                style: TextStyle(fontSize: 11.5, color: warna),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Skor 0..3: panjang, variasi huruf, angka, dan simbol.
  int _hitung(String password) {
    if (password.length < 8) return 0;

    var skor = 1;
    if (password.length >= 12) skor++;
    if (RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password)) {
      skor++;
    }
    if (RegExp(r'\d').hasMatch(password) &&
        RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      skor++;
    }
    return skor.clamp(0, 3);
  }
}
