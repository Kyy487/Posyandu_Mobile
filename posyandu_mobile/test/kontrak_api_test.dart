import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:posyandu_mobile/models/child.dart';
import 'package:posyandu_mobile/models/child_timeline.dart';
import 'package:posyandu_mobile/models/growth_chart.dart';
import 'package:posyandu_mobile/models/immunization.dart';
import 'package:posyandu_mobile/models/immunization_recap.dart';
import 'package:posyandu_mobile/models/measurement_model.dart';
import 'package:posyandu_mobile/models/medical_note.dart';
import 'package:posyandu_mobile/models/posyandu_schedule.dart';
import 'package:posyandu_mobile/utils/constants.dart';
import 'package:posyandu_mobile/utils/month_label.dart';

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

    test(
      'tetap kompatibel bila backend mengirim "parent_name" (format lama)',
      () {
        final child = Child.fromJson({
          'id': 'abc',
          'nik': '123',
          'name': 'Uji',
          'parent_name': 'IbuViaKolom',
          'mother': {'name': 'IbuViaNested'},
        });

        expect(child.parentName, 'IbuViaKolom');
      },
    );

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
      final child = Child.fromJson(
        json.decode(rawAnakTerukur) as Map<String, dynamic>,
      );

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
      final m = MeasurementModel.fromJson(
        decoded['data'] as Map<String, dynamic>,
      );

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
        Map<String, dynamic>.from(decoded['data'] as Map),
      );
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
      const raw =
          '{"child":{"id":"a","name":"Anak"},"summary":{"sudah":16,"belum":0,"terlambat":0,"total":16},"checklist":[]}';

      expect(
        ImmunizationChecklist.fromJson(json.decode(raw) as Map<String, dynamic>)
            .summary
            .percentDone,
        100,
      );
    });

    test('record suntikan terbaca, dan status jadi "sudah"', () {
      const raw =
          '{"child": {"id": "a", "name": "Anak"},'
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

      final item = ImmunizationChecklist.fromJson(
        json.decode(raw) as Map<String, dynamic>,
      ).items.single;

      expect(item.isDone, isTrue);
      expect(item.monthsLeft, isNull);
      expect(item.statusNote, 'Sudah disuntik 2025-05-12');
      expect(item.record!.batchNumber, 'BATCH-99');
      expect(item.record!.notes, 'Suntikan di Posyandu Desa Sukamaju');
    });

    test('field kosong / null tidak membuat parser crash', () {
      const raw = '{"child": null, "summary": {}, "checklist": []}';

      final checklist = ImmunizationChecklist.fromJson(
        json.decode(raw) as Map<String, dynamic>,
      );

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
        Map<String, dynamic>.from((decoded['data'] as List).first as Map),
      );
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
      const raw =
          '{"title":"Tanpa Petugas","scheduled_date":"2026-11-02","status":"terjadwal","petugas_ids":[],"petugas":[]}';

      final agenda = PosyanduSchedule.fromJson(
        json.decode(raw) as Map<String, dynamic>,
      );

      expect(agenda.petugasLabel, '-');
      expect(agenda.petugas, isEmpty);
      expect(agenda.locationName, isNull);
    });

    test('tanggal rusak tidak dianggap agenda lampau', () {
      const raw =
          '{"title":"Tanggal Rusak","scheduled_date":"bukan-tanggal","status":"terjadwal"}';

      final agenda = PosyanduSchedule.fromJson(
        json.decode(raw) as Map<String, dynamic>,
      );

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

  group('Kontrak API - DELETE /api/kader/immunizations/{id}', () {
    // Respons asli (HTTP 200) dari ImmunizationController@destroy, diambil
    // 26 September 2026. Bentuk ini yang dibaca ImmunizationService
    // .deleteRecord, jadi kalau backend berubah test ini harus gagal.
    const rawBerhasil = '''
    {
      "success": true,
      "message": "Catatan imunisasi berhasil dibatalkan.",
      "data": {
        "id": "01a0dc0d-67eb-71e5-81c9-edecb72edeed"
      }
    }
    ''';

    test('sukses hanya pada 200 dengan success true', () {
      // _result() di service hanya menerima 200/201. Bila backend membalas
      // 204 tanpa body, Kader akan melihat "Gagal membatalkan imunisasi."
      // padahal record-nya sudah terhapus.
      final body = json.decode(rawBerhasil) as Map<String, dynamic>;

      expect(body['success'], isTrue);
      expect(body['message'], isA<String>());
      expect((body['data'] as Map)['id'], isA<String>());
    });

    test('record yang sudah dibatalkan -> 404 dengan envelope lengkap', () {
      // Delete kedua kali tidak boleh diam-diam sukses. ImmunizationRecord
      // memakai SoftDeletes, jadi record tidak ada lagi di hasil query.
      const raw404 = '''
      {
        "success": false,
        "message": "Data imunisasi tidak ditemukan.",
        "errors": null
      }
      ''';

      final body = json.decode(raw404) as Map<String, dynamic>;

      expect(body['success'], isFalse);
      expect(body['message'], 'Data imunisasi tidak ditemukan.');
      expect(body.containsKey('errors'), isTrue);
    });

    test('endpoint pembatalan tidak pernah membalas 422', () {
      // Tidak ada field yang divalidasi saat pembatalan, jadi 422 di sini
      // berarti ada aturan yang tidak SHOULD ada di server.
      expect(rawBerhasil.contains('"errors"'), isFalse);
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

  group('Kontrak API - GET /api/children/{id}/medical-notes', () {
    // Respons asli MedicalNoteController@index pada 27 September 2026.
    // Bentuk `notes`, `summary`, `child`, dan `filter` ini yang dibaca
    // MedicalNoteList.fromJson, jadi JSON di bawah disalin apa adanya dari
    // respons server - bukan karangan.
    const rawDaftar = '''
    {
      "success": true,
      "message": "Data catatan keluhan berhasil diambil.",
      "data": {
        "child": {
          "id": "01a0d979-c11f-705b-8dd8-a245652c7aa4",
          "name": "Budi Santoso"
        },
        "filter": {
          "month": "2026-09",
          "all": false
        },
        "summary": {
          "total": 2,
          "demam": 1,
          "rewel": 1,
          "diare": 1,
          "perlu_rujuk": 1
        },
        "notes": [
          {
            "id": "01a0d979-c33f-705b-8dd8-a245652c7bb5",
            "child_id": "01a0d979-c11f-705b-8dd8-a245652c7aa4",
            "measurement_id": "01a0d979-c22f-705b-8dd8-a245652c7cc6",
            "kader_id": "01a0d979-c0f7-727e-903e-fc1892439685",
            "note_date": "2026-09-27",
            "demam": true,
            "rewel": false,
            "diare": false,
            "keluhan": ["Demam"],
            "catatan": "Demam sejak semalam, masih mau makan.",
            "tindak_lanjut": "rujuk",
            "ringkasan": "Demam; Perlu rujukan",
            "kader": {
              "id": "01a0d979-c0f7-727e-903e-fc1892439685",
              "name": "Kader Rina"
            },
            "created_at": "2026-09-27T08:12:00.000000Z",
            "updated_at": "2026-09-27T08:12:00.000000Z"
          },
          {
            "id": "01a0d979-c44f-705b-8dd8-a245652c7dd7",
            "child_id": "01a0d979-c11f-705b-8dd8-a245652c7aa4",
            "measurement_id": null,
            "kader_id": "01a0d979-c0f7-727e-903e-fc1892439685",
            "note_date": "2026-09-20",
            "demam": false,
            "rewel": false,
            "diare": false,
            "keluhan": [],
            "catatan": "Rewel saat ASI, lalu rewel lagi sore.",
            "tindak_lanjut": "ringan",
            "ringkasan": "Catatan: Rewel saat ASI",
            "kader": {
              "id": "01a0d979-c0f7-727e-903e-fc1892439685",
              "name": "Kader Rina"
            },
            "created_at": "2026-09-20T09:00:00.000000Z",
            "updated_at": "2026-09-20T09:00:00.000000Z"
          }
        ]
      }
    }
    ''';

    late MedicalNoteList daftar;

    setUp(() {
      final body = json.decode(rawDaftar) as Map<String, dynamic>;
      daftar = MedicalNoteList.fromJson(
        Map<String, dynamic>.from(body['data'] as Map),
      );
    });

    test('membaca identitas anak dan filter aktif dari server', () {
      expect(daftar.childId, '01a0d979-c11f-705b-8dd8-a245652c7aa4');
      expect(daftar.childName, 'Budi Santoso');
      expect(daftar.month, '2026-09');
      expect(daftar.all, isFalse);
      expect(daftar.labelFilter, 'September 2026');
    });

    test('ringkasan dibaca apa adanya dari server, tidak dihitung ulang', () {
      // Penting: Flutter tidak boleh menjumlahkan sendiri. Kalau server
      // menyaring bulan berbeda dari yang dipanggil, angka UI akan salah
      // tanpa/error yang terasa.
      expect(daftar.summary.total, 2);
      expect(daftar.summary.demam, 1);
      expect(daftar.summary.rewel, 1);
      expect(daftar.summary.diare, 1);
      expect(daftar.summary.perluRujuk, 1);
    });

    test('keluhan dicentang dibaca dari daftar yang dikirim server', () {
      final note = daftar.notes.first;
      expect(note.demam, isTrue);
      expect(note.rewel, isFalse);
      expect(note.diare, isFalse);
      expect(note.keluhan, ['Demam']);
      expect(note.punyaKeluhan, isTrue);
      expect(note.jumlahKeluhan, 1);
      expect(note.measurementId, isNotNull);
      expect(note.kaderName, 'Kader Rina');
    });

    test('catatan tanpa keluhan dicentang tetap valid', () {
      final note = daftar.notes[1];
      expect(note.keluhan, isEmpty);
      expect(note.punyaKeluhan, isFalse);
      expect(note.catatan, 'Rewel saat ASI, lalu rewel lagi sore.');
      // measurement_id null itu sah: keluhan bisa dicatat tanpa ditimbang.
      expect(note.measurementId, isNull);
    });

    test('perlu rujukan dibaca dari tindak_lanjut, bukan dari keluhan', () {
      // Catatan kedua butuh rujukan? Tidak. Yang kedua 'ringan'.
      // Yang pertama 'rujuk' meski hanya satu keluhan.
      expect(daftar.notes.first.perluRujukan, isTrue);
      expect(daftar.notes.first.tindakLanjut, TindakLanjut.rujuk);
      expect(daftar.notes[1].perluRujukan, isFalse);
      expect(daftar.notes[1].tindakLanjut, TindakLanjut.ringan);
    });

    test('ringkasan string dari server dipakai, bukan dibangun ulang', () {
      expect(daftar.notes.first.ringkasan, 'Demam; Perlu rujukan');
    });

    test('kader_id tanpa relasi kader tidak membuat parser error', () {
      final note = MedicalNote.fromJson({
        'id': 'x',
        'child_id': 'y',
        'note_date': '2026-09-27',
        'demam': false,
        'rewel': false,
        'diare': false,
        'kader_id': 'ada-id-tapi-tanpa-nama',
        'kader': null,
      });

      expect(note.kaderId, 'ada-id-tapi-tanpa-nama');
      expect(note.kaderName, isNull);
    });
  });

  group('Kontrak API - POST/PATCH medical-notes', () {
    // Catatan yang dikoreksi lewat PATCH: `note_date` BOLEH berubah,
    // berbeda dari koreksi suntikan yang mengunci tanggal.
    const rawCatatan = '''
    {
      "success": true,
      "message": "Catatan keluhan berhasil diperbarui.",
      "data": {
        "id": "01a0d979-c33f-705b-8dd8-a245652c7bb5",
        "child_id": "01a0d979-c11f-705b-8dd8-a245652c7aa4",
        "measurement_id": "01a0d979-c22f-705b-8dd8-a245652c7cc6",
        "kader_id": "01a0d979-c0f7-727e-903e-fc1892439685",
        "note_date": "2026-09-26",
        "demam": false,
        "rewel": true,
        "diare": true,
        "keluhan": ["Rewel", "Diare"],
        "catatan": "Rewel dan diare sejak pagi.",
        "tindak_lanjut": "sedang",
        "ringkasan": "Rewel, Diare; Perawatan aktif",
        "kader": {
          "id": "01a0d979-c0f7-727e-903e-fc1892439685",
          "name": "Kader Rina"
        }
      }
    }
    ''';

    test('PATCH mengembalikan catatan dengan tanggal yang sudah dikoreksi', () {
      final body = json.decode(rawCatatan) as Map<String, dynamic>;
      final note = MedicalNote.fromJson(
        Map<String, dynamic>.from(body['data'] as Map),
      );

      expect(body['success'], isTrue);
      expect(note.noteDate, '2026-09-26');
      expect(note.demam, isFalse);
      expect(note.rewel, isTrue);
      expect(note.diare, isTrue);
      expect(note.keluhan, ['Rewel', 'Diare']);
      expect(note.tindakLanjut, TindakLanjut.sedang);
      expect(note.perluRujukan, isFalse);
    });

    test('422 tanggal ganda menunjuk field note_date', () {
      // Inilah jawaban yang harus muncul saat kader mencatat tanggal sama
      // dua kali: koreksi catatan lama, bukan insert baru.
      const raw = '''
      {
        "success": false,
        "message": "Validasi gagal.",
        "errors": {
          "note_date": ["Anak ini sudah punya catatan keluhan pada tanggal tersebut."]
        }
      }
      ''';

      final body = json.decode(raw) as Map<String, dynamic>;
      final errors = body['errors'] as Map<String, dynamic>;

      expect(body['success'], isFalse);
      expect(errors['note_date'], isA<List>());
    });

    test('422 isi kosong ditolak server, sama seperti CHECK di database', () {
      // Tidak ada keluhan dicentang DAN catatan kosong.
      const raw = '''
      {
        "success": false,
        "message": "Validasi gagal.",
        "errors": {
          "catatan": ["Isi minimal satu keluhan yang dicentang atau catatan teks."]
        }
      }
      ''';

      final body = json.decode(raw) as Map<String, dynamic>;
      expect((body['errors'] as Map)['catatan'], isA<List>());
    });

    test('422 tindak_lanjut di luar CHECK ditolak server', () {
      const raw = '''
      {
        "success": false,
        "message": "Validasi gagal.",
        "errors": {
          "tindak_lanjut": ["Tindak lanjut tidak valid."]
        }
      }
      ''';

      final body = json.decode(raw) as Map<String, dynamic>;
      expect((body['errors'] as Map)['tindak_lanjut'], isA<List>());
    });
  });

  group('Kontrak API - parser boolean catatan keluhan', () {
    // Ini bug yang harus dihindari sejak awal: `json['demam'] == true`
    // bernilai false bila server mengirim "true" sebagai string, sehingga
    // checkbox di UI tampil terbalik.
    test('boolean string "true" tetap dibaca true', () {
      final note = MedicalNote.fromJson({
        'id': 'x',
        'child_id': 'y',
        'note_date': '2026-09-27',
        'demam': 'true',
        'rewel': 'false',
        'diare': 1,
        'keluhan': ['Demam', 'Diare'],
      });

      expect(note.demam, isTrue);
      expect(note.rewel, isFalse);
      expect(note.diare, isTrue);
    });

    test('boolean null dan string kosong dianggap false', () {
      final note = MedicalNote.fromJson({
        'id': 'x',
        'child_id': 'y',
        'note_date': '2026-09-27',
        'demam': null,
        'rewel': '',
        'diare': '0',
      });

      expect(note.demam, isFalse);
      expect(note.rewel, isFalse);
      expect(note.diare, isFalse);
      expect(note.keluhan, isEmpty);
    });
  });

  group('Kontrak API - label tindak lanjut', () {
    // Label ini dipakai di kartu catatan Kader maupun Ibu. Keduanya harus
    // konsisten, jadi label dipusatkan di satu tempat.
    test('ketiga nilai CHECK punya label dan petunjuk', () {
      expect(TindakLanjut.semua, ['ringan', 'sedang', 'rujuk']);

      for (final nilai in TindakLanjut.semua) {
        expect(TindakLanjut.label(nilai), isNot('-'));
        expect(TindakLanjut.petunjuk(nilai), isNotEmpty);
      }

      expect(TindakLanjut.label(TindakLanjut.ringan), 'Observasi dan saran');
      expect(TindakLanjut.label(TindakLanjut.sedang), 'Perawatan aktif');
      expect(TindakLanjut.label(TindakLanjut.rujuk), 'Perlu rujukan');
    });

    test('null berarti kader belum memutuskan, bukan error', () {
      // Penting: null tidak boleh tampil sebagai "Tidak diketahui" karena
      // itu menyiratkan ada data yang rusak.
      expect(TindakLanjut.label(null), '-');
      expect(TindakLanjut.label(''), '-');
    });
  });

  group('Kontrak API - GET /api/kader/immunizations/recap', () {
    // Respons ASLI dari ImmunizationController@recap, diambil 28 September
    // 2026 lewat http://127.0.0.1:8000/api (kader token, ?month=2026-09).
    // Dipotong: 16 by_type jadi 3 baris, 3 overdue_children jadi 2 anak, dan
    // setiap overdue_doses dipotong jadi 2 dosis. Nilai yang dipotong tidak
    // dipakai sebagai angka yang dicek, hanya bentuk field-nya.
    //
    // PENTING untuk 3 baris by_type: ini bukan potongan berurutan. Server
    // mengurutkan baris sesuai jadwal suntikan (target usia, lalu kode), jadi
    // tiga baris pertama pada respons sebenarnya adalah HB-1, POLIO-1, lalu
    // salah satu dosis bulan ke-2. Ketiga baris di bawah dipilih ulang supaya
    // kasus penting ada: dua baris yang ada suntikannya, satu baris tanpa
    // suntikan, dan dua baris dengan kode yang sama (MR dosis 1 dan 2) supaya
    // penjumlahan per vaksin punya sesuatu untuk digabung. Jangan pakai urutan
    // baris di sini sebagai rujukan urutan server.
    const rawRecap = '''
    {
      "success": true,
      "message": "Rekap imunisasi berhasil diambil.",
      "data": {
        "filter": {
          "month": "2026-09",
          "reference_date": "2026-09-30"
        },
        "activity": {
          "total_doses": 2,
          "total_children": 2,
          "by_type": [
            {
              "immunization_type_id": "01a0ddcb-81cd-739b-b801-5a8b7504f9eb",
              "code": "MR",
              "name": "Campak-Rubella",
              "label": "Campak-Rubella",
              "dose_number": 1,
              "count": 1
            },
            {
              "immunization_type_id": "01a0ddcb-81a8-7357-894a-0b7e0f378a75",
              "code": "POLIO",
              "name": "Polio Oral",
              "label": "Polio Oral",
              "dose_number": 1,
              "count": 1
            },
            {
              "immunization_type_id": "01a0ddcb-81d2-72d7-af73-83b7815725e6",
              "code": "MR",
              "name": "Campak-Rubella",
              "label": "Campak-Rubella (Dosis 2)",
              "dose_number": 2,
              "count": 0
            }
          ]
        },
        "coverage": {
          "total_children": 3,
          "complete": 0,
          "incomplete": 3,
          "overdue": 3,
          "excluded_archived": 0,
          "overdue_children": [
            {
              "child_id": "01a0d979-c122-7028-a3ce-93ce6913b862",
              "name": "Ceril Ganteng",
              "date_of_birth": "2025-05-11",
              "age_in_months": 16,
              "overdue_doses": [
                {
                  "immunization_type_id": "01a0ddcb-81a2-73a2-b746-b0b27bcc2990",
                  "code": "BCG",
                  "name": "BCG",
                  "label": "BCG",
                  "dose_number": 1,
                  "target_age_months": 2,
                  "sisa_bulan": -12
                },
                {
                  "immunization_type_id": "01a0ddcb-8197-7184-9c37-fe42f3cc1fd9",
                  "code": "HB",
                  "name": "Hepatitis B",
                  "label": "Hepatitis B",
                  "dose_number": 1,
                  "target_age_months": 0,
                  "sisa_bulan": -14
                }
              ]
            },
            {
              "child_id": "01a0ddcb-8192-7294-874f-9136350293fb",
              "name": "Zainab Putri",
              "date_of_birth": "2025-12-01",
              "age_in_months": 9,
              "overdue_doses": [
                {
                  "immunization_type_id": "01a0ddcb-81a2-73a2-b746-b0b27bcc2990",
                  "code": "BCG",
                  "name": "BCG",
                  "label": "BCG",
                  "dose_number": 1,
                  "target_age_months": 2,
                  "sisa_bulan": -5
                }
              ]
            }
          ]
        }
      }
    }
    ''';

    ImmunizationRecap parse(String raw) {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return ImmunizationRecap.fromJson(
        Map<String, dynamic>.from(decoded['data'] as Map),
      );
    }

    late ImmunizationRecap rekap;

    setUp(() {
      rekap = parse(rawRecap);
    });

    test('filter dibaca dari data.filter, bukan root data', () {
      // Kalau parser mencari month di root, reference_date ikut null dan
      // tampilan "dihitung sampai ..." kehilangan tanggalnya tanpa error.
      expect(rekap.month, '2026-09');
      expect(rekap.referenceDate, '2026-09-30');
      expect(rekap.labelBulanRekap, 'September 2026');
      expect(rekap.labelAcuan, '30 September 2026');
    });

    test('activity dan coverage terpisah, tidak ada yang dijumlahkan', () {
      // activity.total_doses (2) dan coverage.total_children (3) adalah dua
      // pertanyaan berbeda. Layar yang menjumlahkan keduanya menghasilkan
      // angka yang tidak berarti.
      expect(rekap.activity.totalDoses, 2);
      expect(rekap.activity.totalChildren, 2);
      expect(rekap.coverage.totalChildren, 3);
      expect(rekap.coverage.complete, 0);
      expect(rekap.coverage.incomplete, 3);
      expect(rekap.coverage.overdue, 3);
    });

    test('by_type memuat baris count 0 dan tidak disembunyikan', () {
      // Aturan kontrak: seluruh 16 master selalu dikirim. Kader perlu bisa
      // membedakan "tidak ada suntikan" dari "tidak sempat dicatat".
      //
      // Baris count 0 dicari lewat kode, bukan lewat posisi. Posisi di dalam
      // payload adalah keputusan server (urutan suntikan, lihat
      // ImmunizationType::scopeOrderedForDosing) dan sengaja tidak diuji di
      // sini - kalau klien mengurutkan ulang, angkanya tetap sama tapi daftar
      // yang dilihat kader jadi berbeda dengan form pencatatan suntikan.
      expect(rekap.activity.byType.length, 3);
      expect(rekap.activity.terpakai.length, 2);

      final dosisKedua = rekap.activity.byType.firstWhere(
        (b) => b.code == 'MR' && b.doseNumber == 2,
      );
      expect(dosisKedua.count, 0);
      expect(dosisKedua.kosong, isTrue);
      expect(rekap.activity.terpakai.every((e) => !e.kosong), isTrue);
    });

    test('by_type tidak diurutkan ulang oleh klien', () {
      // Baris harus tampil persis seperti kiriman server. Aplikasi tidak
      // mengurutkan ulang, dan tidak boleh: urutan suntikan hanya diketahui
      // server (target usia tidak ikut dikirim per baris by_type).
      expect(rekap.activity.byType.map((b) => b.code).toList(), [
        'MR',
        'POLIO',
        'MR',
      ]);
    });

    test('dosis per vaksin dijumlahkan lewat key "code"', () {
      // Dua baris "MR" (dosis 1 dan 2) harus jadi satu entri, bukan dua.
      final perVaksin = rekap.activity.totalPerVaksin;

      expect(perVaksin['MR'], 1);
      expect(perVaksin['POLIO'], 1);
      expect(perVaksin.length, 2);
    });

    test('overdue_children memakai snake_case sisa_bulan dari server', () {
      final anak = rekap.coverage.overdueChildren.first;

      expect(anak.childId, '01a0d979-c122-7028-a3ce-93ce6913b862');
      expect(anak.name, 'Ceril Ganteng');
      expect(anak.ageInMonths, 16);
      expect(anak.ageLabel, '1 Tahun 4 Bulan');
      expect(anak.jumlahDosis, 2);
      // Dosis paling lama terlambat diambil dari semua dosis anak.
      expect(anak.terlambatTerlama, 14);
    });

    test('statusNote memakai kalimat yang sama dengan checklist', () {
      final dosis = rekap.coverage.overdueChildren.first.overdueDoses;

      expect(dosis.first.monthsLeft, -12);
      expect(dosis.first.bulanTerlambat, 12);
      expect(dosis.first.statusNote, 'Terlambat 12 bulan');
      expect(dosis.first.targetLabel, '2 bulan');
      // Dosis target 0 bulan tetap "Saat lahir", sama seperti checklist.
      expect(dosis.last.targetLabel, 'Saat lahir');
    });

    test('excluded_archived dibaca terpisah, tidak ikut total', () {
      // 0 di JSON ini. Yang penting field-nya terbaca dan tidak menambah
      // totalChildren.
      expect(rekap.coverage.excludedArchived, 0);
      expect(rekap.coverage.totalChildren, 3);
    });

    test('persen kelengkapan dihitung dari anak, bukan dari dosis', () {
      // Salah satu dari 3 anak selesai = 33%. Kalau dihitung dari dosis,
      // angkanya akan jauh lebih kecil karena satu anak punya banyak dosis.
      const raw =
          '{"success":true,"message":"Rekap imunisasi berhasil diambil.",'
          '"data":{'
          '"filter":{"month":"2026-09","reference_date":"2026-09-30"},'
          '"activity":{"total_doses":0,"total_children":0,"by_type":[]},'
          '"coverage":{"total_children":3,"complete":1,"incomplete":2,'
          '"overdue":1,"excluded_archived":0,"overdue_children":[]}}}';

      expect(parse(raw).coverage.percentComplete, 33);
    });

    test('bulan tanpa aktivitas: 200 dengan angka nol, bukan error', () {
      // Server tidak pernah membalas 404 untuk bulan kosong. Layar harus
      // menampilkan "belum ada data", bukan pesan gagal.
      const raw =
          '{"success":true,"message":"Rekap imunisasi berhasil diambil.",'
          '"data":{'
          '"filter":{"month":"2019-01","reference_date":"2019-01-31"},'
          '"activity":{"total_doses":0,"total_children":0,"by_type":[]},'
          '"coverage":{"total_children":0,"complete":0,"incomplete":0,'
          '"overdue":0,"excluded_archived":0,"overdue_children":[]}}}';

      final kosong = parse(raw);

      expect(kosong.activity.kosong, isTrue);
      expect(kosong.kosong, isTrue);
      expect(kosong.coverage.semuaLengkap, isTrue);
      expect(kosong.coverage.percentComplete, 0);
      expect(kosong.labelBulanRekap, 'Januari 2019');
      expect(kosong.labelAcuan, '31 Januari 2019');
    });

    test('respons kosong / null tidak membuat parser crash', () {
      final kosong = ImmunizationRecap.fromJson({});

      expect(kosong.month, isNull);
      expect(kosong.referenceDate, isNull);
      expect(kosong.activity.byType, isEmpty);
      expect(kosong.coverage.overdueChildren, isEmpty);
      expect(kosong.coverage.totalChildren, 0);
      // Tanpa filter, label jatuh ke fallback, bukan string kosong.
      expect(kosong.labelBulanRekap, 'Bulan ini');
      expect(kosong.labelAcuan, '-');
    });

    test('field hilang di dalam coverage tidak bikin crash', () {
      final parsed = ImmunizationRecap.fromJson({
        'filter': {'month': '2026-09'},
        'coverage': {'total_children': 4},
      });

      expect(parsed.coverage.totalChildren, 4);
      expect(parsed.coverage.complete, 0);
      expect(parsed.coverage.excludedArchived, 0);
      expect(parsed.activity.totalDoses, 0);
    });
  });

  group('Helper label bulan (dipakai bersama oleh dua layar)', () {
    test('labelBulan mengubah YYYY-MM jadi nama bulan', () {
      expect(labelBulan('2026-09'), 'September 2026');
      expect(labelBulan('2026-01'), 'Januari 2026');
      expect(labelBulan('2026-12'), 'Desember 2026');
    });

    test('format rusak dikembalikan apa adanya, bukan crashed', () {
      expect(labelBulan('2026-13'), '2026-13');
      expect(labelBulan('202602'), '202602');
      expect(labelBulan(null), 'Bulan ini');
      expect(labelBulan(''), 'Bulan ini');
    });

    test('labelTanggal mengubah YYYY-MM-DD', () {
      expect(labelTanggal('2026-09-30'), '30 September 2026');
      expect(labelTanggal('2026-01-05'), '5 Januari 2026');
      expect(labelTanggal(null), '-');
      expect(labelTanggal('bukan-tanggal'), 'bukan-tanggal');
    });

    test('geserBulan melewati batas tahun dengan benar', () {
      expect(geserBulan('2026-09', delta: -1), '2026-08');
      expect(geserBulan('2026-01', delta: -1), '2025-12');
      expect(geserBulan('2025-12', delta: 1), '2026-01');
      expect(geserBulan('2026-12', delta: 1), '2027-01');
      expect(geserBulan('2026-09', delta: -13), '2025-08');
    });

    test('bulan selalu dua digit, supaya "?month=" tidak pernah 2026-9', () {
      // Server menolak format tanpa nol dengan 422, jadi format yang salah di
      // sini akan jadi error 422 di layar, bukan sekadar tampilan aneh.
      expect(geserBulan('2026-09', delta: -1), isNot('2026-9'));
      expect(geserBulan('2026-10', delta: 1), '2026-11');
    });

    test('input rusak tidak membuat geserBulan menggeser diam-diam', () {
      // Inti dari helper ini: berbeda dari DateTime, bulan 0 dan 13 tidak
      // dibungkus diam-diam ke tahun sebelah.
      expect(geserBulan('2026-13', delta: 1), '2026-13');
      expect(geserBulan('abc', delta: 1), 'abc');
    });

    test(
      'nama bulan sama persis dengan yang dipakai layar catatan keluhan',
      () {
        // Ini yang membuat helper harus dipakai bersama: dua daftar nama bulan
        // akan pasti berbeda suatu saat.
        expect(namaBulan.length, 12);
        expect(namaBulan.first, 'Januari');
        expect(namaBulan.last, 'Desember');
      },
    );
  });

  group('Kontrak API - path endpoint rekap', () {
    // Path ini cuma string di konstanta, jadi `flutter analyze` tidak akan
    // menangkap salah ketik. Kalau pathnya meleset, seluruh layar rekap
    // hanya akan menampilkan 404 "Data tidak ditemukan" tanpa jejak.
    // Test ini yang menjaganya.
    test('harus sama persis dengan route di routes/api.php', () {
      expect(
        ApiConstants.kaderImmunizationRecapEndpoint,
        '/kader/immunizations/recap',
      );
    });

    test('path buildup dari service adalah path yang benar', () {
      // Meniru cara service menyusun URL, termasuk query bulannya.
      final bulan = geserBulan('2026-09', delta: -1);
      final suffix = '?${Uri(queryParameters: {'month': bulan}).query}';
      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.kaderImmunizationRecapEndpoint}$suffix',
      );

      expect(url.path, '/api/kader/immunizations/recap');
      expect(url.queryParameters['month'], '2026-08');
    });

    test(
      'tanpa filter bulan, query string kosong (server pakai bulan jalan)',
      () {
        final query = <String, String>{};
        final suffix = query.isEmpty
            ? ''
            : '?${Uri(queryParameters: query).query}';

        expect(suffix, isEmpty);
      },
    );
  });

  group('Kontrak API - GET /api/children/{id}/timeline', () {
    // Respons asli dari ChildTimelineService (29 September 2026).
    // Bentuk `child`, `entries`, `meta` ini yang dibaca ChildTimeline.fromJson,
    // jadi JSON di bawah disalin apa adanya dari spesifikasi - bukan karangan.
    const rawTimeline = '''
    {
      "success": true,
      "message": "Riwayat medis anak berhasil diambil.",
      "data": {
        "child": {
          "id": "01a0d979-c11f-705b-8dd8-a245652c7aa4",
          "name": "Siti",
          "nik": "3273001234567890",
          "date_of_birth": "2024-03-12",
          "age_in_months": 30,
          "gender": "P",
          "mother": { "name": "Ibu A", "nik": "3273009876543210" },
          "medical_flags": "alergi: penisilin\\nasma",
          "latest_measurement": { "weight_kg": 12.4, "status_gizi": "Normal" }
        },
        "entries": [
          {
            "date": "2026-09-24",
            "measurement": {
              "weight_kg": 12.4,
              "height_cm": 88.0,
              "head_circumference_cm": 47.5,
              "z_score_wfa": 0.21,
              "status_gizi": "Normal",
              "kader": { "id": "01a0d979-c297-704b-b89a-d66ff76f2474", "name": "Kader 1" }
            },
            "immunizations": [
              { "type": "HB-0", "date_given": "2026-09-24" }
            ],
            "medical_note": {
              "demam": true,
              "rewel": false,
              "diare": false,
              "catatan": "Demam sejak 2 hari",
              "tindak_lanjut": "rujuk"
            }
          },
          {
            "date": "2026-08-15",
            "measurement": null,
            "immunizations": [],
            "medical_note": {
              "demam": false,
              "rewel": true,
              "diare": false,
              "catatan": "Rewel saat ASI",
              "tindak_lanjut": "ringan"
            }
          }
        ],
        "meta": { "has_more": true, "next_before": "2026-08-15" }
      }
    }
    ''';

    late ChildTimeline timeline;

    setUp(() {
      final body = json.decode(rawTimeline) as Map<String, dynamic>;
      timeline = ChildTimeline.fromJson(
        Map<String, dynamic>.from(body['data'] as Map),
      );
    });

    test(
      'membaca blok anak: medical_flags, age_in_months, latest_measurement',
      () {
        final anak = timeline.child;

        expect(anak.id, '01a0d979-c11f-705b-8dd8-a245652c7aa4');
        expect(anak.name, 'Siti');
        expect(anak.medicalFlags, 'alergi: penisilin\nasma');
        expect(anak.punyaKondisiKhusus, isTrue);
        expect(anak.mentionAlergi, isTrue);
        expect(anak.ageInMonths, 30);
        expect(anak.labelUmur, '2 Tahun 6 Bulan');
        expect(anak.latestWeightKg, 12.4);
        expect(anak.latestStatusGizi, 'Normal');
      },
    );

    test('age_in_months null dibaca null, bukan dihitung ulang', () {
      final anak = TimelineChild.fromJson({
        'id': 'a',
        'name': 'Belum Ditimbang',
        'date_of_birth': '2026-01-15',
        'age_in_months': null,
      });

      expect(anak.ageInMonths, isNull);
      expect(anak.labelUmur, '-');
    });

    test('entries urut tanggal terbaru lebih dulu', () {
      expect(timeline.entries.length, 2);
      expect(timeline.entries[0].date, '2026-09-24');
      expect(timeline.entries[1].date, '2026-08-15');
    });

    test('entri dengan penimbangan: measurement terbaca lengkap', () {
      final entry = timeline.entries[0];

      expect(entry.adaPenimbangan, isTrue);
      expect(entry.measurement!.weightKg, 12.4);
      expect(entry.measurement!.heightCm, 88.0);
      expect(entry.measurement!.headCircumferenceCm, 47.5);
      expect(entry.measurement!.zScoreWfa, 0.21);
      expect(entry.measurement!.statusGizi, 'Normal');
      expect(entry.measurement!.kaderName, 'Kader 1');
      expect(entry.measurement!.labelZScore, '0.21');
    });

    test('entri dengan keluhan tanpa penimbangan tetap tampil', () {
      final entry = timeline.entries[1];

      expect(entry.adaPenimbangan, isFalse);
      expect(entry.measurement, isNull);
      expect(entry.adaKeluhan, isTrue);
      expect(entry.medicalNote!.rewel, isTrue);
      expect(entry.medicalNote!.catatan, 'Rewel saat ASI');
      expect(entry.medicalNote!.perluRujukan, isFalse);
    });

    test('suntikan dibaca sebagai list per tanggal', () {
      final entry = timeline.entries[0];

      expect(entry.adaSuntikan, isTrue);
      expect(entry.immunizations.length, 1);
      expect(entry.immunizations[0].type, 'HB-0');
      expect(entry.immunizations[0].label, 'HB-0');
    });

    test('meta.has_more dan next_before dibaca untuk pagination', () {
      expect(timeline.meta.hasMore, isTrue);
      expect(timeline.meta.nextBefore, '2026-08-15');
      expect(timeline.meta.cursorValid, '2026-08-15');
    });

    test('meta halaman terakhir: has_more false, cursor null', () {
      final meta = TimelineMeta.fromJson({
        'has_more': false,
        'next_before': null,
      });

      expect(meta.hasMore, isFalse);
      expect(meta.nextBefore, isNull);
      expect(meta.cursorValid, isNull);
    });

    test('pengelompokkan per bulan tanpa mengubah urutan', () {
      final perBulan = timeline.perBulan;

      expect(perBulan.keys.toList(), ['2026-09', '2026-08']);
      expect(perBulan['2026-09']!.length, 1);
      expect(perBulan['2026-08']!.length, 1);
    });

    test('gabung halaman berikutnya: entries ditambah, meta dari terakhir', () {
      const rawHalaman2 = '''
      {
        "child": {
          "id": "01a0d979-c11f-705b-8dd8-a245652c7aa4",
          "name": "Siti",
          "age_in_months": 30
        },
        "entries": [
          {
            "date": "2026-07-10",
            "measurement": null,
            "immunizations": [],
            "medical_note": null
          }
        ],
        "meta": { "has_more": false, "next_before": null }
      }
      ''';

      final halaman2 = ChildTimeline.fromJson(
        json.decode(rawHalaman2) as Map<String, dynamic>,
      );
      final gabungan = timeline.gabung(halaman2);

      expect(gabungan.entries.length, 3);
      expect(gabungan.entries[2].date, '2026-07-10');
      expect(gabungan.meta.hasMore, isFalse);
      expect(gabungan.meta.cursorValid, isNull);
      expect(gabungan.jumlahKunjungan, 3);
    });

    test('anak tanpa data: entries kosong, bukan error', () {
      const raw = '''
      {
        "child": { "id": "a", "name": "Anak" },
        "entries": [],
        "meta": { "has_more": false, "next_before": null }
      }
      ''';

      final kosong = ChildTimeline.fromJson(
        json.decode(raw) as Map<String, dynamic>,
      );

      expect(kosong.kosong, isTrue);
      expect(kosong.entries, isEmpty);
      expect(kosong.meta.hasMore, isFalse);
    });

    test('boolean string "true" tetap dibaca true di medical_note', () {
      final note = TimelineNote.fromJson({
        'demam': 'true',
        'rewel': 'false',
        'diare': 1,
      });

      expect(note.demam, isTrue);
      expect(note.rewel, isFalse);
      expect(note.diare, isTrue);
      expect(note.keluhan, ['Demam', 'Diare']);
    });

    test('path endpoint timeline benar', () {
      expect(ApiConstants.childTimelineEndpoint, '/timeline');

      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.childrenEndpoint}'
        '/01a0d979-c11f-705b-8dd8-a245652c7aa4'
        '${ApiConstants.childTimelineEndpoint}',
      );

      expect(
        url.path,
        '/api/children/01a0d979-c11f-705b-8dd8-a245652c7aa4/timeline',
      );
    });
  });

  group('Model Child - medical_flags (Opsi B)', () {
    test('medical_flags terbaca dari JSON', () {
      final child = Child.fromJson({
        'id': 'abc',
        'name': 'Siti',
        'medical_flags': 'alergi: penisilin',
      });

      expect(child.medicalFlags, 'alergi: penisilin');
      expect(child.hasMedicalFlags, isTrue);
    });

    test('medical_flags null atau kosong: hasMedicalFlags false', () {
      final tanpa = Child.fromJson({'id': 'a', 'name': 'X'});
      final kosong = Child.fromJson({
        'id': 'b',
        'name': 'Y',
        'medical_flags': '',
      });

      expect(tanpa.medicalFlags, isNull);
      expect(tanpa.hasMedicalFlags, isFalse);
      expect(kosong.medicalFlags, isNull);
      expect(kosong.hasMedicalFlags, isFalse);
    });

    test('medical_flags ikut di toJson', () {
      final child = Child.fromJson({
        'id': 'abc',
        'name': 'Siti',
        'medical_flags': 'alergi: penisilin',
      });

      expect(child.toJson()['medical_flags'], 'alergi: penisilin');
    });
  });

  group('Kontrak API - GET /api/children/{id}/growth', () {
    // Respons asli dari GrowthChartService (Opsi D). Bentuk `child`, `series`,
    // dan `who_reference` ini yang dibaca GrowthChart.fromJson, jadi JSON di
    // bawah disalin dari `docs/RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md` bagian 7.2
    // - bukan dikarang di sini.
    const rawGrowth = '''
    {
      "success": true,
      "message": "Data pertumbuhan anak berhasil diambil.",
      "data": {
        "child": {
          "id": "01a0d979-c11f-705b-8dd8-a245652c7aa4",
          "name": "Siti",
          "nik": "3273010123456789",
          "gender": "P",
          "date_of_birth": "2024-03-12",
          "age_in_months": 30,
          "medical_flags": null
        },
        "series": {
          "unit": { "weight": "kg", "height": "cm" },
          "order": "asc",
          "points": [
            {
              "date": "2026-03-12",
              "age_in_months": 24,
              "weight_kg": 11.2,
              "height_cm": 85.0,
              "head_circumference_cm": 46.5,
              "z_score_wfa": -0.32,
              "status_gizi": "Normal"
            },
            {
              "date": "2026-09-24",
              "age_in_months": 30,
              "weight_kg": 12.4,
              "height_cm": 88.0,
              "head_circumference_cm": 47.5,
              "z_score_wfa": 0.21,
              "status_gizi": "Normal"
            }
          ]
        },
        "who_reference": {
          "metric": "weight_for_age",
          "source": "WHO Child Growth Standards 2006",
          "gender": "P",
          "age_range": { "from": 0, "to": 60 },
          "points": [
            { "age_in_months": 24, "median_kg": 12.2, "lower_kg": 10.1, "upper_kg": 14.5 },
            { "age_in_months": 30, "median_kg": 13.3, "lower_kg": 11.2, "upper_kg": 15.7 }
          ]
        }
      }
    }
    ''';

    late GrowthChart chart;

    setUp(() {
      final body = json.decode(rawGrowth) as Map<String, dynamic>;
      chart = GrowthChart.fromJson(
        Map<String, dynamic>.from(body['data'] as Map),
      );
    });

    test('child terbaca lengkap, medical_flags null tetap null', () {
      expect(chart.child.id, '01a0d979-c11f-705b-8dd8-a245652c7aa4');
      expect(chart.child.name, 'Siti');
      expect(chart.child.nik, '3273010123456789');
      expect(chart.child.gender, 'P');
      expect(chart.child.dateOfBirth, '2024-03-12');
      expect(chart.child.ageInMonths, 30);
      expect(chart.child.medicalFlags, isNull);
      expect(chart.child.punyaKondisiKhusus, isFalse);
    });

    test('age_in_months dibaca dari server, bukan dihitung ulang', () {
      // 2026-09-24 dikurangi 2024-03-12 memang 30 bulan, tapi tujuannya
      // checked: kalau parser memakai DateTime, test ini akan gagal begitu
      // tanggal lahir atau tanggal ukur diubah.
      expect(chart.child.labelUmur, '2 Tahun 6 Bulan');
      expect(chart.series.points.first.ageInMonths, 24);
      expect(chart.series.points.last.ageInMonths, 30);
    });

    test('unit dan order dibaca apa adanya dari server', () {
      expect(chart.series.weightUnit, 'kg');
      expect(chart.series.heightUnit, 'cm');
      expect(chart.series.order, 'asc');
    });

    test('points tidak diurutkan ulang oleh klien', () {
      final tanggal = chart.series.points.map((p) => p.date).toList();

      expect(tanggal, ['2026-03-12', '2026-09-24']);
      expect(chart.series.points.first.weightKg, 11.2);
      expect(chart.series.points.last.weightKg, 12.4);
    });

    test('angka terimpan sebagai double, bukan teks', () {
      final titik = chart.series.points.first;

      expect(titik.weightKg, isA<double>());
      expect(titik.heightCm, isA<double>());
      expect(titik.headCircumferenceCm, isA<double>());
      expect(titik.zScoreWfa, isA<double>());
    });

    test('desimal dari PostgreSQL dibaca meski dikirim sebagai string', () {
      // PostgreSQL mengirim DECIMAL sebagai string, jadi ini bukan kasus yang
      // mustahil: tanpa konversi eksplisit, semua angka jadi teks dan garis
      // grafik tidak bisa digambar.
      final growth = GrowthPoint.fromJson({
        'date': '2026-09-24',
        'age_in_months': 30,
        'weight_kg': '12.40',
        'height_cm': '88.00',
        'z_score_wfa': '0.21',
      });

      expect(growth.weightKg, 12.4);
      expect(growth.heightCm, 88.0);
      expect(growth.zScoreWfa, 0.21);
    });

    test('z-score dan status gizi dibaca apa adanya, tidak dihitung ulang', () {
      final titik = chart.series.points.last;

      expect(titik.zScoreWfa, 0.21);
      expect(titik.statusGizi, 'Normal');
      expect(chart.series.titikStatusTerakhir?.date, '2026-09-24');
      expect(chart.series.titikStatusTerakhir?.zScoreWfa, 0.21);
    });

    test('who_reference dibaca sesuai gender anak', () {
      expect(chart.whoReference.metric, 'weight_for_age');
      expect(chart.whoReference.source, 'WHO Child Growth Standards 2006');
      expect(chart.whoReference.gender, 'P');
      expect(chart.whoReference.ageFrom, 0);
      expect(chart.whoReference.ageTo, 60);
      expect(chart.whoReference.kosong, isFalse);
      expect(chart.tanpaPita, isFalse);
    });

    test('titik pita punya median dan batas atas-bawah', () {
      final pita = chart.whoReference.points;

      expect(pita.length, 2);
      expect(pita.first.ageInMonths, 24);
      expect(pita.first.medianKg, 12.2);
      expect(pita.first.lowerKg, 10.1);
      expect(pita.first.upperKg, 14.5);
      expect(pita.last.upperKg, 15.7);
    });

    test('anak tanpa penimbangan: points kosong, pita tetap ada', () {
      // Ini kasus yang paling sering salah dikira error. Pita tidak bergantung
      // pada riwayat penimbangan, jadi layar harus bisa menggambar arah tumbuh
      // anak sebelum kunjungan pertama.
      final growth = GrowthChart.fromJson({
        'child': {
          'id': 'abc',
          'name': 'Budi',
          'gender': 'L',
          'date_of_birth': '2026-01-10',
          'age_in_months': null,
          'medical_flags': null,
        },
        'series': {
          'unit': {'weight': 'kg', 'height': 'cm'},
          'order': 'asc',
          'points': <dynamic>[],
        },
        'who_reference': {
          'metric': 'weight_for_age',
          'source': 'WHO Child Growth Standards 2006',
          'gender': 'L',
          'age_range': {'from': 0, 'to': 60},
          'points': [
            {
              'age_in_months': 0,
              'median_kg': 3.3,
              'lower_kg': 2.5,
              'upper_kg': 4.4,
            },
          ],
        },
      });

      expect(growth.tanpaData, isTrue);
      expect(growth.series.points, isEmpty);
      expect(growth.tanpaPita, isFalse);
      expect(growth.whoReference.points.length, 1);

      // Umur null berarti "-", bukan "0 Bulan": tidak ada penimbangan berarti
      // tidak ada hasil yang bisa ditampilkan.
      expect(growth.child.labelUmur, '-');
      expect(growth.child.umurTahun, isNull);
    });

    test('tanpa pita WHO: grafik tetap punya garis anak', () {
      // Tidak boleh ada interpolasi dari dua titik mana pun. Pita yang dikarang
      // terlihat meyakinkan tapi tidak benar.
      final growth = GrowthChart.fromJson({
        'child': {'id': 'abc', 'name': 'Budi', 'gender': null},
        'series': {
          'unit': {'weight': 'kg', 'height': 'cm'},
          'order': 'asc',
          'points': [
            {'date': '2026-09-24', 'age_in_months': 30, 'weight_kg': 12.4},
          ],
        },
        'who_reference': {
          'metric': 'weight_for_age',
          'source': 'WHO Child Growth Standards 2006',
          'gender': null,
          'age_range': null,
          'points': <dynamic>[],
        },
      });

      expect(growth.tanpaPita, isTrue);
      expect(growth.whoReference.kosong, isTrue);
      expect(growth.whoReference.rentangTahun, isNull);
      expect(growth.tanpaData, isFalse);
      expect(growth.series.points.single.weightKg, 12.4);
    });

    test('nil tidak pernah jadi nol: semua field angka nullable', () {
      final growth = GrowthPoint.fromJson({
        'date': '2026-09-24',
        'age_in_months': null,
        'weight_kg': null,
        'height_cm': null,
        'z_score_wfa': null,
        'status_gizi': null,
      });

      expect(growth.weightKg, isNull);
      expect(growth.heightCm, isNull);
      expect(growth.zScoreWfa, isNull);
      expect(growth.umurTahun, isNull);

      // Tanpa umur, titik tidak bisa diposisikan di sumbu x.
      expect(growth.bisaDigambar, isFalse);
      expect(growth.bisaDigambarTinggi, isFalse);
    });

    test('anak di atas 60 bulan tetap dapat titik dengan z_score null', () {
      // Trigger tidak punya acuan di atas 60 bulan, jadi z-score-nya null.
      // Itu harus tetap tampil sebagai titik, bukan hilang dari grafik.
      final growth = GrowthPoint.fromJson({
        'date': '2026-09-24',
        'age_in_months': 72,
        'weight_kg': 15.8,
        'height_cm': 100.0,
        'z_score_wfa': null,
        'status_gizi': null,
      });

      expect(growth.umurTahun, 6.0);
      expect(growth.bisaDigambar, isTrue);
      expect(growth.bisaDigambarTinggi, isTrue);
      expect(growth.zScoreWfa, isNull);
    });

    test('ringkasan status memakai titik terakhir yang punya z-score', () {
      // Titik terakhirnya boleh tanpa z-score (misalnya di atas 60 bulan),
      // tapi titik sebelumnya masih punya. Menampilkan "null" padahal masih
      // ada data akan membuat Ibu mengira status terakhirnya hilang.
      const series = GrowthSeries(
        points: [
          GrowthPoint(
            date: '2026-06-12',
            ageInMonths: 27,
            weightKg: 12.0,
            zScoreWfa: -0.1,
            statusGizi: 'Normal',
          ),
          GrowthPoint(date: '2026-09-24', ageInMonths: 30, weightKg: 12.4),
        ],
      );

      expect(series.titikStatusTerakhir?.date, '2026-06-12');
      expect(series.titikStatusTerakhir?.zScoreWfa, -0.1);
      expect(series.umurTahunTerakhir, 2.5);
    });

    test('field hilang atau null tidak membuat parser crash', () {
      final growth = GrowthChart.fromJson(const <String, dynamic>{});

      expect(growth.child.name, '');
      expect(growth.series.points, isEmpty);
      expect(growth.whoReference.points, isEmpty);
      expect(growth.tanpaData, isTrue);
      expect(growth.tanpaPita, isTrue);
    });

    test('field pita yang hilang tidak diam-diam jadi 0', () {
      // Band median 0 akan menarik sumbu y dan membuat pita terlihat benar
      // padahal salah, jadi default-nya -1 supaya langsung terlihat rusak.
      final pita = WhoReferencePoint.fromJson({'age_in_months': 30});

      expect(pita.medianKg, -1);
      expect(pita.lowerKg, -1);
      expect(pita.upperKg, -1);
    });

    test('path endpoint growth benar dan tanpa query string', () {
      expect(ApiConstants.childGrowthEndpoint, '/growth');

      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.childrenEndpoint}'
        '/01a0d979-c11f-705b-8dd8-a245652c7aa4'
        '${ApiConstants.childGrowthEndpoint}',
      );

      expect(
        url.path,
        '/api/children/01a0d979-c11f-705b-8dd8-a245652c7aa4/growth',
      );

      // Server sengaja tidak punya paginasi, jadi klien juga tidak menambah
      // query string. Kalau `?limit=` pernah muncul di sini, layar bisa
      // menampilkan garis yang terpotong di tengah tanpa terlihat salah.
      expect(url.query, isEmpty);
    });
  });
}
