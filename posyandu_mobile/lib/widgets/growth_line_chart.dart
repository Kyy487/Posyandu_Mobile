import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/growth_chart.dart';

/// Metrik yang sedang ditebalkan di grafik.
///
/// Grafik selalu menggambar BB **dan** TB di satu kanvas, jadi enum ini bukan
/// pemilih data - hanya memilih garis mana yang ditebalkan dan_series mana yang
/// dipakai untuk tooltip.
enum GrowthMetric { weight, height }

/// Grafik tumbuh kembang: pita WHO BB/U + garis BB + garis TB.
///
/// Wrapper tipis di atas `fl_chart`. Semua keputusan bentuk grafik sudah ditulis
/// di `docs/RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md` bagian 8; widget ini hanya
/// menerjemahkannya jadi `LineChart`. Kalau bentuk visualnya perlu berubah,
/// dokumennya yang diubah lebih dulu.
///
/// Empat keputusan yang tidak boleh dibalik di sini:
///
///  1. **Sumbu x adalah umur dalam tahun, bukan tanggal.** Pita WHO diindeks
///     umur, jadi sumbu tanggal tidak akan bisa disejajarkan dengan pita.
///     Umurnya diambil dari `age_in_months` milik server, tidak dihitung dari
///     `date_of_birth`.
///  2. **Pita hanya untuk BB/U.** Tidak ada pita tinggi badan, dan tidak akan
///     ada selama database tidak punya acuan TB/U. Garis TB tetap digambar
///     tanpa band, dan legenda menyatakan itu.
///  3. **Tidak ada perhitungan z-score di klien.** Widget ini tidak pernah
///     menghitung apa pun dari `date_of_birth`; itu keputusan trigger
///     PostgreSQL, dan menghitungnya lagi di sini hanya membuka pintu untuk dua
///     tampilan yang berbeda.
///  4. **Angka nol tidak pernah diplot.** Titik dengan `weight_kg` atau
///     `height_cm` `null` dilewati, dan titik tanpa umur dilewati karena tidak
///     bisa diposisikan. `MeasurementModel` yang lama memakai `?? 0`; pola itu
///     di sini akan membuat Ibu melihat anak beratnya nol pada kunjungan yang
///     memang tidak menimbang.
class GrowthLineChart extends StatelessWidget {
  final GrowthSeries series;
  final WhoReference whoReference;
  final GrowthMetric metrikAktif;

  const GrowthLineChart({
    super.key,
    required this.series,
    required this.whoReference,
    this.metrikAktif = GrowthMetric.weight,
  });

  static const _warnaBerat = Color(0xFFD81B60);
  static const _warnaTinggi = Color(0xFF00897B);
  static const _warnaPita = Color(0xFF9E9E9E);
  static const _warnaPitaIsi = Color(0xFFE0E0E0);
  static const _warnaMedian = Color(0xFF757575);

  @override
  Widget build(BuildContext context) {
    final skala = _Skala.from(series, whoReference);

    // Tanpa satu pun titik yang bisa digambar, `LineChart` akan menggambar
    // kanvas kosong tanpa tahu itu. Layar yang bisa menampilkan pesan "belum ada
    // penimbangan" lebih berguna daripada kanvas hampa.
    if (skala.tanpaTitik) {
      return const SizedBox.shrink();
    }

    return LineChart(
      skala.jadiLineChartData(
        warnaBerat: _warnaBerat,
        warnaTinggi: _warnaTinggi,
        warnaPita: _warnaPita,
        warnaPitaIsi: _warnaPitaIsi,
        warnaMedian: _warnaMedian,
        weightUnit: series.weightUnit,
        heightUnit: series.heightUnit,
        metrikAktif: metrikAktif,
      ),
      duration: const Duration(milliseconds: 250),
    );
  }
}

