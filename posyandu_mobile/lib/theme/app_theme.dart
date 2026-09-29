import 'package:flutter/material.dart';

/// Warna & komponen bersama untuk layar autentikasi.
///
/// Nilai warna sengaja memakai hue yang sama dengan dashboard Kader
/// (`Colors.blue[800]`) supaya perpindahan dari login ke aplikasi terasa
/// menyambung, sementara dashboard Ibu tetap bebas memakai pink-nya sendiri.
class AppTheme {
  const AppTheme._();

  static const Color primary = Color(0xFF1565C0);
  static const Color primaryDark = Color(0xFF0D47A1);
  static const Color primaryLight = Color(0xFF42A5F5);
  static const Color surface = Color(0xFFF6F8FB);
  static const Color ink = Color(0xFF1A2233);
  static const Color muted = Color(0xFF6B7A90);
  static const Color danger = Color(0xFFD32F2F);
  static const Color success = Color(0xFF2E7D32);
  static const Color border = Color(0xFFDCE3ED);

  /// Latar atas layar auth: gradien lembut biru.
  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDark, primary, primaryLight],
  );

  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        error: danger,
      ),
      scaffoldBackgroundColor: surface,
    );

    return base.copyWith(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: _border(Colors.white),
        enabledBorder: _border(Colors.white),
        focusedBorder: _border(primary, width: 2),
        errorBorder: _border(danger),
        focusedErrorBorder: _border(danger, width: 2),
        labelStyle: const TextStyle(color: muted),
        floatingLabelStyle: const TextStyle(color: primary),
        prefixIconColor: muted,
        suffixIconColor: muted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static OutlineInputBorder _border(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

/// Kartu putih dengan bayangan lembut - dipakai di seluruh layar auth.
class AuthCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const AuthCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Banner pesan error/sukses di dalam layar (bukan Snackbar).
///
/// Snackbar mudah hilang sebelum dibaca, sedangkan banner tetap terlihat sampai
/// user menutupnya atau memperbaiki isinya.
class AuthBanner extends StatelessWidget {
  final String message;
  final bool isError;
  final VoidCallback? onDismiss;

  const AuthBanner({
    super.key,
    required this.message,
    this.isError = true,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppTheme.danger : AppTheme.success;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 13, height: 1.35),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: Icon(Icons.close, color: color, size: 18),
              visualDensity: VisualDensity.compact,
              tooltip: 'Tutup pesan',
            ),
        ],
      ),
    );
  }
}
