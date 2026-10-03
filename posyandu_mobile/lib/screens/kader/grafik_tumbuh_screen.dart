import 'package:flutter/material.dart';

import '../../widgets/growth_chart_view.dart';

/// Grafik tumbuh kembang untuk Kader. Tetap read-only.
///
/// Kader melihat data yang sama persis dengan Ibu - grafik, pita WHO, z-score,
/// dan status gizi dibaca dari endpoint dan model yang sama. Yang berbeda hanya
/// warnanya (biru, sesuai layar Kader lain) dan tempat pembukaannya: dari
/// `detail_anak_screen.dart`, bukan dari dashboard.
///
/// Kader **tidak** mencatat penimbangan dari layar ini. Inputnya tetap lewat
/// `input_penimbangan_screen.dart`, supaya tidak ada dua jalan menulis ke
/// `measurements`.
///
/// Layar ini juga tidak memakai cache `KaderService` yang sudah dimuat di
/// `detail_anak_screen.dart`. Kalau memakainya, grafik akan menampilkan angka
/// yang berbeda dari kartu "Penimbangan Terakhir" tepat di sebelahnya setelah
/// kader mencatat penimbangan baru - jadi layar ini selalu ambil sendiri lewat
/// `GrowthChartService`, sama seperti layar Ibu.
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
      palette: GrowthChartPalette.kader,
    );
  }
}