/// Indeks baris di `lineBarsData`.
///
/// Dipakai `betweenBarsData` untuk mengisi pita, jadi urutannya harus sama
/// dengan urutan di [_Skala.baruBaris]. Kalau salah, pita akan terisi antara
/// garis yang salah - dan itu terlihat meyakinkan tanpa benar.
const int _indeksPitaBawah = 0;
const int _indeksPitaAtas = 1;

/// Baris median tidak dipakai di tooltip, tapi tetap harus punya slot supaya
/// indeks berat dan tinggi tidak bergeser.
const int _indeksMedian = 2;

const int _indeksBerat = 3;
const int _indeksTinggi = 4;

/// Berapa baris yang harus ada di `lineBarsData`.
///
/// Dipakai test widget untuk memeriksa urutannya, jadi mengubah urutan di
/// `_baris` tidak bisa lolos tanpa test ini ikut diperbarui.
const int jumlahBarisGrafik = 5;

/// Semua perhitungan posisi titik dan batas sumbu, terkumpul di satu tempat.
///
/// Dipisah dari widget supaya aturan gambarnya bisa dibaca terpisah:
/// semua nilai di sini **dibaca** dari server, tidak ada satu pun yang dihitung
/// ulang dari tanggal lahir.
class _Skala {
  /// Koordinat sumbu y dalam satuan yang sama dengan `weight_kg`.
  final double yMin;
  final double yMax;
  final double xMin;
  final double xMax;

  /// Rentang tinggi badan dalam cm, dipetakan ke koordinat y yang sama supaya
  /// kedua garis bisa berbagi satu kanvas tanpa saling menutupi.
  final double cmMin;
  final double cmRentang;

  final List<LineChartBarData> baris;
  final List<GrowthPoint> titik;
  final bool tanpaTitik;
  final bool pitaAda;

  _Skala({
    required this.yMin,
    required this.yMax,
    required this.xMin,
    required this.xMax,
    required this.cmMin,
    required this.cmRentang,
    required this.baris,
    required this.titik,
    required this.tanpaTitik,
    required this.pitaAda,
  });

  double get intervalY => _intervalRapi((yMax - yMin) / 4);
  double get intervalX => _intervalRapi((xMax - xMin) / 4);

  /// Koordinat y untuk nilai tinggi badan dalam cm.
  ///
  /// Tinggi badan tidak bisa langsung dipakai sebagai `y` karena satuannya cm
  /// sementara pita WHO-nya kg. Menyamakan rentang keduanya membuat kedua garis
  /// memenuhi kanvas, dan sumbu kanan menerjemahkan kembali ke cm - jadi angka
  /// yang dibaca Ibu tetap satuan aslinya.
  double yDariCm(double cm) {
    if (cmRentang <= 0) return yMin;
    return yMin + ((cm - cmMin) / cmRentang) * (yMax - yMin);
  }

  /// Nilai cm yang dibaca dari koordinat y, untuk label sumbu kanan.
  double cmDariY(double y) {
    if (yMax <= yMin) return cmMin;
    return cmMin + ((y - yMin) / (yMax - yMin)) * cmRentang;
  }

  /// Tanggal penimbangan yang berdekatan dengan koordinat y yang disentuh.
  ///
  /// Dipakai supaya tooltip menyebut kapan penimbangan itu terjadi. Dicocokkan
  /// dari titik yang **sudah bisa digambar**, jadi urutannya sama dengan yang
  /// Ibu lihat di garis - tooltip yang menunjuk tanggal lain akan sangat
  /// menyesatkan.
  String tanggalUntuk(double y) {
    GrowthPoint? terdekat;
    double jarakTerdekat = double.infinity;

    for (final p in titik) {
      if (p.umurTahun == null) continue;
      final yTitik = p.weightKg ?? yDariCm(p.heightCm ?? 0);
      final jarak = (yTitik - y).abs();
      if (jarak < jarakTerdekat) {
        jarakTerdekat = jarak;
        terdekat = p;
      }
    }

    return terdekat?.date ?? '';
  }

