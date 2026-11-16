// Widget test untuk grafik tumbuh kembang (Opsi D + amendemen multidimensi).
//
// Yang diuji di sini adalah apa yang tidak terlihat di `kontrak_api_test.dart`:
// apakah `GrowthLineChart` benar-benar bisa dirender pada kasus tepi, apakah
// pitanya terisi antara dua garis yang benar, dan apakah tiap metrik (BB/U,
// TB/U, IMT/U) memakai nilai titik dan pita yang sesuai.
//
// Parser JSON diuji terpisah di kontrak_api_test.dart. Test ini sengaja
// tidak memanggil HTTP apa pun - `GrowthChartService` butuh
// `flutter_secure_storage`, jadi hanya widget grafik yang dim-pump langsung.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:posyandu_mobile/models/growth_chart.dart';
import 'package:posyandu_mobile/widgets/growth_line_chart.dart';

/// Pita BB/U seadanya: dua titik sudah cukup untuk memeriksa pasangan indeks
/// `betweenBarsData`, dan tidak perlu 61 baris untuk itu.
const WhoBandReference _pitaBerat = WhoBandReference(
  metric: 'weight_for_age',
  label: 'BB/U',
  unit: 'kg',
  source: 'WHO Child Growth Standards 2006',
  gender: 'P',
  ageFrom: 0,
  ageTo: 60,
  points: [
    WhoBandPoint(ageInMonths: 24, median: 12.2, lower: 10.1, upper: 14.5),
    WhoBandPoint(ageInMonths: 30, median: 13.3, lower: 11.2, upper: 15.7),
  ],
);

const WhoBandReference _pitaTinggi = WhoBandReference(
  metric: 'height_for_age',
  label: 'TB/U',
  unit: 'cm',
  source: 'WHO Child Growth Standards 2006',
  gender: 'P',
  ageFrom: 0,
  ageTo: 60,
  points: [
    WhoBandPoint(ageInMonths: 24, median: 87.1, lower: 81.0, upper: 93.2),
    WhoBandPoint(ageInMonths: 30, median: 90.5, lower: 84.0, upper: 97.0),
  ],
);

const WhoBandReference _pitaBmi = WhoBandReference(
  metric: 'bmi_for_age',
  label: 'IMT/U',
  unit: 'kg/m2',
  source: 'WHO Child Growth Standards 2006',
  gender: 'P',
  ageFrom: 0,
  ageTo: 60,
  points: [
    WhoBandPoint(ageInMonths: 24, median: 16.0, lower: 13.8, upper: 18.9),
    WhoBandPoint(ageInMonths: 30, median: 16.2, lower: 13.6, upper: 19.4),
  ],
);

const List<WhoBandReference> _tigaPita = [
  _pitaBerat,
  _pitaTinggi,
  _pitaBmi,
];

/// Deret penimbangan dengan satuan dan arah urut yang sama seperti server.
GrowthSeries _deret(List<GrowthPoint> points) {
  return GrowthSeries(
    weightUnit: 'kg',
    heightUnit: 'cm',
    bmiUnit: 'kg/m2',
    order: 'asc',
    points: points,
  );
}

Widget _bungkus(Widget anak) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 320,
        child: Padding(padding: const EdgeInsets.all(8), child: anak),
      ),
    ),
  );
}

LineChart _lineChart(WidgetTester tester) {
  return tester.widget<LineChart>(find.byType(LineChart));
}

