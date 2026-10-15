import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/growth_chart.dart';

/// Metrik yang sedang digambar di grafik.
///
/// Grafik sekarang menggambar **satu** kurva anak dengan **satu** pitanya,
/// dipilih lewat tombol di layar. Sebelumnya enum ini cuma menebalkan salah satu
/// dari dua garis di kanvas yang sama; sekarang ia benar-benar pemilih data.
///
/// IMT/U ditambahkan karena satuannya `kg/m²` tidak bisa dipetakan ke kanvas
/// yang sama dengan kg dan cm - itulah alasan dual-axis dihapus.
enum GrowthMetric { weightForAge, heightForAge, bmiForAge }

/// Kunci `metric` di `who_references` untuk tiap pilihan.
///
/// Dicocokkan lewat kunci ini, bukan lewat label tampilan ("BB/U"), karena label
/// bisa berubah tanpa mengubah kontrak.
extension GrowthMetricInfo on GrowthMetric {
  String get metricKey => switch (this) {
    GrowthMetric.weightForAge => 'weight_for_age',
    GrowthMetric.heightForAge => 'height_for_age',
    GrowthMetric.bmiForAge => 'bmi_for_age',
  };

  /// Label pendek untuk tombol metrik.
  String get label => switch (this) {
    GrowthMetric.weightForAge => 'BB/U',
    GrowthMetric.heightForAge => 'TB/U',
    GrowthMetric.bmiForAge => 'IMT/U',
  };

  /// Label panjang untuk tooltip.
  String get labelPanjang => switch (this) {
    GrowthMetric.weightForAge => 'Berat Badan',
    GrowthMetric.heightForAge => 'Tinggi Badan',
    GrowthMetric.bmiForAge => 'IMT',
  };

  /// Satuan yang sesuai, dibaca dari `series.unit`.
  String satuanDari(GrowthSeries series) => switch (this) {
    GrowthMetric.weightForAge => series.weightUnit,
    GrowthMetric.heightForAge => series.heightUnit,
    GrowthMetric.bmiForAge => series.bmiUnit,
  };

  /// Nilai titik untuk metrik ini. `null` berarti tidak diukur hari itu.
  double? nilaiDari(GrowthPoint point) => switch (this) {
    GrowthMetric.weightForAge => point.weightKg,
    GrowthMetric.heightForAge => point.heightCm,
    GrowthMetric.bmiForAge => point.bmi,
  };
}

/// Grafik tumbuh kembang: satu pita WHO + satu garis anak.
///
/// Wrapper tipis di atas `fl_chart`. Semua keputusan bentuk grafik ada di
/// `docs/RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md` bagian 8 dan
/// `docs/RANCANGAN_WHO_MULTIDIM.md` bagian 7.2; widget ini hanya
/// menerjemahkannya jadi `LineChart`. Kalau bentuk visualnya berubah,
/// dokumennya yang diubah lebih dulu.
///
/// Empat keputusan yang tidak boleh dibalik di sini:
///
///  1. **Sumbu x adalah umur dalam tahun, bukan tanggal.** Pita WHO diindeks
///     umur, jadi sumbu tanggal tidak bisa disejajarkan dengan pita. Umurnya
///     diambil dari `age_in_months` milik server, tidak dihitung dari
///     `date_of_birth`.
///  2. **Satu metrik per kanvas.** BB/U, TB/U, dan IMT/U tidak pernah digambar
///     bersama; IMT/U bersatuan `kg/m²` yang tidak punya padanan di sumbu kg
///     atau cm. Pita yang dipakai adalah entri `who_references` bermetrik sama.
///  3. **Tidak ada perhitungan z-score di klien.** Widget ini tidak pernah
///     menghitung apa pun dari `date_of_birth`; itu keputusan trigger
///     PostgreSQL, dan menghitungnya lagi di sini hanya membuka pintu untuk dua
///     tampilan yang berbeda. `bmi` pun dihitung server.
///  4. **Angka nol tidak pernah diplot.** Titik yang nilainya `null` untuk
///     metrik aktif dilewati, dan titik tanpa umur dilewati karena tidak bisa
///     diposisikan.
class GrowthLineChart extends StatelessWidget {
  final GrowthSeries series;
  final List<WhoBandReference> whoBands;
  final GrowthMetric metrikAktif;

  const GrowthLineChart({
    super.key,
    required this.series,
    this.whoBands = const <WhoBandReference>[],
    this.metrikAktif = GrowthMetric.weightForAge,
  });

  static const _warnaBerat = Color(0xFFD81B60);
  static const _warnaTinggi = Color(0xFF00897B);
  static const _warnaBmi = Color(0xFF6A1B9A);
  static const _warnaPita = Color(0xFF9E9E9E);
  static const _warnaPitaIsi = Color(0xFFE0E0E0);
  static const _warnaMedian = Color(0xFF757575);

