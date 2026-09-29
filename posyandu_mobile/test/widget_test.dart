// Widget test untuk layar autentikasi (login & register).
//
// Yang diuji di sini adalah perilaku interaktif yang ditambahkan saat redesign:
// tombol lihat password, penghitung digit NIK, indikator kekuatan password,
// section kode kader yang bisa dilipat, banner error, dan tombol reset.
//
// Catatan: `flutter_secure_storage` memakai platform channel. Karena itu test
// ini mem-pump widget layar secara langsung, bukan lewat `MyApp()`, agar
// tidak menyentuh storage. Parser JSON diuji terpisah di kontrak_api_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:posyandu_mobile/screens/login_screen.dart';
import 'package:posyandu_mobile/screens/register_screen.dart';
import 'package:posyandu_mobile/theme/app_theme.dart';

Widget _bungkus(Widget layar) {
  return MaterialApp(theme: AppTheme.build(), home: layar);
}

/// Mencari field lewat `labelText` (dipakai di layar login).
Finder _byLabel(String label) => find.widgetWithText(TextFormField, label);

/// Mencari field lewat `hintText` (dipakai di layar register, yang labelnya
/// dirender sebagai `Text` terpisah di atas field).
Finder _byHint(String hint) => find.widgetWithText(TextFormField, hint);

TextFormField _field(WidgetTester tester, Finder finder) =>
    tester.widget<TextFormField>(finder);

String _teks(WidgetTester tester, Finder finder) =>
    _field(tester, finder).controller?.text ?? '';

/// `obscureText` tidak diekspos TextFormField, jadi dibaca dari EditableText
/// di dalamnya.
bool _obscure(WidgetTester tester, Finder finder) => tester
    .widget<EditableText>(
      find.descendant(of: finder, matching: find.byType(EditableText)),
    )
    .obscureText;

