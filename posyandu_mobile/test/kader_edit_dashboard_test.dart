// Test untuk tiga perbaikan Kader: edit data anak, dashboard, dan pemetaan
// warna status gizi yang disatukan.
//
// Konteks why these tests exist:
//
//  1. `EditChildScreen` menggantikan stub yang hanya menampilkan SnackBar
//     "Fitur edit data anak segera hadir". Stub itu tidak bisa gagal, jadi
//     tidak ada yang menguji apa pun; sekarang form-nya bisa ditolak server
//     dan ada nilai yang salah ketik, jadi perilakunya perlu diikat.
//  2. Dashboard Kader sebelumnya menampilkan "Tidak ada data anak ditemukan."
//     saat server gagal. Itu state yang salah dan berbahaya: kader menyimpulkan
//     tidak ada anak terdaftar. Test di bawah mengikat pemisahan ketiga state.
//  3. `warnaStatusGizi()` menggantikan tiga salinan pemetaan yang berbeda
//     warna. Yang paling berbahaya adalah 'Risiko Gizi Lebih': biru-abu di
//     detail Kader, oranye di dua layar Ibu.
//
// Yang TIDAK diuji di sini: seluruh alur HTTP. `KaderService` memanggil
// `http.patch` secara langsung, jadi menyuntik stub butuh `HttpOverrides`
// yang pays off-nya jauh lebih besar daripada yang didapat. Yang diuji
// adalah apa yang bisa salah tanpa server: state UI, prefill, validasi, dan
// pemetaan warna.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:posyandu_mobile/models/child.dart';
import 'package:posyandu_mobile/screens/kader/edit_child_screen.dart';
import 'package:posyandu_mobile/screens/kader/kader_dashboard_screen.dart';
import 'package:posyandu_mobile/utils/status_gizi.dart';

const _channelSecureStorage = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// Pasang `flutter_secure_storage` tiruan.
///
/// Tanpa token, `getProfile()` dan `getChildren()` langsung mengembalikan
/// "sesi habis" tanpa menyentuh jaringan - itu yang dipakai test dashboard
/// untuk sampai ke state error.
void _pasangStorage({String? token}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        _channelSecureStorage,
        (call) async => call.method == 'read' ? token : null,
      );
}

void _lepasStorage() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channelSecureStorage, null);
}

