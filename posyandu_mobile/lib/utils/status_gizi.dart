import 'package:flutter/material.dart';

/// Warna + ikon untuk status gizi hasil hitungan Z-Score.
///
/// String yang dipetakan di sini adalah nilai yang benar-benar ditulis trigger
/// `measurements` pada tabel (lihat migration
/// `2026_09_26_010000_create_who_wfa_standards_and_fix_zscore_trigger.php`):
/// `Gizi Buruk`, `Gizi Kurang`, `Risiko Gizi Lebih`, dan `Normal`.
///
/// Fungsi ini menggantikan tiga pemetaan yang sebelumnya berdiri sendiri di
/// `detail_anak_screen.dart`, `dashboard_ibu_screen.dart`, dan
/// `growth_chart_view.dart`. Akibatnya "Risiko Gizi Lebih" tampil oranye tua di
/// semua layar; sebelumnya warna itu berbeda antara detail Kader dan dua layar
/// Ibu, sehingga kader dan ibu membandingkan layar yang berbeda untuk anak yang
/// sama.
///
/// Pencocokan dilakukan persis pada daftar nilai di atas, bukan
/// `status.contains(...)`. `contains` rapuh di sini: 'Risiko Gizi Lebih'
/// mengandung 'Risiko', jadi urutan percabangan diam-diam menentukan warnanya.
({Color warna, IconData ikon}) warnaStatusGizi(String? status) {
  final key = status?.trim().toLowerCase();

  return switch (key) {
    'gizi buruk' => (warna: Colors.red, ikon: Icons.warning_amber),
    // 'Stunting' tidak lagi ditulis trigger (terminologiWHO sekarang memakai
    // 'Gizi Buruk'), tapi baris lama di database masih memegangnya.
    'stunting' => (warna: Colors.red, ikon: Icons.warning_amber),
    'gizi kurang' => (warna: Colors.orange, ikon: Icons.info_outline),
    'risiko gizi lebih' => (warna: Colors.deepOrange, ikon: Icons.trending_up),
    'gizi lebih' => (warna: Colors.deepOrange, ikon: Icons.trending_up),
    'normal' => (warna: Colors.green, ikon: Icons.check_circle_outline),
    _ => (warna: Colors.grey, ikon: Icons.help_outline),
  };
}
