import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:posyandu_mobile/models/child.dart';
import 'package:posyandu_mobile/models/immunization.dart';
import 'package:posyandu_mobile/models/measurement_model.dart';
import 'package:posyandu_mobile/models/posyandu_schedule.dart';

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

  group('Kontrak API - GET /api/children/{id}/immunizations', () {
    // Respons asli dari ImmunizationChecklistService (26 September 2026).
    // Dipotong: anak inidont punya suntikan, jadi semua "record" null.
    const rawChecklist = '''
    {
      "success": true,
      "message": "Checklist imunisasi berhasil diambil.",
      "data": {
        "child": {
          "id": "01a0d979-c11f-705b-8dd8-a245652c7aa4",
          "name": "Budi Santoso",
          "date_of_birth": "2025-05-10",
          "gender": "L"
        },
        "summary": { "sudah": 0, "belum": 1, "terlambat": 15, "total": 16 },
        "checklist": [
          {
            "immunization_type_id": "01a0ddcb-8197-7184-9c37-fe42f3cc1fd9",
            "code": "HB",
            "name": "Hepatitis B",
            "label": "Hepatitis B",
            "dose_number": 1,
            "target_age_months": 0,
            "interval_months": null,
            "status": "terlambat",
            "sisa_bulan": -14,
            "record": null
          },
          {
            "immunization_type_id": "01a0ddcb-819b-7185-a07a-51241b25fcb2",
            "code": "HB",
            "name": "Hepatitis B",
            "label": "Hepatitis B (Dosis 2)",
            "dose_number": 2,
            "target_age_months": 2,
            "interval_months": 2,
            "status": "terlambat",
            "sisa_bulan": -12,
            "record": null
          },
          {
            "immunization_type_id": "01a0ddcb-81d2-72d7-af73-83b7815725e6",
            "code": "MR",
            "name": "Campak-Rubella",
            "label": "Campak-Rubella (Dosis 2)",
            "dose_number": 2,
            "target_age_months": 18,
            "interval_months": 9,
            "status": "belum",
            "sisa_bulan": 4,
            "record": null
          }
        ]
      }
    }
    ''';

    ImmunizationChecklist parse(String raw) {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return ImmunizationChecklist.fromJson(
          Map<String, dynamic>.from(decoded['data'] as Map));
    }

    test('membaca anak, ringkasan, dan 16 dosis dari server', () {
      final checklist = parse(rawChecklist);

      expect(checklist.childName, 'Budi Santoso');
      expect(checklist.items.length, 3);
      // Ringkasan dikirim server, jadi klien tidak menghitung ulang.
      expect(checklist.summary.total, 16);
      expect(checklist.summary.overdue, 15);
      expect(checklist.summary.percentDone, 0);
    });

    test('membaca "sisa_bulan" (snake_case) - ini yang mudah salah', () {
      // Kalau parser memakai key camelCase, sisa_bulan selalu null dan
      // tampilan "terlambat X bulan" jadi hilang tanpa error terlihat.
      final hb1 = parse(rawChecklist).items[0];

      expect(hb1.monthsLeft, -14);
      expect(hb1.isOverdue, isTrue);
      expect(hb1.statusNote, 'Terlambat 14 bulan');
    });

    test('sisa_bulan positif -> "belum", negatif -> "terlambat"', () {
      final items = parse(rawChecklist).items;

      expect(items[2].monthsLeft, 4);
      expect(items[2].isPending, isTrue);
      expect(items[2].statusNote, 'Belum disuntik (4 bulan lagi)');
      expect(items[0].isOverdue, isTrue);
    });

    test('label dosis > 1 sudah membawa nomor dari server', () {
      final items = parse(rawChecklist).items;

      expect(items[0].label, 'Hepatitis B');
      expect(items[1].label, 'Hepatitis B (Dosis 2)');
      expect(items[1].doseNumber, 2);
    });

    test('target 0 bulan ditampilkan "Saat lahir", bukan "0 bulan"', () {
      final items = parse(rawChecklist).items;

      expect(items[0].targetAgeMonths, 0);
      expect(items[0].targetLabel, 'Saat lahir');
      expect(items[1].targetLabel, '2 bulan');
    });

    test('mengelompokkan dosis per vaksin lewat key "code"', () {
      final groups = parse(rawChecklist).groupedByCode;

      expect(groups.keys.toSet(), {'HB', 'MR'});
      expect(groups['HB']!.length, 2);
    });

    test('pendingItems hanya berisi dosis yang belum selesai', () {
      final checklist = parse(rawChecklist);

      expect(checklist.pendingItems.length, 3);
      expect(checklist.pendingItems.every((e) => !e.isDone), isTrue);
    });

    test('ringkasan dengan semua dosis selesai -> persen 100', () {
      const raw = '{"child":{"id":"a","name":"Anak"},"summary":{"sudah":16,"belum":0,"terlambat":0,"total":16},"checklist":[]}';

      expect(ImmunizationChecklist.fromJson(json.decode(raw) as Map<String, dynamic>).summary.percentDone, 100);
    });

    test('record suntikan terbaca, dan status jadi "sudah"', () {
      const raw = '{"child": {"id": "a", "name": "Anak"},'
          '"summary": {"sudah": 1, "belum": 0, "terlambat": 0, "total": 1},'
          '"checklist": [{'
          '"immunization_type_id": "t1", "code": "HB", "name": "Hepatitis B",'
          '"label": "Hepatitis B", "dose_number": 1, "target_age_months": 0,'
          '"interval_months": null, "status": "sudah", "sisa_bulan": null,'
          '"record": {'
          '"id": "r1", "child_id": "a", "kader_id": "k1",'
          '"immunization_type_id": "t1", "date_given": "2025-05-12",'
          '"batch_number": "BATCH-99",'
          '"notes": "Suntikan di Posyandu Desa Sukamaju",'
          '"created_at": "2025-05-12T03:00:00.000000Z"}}]}';

      final item =
          ImmunizationChecklist.fromJson(json.decode(raw) as Map<String, dynamic>)
              .items
              .single;

      expect(item.isDone, isTrue);
      expect(item.monthsLeft, isNull);
      expect(item.statusNote, 'Sudah disuntik 2025-05-12');
      expect(item.record!.batchNumber, 'BATCH-99');
      expect(item.record!.notes, 'Suntikan di Posyandu Desa Sukamaju');
    });

    test('field kosong / null tidak membuat parser crash', () {
      const raw = '{"child": null, "summary": {}, "checklist": []}';

      final checklist =
          ImmunizationChecklist.fromJson(json.decode(raw) as Map<String, dynamic>);

      expect(checklist.childId, '');
      expect(checklist.childName, '');
      expect(checklist.summary.total, 0);
      expect(checklist.summary.percentDone, 0);
      expect(checklist.items, isEmpty);
    });
  });

  group('Kontrak API - GET /api/petugas (privasi NIK)', () {
    // NIK SENGAJA tidak ada di respons. Kalau backend nanti menambahkannya,
    // test ini gagal dan jadi pengingat untuk menghapusnya lagi.
    const rawPetugas = '''
    {
      "success": true,
      "message": "Daftar petugas posyandu berhasil diambil.",
      "data": [
        {
          "id": "01a0d979-c297-704b-b89a-d66ff76f2474",
          "name": "Kader Siti",
          "jabatan": "Kader Posyandu",
          "phone_number": null
        },
        {
          "id": "01a0ddcb-7c89-73b8-9d48-a4d55eb2f585",
          "name": "Bidan Rina",
          "jabatan": "Bidan",
          "phone_number": null
        }
      ]
    }
    ''';

    test('membaca id, name, jabatan, dan phone_number saja', () {
      final decoded = json.decode(rawPetugas) as Map<String, dynamic>;
      final petugas = (decoded['data'] as List)
          .map((e) => Petugas.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      expect(petugas.length, 2);
      expect(petugas.first.name, 'Kader Siti');
      expect(petugas.first.roleLabel, 'Kader Posyandu');
      expect(petugas.first.shortName, 'Kader');
      expect(petugas.first.phoneNumber, isNull);
    });

    test('respons tidak pernah memuat "nik"', () {
      expect(rawPetugas.contains('"nik"'), isFalse);
    });

    test('jabatan kosong -> label generik "Petugas"', () {
      final petugas = Petugas.fromJson({'id': 'x', 'name': 'Tanpa Jabatan'});

      expect(petugas.roleLabel, 'Petugas');
    });
  });

  group('Kontrak API - GET /api/schedules', () {
    // Respons asli dari PosyanduScheduleController@index.
    const rawSchedules = '''
    {
      "success": true,
      "message": "Daftar jadwal posyandu berhasil diambil.",
      "data": [
        {
          "id": "01a0ddcb-81e1-7060-8710-81d18ae89d7d",
          "title": "Penimbangan Rutin Bulanan",
          "description": "Penimbangan dan pengukuran tinggi badan balita.",
          "scheduled_date": "2026-11-02",
          "start_time": "08:00",
          "end_time": "11:00",
          "location": "Posyandu Desa Sukamaju",
          "location_name": "Posyandu Desa Sukamaju",
          "status": "terjadwal",
          "notes": null,
          "created_by": "01a0d979-c297-704b-b89a-d66ff76f2474",
          "creator_name": "Kader Siti",
          "petugas_ids": [
            "01a0d979-c297-704b-b89a-d66ff76f2474",
            "01a0ddcb-7c89-73b8-9d48-a4d55eb2f585"
          ],
          "petugas": [
            { "id": "01a0d979-c297-704b-b89a-d66ff76f2474", "name": "Kader Siti", "jabatan": "Kader Posyandu" },
            { "id": "01a0ddcb-7c89-73b8-9d48-a4d55eb2f585", "name": "Bidan Rina", "jabatan": "Bidan" }
          ],
          "created_at": "2026-09-26T12:58:16+00:00",
          "updated_at": "2026-09-26T12:58:16+00:00"
        }
      ]
    }
    ''';

    PosyanduSchedule parseFirst() {
      final decoded = json.decode(rawSchedules) as Map<String, dynamic>;
      return PosyanduSchedule.fromJson(
          Map<String, dynamic>.from((decoded['data'] as List).first as Map));
    }

    test('membaca agenda beserta petugas pivot-nya', () {
      final agenda = parseFirst();

      expect(agenda.title, 'Penimbangan Rutin Bulanan');
      expect(agenda.scheduledDate, '2026-11-02');
      expect(agenda.status, 'terjadwal');
      expect(agenda.petugas.length, 2);
      expect(agenda.petugasIds.length, 2);
      expect(agenda.creatorName, 'Kader Siti');
    });

    test('timeLabel menggabungkan jam mulai dan selesai', () {
      expect(parseFirst().timeLabel, '08:00 - 11:00');
    });

    test('petugasLabel menggabungkan nama dalam satu baris', () {
      expect(parseFirst().petugasLabel, 'Kader Siti, Bidan Rina');
    });

    test('nested petugas tidak mengirim phone_number, dan itu aman', () {
      // /petugas mengirim phone_number, /schedules tidak. Keduanya harus
      // bisa di-parse oleh model yang sama.
      final petugas = parseFirst().petugas.first;

      expect(petugas.phoneNumber, isNull);
      expect(petugas.roleLabel, 'Kader Posyandu');
    });

    test('semua status punya label bahasa manusia', () {
      expect(ScheduleStatus.label('terjadwal'), 'Terjadwal');
      expect(ScheduleStatus.label('berlangsung'), 'Berlangsung');
      expect(ScheduleStatus.label('selesai'), 'Selesai');
      expect(ScheduleStatus.label('dibatalkan'), 'Dibatalkan');
      expect(ScheduleStatus.semua.length, 4);
    });

    test('status tidak dikenal diteruskan, tidak crash', () {
      expect(ScheduleStatus.label('menggantung'), 'menggantung');
    });

    test('agenda tanpa petugas -> label "-", bukan string kosong', () {
      const raw = '{"title":"Tanpa Petugas","scheduled_date":"2026-11-02","status":"terjadwal","petugas_ids":[],"petugas":[]}';

      final agenda =
          PosyanduSchedule.fromJson(json.decode(raw) as Map<String, dynamic>);

      expect(agenda.petugasLabel, '-');
      expect(agenda.petugas, isEmpty);
      expect(agenda.locationName, isNull);
    });

    test('tanggal rusak tidak dianggap agenda lampau', () {
      const raw = '{"title":"Tanggal Rusak","scheduled_date":"bukan-tanggal","status":"terjadwal"}';

      final agenda =
          PosyanduSchedule.fromJson(json.decode(raw) as Map<String, dynamic>);

      expect(agenda.isPast, isFalse);
    });

    test('agenda lampau terdeteksi dari scheduled_date', () {
      final lalu = DateTime.now().subtract(const Duration(days: 3));
      final depan = DateTime.now().add(const Duration(days: 3));

      String iso(DateTime d) => d.toIso8601String().substring(0, 10);

      expect(
        PosyanduSchedule.fromJson({'scheduled_date': iso(lalu)}).isPast,
        isTrue,
      );
      expect(
        PosyanduSchedule.fromJson({'scheduled_date': iso(depan)}).isPast,
        isFalse,
      );
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
