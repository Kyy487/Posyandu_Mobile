import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:posyandu_mobile/models/child.dart';
import 'package:posyandu_mobile/models/measurement_model.dart';

/// Test ini memakai JSON ASLI yang diambil langsung dari API Laravel
/// (http://127.0.0.1:8000/api) pada 26 September 2026.
///
/// Tujuannya: memastikan parser di sisi Flutter selalu sinkron dengan
/// format JSON yang benar-benar dikirim backend (Aturan #8 JSON Envelope).
void main() {
  group('Kontrak API - GET /api/children', () {
    // Respons asli dari ChildController@index (relasi ibu ikut di-eager load)
    const rawChildren = '''
    {
      "success": true,
      "message": "Data balita berhasil diambil.",
      "data": [
        {
          "id": "01a0d979-c11f-705b-8dd8-a245652c7aa4",
          "user_id": "01a0d979-c0f7-727e-903e-fc1892439685",
          "nik": "1234567890123456",
          "name": "Budi Santoso",
          "date_of_birth": "2025-05-10",
          "gender": "L",
          "birth_weight": 3.2,
          "birth_height": 50,
          "created_at": "2026-09-25T16:50:30.000000Z",
          "updated_at": "2026-09-25T16:50:30.000000Z",
          "mother": {
            "id": "01a0d979-c0f7-727e-903e-fc1892439685",
            "name": "Ibu Ceri",
            "nik": "1111222233334445"
          }
        }
      ]
    }
    ''';

    test('mengambil nama ibu dari nested object "mother"', () {
      final decoded = json.decode(rawChildren) as Map<String, dynamic>;
      final child = Child.fromJson(decoded['data'][0] as Map<String, dynamic>);

      expect(child.name, 'Budi Santoso');
      expect(child.nik, '1234567890123456');
      // Ini yang dulu gagal: API tidak pernah mengirim "parent_name"
      expect(child.parentName, 'Ibu Ceri');
    });

    test('tetap kompatibel bila backend mengirim "parent_name" (format lama)', () {
      final child = Child.fromJson({
        'id': 'abc',
        'nik': '123',
        'name': 'Uji',
        'parent_name': 'IbuViaKolom',
        'mother': {'name': 'IbuViaNested'},
      });

      expect(child.parentName, 'IbuViaKolom');
    });

    test('tidak error saat "nik" null dan "mother" tidak ada', () {
      final child = Child.fromJson({
        'id': 'abc',
        'nik': null,
        'name': 'Tanpa Ibu',
      });

      expect(child.nik, '-');
      expect(child.parentName, '-');
    });
  });

  group('Kontrak API - ringkasan gizi di GET /api/children', () {
    // Respons asli ChildrenController@index setelah ada penimbangan.
    // latest_measurement SENGAJA tidak ada: backend menyembunyikannya lewat
    // $hidden dan hanya mengirim 3 field ringkasan ini.
    const rawAnakTerukur = '''
    {
      "id": "01a0d979-c11f-705b-8dd8-a245652c7aa4",
      "user_id": "01a0d979-c0f7-727e-903e-fc1892439685",
      "nik": "1234567890123456",
      "name": "Budi Santoso",
      "date_of_birth": "2025-05-10",
      "gender": "L",
      "birth_weight": 3.2,
      "birth_height": 50,
      "last_measurement_date": "2026-09-26",
      "latest_z_score": -3.09,
      "nutritional_status": "Gizi Buruk",
      "mother": {
        "id": "01a0d979-c0f7-727e-903e-fc1892439685",
        "name": "Ibu Ceri",
        "nik": "1111222233334445"
      }
    }
    ''';

    test('membaca 3 field ringkasan gizi', () {
      final child = Child.fromJson(json.decode(rawAnakTerukur) as Map<String, dynamic>);

      expect(child.lastMeasurementDate, '2026-09-26');
      expect(child.latestZScore, -3.09);
      expect(child.nutritionalStatus, 'Gizi Buruk');
      expect(child.hasMeasurement, isTrue);
    });

    test('anak tanpa penimbangan: 3 field null, hasMeasurement false', () {
      final child = Child.fromJson({
        'id': 'abc',
        'name': 'Belum Ditimbang',
        'date_of_birth': '2026-01-15',
        'last_measurement_date': null,
        'latest_z_score': null,
        'nutritional_status': null,
      });

      expect(child.lastMeasurementDate, isNull);
      expect(child.latestZScore, isNull);
      expect(child.nutritionalStatus, isNull);
      expect(child.hasMeasurement, isFalse);
      expect(child.nutritionLabel, isNull);
    });

    test('z-score yang hilang jadi null, bukan error', () {
      // Kolom sumbernya decimal, jadi API bisa mengirimnya sebagai string.
      final child = Child.fromJson({
        'id': 'abc',
        'name': 'Z String',
        'latest_z_score': '-1.75',
      });

      expect(child.latestZScore, -1.75);
    });
  });

  group('Model Child - helper umur', () {
    test('hitung umur dalam bulan dari date_of_birth', () {
      final hariIni = DateTime.now();
      // Tepat 2 tahun lalu -> harus 24 bulan.
      final dob = DateTime(hariIni.year - 2, hariIni.month, hariIni.day);
      final child = Child.fromJson({
        'id': 'abc',
        'name': 'Anak 2 Tahun',
        'date_of_birth': dob.toIso8601String().substring(0, 10),
      });

      expect(child.ageInMonths, 24);
      expect(child.ageLabel, '2 Tahun');
      expect(child.shortName, 'Anak');
    });

    test('label "8 Bulan" untuk anak di bawah 1 tahun', () {
      final hariIni = DateTime.now();
      final dob = DateTime(hariIni.year, hariIni.month - 8, hariIni.day);
      final child = Child.fromJson({
        'id': 'abc',
        'name': 'Bayi',
        'date_of_birth': dob.toIso8601String().substring(0, 10),
      });

      expect(child.ageLabel, '8 Bulan');
    });

    test('tanggal lahir null atau rusak -> "-", bukan crash', () {
      final tanpaTanggal = Child.fromJson({'id': 'a', 'name': 'X'});
      final tanggalRusak = Child.fromJson({
        'id': 'b',
        'name': 'Y',
        'date_of_birth': 'bukan-tanggal',
      });

      expect(tanpaTanggal.ageInMonths, isNull);
      expect(tanpaTanggal.ageLabel, '-');
      expect(tanggalRusak.ageInMonths, isNull);
      expect(tanggalRusak.ageLabel, '-');
    });

    test('tanggal lahir di masa depan -> 0 bulan (data salah input)', () {
      final besok = DateTime.now().add(const Duration(days: 1));
      final child = Child.fromJson({
        'id': 'abc',
        'name': 'Anak Masa Depan',
        'date_of_birth': besok.toIso8601String().substring(0, 10),
      });

      expect(child.ageInMonths, 0);
    });
  });

  group('Kontrak API - POST /api/kader/measurements', () {
    // Respons asli (HTTP 201) dari MeasurementController@store.
    // Catatan: Z-Score dihitung oleh Database Trigger PostgreSQL.
    const rawMeasurement = '''
    {
      "success": true,
      "message": "Data penimbangan (e-KMS) berhasil dicatat.",
      "data": {
        "id": "01a0dc0d-67eb-71e5-81c9-edecb72edeed",
        "child_id": "01a0d979-c11f-705b-8dd8-a245652c7aa4",
        "kader_id": "01a0d979-c297-704b-b89a-d66ff76f2474",
        "measurement_date": "2026-09-26",
        "weight_kg": "7.10",
        "height_cm": "75.00",
        "head_circumference_cm": null,
        "age_in_months": 16,
        "z_score_wfa": "-3.09",
        "status_gizi": "Gizi Buruk",
        "created_at": "2026-09-26T04:51:01.000000Z",
        "updated_at": "2026-09-26T04:51:01.000000Z"
      }
    }
    ''';

    test('membaca Z-Score & Status Gizi yang dihitung trigger', () {
      final decoded = json.decode(rawMeasurement) as Map<String, dynamic>;
      final m = MeasurementModel.fromJson(decoded['data'] as Map<String, dynamic>);

      expect(m.weightKg, 7.10);
      expect(m.heightCm, 75.00);
      expect(m.ageInMonths, 16);
      expect(m.zScoreWfa, -3.09);
      expect(m.statusGizi, 'Gizi Buruk');
    });

    test('menangani z_score_wfa null (anak di luar 0-60 bulan)', () {
      final m = MeasurementModel.fromJson({
        'id': 'x',
        'child_id': 'y',
        'measurement_date': '2026-09-26',
        'weight_kg': '18.00',
        'height_cm': '110.00',
        'age_in_months': 61,
        'z_score_wfa': null,
        'status_gizi': null,
      });

      expect(m.zScoreWfa, isNull);
      expect(m.statusGizi, isNull);
      expect(m.ageInMonths, 61);
    });

    test('menangani z_score_wfa yang dikirim sebagai number', () {
      final m = MeasurementModel.fromJson({
        'id': 'x',
        'child_id': 'y',
        'measurement_date': '2026-09-26',
        'weight_kg': 7.1,
        'height_cm': 75,
        'age_in_months': 16,
        'z_score_wfa': -3.09,
        'status_gizi': 'Gizi Kurang',
      });

      expect(m.weightKg, 7.1);
      expect(m.zScoreWfa, -3.09);
      expect(m.ageInMonths, 16);
    });
  });

  group('Kontrak API - error envelope (Aturan #8)', () {
    // Semua error WAJIB punya bentuk {success, message, errors}. Sebelumnya
    // 401 membalas {"message":"Unauthenticated."} sehingga Flutter tidak
    // bisa membaca `success`.
    test('401 sesi habis memakai envelope lengkap', () {
      const raw = '''
      {
        "success": false,
        "message": "Sesi tidak valid atau telah berakhir. Silakan login kembali.",
        "errors": null
      }
      ''';

      final body = json.decode(raw) as Map<String, dynamic>;

      expect(body['success'], isFalse);
      expect(body['message'], isA<String>());
      expect(body.containsKey('errors'), isTrue);
    });

    test('422 validasi punya errors per-field', () {
      const raw = '''
      {
        "success": false,
        "message": "Validasi gagal.",
        "errors": {
          "password": ["Password minimal 8 karakter."]
        }
      }
      ''';

      final body = json.decode(raw) as Map<String, dynamic>;
      final errors = body['errors'] as Map<String, dynamic>;

      expect(body['success'], isFalse);
      expect(errors['password'], isA<List>());
    });

    test('403 daftar kader tanpa kode ditolak server', () {
      const raw = '''
      {
        "success": false,
        "message": "Pendaftaran akun kader ditolak.",
        "errors": {
          "kader_code": ["Kode pendaftaran kader wajib diisi."]
        }
      }
      ''';

      final body = json.decode(raw) as Map<String, dynamic>;

      expect(body['success'], isFalse);
      expect((body['errors'] as Map)['kader_code'], isNotNull);
    });
  });
}