  /// Warna garis anak dan label sumbu untuk metrik aktif.
  static Color warnaMetrik(GrowthMetric metrik) => switch (metrik) {
    GrowthMetric.weightForAge => _warnaBerat,
    GrowthMetric.heightForAge => _warnaTinggi,
    GrowthMetric.bmiForAge => _warnaBmi,
  };

  @override
  Widget build(BuildContext context) {
    final band = _bandUntuk(whoBands, metrikAktif);
    final skala = _Skala.from(series, band, metrikAktif);

    // Tanpa satu pun titik yang bisa digambar untuk metrik ini, `LineChart`
    // akan menggambar kanvas kosong tanpa tahu itu. Layar yang bisa menampilkan
    // pesan "belum ada data" lebih berguna daripada kanvas hampa.
    if (skala.tanpaTitik) {
      return const SizedBox.shrink();
    }

    return LineChart(
      skala.jadiLineChartData(
        warnaPitaIsi: _warnaPitaIsi,
        satuan: metrikAktif.satuanDari(series),
        warnaMetrik: warnaMetrik(metrikAktif),
      ),
      duration: const Duration(milliseconds: 250),
    );
  }

  /// Pita untuk metrik aktif, atau `null` kalau server tidak mengirimnya.
  static WhoBandReference? _bandUntuk(
    List<WhoBandReference> bands,
    GrowthMetric metrik,
  ) {
    for (final band in bands) {
      if (band.metric == metrik.metricKey) return band;
    }
    return null;
  }
}

/// Indeks baris di `lineBarsData`.
///
/// Dipakai `betweenBarsData` untuk mengisi pita, jadi urutannya harus sama
/// dengan urutan di [_Skala.baris]. Kalau salah, pita akan terisi antara garis
/// yang salah - dan itu terlihat meyakinkan tanpa benar.
const int _indeksPitaBawah = 0;
const int _indeksPitaAtas = 1;

/// Baris median tidak dipakai di tooltip, tapi tetap harus punya slot supaya
/// indeks garis nilai tidak bergeser.
const int _indeksMedian = 2;

const int _indeksNilai = 3;

/// Berapa baris yang harus ada di `lineBarsData`.
///
/// Dipakai test widget untuk memeriksa urutannya, jadi mengubah urutan di
/// `_baris` tidak bisa lolos tanpa test ini ikut diperbarui.
const int jumlahBarisGrafik = 4;

/// Semua perhitungan posisi titik dan batas sumbu, terkumpul di satu tempat.
///
/// Dipisah dari widget supaya aturan gambarnya bisa dibaca terpisah:
/// semua nilai di sini **dibaca** dari server, tidak ada satu pun yang dihitung
/// ulang dari tanggal lahir.
class _Skala {
  /// Koordinat sumbu y dalam satuan metrik aktif (kg, cm, atau kg/m²).
  final double yMin;
  final double yMax;
  final double xMin;
  final double xMax;

  final List<LineChartBarData> baris;

  /// Titik anak yang bisa digambar di metrik aktif. Dipakai tooltip supaya
  /// tanggal yang disebut cocok dengan titik yang benar-benar terlihat.
  final List<GrowthPoint> titik;
  final bool tanpaTitik;
  final bool pitaAda;

  /// Metrik aktif. Disimpan supaya tooltip bisa mengambil nilai titik yang
  /// benar tanpa parameter tambahan di tiap pemanggilan.
  final GrowthMetric metrik;

  const _Skala({
    required this.yMin,
    required this.yMax,
    required this.xMin,
    required this.xMax,
    required this.baris,
    required this.titik,
    required this.tanpaTitik,
    required this.pitaAda,
    required this.metrik,
  });

