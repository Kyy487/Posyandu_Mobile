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

  // --- Palet Dashboard Kader (mengikuti mockup docs/design/kader) ---
  //
  // Dipasang lewat [kader] dan di-scope ke subtree Dashboard Kader saja,
  // supaya layar auth/Ibu yang biru tidak ikut berubah pada tahap ini.
  static const Color brand = Color(0xFF0E7C7B);
  static const Color brandDark = Color(0xFF0B6B69);
  static const Color brandLight = Color(0xFF2FA9A3);
  static const Color brandSurface = Color(0xFFF2F6F5);
  static const Color accent = Color(0xFFF2845C);
  static const Color navBar = Color(0xFF12302F);

  /// Latar atas layar auth: gradien lembut biru.
  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDark, primary, primaryLight],
  );

  /// Header Dashboard Kader: gradien teal lembut.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandDark, brand, brandLight],
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
      inputDecorationTheme: _inputTheme(primary),
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

  /// Tema khusus Dashboard Kader (teal).
  ///
  /// Dipasang lewat `Theme(data: AppTheme.kader())` di bawah Dashboard Kader
  /// saja, jadi layar auth dan dashboard Ibu yang masih biru tidak terpengaruh.
  static ThemeData kader() {
    return build().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: brand,
        primary: brand,
        error: danger,
      ),
      scaffoldBackgroundColor: brandSurface,
      inputDecorationTheme: _inputTheme(brand),
      appBarTheme: const AppBarTheme(
        backgroundColor: brandSurface,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: brand),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: brand),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
    );
  }

  /// Dekorasi input dengan warna fokus sesuai [focus], dipakai bersama oleh
  /// tema auth (biru) dan dashboard/login Kader (teal).
  static InputDecorationTheme _inputTheme(Color focus) {
    return InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: _border(Colors.white),
      enabledBorder: _border(Colors.white),
      focusedBorder: _border(focus, width: 2),
      errorBorder: _border(danger),
      focusedErrorBorder: _border(danger, width: 2),
      labelStyle: const TextStyle(color: muted),
      floatingLabelStyle: TextStyle(color: focus),
      prefixIconColor: muted,
      suffixIconColor: muted,
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

/// Kartu putih dengan sudut membulat dan bayangan lembut.
///
/// Dipakai Dashboard Kader supaya kotak-kotaknya seragam, alih-alih tiap
/// layar menulis `BoxDecoration` sendiri dengan radius dan bayangan berbeda.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isi = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return Padding(padding: margin, child: isi);

    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: isi,
        ),
      ),
    );
  }
}

/// Judul seksi dengan aksi opsional di sisi kanan (mis. "Semua >").
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(actionLabel!, style: const TextStyle(fontSize: 13)),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}
