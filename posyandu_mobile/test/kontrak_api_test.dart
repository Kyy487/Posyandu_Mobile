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
  group('Kontrak API — GET /api/children', () {
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

  group('Kontrak API — POST /api/kader/measurements', () {
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
      expect(m.heightKg, 75.00);
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
}
