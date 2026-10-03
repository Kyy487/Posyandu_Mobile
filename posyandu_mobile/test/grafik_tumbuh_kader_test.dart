// Test untuk Fase 2 grafik tumbuh: layar Kader (Opsi D).
//
// Fase 1 sudah menguji parsing JSON (`kontrak_api_test.dart`) dan gambar grafik
// (`grafik_tumbuh_widget_test.dart`). Fase 2 tidak menambah keduanya - isinya
// identik untuk Ibu dan Kader. Yang diuji di sini justru hal yang baru:
//
//  1. Kedua palet benar-benar berbeda dan tidak tertukar. Kalau `kader` ikut
//     berubah jadi pink karena refactor, layar Kader akan terlihat seperti
//     layar Ibu dan tidak ada yang salah - hanya kelihatan keliru.
//  2. Kedua layar benar-benar bisa dipasang dan memakai paletnya masing-masing.
//     Ini butuh mock method channel `flutter_secure_storage`, karena
//     `GrowthChartService` membaca token saat `initState` dan tanpa token
//     layanan itu tidak pernah selesai.
//
// Yang TIDAK diuji di sini: isi grafik. Sudah ada di dua file lain, dan
// menyalinnya berarti satu daftar test yang bisa berbeda jauh lebih berbahaya
// daripada satu daftar yang lengkap.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:posyandu_mobile/screens/ibu/grafik_tumbuh_screen.dart' as ibu;
import 'package:posyandu_mobile/screens/kader/grafik_tumbuh_screen.dart'
    as kader;
import 'package:posyandu_mobile/widgets/growth_chart_view.dart';

/// Warna `Colors.blue[800]`, warna `AppBar` semua layar Kader yang sudah ada.
const _biru800 = Color(0xFF1565C0);

/// Warna `Colors.blue[100]`.
const _biru100 = Color(0xFFBBDEFB);

/// Warna `Colors.pink[400]`, warna `AppBar` semua layar Ibu.
const _pink400 = Color(0xFFE91E63);

/// Warna `Colors.pink[200]`.
const _pink200 = Color(0xFFF8BBD0);

const _channelSecureStorage = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// Pasang `flutter_secure_storage` tiruan.
///
/// [token] `null` berarti tidak ada sesi tersimpan, dan layar akan
/// mengarahkan ke login. String berarti ada sesi, sehingga layar benar-benar
/// mencoba memuat grafik - di lingkungan test tidak ada server, jadi hasilnya
/// state gagal, dan itu yang ingin diperiksa: kedua layar harus bisa mencapai
/// sana tanpa melempar exception.
void _pasangStorage({String? token = 'token-uji'}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        _channelSecureStorage,
        (call) async => call.method == 'read' ? token : null,
      );
}

/// Lepas lagi mock-nya supaya tidak bocor ke test lain.
void _lepasStorage() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channelSecureStorage, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Palet grafik tumbuh - GrowthChartPalette', () {
    test('kader dan ibu tidak boleh punya warna yang sama', () {
      // Dihitung per field, bukan hanya "objeknya beda": palet bisa jadi objek
      // berbeda padahal semua warnanya sama, dan itu tetap salah.
      expect(
        GrowthChartPalette.kader.appBar,
        isNot(GrowthChartPalette.ibu.appBar),
      );
      expect(
        GrowthChartPalette.kader.latar,
        isNot(GrowthChartPalette.ibu.latar),
      );
      expect(
        GrowthChartPalette.kader.aksen,
        isNot(GrowthChartPalette.ibu.aksen),
      );
      expect(
        GrowthChartPalette.kader.warnaTeksAksen,
        isNot(GrowthChartPalette.ibu.warnaTeksAksen),
      );
      expect(
        GrowthChartPalette.kader.warnaIkonKosong,
        isNot(GrowthChartPalette.ibu.warnaIkonKosong),
      );
    });

    test('palet kader memakai biru yang sama dengan layar Kader lain', () {
      // `detail_anak_screen.dart`, `kader_dashboard_screen.dart`, dan
      // `catatan_keluhan_screen.dart` semuanya memakai `Colors.blue[800]` untuk
      // AppBar. Grafik harus ikut warna itu, kalau tidak layar ini terlihat
      // seperti aplikasi yang berbeda.
      expect(GrowthChartPalette.kader.appBar, _biru800);
      expect(GrowthChartPalette.kader.warnaIkonKosong, _biru100);
    });

    test('palet ibu tetap pink seperti sebelum ekstraksi', () {
      // Nilai ini diambil dari `grafik_tumbuh_screen.dart` Fase 1. Kalau layar
      // Ibu berubah warna diam-diam karena ekstraksi ke `growth_chart_view.dart`,
      // test ini yang menangkapnya.
      expect(GrowthChartPalette.ibu.appBar, _pink400);
      expect(GrowthChartPalette.ibu.warnaIkonKosong, _pink200);
    });
  });

  group('Layar grafik tumbuh Ibu dan Kader', () {
    setUp(() => _pasangStorage());
    tearDown(_lepasStorage);

    testWidgets('layar Ibu bisa dipasang dan memakai palet pink', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ibu.GrafikTumbuhScreen(
            childId: 'a0000000-0000-4000-8000-000000000001',
            childName: 'Siti',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, GrowthChartPalette.ibu.appBar);
      expect(find.text('Grafik Tumbuh'), findsOneWidget);
    });

    testWidgets('layar Kader bisa dipasang dan memakai palet biru', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: kader.GrafikTumbuhScreen(
            childId: 'a0000000-0000-4000-8000-000000000002',
            childName: 'Budi',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, GrowthChartPalette.kader.appBar);
      expect(find.text('Grafik Tumbuh'), findsOneWidget);
    });

    testWidgets(
      'dengan sesi tapi server mati, kedua layar menampilkan state gagal',
      (tester) async {
        // Di lingkungan test tidak ada backend, jadi `http.get` gagal dan
        // `GrowthChartService` mengembalikan pesan offline. Yang diuji bukan
        // pesannya, tapi bahwa kedua layar bisa mencapai state gagal tanpa
        // melempar exception - ekstraksi ke `GrowthChartView` tidak boleh membuat
        // satu role meledak dan yang lain tidak.
        for (final layar in <Widget>[
          const ibu.GrafikTumbuhScreen(childId: 'x', childName: 'Siti'),
          const kader.GrafikTumbuhScreen(childId: 'x', childName: 'Budi'),
        ]) {
          await tester.pumpWidget(MaterialApp(home: layar));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('Gagal memuat grafik'), findsOneWidget);
          expect(
            find.widgetWithText(FilledButton, 'Coba Lagi'),
            findsOneWidget,
          );
        }
      },
    );
  });
}