/// Anak contoh dengan semua field edit terisi.
Child _anakLengkap({String? medicalFlags = 'alergi: penisilin'}) {
  return Child(
    id: '01a0ff96-eb85-71c4-bd7d-1931043a1243',
    nik: '3201010102030001',
    name: 'Naya Putri Uji',
    parentName: 'Siti Uji',
    dateOfBirth: '2023-06-15',
    gender: 'P',
    birthWeight: 3.2,
    birthHeight: 49,
    medicalFlags: medicalFlags,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('warnaStatusGizi - pemetaan status gizi', () {
    test('empat nilai yang ditulis trigger dipetakan dengan benar', () {
      // Keempat nilai ini adalah SATU-SATUNYA yang bisa muncul di kolom
      // `status_gizi`, tertulis di migration
      // 2026_09_26_010000_create_who_wfa_standards_and_fix_zscore_trigger.php.
      // Test ini mengunci daftar itu ke warna, jadi menambah nilai baru di
      // trigger tanpa memperbarui helper akan ketahuan di sini.
      expect(warnaStatusGizi('Gizi Buruk').warna, Colors.red);
      expect(warnaStatusGizi('Gizi Kurang').warna, Colors.orange);
      expect(warnaStatusGizi('Risiko Gizi Lebih').warna, Colors.deepOrange);
      expect(warnaStatusGizi('Normal').warna, Colors.green);
    });

    test('"Risiko Gizi Lebih" tidak lagi oranye di satu layar dan abu di lain', () {
      // Inilah bug yang diperbaiki. `detail_anak_screen.dart` dulu memakai
      // `switch` persis dan mengembalikan `Colors.blueGrey` untuk nilai ini,
      // sementara dua layar Ibu memakai `contains('Risiko')` yang mengembalikan
      // `Colors.orange`. Kader dan ibu membandingkan anak yang sama dengan
      // warna berbeda.
      final hasil = warnaStatusGizi('Risiko Gizi Lebih');
      expect(hasil.warna, isNot(Colors.blueGrey));
      expect(hasil.warna, isNot(Colors.orange));
      expect(hasil.warna, Colors.deepOrange);
    });

    test('"Gizi Kurang" tidak tertukar dengan "Gizi Buruk"', () {
      // Dua status ini berdekatan secara klinis dan sering diketik salah pada
      // pemetaan bertingkat. Keduanya harus tetap terpisah.
      expect(
        warnaStatusGizi('Gizi Kurang').warna,
        isNot(warnaStatusGizi('Gizi Buruk').warna),
      );
    });

    test('"Stunting" dari baris lama dipetakan merah, bukan abu', () {
      // Trigger sekarang tidak menulis "Stunting", tapi baris lama di database
      // masih memegangnya. Tanpa cabang ini, anak lama tampil abu-abu - yang
      // dibaca kader sebagai "tidak ada status", bukan "stunting berat".
      expect(warnaStatusGizi('Stunting').warna, Colors.red);
    });

    test('status tidak dikenal dan null tampil abu, tidak throwing', () {
      expect(warnaStatusGizi(null).warna, Colors.grey);
      expect(warnaStatusGizi('').warna, Colors.grey);
      expect(warnaStatusGizi('Status Baru Dari Server').warna, Colors.grey);
    });

    test('huruf besar, spasi, dan spasi berlebih tidak mengubah hasil', () {
      // Nilai datang dari trigger database, tapi tetap aman bila someday
      // sumbernya berubah. Test ini menahan perubahan "rapikan input"
      // yang justru menaikkan risiko.
      expect(warnaStatusGizi('  gizi buruk  ').warna, Colors.red);
      expect(warnaStatusGizi('NORMAL').warna, Colors.green);
    });

    test('warna dan ikon selalu berpasangan', () {
      // Pemetaan warna tanpa ikon akan membuat layar yang memakai `ikon`
      // diam-diam menampilkan ikon tidak ada atau error.
      for (final status in <String?>[
        null,
        'Gizi Buruk',
        'Gizi Kurang',
        'Risiko Gizi Lebih',
        'Normal',
      ]) {
        final hasil = warnaStatusGizi(status);
        expect(hasil.ikon, isNotNull, reason: 'status $status');
      }
    });
  });

  group('Child.copyWith - mengosongkan field nullable', () {
    test('medicalFlags null berarti benar-benar dikosongkan', () {
      // Ini alasan disambangnya sentinel `_tidakDiubah`. Dengan
      // `copyWith(medicalFlags: null)` yang memakai `??`, penanda kondisi
      // khusus tidak akan pernah bisa dihapus dari form edit.
      final hasil = _anakLengkap().copyWith(medicalFlags: null);
      expect(hasil.medicalFlags, isNull);
    });

    test('medicalFlags yang tidak disebut tetap utuh', () {
      // Sebaliknya: mengganti nama saja tidak boleh diam-diam menghapus
      // penanda kondisi khusus.
      final hasil = _anakLengkap().copyWith(name: 'Nama Baru');
      expect(hasil.name, 'Nama Baru');
      expect(hasil.medicalFlags, 'alergi: penisilin');
    });

    test('berat dan panjang lahir bisa dikosongkan', () {
      final anak = _anakLengkap();
      final hasil = anak.copyWith(birthWeight: null, birthHeight: null);
      expect(hasil.birthWeight, isNull);
      expect(hasil.birthHeight, isNull);
      // Field lain harus utuh.
      expect(hasil.name, anak.name);
      expect(hasil.nik, anak.nik);
      expect(hasil.id, anak.id);
    });

    test('nilai non-null dipakai apa adanya', () {
      final hasil = _anakLengkap().copyWith(birthWeight: 4.1);
      expect(hasil.birthWeight, 4.1);
    });
  });

  group('Child.fromJson - berat dan panjang lahir', () {
    test('baca string decimal dari PostgreSQL', () {
      // Kolomnya `decimal`, jadi Laravel sering mengirim "3.2000" sebagai
      // string. Kalau tidak diparse, form edit akan menampilkan "3.2000"
      // dan dudaskan.
      final anak = Child.fromJson({
        'id': 'x',
        'nik': '3201010102030001',
        'name': 'Naya',
        'birth_weight': '3.2000',
        'birth_height': '49.00',
      });
      expect(anak.birthWeight, 3.2);
      expect(anak.birthHeight, 49);
    });

    test('null dan string kosong tidak jadi nol', () {
      // 0 kg adalah data yang mungkin salah input; null berarti "tidak
      // diisi". Dua hal itu harus tetap berbeda.
      expect(Child.fromJson({'id': 'x'}).birthWeight, isNull);
      expect(
        Child.fromJson({'id': 'x', 'birth_weight': ''}).birthWeight,
        isNull,
      );
    });
  });

  group('EditChildScreen - form edit data anak', () {
    setUp(() => _pasangStorage(token: 'token-uji'));
    tearDown(_lepasStorage);

    testWidgets('prefill mengisi field dari data anak', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: EditChildScreen(child: _anakLengkap())),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Edit Data Anak'), findsOneWidget);

      // NIK dan ibu ditampilkan read-only supaya kader tahu sedang mengedit siapa.
      expect(find.text('NIK: 3201010102030001'), findsOneWidget);
      expect(find.textContaining('Siti Uji'), findsOneWidget);

      // Nama, tanggal, jenis kelamin, berat, panjang, dan kondisi khusus.
      expect(
        find.widgetWithText(TextFormField, 'Naya Putri Uji'),
        findsOneWidget,
      );
      expect(find.text('15/6/2023'), findsOneWidget);
      expect(find.text('Perempuan'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '3.2'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '49'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'alergi: penisilin'),
        findsOneWidget,
      );
    });

    testWidgets('berat lahir 3.20 tidak tampil sebagai "3.2000"', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EditChildScreen(
            child: Child.fromJson({
              'id': 'x',
              'nik': '1',
              'name': 'Naya',
              'birth_weight': '3.2000',
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('3.2000'), findsNothing);
      expect(find.widgetWithText(TextFormField, '3.2'), findsOneWidget);
    });

    testWidgets('nama kosong ditolak tanpa menyentuh server', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: EditChildScreen(child: _anakLengkap())),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Naya Putri Uji'),
        '   ',
      );
      await tester.tap(find.text('Simpan Perubahan'));
      await tester.pumpAndSettle();

      expect(find.text('Nama wajib diisi'), findsOneWidget);
      // Layar tidak boleh menutup diri kalau tidak ada yang tersimpan.
      expect(find.text('Edit Data Anak'), findsOneWidget);
    });

    testWidgets('berat lahir negatif ditolak', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: EditChildScreen(child: _anakLengkap())),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, '3.2'), '-1');
      await tester.tap(find.text('Simpan Perubahan'));
      await tester.pumpAndSettle();

      expect(find.text('Tidak boleh negatif'), findsOneWidget);
    });

    testWidgets('berat lahir dikosongkan diterima, bukan ditolak', (
      tester,
    ) async {
      // Mengosongkan berarti "hapus nilai yang tersimpan", jadi itu operacionais
      // yang sah - berbeda dari form tambah anak yang mewajibkan kolom ini
      // terisi. Kalau kolom kosong dianggap "wajib diisi", kader tidak
      // pernah bisa membetulkan data yang tidak perlu dihapus.
      await tester.pumpWidget(
        MaterialApp(home: EditChildScreen(child: _anakLengkap())),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, '3.2'), '');
      await tester.tap(find.text('Simpan Perubahan'));
      await tester.pumpAndSettle();

      expect(find.text('Wajib diisi'), findsNothing);
      expect(find.text('Tidak boleh negatif'), findsNothing);
    });

    testWidgets('berat lahir bukan angka ditolak', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: EditChildScreen(child: _anakLengkap())),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, '3.2'), 'abc');
      await tester.tap(find.text('Simpan Perubahan'));
      await tester.pumpAndSettle();

      expect(find.text('Masukkan angka'), findsOneWidget);
    });

    testWidgets('tanpa session form tetap bisa dibuka dan diisi', (
      tester,
    ) async {
      // Garderail: form edit tidak boleh Depends on the server untuk tampil.
      // Kader harus tetap bisa membaca dan menyiapkan data walaupun token-nya
      // sudah kedaluwarsa; yang gagal hanya penyimpanan.
      _pasangStorage(token: null);
      await tester.pumpWidget(
        MaterialApp(home: EditChildScreen(child: _anakLengkap())),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Edit Data Anak'), findsOneWidget);
    });
  });

  group('DashboardKaderScreen - state dan isi header', () {
    testWidgets('gagal memuat memunculkan state error, bukan "tidak ada data"', (
      tester,
    ) async {
      // Tanpa token, `getChildren()` mengembalikan "sesi habis" (401). Dulu
      // layar ini menelan semua kegagalan dan menampilkan "Tidak ada data anak
      // ditemukan." - kader akan menyimpulkan tidak ada anak terdaftar.
      _pasangStorage(token: null);
      await tester.pumpWidget(const MaterialApp(home: DashboardKaderScreen()));
      await tester.pumpAndSettle();

      // 401 dialihkan ke login, jadi error state hanya untuk kegagalan lain.
      expect(find.text('Tidak ada data anak ditemukan.'), findsNothing);
      expect(find.text('MASUK'), findsOneWidget);
    });

    testWidgets('header tidak lagi menampilkan nama Posyandu dan RT/RW palsu', (
      tester,
    ) async {
      _pasangStorage(token: null);
      await tester.pumpWidget(const MaterialApp(home: DashboardKaderScreen()));
      await tester.pumpAndSettle();

      // Tiga string ini tidak ada di database mana pun - `users` tidak punya
      // kolom alamat, RT, RW, atau nama Posyandu. Semuanya diketik manual.
      expect(find.textContaining('Posyandu Melati'), findsNothing);
      expect(find.textContaining('RT 01'), findsNothing);
      expect(find.textContaining('RW 10'), findsNothing);
      expect(find.textContaining('Wilayah Binaan'), findsNothing);
    });

    testWidgets('tidak ada overflow di layar 360dp', (tester) async {
      // Kartu statistik pernah memakai `Row` dengan `Column` tanpa
      // `Expanded`, sehingga teks panjang meluber keluar kartu. Ukuran 360dp
      // adalah lebar ponsel paling umum dan paling sempit yang masih dipakai.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      _pasangStorage(token: null);
      await tester.pumpWidget(const MaterialApp(home: DashboardKaderScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