  LineChartData jadiLineChartData({
    required Color warnaBerat,
    required Color warnaTinggi,
    required Color warnaPita,
    required Color warnaPitaIsi,
    required Color warnaMedian,
    required String weightUnit,
    required String heightUnit,
    required GrowthMetric metrikAktif,
  }) {
    // Urutan baris di `_baris()` mengikat tiga hal sekaligus: indeks
    // `betweenBarsData` yang mengisi pita, indeks `spot.barIndex` di tooltip,
    // dan jumlah baris yang diharapkan test. Kalau salah satu berubah, ketiga
    // tempatnya harus ikut - assertion ini menangkapnya lebih awal daripada
    // pita yang terisi antara garis yang salah.
    assert(
      baris.length == jumlahBarisGrafik,
      'lineBarsData harus berisi $jumlahBarisGrafik baris, bukan ${baris.length}.',
    );

    return LineChartData(
      minX: xMin,
      maxX: xMax,
      minY: yMin,
      maxY: yMax,

      lineBarsData: baris,

      // Pita diisi lewat `betweenBarsData`, bukan `BarAreaData`. `BarAreaData`
      // mengisi ke bawah satu garis, sedangkan pita ini punya batas atas dan
      // bawah - jadi butuh dua garis batas dan area di antaranya.
      betweenBarsData: [
        if (pitaAda)
          BetweenBarsData(
            fromIndex: _indeksPitaBawah,
            toIndex: _indeksPitaAtas,
            color: warnaPitaIsi,
          ),
      ],

      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 38,
            interval: intervalY,
            getTitlesWidget: (value, meta) => _label(
              value,
              meta,
              '${_angka(value)} $weightUnit',
              metrikAktif == GrowthMetric.weight
                  ? warnaBerat
                  : Colors.grey[600]!,
            ),
          ),
        ),
        rightTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 34,
            interval: intervalY,
            // Sumbu kanan menampilkan cm asli, bukan koordinat yang sudah
            // diskalakan, jadi angka yang dibaca Ibu selalu satuan yang benar.
            getTitlesWidget: (value, meta) => _label(
              value,
              meta,
              '${_angka(cmDariY(value))} $heightUnit',
              metrikAktif == GrowthMetric.height
                  ? warnaTinggi
                  : Colors.grey[600]!,
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            interval: intervalX,
            getTitlesWidget: (value, meta) =>
                _label(value, meta, _labelUmur(value), Colors.grey[700]!),
          ),
        ),
      ),

      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: intervalY,
        verticalInterval: intervalX,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: Color(0xFFE8E8E8), strokeWidth: 1),
        getDrawingVerticalLine: (_) =>
            const FlLine(color: Color(0xFFF0F0F0), strokeWidth: 1),
      ),

      borderData: FlBorderData(
        show: true,
        border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
      ),

      lineTouchData: LineTouchData(
        enabled: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.white,
          tooltipBorderRadius: BorderRadius.circular(8),
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItems: (spots) => spots.map((spot) {
            // Baris pita dan median bukan data penimbangan, jadi menampilkan
            // angka di sana akan membuat Ibu mengira itu hasil pemeriksaan
            // anaknya. Ketiganya ditulis eksplisit karena ketiganya memang
            // benda berbeda - median pernah diikutkan tanpa sengaja.
            final barisBukanDataAnak =
                spot.barIndex == _indeksPitaBawah ||
                spot.barIndex == _indeksPitaAtas ||
                spot.barIndex == _indeksMedian;

            if (barisBukanDataAnak) {
              return const LineTooltipItem(
                '',
                TextStyle(fontSize: 0, color: Colors.transparent),
              );
            }

            // Bukan `else`: dua baris terakhir memang data anak, dan bulat ini
            // yang menentukan tooltipnya menampilkan kg atau cm.
            final berat = spot.barIndex == _indeksBerat;
            assert(
              spot.barIndex == _indeksTinggi || berat,
              'Ada baris di luar pita/median yang tidak dikenal: ${spot.barIndex}.',
            );
            final nilai = berat ? spot.y : cmDariY(spot.y);
            final satuan = berat ? weightUnit : heightUnit;
            final warna = berat ? warnaBerat : warnaTinggi;
            final tanggal = tanggalUntuk(spot.y);

            return LineTooltipItem(
              '$nilai $satuan\n$tanggal',
              TextStyle(
                fontSize: 11,
                color: warna,
                fontWeight: FontWeight.w600,
              ),
            );
          }).toList(),
        ),
        getTouchedSpotIndicator: (bar, indexes) => indexes
            .map(
              (_) => TouchedSpotIndicatorData(
                FlLine(color: bar.color ?? Colors.grey, strokeWidth: 1),
                FlDotData(
                  getDotPainter: (spot, percent, barData, index) =>
                      FlDotCirclePainter(
                        radius: 4,
                        color: barData.color ?? Colors.grey,
                        strokeWidth: 1,
                        strokeColor: Colors.white,
                      ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  static Widget _label(double value, TitleMeta meta, String teks, Color warna) {
    return SideTitleWidget(
      meta: meta,
      space: 4,
      child: Text(
        teks,
        style: TextStyle(
          fontSize: 10,
          color: warna,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  static String _labelUmur(double tahun) {
    final bulan = (tahun * 12).round();
    if (bulan <= 0) return 'lahir';
    if (bulan < 12) return '$bulan bln';
    final th = bulan ~/ 12;
    final sisa = bulan % 12;
    return sisa == 0 ? '$th th' : '$th th $sisa';
  }

  /// Angka sumbu dibulatkan supaya tidak jadi "12.399999".
  static String _angka(double nilai) {
    if (nilai.isNaN || nilai.isInfinite) return '-';
    return nilai.round().toString();
  }

  /// Titik yang bisa diposisikan: harus punya umur (sumbu x) dan nilai metrik.
  static List<GrowthPoint> _titikSiap(
    List<GrowthPoint> sumber, {
    required bool berat,
  }) {
    return sumber
        .where((p) {
          if (p.umurTahun == null) return false;
          return berat ? p.weightKg != null : p.heightCm != null;
        })
        .toList(growable: false);
  }

  /// Batas sumbu yang "bagus" dibaca mata: 1, 2, 5, atau 10.
  ///
  /// Tanpa ini sumbu bisa terbaca "3,75 kg" untuk anak yang ditimbang 3,8 kg -
  /// presisi yang tidak ada artinya di layar 300 piksel.
  static double _intervalRapi(double kasar) {
    if (kasar <= 0 || !kasar.isFinite) return 1;
    if (kasar >= 10) return kasar.roundToDouble();
    if (kasar >= 5) return 5;
    if (kasar >= 2) return 2;
    return 1;
  }

  factory _Skala.from(GrowthSeries series, WhoReference pita) {
    final titikBerat = _titikSiap(series.points, berat: true);
    final titikTinggi = _titikSiap(series.points, berat: false);

    if (titikBerat.isEmpty && titikTinggi.isEmpty) {
      return _Skala(
        yMin: 0,
        yMax: 1,
        xMin: 0,
        xMax: 1,
        cmMin: 0,
        cmRentang: 0,
        baris: const <LineChartBarData>[],
        titik: const <GrowthPoint>[],
        tanpaTitik: true,
        pitaAda: false,
      );
    }

    // Pita ikut menentukan rentang y. Kalau hanya garis anak yang menentukan,
    // pita yang lebih lebar akan meluber keluar area gambar dan terlihat
    // terpotong - dan pita yang terpotong persis seperti pita yang salah.
    //
    // Daftar sumber bisa kosong: anak yang ditimbang beratnya saja tidak punya
    // satu pun titik tinggi badan, dan anak tanpa pita pun tidak ada. `_min` dan
    // `_max` deshalb menerima nilai cadangan, bukan `reduce` telanjang yang
    // melempar `StateError` saat daftarnya kosong.
    var yMin = _min([
      for (final p in titikBerat) p.weightKg!,
      for (final w in pita.points) w.lowerKg,
    ], cadangan: 0);
    var yMax = _max([
      for (final p in titikBerat) p.weightKg!,
      for (final w in pita.points) w.upperKg,
    ], cadangan: 10);
    [yMin, yMax] = _bantalan(yMin, yMax, minimum: 1);

    // Tanpa satu pun titik tinggi badan, tidak ada sumbu kanan yang punya
    // angka. Rentang cm 0 dipakai supaya `cmDariY` dan `yDariCm` tidak
    // membagi dengan nol; tidak ada yang memanggilnya karena garis TB kosong.
    var cmMin = _min([for (final p in titikTinggi) p.heightCm!], cadangan: 0);
    var cmMaks = _max([for (final p in titikTinggi) p.heightCm!], cadangan: 1);
    [cmMin, cmMaks] = _bantalan(cmMin, cmMaks, minimum: 1);

    // Sumbu x mengikuti umur anak yang tercatat, bukan rentang pita. Kalau pita
    // yang menentukan, anak 2 bulan mendapat kanvas 0-60 bulan dan garisnya
    // jadi titik kecil di tepi.
    final umur = [
      for (final p in series.points)
        if (p.umurTahun != null) p.umurTahun!,
    ];
    // Daftar `umur` tidak pernah kosong di titik ini: `_Skala.from` sudah
    // keluar lebih awal kalau tidak ada satu pun titik yang bisa digambar.
    var xMin = _min(umur, cadangan: 0);
    var xMax = _max(umur, cadangan: 1);
    if (xMax - xMin < 0.5) {
      xMin = (xMin - 0.25).clamp(0.0, double.infinity);
      xMax = xMax + 0.25;
    } else {
      final bantalan = (xMax - xMin) * 0.05;
      xMin = (xMin - bantalan).clamp(0.0, double.infinity);
      xMax = xMax + bantalan;
    }

    return _Skala(
      yMin: yMin,
      yMax: yMax,
      xMin: xMin,
      xMax: xMax,
      cmMin: cmMin,
      cmRentang: cmMaks - cmMin,
      baris: const <LineChartBarData>[],
      titik: series.points,
      tanpaTitik: false,
      pitaAda: !pita.kosong,
    )._denganBaris(pita, titikBerat, titikTinggi);
  }

  /// Salinan dengan baris garis terisi.
  ///
  /// Dipisah dari constructor utama karena baris pita butuh [_Skala] ini sudah
  /// jadi untuk memetakan tinggi badan ke koordinat y - dan kolom `final` tidak
  /// bisa diisi setelahnya.
  _Skala _denganBaris(
    WhoReference pita,
    List<GrowthPoint> titikBerat,
    List<GrowthPoint> titikTinggi,
  ) {
    return _Skala(
      yMin: yMin,
      yMax: yMax,
      xMin: xMin,
      xMax: xMax,
      cmMin: cmMin,
      cmRentang: cmRentang,
      baris: _baris(pita, titikBerat, titikTinggi),
      titik: titik,
      tanpaTitik: tanpaTitik,
      pitaAda: pitaAda,
    );
  }

  /// Tambah ruang kosong di atas dan bawah, atau lebarkan kalau rentangnya nol.
  ///
  /// Satu titik tunggal selalu punya rentang nol, dan `fl_chart` akan membagi
  /// dengan nol saat menghitung posisi kalau itu dibiarkan.
  static List<double> _bantalan(
    double min,
    double maks, {
    required double minimum,
  }) {
    if (maks - min < minimum) {
      return [min - minimum / 2, maks + minimum / 2];
    }
    final bantalan = (maks - min) * 0.08;
    return [min - bantalan, maks + bantalan];
  }

  /// Batas terkecil dari daftar, atau [cadangan] kalau daftarnya kosong.
  ///
  /// `cadangan` dipakai supaya anak yang hanya ditimbang tinggi badannya - atau
  /// grafik tanpa pita dan tanpa titik berat - tidak membuat widget meledak
  /// dengan `StateError` dari `reduce` atas daftar kosong.
  static double _min(List<double> nilai, {required double cadangan}) {
    if (nilai.isEmpty) return cadangan;
    return nilai.reduce((a, b) => a < b ? a : b);
  }

  /// Batas terbesar dari daftar, atau [cadangan] kalau daftarnya kosong.
  static double _max(List<double> nilai, {required double cadangan}) {
    if (nilai.isEmpty) return cadangan;
    return nilai.reduce((a, b) => a > b ? a : b);
  }

  /// Baris-baris garis yang akan digambar, urutannya dikunci oleh indeks di
  /// bagian atas file.
  ///
  /// Bukan `static` karena garis tinggi badan butuh [yDariCm] untuk memetakan cm
  /// ke koordinat y yang sama dengan pita.
  List<LineChartBarData> _baris(
    WhoReference pita,
    List<GrowthPoint> titikBerat,
    List<GrowthPoint> titikTinggi,
  ) {
    final hasil = <LineChartBarData>[];

    // Pita hanya digambar kalau WHO mengirimnya. Interpolasi dari dua titik yang
    // berdekatan menghasilkan pita yang terlihat meyakinkan tapi tidak benar,
    // dan itu lebih buruk daripada tidak ada pita sama sekali.
    if (pita.kosong) {
      // Tiga baris kosong supaya indeks median, berat, dan tinggi tidak
      // bergeser. `betweenBarsData` hanya dirender kalau `pitaAda`, jadi
      // placeholder ini tidak pernah terlihat.
      hasil.add(_garisBatas(const <FlSpot>[]));
      hasil.add(_garisBatas(const <FlSpot>[]));
      hasil.add(
        LineChartBarData(
          spots: const <FlSpot>[],
          isCurved: false,
          dotData: const FlDotData(show: false),
        ),
      );
    } else {
      hasil.add(
        _garisBatas([
          for (final w in pita.points) FlSpot(w.umurTahun, w.lowerKg),
        ]),
      );
      hasil.add(
        _garisBatas([
          for (final w in pita.points) FlSpot(w.umurTahun, w.upperKg),
        ]),
      );
      hasil.add(
        LineChartBarData(
          spots: [for (final w in pita.points) FlSpot(w.umurTahun, w.medianKg)],
          isCurved: false,
          color: GrowthLineChart._warnaMedian,
          barWidth: 1,
          dashArray: const [4, 4],
          dotData: const FlDotData(show: false),
        ),
      );
    }

    hasil.add(
      LineChartBarData(
        spots: [for (final p in titikBerat) FlSpot(p.umurTahun!, p.weightKg!)],
        isCurved: true,
        curveSmoothness: 0.2,
        preventCurveOverShooting: true,
        color: GrowthLineChart._warnaBerat,
        barWidth: 3,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
            radius: 3,
            color: GrowthLineChart._warnaBerat,
            strokeWidth: 1,
            strokeColor: Colors.white,
          ),
        ),
      ),
    );

    hasil.add(
      LineChartBarData(
        spots: [
          for (final p in titikTinggi)
            FlSpot(p.umurTahun!, yDariCm(p.heightCm!)),
        ],
        isCurved: true,
        curveSmoothness: 0.2,
        preventCurveOverShooting: true,
        color: GrowthLineChart._warnaTinggi,
        barWidth: 2,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
            radius: 2.5,
            color: GrowthLineChart._warnaTinggi,
            strokeWidth: 1,
            strokeColor: Colors.white,
          ),
        ),
      ),
    );

    return hasil;
  }

  /// Garis tipis tanpa titik, untuk batas pita.
  static LineChartBarData _garisBatas(List<FlSpot> spots) {
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: GrowthLineChart._warnaPita,
      barWidth: 1,
      dotData: const FlDotData(show: false),
    );
  }
}
