import 'package:flutter/material.dart';

import '../../widgets/growth_chart_view.dart';

/// Grafik tumbuh kembang untuk orang tua. Sepenuhnya read-only.
///
/// Layar ini menampilkan dua hal sekaligus: seluruh riwayat penimbangan anak
/// (garis BB dan garis TB) dan pita acuan WHO BB/U. Angka z-score dan status
/// gizi di bawah grafik dibaca apa adanya dari server - layar ini tidak
/// menghitung apa pun, karena angka itu sudah dihitung trigger PostgreSQL saat
/// penimbangan dicatat.
///
/// Seluruh isi layannya ada di [GrowthChartView] dan dipakai bersama dengan
/// layar Kader; perbedaannya hanya warna. Bentuknya dikunci di
/// `docs/RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md` bagian 8. Kalau perlu berubah,
/// dokumennya yang diubah lebih dulu.
class GrafikTumbuhScreen extends StatelessWidget {
  final String childId;
  final String childName;

  const GrafikTumbuhScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  Widget build(BuildContext context) {
    return GrowthChartView(
      childId: childId,
      childName: childName,
      palette: GrowthChartPalette.ibu,
    );
  }
}
