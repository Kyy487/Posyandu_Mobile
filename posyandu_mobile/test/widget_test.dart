// Widget test dasar: memastikan aplikasi bisa dibangun dan menampilkan
// layar login tanpa error.
//
// Catatan: `flutter_secure_storage` memakai platform channel, sehingga
// `pumpWidget(const MyApp())` di sini TIDAK memanggil storage. Semua parser
// JSON diuji terpisah di `kontrak_api_test.dart` memakai data asli dari API.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:posyandu_mobile/main.dart';

void main() {
  testWidgets('aplikasi menampilkan layar login', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Judul aplikasi harus tampil.
    expect(find.text('Smart Posyandu'), findsWidgets);

    // Tidak ada error_exception yang tertangkap saat build pertama.
    expect(tester.takeException(), isNull);
  });

  testWidgets('MaterialApp punya title yang benar', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'Smart Posyandu');
  });
}
