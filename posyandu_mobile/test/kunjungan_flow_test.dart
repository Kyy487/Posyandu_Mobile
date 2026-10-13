// Test untuk alur "buat kunjungan → input data → selesai".
//
// Alur ini menyambung `KunjunganScreen` ke empat layar input lewat satu utas:
// id kunjungan yang baru dibuat. Yang paling mudah rusak dan paling mahal
// diam-diam adalah utas itu putus - layar input terbuka tanpa membawa
// kunjungan, datanya tersimpan lepas, dan kader baru sadar belakangan saat
// rekap kunjungan kosong.
//
// Karena itu yang diikat di sini ada dua:
//
//  1. Setiap layar input benar-benar MENERIMA id kunjungan lewat
//     konstruktornya. Ini kontrak yang dipakai `KunjunganScreen._bukaInput`;
//     kalau nama field berubah, test ini gagal sebelum aplikasinya.
//  2. Banner "menempel pada kunjungan" muncul hanya saat kunjungan dikirim.
//     Banner yang selalu tampil sama menyesatkannya dengan banner yang tidak
//     pernah tampil.
//
// Yang TIDAK diuji di sini: perjalanan HTTP-nya. Tiga layar input memuat data
// di `initState` dan tanpa server test berakhir di state gagal; itu sudah
// ditangani pola yang sama di `grafik_tumbuh_kader_test.dart`. Yang bisa
// diperiksa tanpa jaringan justru utas datanya - apakah id kunjungan benar
// sampai ke layar - dan itulah fokus file ini.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:posyandu_mobile/screens/kader/catatan_keluhan_screen.dart';
import 'package:posyandu_mobile/screens/kader/imunisasi_screen.dart';
import 'package:posyandu_mobile/screens/kader/input_penimbangan_screen.dart';
import 'package:posyandu_mobile/screens/kader/kunjungan_screen.dart';
import 'package:posyandu_mobile/screens/kader/rujukan_screen.dart';

void main() {
  group('Layar input menerima id kunjungan', () {
    // Field-field ini publik supaya `KunjunganScreen` bisa mengisinya. Test
    // memanggilnya langsung - bukan lewat UI - karena itu persis cara alur
    // memakainya.
    test('KunjunganScreen membawa childId dan childName', () {
      const layar = KunjunganScreen(childId: 'anak-1', childName: 'Naya');

      expect(layar.childId, 'anak-1');
      expect(layar.childName, 'Naya');
    });

    test('InputPenimbanganScreen membawa visitId dan visitLabel', () {
      const layar = InputPenimbanganScreen(
        childId: 'anak-1',
        visitId: 'kunjungan-1',
        visitLabel: '13 Oktober 2026 · Posyandu',
      );

      expect(layar.visitId, 'kunjungan-1');
      expect(layar.visitLabel, '13 Oktober 2026 · Posyandu');
    });

    test('ImunisasiScreen membawa visitId dan visitLabel', () {
      const layar = ImunisasiScreen(
        childId: 'anak-1',
        childName: 'Naya',
        visitId: 'kunjungan-1',
        visitLabel: '13 Oktober 2026 · Posyandu',
      );

      expect(layar.visitId, 'kunjungan-1');
      expect(layar.visitLabel, '13 Oktober 2026 · Posyandu');
    });

    test('CatatanKeluhanScreen membawa visitId dan visitLabel', () {
      const layar = CatatanKeluhanScreen(
        childId: 'anak-1',
        childName: 'Naya',
        visitId: 'kunjungan-1',
        visitLabel: '13 Oktober 2026 · Posyandu',
      );

      expect(layar.visitId, 'kunjungan-1');
      expect(layar.visitLabel, '13 Oktober 2026 · Posyandu');
    });

    test('RujukanScreen membawa initialVisitId untuk pra-pilih', () {
      // Berbeda dari tiga layar lain: rujukan WAJIB punya kunjungan, jadi
      // yang dibawa bukan "kunjungan baru menempel" melainkan "kunjungan ini
      // yang sudah dipilih di form".
      const layar = RujukanScreen(
        childId: 'anak-1',
        childName: 'Naya',
        initialVisitId: 'kunjungan-1',
      );

      expect(layar.initialVisitId, 'kunjungan-1');
    });

    test('visitId opsional - layar tetap bisa dibuka tanpa kunjungan', () {
      // Kader masih bisa menimbang tanpa membuat kunjungan lebih dulu; itu
      // jalan lama yang tidak boleh ikut rusak.
      const layar = InputPenimbanganScreen(childId: 'anak-1');

      expect(layar.visitId, isNull);
      expect(layar.visitLabel, isNull);
    });
  });

  group('Banner kunjungan di layar penimbangan', () {
    // `InputPenimbanganScreen` tidak memuat apa pun di `initState`, jadi
    // banner-nya bisa diperiksa tanpa memalsukan server - satu-satunya dari
    // empat layar yang bisa begitu.
    testWidgets('tampil saat kunjungan dikirim', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: InputPenimbanganScreen(
            childId: 'anak-1',
            visitId: 'kunjungan-1',
            visitLabel: '13 Oktober 2026 · Posyandu',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Menempel pada kunjungan'), findsOneWidget);
      expect(find.text('13 Oktober 2026 · Posyandu'), findsOneWidget);
    });

    testWidgets('tidak tampil saat kunjungan tidak dikirim', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: InputPenimbanganScreen(childId: 'anak-1')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Menempel pada kunjungan'), findsNothing);
      // Jalan lama: tanggal penimbangan tetap bisa diisi.
      expect(find.text('Tanggal Penimbangan'), findsOneWidget);
    });
  });
}
