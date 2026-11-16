// Test fitur koreksi penimbangan (e-KMS) di sisi Flutter.
//
// Sejak `PATCH /kader/measurements/{id}` ditambahkan, layar penimbangan jadi
// dua mode dalam satu form: input baru dan koreksi. Yang harus dijaga di sini
// adalah dua hal yang paling mudah patah diam-diam:
//
//  1. Form koreksi harus TERISI nilai lama, bukan kosong - kader yang membuka
//     layar edit untuk memperbaiki 0,5 kg jangan sampai diminta mengetik ulang
//     seluruh data.
//  2. Label judul dan tombol harus membedakan kedua mode, supaya kader tidak
//     mengira sedang menambah penimbangan kedua pada tanggal yang sama.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:posyandu_mobile/models/measurement_model.dart';
import 'package:posyandu_mobile/screens/kader/kunjungan/input_penimbangan_screen.dart';

MeasurementModel _penimbangan({
  String id = 'm-1',
  String tanggal = '2026-08-01',
  double berat = 11.5,
  double tinggi = 84.0,
}) {
  return MeasurementModel(
    id: id,
    childId: 'anak-1',
    measurementDate: tanggal,
    weightKg: berat,
    heightCm: tinggi,
    ageInMonths: 31,
    zScoreWfa: -1.2,
    statusGizi: 'Normal',
  );
}

void main() {
  group('Konstruktor InputPenimbanganScreen', () {
    test('mode tambah: existing null dan kunjungan opsional tetap null', () {
      const layar = InputPenimbanganScreen(childId: 'anak-1');

      expect(layar.existing, isNull);
      expect(layar.visitId, isNull);
    });

    test('mode edit: membawa baris penimbangan yang akan dikoreksi', () {
      final layar = InputPenimbanganScreen(
        childId: 'anak-1',
        existing: _penimbangan(id: 'm-99'),
      );

      expect(layar.existing, isNotNull);
      expect(layar.existing!.id, 'm-99');
      expect(layar.existing!.weightKg, 11.5);
    });
  });

  group('Form koreksi terisi nilai lama', () {
    testWidgets('berat & tinggi lama terbaca di kolom isian', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InputPenimbanganScreen(childId: 'anak-1', existing: _penimbangan()),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(TextFormField, '11.5'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '84'), findsOneWidget);
    });

    testWidgets(
      'judul & tombol berbeda dari mode tambah supaya kader tidak salah sangka',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: InputPenimbanganScreen(
              childId: 'anak-1',
              existing: _penimbangan(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Edit Penimbangan'), findsOneWidget);
        expect(find.text('Simpan Perubahan'), findsOneWidget);
        // Mode edit tidak boleh menampilkan tombol input baru.
        expect(find.text('Simpan Data Penimbangan'), findsNothing);
      },
    );

    testWidgets(
      'mode tambah tetap memakai label lama (jalan lama tidak berubah)',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: InputPenimbanganScreen(childId: 'anak-1')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Input Penimbangan'), findsOneWidget);
        expect(find.text('Simpan Data Penimbangan'), findsOneWidget);
        expect(find.text('Edit Penimbangan'), findsNothing);
      },
    );

    testWidgets(
      'tanpa kunjungan, banner "menempel pada kunjungan" tidak muncul',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: InputPenimbanganScreen(
              childId: 'anak-1',
              existing: _penimbangan(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Menempel pada kunjungan'), findsNothing);
      },
    );
  });
}