/// Memastikan widget terlihat sebelum ditekan (form register cukup panjang).
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('Layar login', () {
    testWidgets('menampilkan form dan tautan daftar', (tester) async {
      await tester.pumpWidget(_bungkus(const LoginScreen()));
      await tester.pumpAndSettle();

      expect(find.text('MASUK'), findsOneWidget);
      expect(find.text('Daftar di sini'), findsOneWidget);
      expect(_byLabel('NIK'), findsOneWidget);
      expect(_byLabel('Password'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('NIK hanya menerima angka dan dibatasi 16 digit', (
      tester,
    ) async {
      await tester.pumpWidget(_bungkus(const LoginScreen()));
      await tester.pumpAndSettle();

      // Huruf dan strip dibuang, digit dipotong pada 16.
      await tester.enterText(_byLabel('NIK'), '1111-2222-3333-444a5555');
      await tester.pumpAndSettle();

      expect(_teks(tester, _byLabel('NIK')), '1111222233334445');
      // Penghitung digit di suffix ikut berubah.
      expect(find.text('16/16'), findsOneWidget);
    });

    testWidgets('tombol mata menampilkan lalu menyembunyikan password', (
      tester,
    ) async {
      await tester.pumpWidget(_bungkus(const LoginScreen()));
      await tester.pumpAndSettle();

      expect(_obscure(tester, _byLabel('Password')), isTrue);

      await _tap(tester, find.byTooltip('Tampilkan password'));
      expect(_obscure(tester, _byLabel('Password')), isFalse);

      await _tap(tester, find.byTooltip('Sembunyikan password'));
      expect(_obscure(tester, _byLabel('Password')), isTrue);
    });

    testWidgets('NIK tidak valid ditolak lokal, tidak menyentuh server', (
      tester,
    ) async {
      await tester.pumpWidget(_bungkus(const LoginScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(_byLabel('NIK'), '123');
      await tester.enterText(_byLabel('Password'), 'Rahasia123');
      await _tap(tester, find.text('MASUK'));

      expect(find.text('NIK harus 16 digit angka'), findsOneWidget);
      // Bukan banner error dari server, dan tetap di layar login.
      expect(find.byType(AuthBanner), findsNothing);
      expect(find.text('MASUK'), findsOneWidget);
    });

    testWidgets('password kosong ditolak lokal', (tester) async {
      await tester.pumpWidget(_bungkus(const LoginScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(_byLabel('NIK'), '1111222233334445');
      await _tap(tester, find.text('MASUK'));

      expect(find.text('Password tidak boleh kosong'), findsOneWidget);
    });
  });

  group('Layar register', () {
    testWidgets('form menampilkan keempat field utama', (tester) async {
      await tester.pumpWidget(_bungkus(const RegisterScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Daftar Akun Baru'), findsOneWidget);
      expect(_byHint('Contoh: Siti Aminah'), findsOneWidget);
      expect(_byHint('16 digit angka'), findsOneWidget);
      expect(_byHint('Minimal 8 karakter'), findsOneWidget);
      expect(_byHint('Ketik ulang password'), findsOneWidget);
    });

    testWidgets('section kode kader tersembunyi sampai diketuk', (
      tester,
    ) async {
      await tester.pumpWidget(_bungkus(const RegisterScreen()));
      await tester.pumpAndSettle();

      // Ibu tidak perlu melihat field kode kader.
      expect(find.byType(TextFormField), findsNWidgets(4));
      expect(_byHint('Kode kader'), findsNothing);

      await _tap(tester, find.text('Saya petugas posyandu'));

      expect(find.byType(TextFormField), findsNWidgets(5));
      expect(_byHint('Kode kader'), findsOneWidget);

      // Ketuk lagi -> menutup kembali.
      await _tap(tester, find.text('Saya petugas posyandu'));
      expect(find.byType(TextFormField), findsNWidgets(4));
    });

    testWidgets('indikator kekuatan password berubah realtime', (tester) async {
      await tester.pumpWidget(_bungkus(const RegisterScreen()));
      await tester.pumpAndSettle();

      // Belum ada password -> tidak ada indikator.
      expect(find.textContaining('Lemah'), findsNothing);

      await tester.enterText(_byHint('Minimal 8 karakter'), 'abc');
      await tester.pumpAndSettle();
      expect(find.textContaining('Lemah'), findsOneWidget);

      await tester.enterText(_byHint('Minimal 8 karakter'), 'Rahasia123456!');
      await tester.pumpAndSettle();
      expect(find.text('Kuat'), findsOneWidget);
      expect(find.textContaining('Lemah'), findsNothing);
    });

    testWidgets('konfirmasi password tidak cocok ditolak lokal', (
      tester,
    ) async {
      await tester.pumpWidget(_bungkus(const RegisterScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(_byHint('Minimal 8 karakter'), 'Rahasia123');
      await tester.enterText(_byHint('Ketik ulang password'), 'Rahasia124');
      await _tap(tester, find.text('DAFTAR'));

      expect(find.text('Konfirmasi password tidak cocok'), findsOneWidget);
      expect(find.byType(AuthBanner), findsNothing);
    });

    testWidgets('NIK kurang dari 16 digit ditolak lokal', (tester) async {
      await tester.pumpWidget(_bungkus(const RegisterScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(_byHint('Contoh: Siti Aminah'), 'Siti Aminah');
      await tester.enterText(_byHint('16 digit angka'), '12345');
      await tester.enterText(_byHint('Minimal 8 karakter'), 'Rahasia123');
      await tester.enterText(_byHint('Ketik ulang password'), 'Rahasia123');
      await _tap(tester, find.text('DAFTAR'));

      expect(find.text('NIK harus 16 digit angka'), findsOneWidget);
    });

    testWidgets('tombol reset mengosongkan form', (tester) async {
      await tester.pumpWidget(_bungkus(const RegisterScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(_byHint('Contoh: Siti Aminah'), 'Siti Aminah');
      await tester.enterText(_byHint('16 digit angka'), '1111222233334445');
      await _tap(tester, find.byTooltip('Kosongkan form'));

      expect(_teks(tester, _byHint('Contoh: Siti Aminah')), isEmpty);
      expect(_teks(tester, _byHint('16 digit angka')), isEmpty);
    });
  });
}