  double get intervalY => _intervalRapi((yMax - yMin) / 4);
  double get intervalX => _intervalRapi((xMax - xMin) / 4);

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
      final yTitik = metrik.nilaiDari(p);
      if (yTitik == null) continue;
      final jarak = (yTitik - y).abs();
      if (jarak < jarakTerdekat) {
        jarakTerdekat = jarak;
        terdekat = p;
      }
    }

    return terdekat?.date ?? '';
  }

  LineChartData jadiLineChartData({
    required Color warnaPitaIsi,
    required String satuan,
    required Color warnaMetrik,
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
        // Hanya satu sumbu y sekarang: tidak ada lagi kg di kiri dan cm di
        // kanan, karena setiap kanvas cuma punya satu metrik.
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 42,
            interval: intervalY,
            getTitlesWidget: (value, meta) =>
                _label(value, meta, '${_angka(value)} $satuan', warnaMetrik),
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

            assert(
              spot.barIndex == _indeksNilai,
              'Ada baris di luar pita/median yang tidak dikenal: ${spot.barIndex}.',
            );

            final tanggal = tanggalUntuk(spot.y);

            return LineTooltipItem(
              '${metrik.labelPanjang}\n'
              '${_angkaDesimal(spot.y)} $satuan\n$tanggal',
              TextStyle(
                fontSize: 11,
                color: warnaMetrik,
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

  /// Angka tooltip satu desimal, lebih informatif daripada pembulatan sumbu.
  static String _angkaDesimal(double nilai) {
    if (nilai.isNaN || nilai.isInfinite) return '-';
    return nilai.toStringAsFixed(1);
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

  factory _Skala.from(
    GrowthSeries series,
    WhoBandReference? pita,
    GrowthMetric metrik,
  ) {
    final titikNilai = series.points
        .where((p) => p.umurTahun != null && metrik.nilaiDari(p) != null)
        .toList(growable: false);

    final bandAda = pita != null && !pita.kosong;

    if (titikNilai.isEmpty) {
      return _Skala(
        yMin: 0,
        yMax: 1,
        xMin: 0,
        xMax: 1,
        baris: const <LineChartBarData>[],
        titik: const <GrowthPoint>[],
        tanpaTitik: true,
        pitaAda: false,
        metrik: metrik,
      );
    }

    // Pita ikut menentukan rentang y. Kalau hanya garis anak yang menentukan,
    // pita yang lebih lebar akan meluber keluar area gambar dan terlihat
    // terpotong - dan pita yang terpotong persis seperti pita yang salah.
    //
    // Daftar sumber bisa kosong: anak tanpa pita tidak punya satu titik pun dari
    // band, dan garis anak tetap harus digambar. `_min` dan `_max` karena itu
    // menerima nilai cadangan, bukan `reduce` telanjang yang melempar
    // `StateError` saat daftarnya kosong.
    var yMin = _min([
      for (final p in titikNilai) metrik.nilaiDari(p)!,
      if (bandAda) for (final w in pita.points) w.lower,
    ], cadangan: 0);
    var yMax = _max([
      for (final p in titikNilai) metrik.nilaiDari(p)!,
      if (bandAda) for (final w in pita.points) w.upper,
    ], cadangan: 1);

    // Satuan metrik (kg, cm, kg/m²) punya rentang yang berbeda-beda, tapi
    // bantalan minimum 1 tetap masuk akal untuk ketiganya: 1 kg, 1 cm, atau
    // 1 kg/m² sama-sama cukup untuk memisahkan satu titik tunggal dari tepi.
    [yMin, yMax] = _bantalan(yMin, yMax, minimum: 1);

    // Sumbu x mengikuti umur anak yang tercatat, bukan rentang pita. Kalau pita
    // yang menentukan, anak 2 bulan mendapat kanvas 0-60 bulan dan garisnya
    // jadi titik kecil di tepi.
    final umur = [
      for (final p in series.points)
        if (p.umurTahun != null) p.umurTahun!,
    ];
    // Daftar `umur` tidak pernah kosong di titik ini: sudah keluar lebih awal
    // kalau tidak ada satu pun titik yang punya nilai untuk metrik aktif.
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
      baris: _baris(pita, titikNilai, metrik),
      titik: titikNilai,
      tanpaTitik: false,
      pitaAda: bandAda,
      metrik: metrik,
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
  /// Selalu empat baris: batas bawah pita, batas atas pita, median, lalu garis
  /// nilai anak. Tanpa pita, tiga baris pertama tetap ada sebagai placeholder
  /// kosong supaya indeks garis nilai tidak bergeser - `betweenBarsData` hanya
  /// dirender kalau `pitaAda`, jadi placeholder tidak pernah terlihat.
  static List<LineChartBarData> _baris(
    WhoBandReference? pita,
    List<GrowthPoint> titikNilai,
    GrowthMetric metrik,
  ) {
    final hasil = <LineChartBarData>[];
    final bandAda = pita != null && !pita.kosong;

    if (!bandAda) {
      hasil.add(_kosong());
      hasil.add(_kosong());
      hasil.add(_kosong());
    } else {
      hasil.add(
        _garisBatas([
          for (final w in pita.points) FlSpot(w.umurTahun, w.lower),
        ]),
      );
      hasil.add(
        _garisBatas([
          for (final w in pita.points) FlSpot(w.umurTahun, w.upper),
        ]),
      );
      hasil.add(
        LineChartBarData(
          spots: [for (final w in pita.points) FlSpot(w.umurTahun, w.median)],
          isCurved: false,
          color: GrowthLineChart._warnaMedian,
          barWidth: 1,
          dashArray: const [4, 4],
          dotData: const FlDotData(show: false),
        ),
      );
    }

    final warna = GrowthLineChart.warnaMetrik(metrik);

    hasil.add(
      LineChartBarData(
        spots: [
          for (final p in titikNilai)
            FlSpot(p.umurTahun!, metrik.nilaiDari(p)!),
        ],
        isCurved: true,
        curveSmoothness: 0.2,
        preventCurveOverShooting: true,
        color: warna,
        barWidth: 3,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
            radius: 3,
            color: warna,
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

  /// Baris kosong sebagai placeholder supaya indeks tidak bergeser.
  static LineChartBarData _kosong() {
    return LineChartBarData(
      spots: const <FlSpot>[],
      isCurved: false,
      dotData: const FlDotData(show: false),
    );
  }
}
