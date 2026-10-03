// Widget test untuk grafik tumbuh kembang (Opsi D).
//
// Yang diuji di sini adalah apa yang tidak terlihat di `kontrak_api_test.dart`:
// apakah `GrowthLineChart` benar-benar bisa dirender pada tiga kasus tepi
// (satu titik, beberapa titik, dan `points: []`), dan apakah pita WHO diisi
// antara dua garis yang benar.
//
// Parser JSON diuji terpisah di kontrak_api_test.dart. Test ini sengaja
// tidak memanggil HTTP apa pun - `GrafikTumbuscreen` bergantung pada
// `GrowthChartService` yang butuh `flutter_secure_storage`, jadi hanya widget
// grafik yang dim-pump langsung.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:posyandu_mobile/models/growth_chart.dart';
import 'package:posyandu_mobile/widgets/growth_line_chart.dart';

/// Pita WHO seadanya: satu titik sudah cukup untuk memeriksa pasangan indeks
/// `betweenBarsData`, dan tidak perlu 61 baris untuk itu.
const WhoReference _pita = WhoReference(
  metric: 'weight_for_age',
  source: 'WHO Child Growth Standards 2006',
  gender: 'P',
  ageFrom: 0,
  ageTo: 60,
  points: [
    WhoReferencePoint(
      ageInMonths: 30,
      medianKg: 13.3,
      lowerKg: 11.2,
      upperKg: 15.7,
    ),
  ],
);

/// Deret penimbangan dengan satuan dan arah urut yang sama seperti server.
GrowthSeries _deret(List<GrowthPoint> points) {
  return GrowthSeries(
    weightUnit: 'kg',
    heightUnit: 'cm',
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
            whoReference: const WhoReference(metric: 'weight_for_age'),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets('tiga titik ter-render dan pitsanya terisi', (tester) async {
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
            whoReference: _pita,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final data = _lineChart(tester).data;

      // Urutan baris dikunci di bagian atas growth_line_chart.dart: dua batas
      // pita, median, berat, tinggi. Kalau berubah, pita akan terisi antara
      // garis yang salah.
      expect(data.lineBarsData.length, jumlahBarisGrafik);
      expect(data.betweenBarsData.length, 1);
      expect(data.betweenBarsData.first.fromIndex, 0);
      expect(data.betweenBarsData.first.toIndex, 1);

      // Pita adalah area antara batas bawah dan batas atas, jadi keduanya
      // harus benar-benar punya titik. Placeholder kosong akan menghasilkan
      // pita yang terlihat benar padahal tidak ada.
      expect(data.lineBarsData[0].spots.length, 1);
      expect(data.lineBarsData[1].spots.length, 1);
      expect(data.lineBarsData[2].spots.length, 1);

      // Baris terakhir: berat dan tinggi. Keduanya harus punya tiga titik
      // dan tidak boleh ada titik yang di-drop karena null.
      expect(data.lineBarsData[3].spots.length, 3);
      expect(data.lineBarsData[4].spots.length, 3);
    });

    testWidgets('points kosong tidak crash dan tidak menggambar apa pun', (
      tester,
    ) async {
      // `points: []` adalah jawaban yang benar untuk anak yang belum pernah
      // ditimbang, jadi widget harus turun diam-diam, bukan melempar error.
      await tester.pumpWidget(
        _bungkus(
          GrowthLineChart(series: _deret(const []), whoReference: _pita),
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
            whoReference: const WhoReference(metric: 'weight_for_age'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final data = _lineChart(tester).data;

      // Dua baris placeholder supaya indeks berat dan tinggi tidak bergeser,
      // tapi tidak ada `betweenBarsData` yang mengisinya.
      expect(data.lineBarsData.length, jumlahBarisGrafik);
      expect(data.betweenBarsData, isEmpty);
      expect(data.lineBarsData[0].spots, isEmpty);
      expect(data.lineBarsData[1].spots, isEmpty);
      expect(data.lineBarsData[3].spots.length, 1);
      expect(data.lineBarsData[4].spots.length, 1);
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
            whoReference: _pita,
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
      expect(data.lineBarsData[4].spots.length, 2);
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
            whoReference: _pita,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final data = _lineChart(tester).data;
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
            whoReference: _pita,
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
      expect(data.lineBarsData[0].spots.first.x, 2.5);
    });
  });

  // -------------------------------------------------------------------
  // Bentuk layar ponsel sungguhan.
  //
  // Test di atas memakai kanvas 400x320 yang longgar. Layar ponsel sempit
  // (360 dp) dan tinggi, jadi ruang untuk label sumbu y dan tinggi badan jauh
  // lebih sedikit - di situlah `RenderFlex` paling sering overflow. Test ini
  // memakai ukuran dan data yang persis seperti hasil server untuk anak aged
  // 3 tahun lebih: pita 61 bulan penuh dan enam titik yang semuanya berada di
  // rentang 34-39 bulan.
  // -------------------------------------------------------------------
  group('Grafik tumbuh di ukuran layar ponsel', () {
    /// 1080x2400 piksel dengan density 3.0 = 360x800 dp, ukuran ponsel biasa.
    void jadiPonsel(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() => tester.view.reset());
    }

    /// Pita WHO 0-60 bulan penuh, seperti yang dikirim server.
    final pitaPenuh = WhoReference(
      metric: 'weight_for_age',
      source: 'WHO Child Growth Standards 2006',
      gender: 'P',
      ageFrom: 0,
      ageTo: 60,
      points: List.generate(
        61,
        (i) => WhoReferencePoint(
          ageInMonths: i,
          // Median dan SD cukup untuk menguji tata letak - bukan angka acuan yang
          // dipakai di produksi, dan tidak disimpan di mana pun.
          medianKg: 3.3 + 0.16 * i + 0.0025 * i * i,
          lowerKg: 2.4 + 0.13 * i + 0.0018 * i * i,
          upperKg: 4.2 + 0.19 * i + 0.0032 * i * i,
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
                whoReference: pitaPenuh,
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
      //
      // `lineBarsData` memuat DUA garis: pita WHO (61 titik) dan garis anak.
      // Yang diperiksa hanya jumlah titiknya, bukan urutannya, karena urutan
      // itu detail internal `GrowthLineChart` dan tidak penting untuk kontrak.
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
                  whoReference: pitaPenuh,
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
