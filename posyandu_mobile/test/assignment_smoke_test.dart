import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:posyandu_mobile/screens/assignment/assignment_dashboard_screen.dart';
import 'package:posyandu_mobile/screens/assignment/kalkulator_screen.dart';
import 'package:posyandu_mobile/theme/app_theme.dart';

Widget _bungkus(Widget layar) {
  return MaterialApp(theme: AppTheme.kader(), home: layar);
}

Finder _display(String value) {
  return find.descendant(
    of: find.byType(FittedBox),
    matching: find.text(value),
  );
}

void main() {
  testWidgets('Dashboard tugas menampilkan lima menu', (tester) async {
    await tester.pumpWidget(_bungkus(const AssignmentDashboardScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Biodata'), findsWidgets);
    expect(find.text('Kontak'), findsOneWidget);
    expect(find.text('Kalkulator'), findsOneWidget);
    expect(find.text('Cuaca'), findsOneWidget);
    expect(find.text('Berita'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Semua tab dashboard dapat dibuka', (tester) async {
    await tester.pumpWidget(_bungkus(const AssignmentDashboardScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.contacts_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Kontak Posyandu'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.calculate_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Kalkulator Sederhana'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.cloud_outlined));
    await tester.pump(const Duration(milliseconds: 650));
    expect(find.text('Bandung, Jawa Barat'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.article_outlined));
    await tester.pump(const Duration(milliseconds: 650));
    expect(find.text('Berita Posyandu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kalkulator menghitung tambah, kuadrat, dan akar', (
    tester,
  ) async {
    await tester.pumpWidget(_bungkus(const KalkulatorScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('7'));
    await tester.tap(find.text('+'));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('='));
    await tester.pump();
    expect(_display('9'), findsOneWidget);

    await tester.tap(find.text('C'));
    await tester.tap(find.text('5'));
    await tester.tap(find.text('x²'));
    await tester.pump();
    expect(_display('25'), findsOneWidget);

    await tester.tap(find.text('C'));
    await tester.tap(find.text('9'));
    await tester.tap(find.text('√'));
    await tester.pump();
    expect(_display('3'), findsOneWidget);
  });
}