void main() {
  group('Widget grafik tumbuh - GrowthLineChart', () {
    testWidgets('satu titik tetap ter-render tanpa error', (tester) async {
      await tester.pumpWidget(
        _bungkus(
          GrowthLineChart(
            series: _deret(const [
              GrowthPoint(
                date: '2026-09-24',
                ageInMonths: 30,
                weightKg: 12.4,
                heightCm: 88.0,
              ),
            ]),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets('tiga titik: pitanya terisi antara batas bawah dan atas', (
      tester,
    ) async {
      await tester.pumpWidget(
        _bungkus(
          GrowthLineChart(
            series: _deret(const [
              GrowthPoint(
                date: '2026-03-12',
                ageInMonths: 24,
                weightKg: 11.2,
                heightCm: 85.0,
              ),
              GrowthPoint(
                date: '2026-06-12',
                ageInMonths: 27,
                weightKg: 11.8,
                heightCm: 86.5,
              ),
              GrowthPoint(
                date: '2026-09-24',
                ageInMonths: 30,
                weightKg: 12.4,
                heightCm: 88.0,
              ),
            ]),
            whoBands: _tigaPita,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final data = _lineChart(tester).data;

      // Urutan baris dikunci di bagian atas growth_line_chart.dart: batas bawah
      // pita, batas atas pita, median, nilai anak. Kalau berubah, pita akan
      // terisi antara garis yang salah.
      expect(data.lineBarsData.length, jumlahBarisGrafik);
      expect(data.betweenBarsData.length, 1);
      expect(data.betweenBarsData.first.fromIndex, 0);
      expect(data.betweenBarsData.first.toIndex, 1);

      // Pita adalah area antara batas bawah dan batas atas, jadi keduanya
      // harus benar-benar punya titik. Placeholder kosong akan menghasilkan
      // pita yang terlihat benar padahal tidak ada.
      expect(data.lineBarsData[0].spots.length, 2);
      expect(data.lineBarsData[1].spots.length, 2);
      expect(data.lineBarsData[2].spots.length, 2);

      // Baris terakhir: nilai anak, tiga titik, tidak ada yang di-drop.
      expect(data.lineBarsData[3].spots.length, 3);
    });

    testWidgets('points kosong tidak crash dan tidak menggambar apa pun', (
      tester,
    ) async {
      // `points: []` adalah jawaban yang benar untuk anak yang belum pernah
      // ditimbang, jadi widget harus turun diam-diam, bukan melempar error.
      await tester.pumpWidget(
        _bungkus(
          GrowthLineChart(series: _deret(const []), whoBands: _tigaPita),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets('tanpa pita WHO, garis anak tetap digambar', (tester) async {
      // Tidak boleh ada pitanya. Interpolasi dari dua titik mana pun akan
      // menghasilkan pita yang terlihat meyakinkan tapi tidak benar.
      await tester.pumpWidget(
        _bungkus(
          GrowthLineChart(
            series: _deret(const [
              GrowthPoint(
                date: '2026-09-24',
                ageInMonths: 30,
                weightKg: 12.4,
                heightCm: 88.0,
              ),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final data = _lineChart(tester).data;

      // Tiga baris placeholder supaya indeks nilai tidak bergeser, tapi tidak
      // ada `betweenBarsData` yang mengisinya.
      expect(data.lineBarsData.length, jumlahBarisGrafik);
      expect(data.betweenBarsData, isEmpty);
      expect(data.lineBarsData[0].spots, isEmpty);
      expect(data.lineBarsData[1].spots, isEmpty);
      expect(data.lineBarsData[3].spots.length, 1);
    });

    testWidgets('titik dengan angka null tidak diplot sebagai nol', (
      tester,
    ) async {
      // Penimbangan yang hanya mengukur tinggi badan punya `weight_kg` null.
      // Kalau diplot sebagai 0, Ibu akan melihat anak beratnya nol - yang
      // tidak pernah terjadi.
      await tester.pumpWidget(
        _bungkus(
          GrowthLineChart(
            series: _deret(const [
              GrowthPoint(date: '2026-06-12', ageInMonths: 27, heightCm: 86.5),
              GrowthPoint(
                date: '2026-09-24',
                ageInMonths: 30,
                weightKg: 12.4,
                heightCm: 88.0,
              ),
            ]),
            whoBands: _tigaPita,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final data = _lineChart(tester).data;

      // Hanya satu titik yang punya berat badan, jadi satu titik di garis
      // berat - bukan dua, dan bukan titik di 0.
      expect(data.lineBarsData[3].spots.length, 1);
      expect(data.lineBarsData[3].spots.first.y, closeTo(12.4, 0.001));
    });

    testWidgets('titik tanpa umur dilewati karena tidak bisa diposisikan', (
      tester,
    ) async {
      await tester.pumpWidget(
        _bungkus(
          GrowthLineChart(
            series: _deret(const [
              GrowthPoint(date: '2026-09-24', weightKg: 12.4),
              GrowthPoint(date: '2026-09-24', ageInMonths: 30, weightKg: 12.4),
            ]),
            whoBands: _tigaPita,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final data = _lineChart(tester).data;
      expect(data.lineBarsData[3].spots.length, 1);
    });

    testWidgets('metrik TB/U memakai tinggi badan dan pita height_for_age', (
      tester,
    ) async {
      await tester.pumpWidget(
        _bungkus(
          GrowthLineChart(
            metrikAktif: GrowthMetric.heightForAge,
            series: _deret(const [
              GrowthPoint(
                date: '2026-09-24',
                ageInMonths: 30,
                weightKg: 12.4,
                heightCm: 88.0,
              ),
            ]),
            whoBands: _tigaPita,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final data = _lineChart(tester).data;

      // Nilai titik adalah tinggi badan, bukan berat badan.
      expect(data.lineBarsData[3].spots.first.y, closeTo(88.0, 0.001));
      // Pita yang dipakai adalah TB/U (median 90.5 di 30 bulan), bukan BB/U.
      expect(data.lineBarsData[2].spots.last.y, closeTo(90.5, 0.001));
    });

    testWidgets('metrik IMT/U memakai bmi dan pita bmi_for_age', (tester) async {
      await tester.pumpWidget(
        _bungkus(
          GrowthLineChart(
            metrikAktif: GrowthMetric.bmiForAge,
            series: _deret(const [
              GrowthPoint(
                date: '2026-09-24',
                ageInMonths: 30,
                weightKg: 12.4,
                heightCm: 88.0,
                bmi: 16.01,
              ),
            ]),
            whoBands: _tigaPita,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final data = _lineChart(tester).data;

      expect(data.lineBarsData[3].spots.first.y, closeTo(16.01, 0.001));
      expect(data.lineBarsData[2].spots.last.y, closeTo(16.2, 0.001));
    });

    testWidgets('IMT/U tanpa nilai bmi tidak menggambar kanvas', (
      tester,
    ) async {
      // Tinggi badan tidak diukur, jadi bmi semua titik null. Bukan error,
      // bukan titik di nol - grafiknya memang tidak bisa digambar.
      await tester.pumpWidget(
        _bungkus(
          GrowthLineChart(
            metrikAktif: GrowthMetric.bmiForAge,
            series: _deret(const [
              GrowthPoint(
                date: '2026-09-24',
                ageInMonths: 30,
                weightKg: 12.4,
              ),
            ]),
            whoBands: _tigaPita,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets('metrik tanpa entri pita digambar tanpa pita', (tester) async {
      // Kalau server tidak mengirim pita untuk metrik aktif (misalnya klien
      // lama), garis anak tetap digambar tanpa area abu-abu.
      await tester.pumpWidget(
        _bungkus(
          GrowthLineChart(
            metrikAktif: GrowthMetric.bmiForAge,
            series: _deret(const [
              GrowthPoint(
                date: '2026-09-24',
                ageInMonths: 30,
                bmi: 16.01,
              ),
            ]),
            whoBands: const [_pitaBerat],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final data = _lineChart(tester).data;
      expect(data.betweenBarsData, isEmpty);
      expect(data.lineBarsData[3].spots.length, 1);
    });

    testWidgets('pita tidak lengkap tetap digambar apa adanya', (tester) async {
      // Sumbu x boleh lebih sempit dari 0-60 bulan, dan pita yang hanya punya
      // sebagian titik tetap digambar. Yang tidak boleh terjadi adalah
      // melebar atau menyempitkan pita untuk mengisinya.
      await tester.pumpWidget(
        _bungkus(
          GrowthLineChart(
            series: _deret(const [
              GrowthPoint(
                date: '2026-09-24',
                ageInMonths: 30,
                weightKg: 12.4,
                heightCm: 88.0,
              ),
            ]),
            whoBands: _tigaPita,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final data = _lineChart(tester).data;

      // 30 bulan = 2,5 tahun, dan sumbu x mengikuti umur anak, bukan rentang
      // pita. Kalau pita yang menentukan, anak 2,5 tahun mendapat kanvas
      // 0-60 bulan dan garisnya jadi titik kecil di tepi.
      expect(data.maxX, lessThan(5.0));
      expect(data.lineBarsData[0].spots.last.x, 2.5);
    });
  });

  // -------------------------------------------------------------------
  // Bentuk layar ponsel sungguhan.
  //
  // Test di atas memakai kanvas 400x320 yang longgar. Layar ponsel sempit
  // (360 dp) dan tinggi, jadi ruang untuk label sumbu y jauh lebih sedikit -
  // di situlah `RenderFlex` paling sering overflow. Test ini memakai ukuran dan
  // data yang persis seperti hasil server untuk anak usia 3 tahun lebih: pita
  // 61 bulan penuh dan enam titik.
  // -------------------------------------------------------------------
  group('Grafik tumbuh di ukuran layar ponsel', () {
    /// 1080x2400 piksel dengan density 3.0 = 360x800 dp, ukuran ponsel biasa.
    void jadiPonsel(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() => tester.view.reset());
    }

    /// Pita WHO 0-60 bulan penuh, seperti yang dikirim server.
    final pitaPenuh = WhoBandReference(
      metric: 'weight_for_age',
      label: 'BB/U',
      unit: 'kg',
      source: 'WHO Child Growth Standards 2006',
      gender: 'P',
      ageFrom: 0,
      ageTo: 60,
      points: List.generate(
        61,
        (i) => WhoBandPoint(
          ageInMonths: i,
          // Median dan batas cukup untuk menguji tata letak - bukan angka acuan
          // yang dipakai di produksi, dan tidak disimpan di mana pun.
          median: 3.3 + 0.16 * i + 0.0025 * i * i,
          lower: 2.4 + 0.13 * i + 0.0018 * i * i,
          upper: 4.2 + 0.19 * i + 0.0032 * i * i,
        ),
      ),
    );

    testWidgets('enam titik dan pita 61 bulan muat di 360 dp', (tester) async {
      jadiPonsel(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: GrowthLineChart(
                series: _deret(const [
                  GrowthPoint(
                    date: '2026-05-20',
                    ageInMonths: 35,
                    weightKg: 12.5,
                    heightCm: 88.0,
                    zScoreWfa: -0.86,
                    statusGizi: 'Normal',
                  ),
                  GrowthPoint(
                    date: '2026-06-20',
                    ageInMonths: 36,
                    weightKg: 13.0,
                    heightCm: 89.0,
                    zScoreWfa: -0.64,
                    statusGizi: 'Normal',
                  ),
                  GrowthPoint(
                    date: '2026-07-20',
                    ageInMonths: 37,
                    weightKg: 13.4,
                    heightCm: 90.0,
                    zScoreWfa: -0.43,
                    statusGizi: 'Normal',
                  ),
                  GrowthPoint(
                    date: '2026-08-20',
                    ageInMonths: 38,
                    weightKg: 13.9,
                    heightCm: 91.0,
                    zScoreWfa: -0.20,
                    statusGizi: 'Normal',
                  ),
                  GrowthPoint(
                    date: '2026-09-20',
                    ageInMonths: 39,
                    weightKg: 14.3,
                    heightCm: 92.0,
                    zScoreWfa: -0.07,
                    statusGizi: 'Normal',
                  ),
                  GrowthPoint(
                    date: '2026-10-02',
                    ageInMonths: 39,
                    weightKg: 14.6,
                    heightCm: 93.0,
                    zScoreWfa: 0.13,
                    statusGizi: 'Normal',
                  ),
                ]),
                whoBands: [pitaPenuh],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Overflow di Flutter dilempar sebagai exception dan tertangkap di sini,
      // jadi satu assert ini menutup semua kemungkinan "grafik meluber" tanpa
      // perlu menghitung piksel.
      expect(tester.takeException(), isNull);
      expect(find.byType(LineChart), findsOneWidget);

      // Pita benar-benar terpasang di 61 bulan, bukan satu titik seperti di
      // test lain - kalau `_rentangUmur` memakai pita, kanvas anak jadi 0-60
      // bulan dan garisnya menghilang di tepi.
      final data = _lineChart(tester).data;
      expect(data.betweenBarsData, isNotEmpty);
      expect(
        data.lineBarsData.map((bar) => bar.spots.length),
        containsAll([61, 6]),
      );
      expect(data.maxX, lessThan(6.0));
    });

    testWidgets(
      'satu titik dengan angka ekstrem tidak meluber di layar sempit',
      (tester) async {
        // Yang diuji: satu titik dengan angka besar tidak membuat label sumbu
        // atau kanvas meluber di 360 dp.
        jadiPonsel(tester);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(12),
                child: GrowthLineChart(
                  series: _deret(const [
                    GrowthPoint(
                      date: '2026-09-20',
                      ageInMonths: 39,
                      weightKg: 21.4,
                      heightCm: 104.0,
                    ),
                  ]),
                  whoBands: [pitaPenuh],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });
}
