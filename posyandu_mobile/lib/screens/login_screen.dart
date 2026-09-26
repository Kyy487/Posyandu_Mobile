import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'ibu/dashboard_ibu_screen.dart';
import 'kader/kader_dashboard_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nikController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberNik = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pulihkanNik();
  }

  /// Mengisi NIK terakhir bila user pernah mencentang "Ingat NIK".
  Future<void> _pulihkanNik() async {
    final nik = await _authService.getRememberedNik();
    if (nik == null || nik.isEmpty) return;
    if (!mounted) return;
    setState(() => _nikController.text = nik);
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final nik = _nikController.text.trim();
    final result = await _authService.login(nik, _passwordController.text);

    if (!mounted) return;

    if (result['success'] == true) {
      await _authService.saveRememberedNik(_rememberNik ? nik : '');
      if (!mounted) return;
      _gotoDashboard(result);
      return;
    }

    setState(() {
      _isLoading = false;
      _errorMessage = result['message']?.toString() ?? 'Login gagal. Coba lagi.';
    });
  }

  /// Membaca role dari respons lalu mengarahkan ke dashboard yang sesuai.
  void _gotoDashboard(Map<String, dynamic> result) {
    final data = result['data'];
    final user = data is Map ? data['user'] : null;
    final role = (user is Map ? user['role'] : data is Map ? data['role'] : null)
        ?.toString()
        .trim()
        .toLowerCase();

    final Widget? tujuan = switch (role) {
      'ibu' => const DashboardIbuScreen(),
      'kader' => const DashboardKaderScreen(),
      _ => null,
    };

    if (tujuan == null) {
      // Role tidak dikenal: jangan tinggalkan user di layar login.
      setState(() {
        _isLoading = false;
        _errorMessage = 'Role akun tidak dikenali. Hubungi coordinator posyandu.';
      });
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, animation, _) => FadeTransition(
          opacity: animation,
          child: tujuan,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
      (route) => false,
    );
  }

  void _bukaRegister() {
    if (_isLoading) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, animation, _) => FadeTransition(
          opacity: animation,
          child: const RegisterScreen(),
        ),
        transitionsBuilder: (_, animation, _, child) => SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: FadeTransition(opacity: animation, child: child),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nikController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.headerGradient,
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                child: ConstrainedBox(
                  // Di tablet/layar lebar, form tidak melebar penuh supaya
                  // tetap terbaca dan tidak terlihat kosong melompong.
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 56,
                    maxWidth: 460,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _BrandHeader(),
                      const SizedBox(height: 24),
                      AuthCard(child: _buildForm(context)),
                      const SizedBox(height: 20),
                      _buildFooter(context),
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

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Masuk ke Akun',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Gunakan NIK dan password yang terdaftar di posyandu.',
            style: TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
          const SizedBox(height: 20),

          if (_errorMessage != null) ...[
            AuthBanner(
              message: _errorMessage!,
              onDismiss: () => setState(() => _errorMessage = null),
            ),
            const SizedBox(height: 16),
          ],

          // NIK - hanya angka, maksimal 16 digit sesuai aturan backend.
          TextFormField(
            controller: _nikController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(16),
            ],
            decoration: InputDecoration(
              labelText: 'NIK',
              hintText: '16 digit angka',
              prefixIcon: const Icon(Icons.badge_outlined),
              // Penghitung digit memberi umpan balik langsung saat mengetik.
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

          // PASSWORD - bisa ditampilkan untuk checking typo.
          TextFormField(
            controller: _passwordController,
            focusNode: _passwordFocus,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) => _handleLogin(),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                tooltip: _obscurePassword
                    ? 'Tampilkan password'
                    : 'Sembunyikan password',
              ),
            ),
            validator: (value) =>
                (value == null || value.isEmpty) ? 'Password tidak boleh kosong' : null,
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              SizedBox(
                height: 24,
                width: 24,
                child: Checkbox(
                  value: _rememberNik,
                  onChanged: (v) => setState(() => _rememberNik = v ?? false),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Ingat NIK di perangkat ini',
                  style: TextStyle(color: AppTheme.muted, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          FilledButton(
            // Tombol tetap occupying tempatnya saat loading supaya layout
            // tidak melompat.
            onPressed: _isLoading ? null : _handleLogin,
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text('MASUK'),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Belum punya akun?',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            TextButton(
              onPressed: _bukaRegister,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Daftar di sini',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Smart Posyandu - Pemantauan tumbuh kembang balita',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ],
    );
  }
}

/// Logo + judul di bagian atas kartu.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.45),
              width: 2,
            ),
          ),
          child: const Icon(
            Icons.favorite_rounded,
            color: Colors.white,
            size: 38,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Smart Posyandu',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Selamat datang kembali',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
