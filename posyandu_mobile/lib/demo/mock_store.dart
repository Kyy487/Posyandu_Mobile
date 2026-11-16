class MockStore {
  static const String kaderId = 'demo-kader-1';
  static const String kaderName = 'Rina Kader';

  static String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static String _isoNow() => DateTime.now().toIso8601String();

  static final List<Map<String, dynamic>> children = [
    {
      'id': 'demo-child-1',
      'nik': '3201010101010001',
      'name': 'Andi Pratama',
      'date_of_birth': '2025-09-15',
      'gender': 'L',
      'birth_weight': 3.2,
      'birth_height': 50,
      'medical_flags': 'alergi: debu',
      'parent_name': 'Siti Rahma',
      'mother': {
        'id': 'demo-mother-1',
        'name': 'Siti Rahma',
        'nik': '3201010101010001',
      },
      'last_measurement_date': '2026-09-15',
      'latest_z_score': 0.4,
      'nutritional_status': 'Normal',
    },
    {
      'id': 'demo-child-2',
      'nik': '3201010101010002',
      'name': 'Raka Surya',
      'date_of_birth': '2025-12-15',
      'gender': 'P',
      'birth_weight': 2.8,
      'birth_height': 48,
      'medical_flags': null,
      'parent_name': 'Rina Kader',
      'mother': {
        'id': 'demo-mother-2',
        'name': 'Rina Kader',
        'nik': '3201010101010002',
      },
      'last_measurement_date': '2026-09-15',
      'latest_z_score': -0.6,
      'nutritional_status': 'Gizi Kurang',
    },
  ];

  static Map<String, dynamic>? findChild(String id) {
    for (final child in children) {
      if (child['id'] == id) return child;
    }
    return null;
  }

  static Map<String, dynamic> getChild(String id) =>
      findChild(id) ?? children.first;

  static int ageInMonthsFor(String childId) {
    final child = findChild(childId);
    if (child == null) return 0;
    final dob = DateTime.tryParse(child['date_of_birth']?.toString() ?? '');
    if (dob == null) return 0;
    final now = DateTime.now();
    var months = (now.year - dob.year) * 12 + (now.month - dob.month);
    if (now.day < dob.day) months--;
    return months < 0 ? 0 : months;
  }

  static Map<String, dynamic> addChild(Map<String, dynamic> body) {
    final child = <String, dynamic>{
      'id': 'demo-child-${DateTime.now().millisecondsSinceEpoch}',
      'nik': body['nik']?.toString() ?? '',
      'name': body['name']?.toString() ?? '',
      'date_of_birth': body['date_of_birth']?.toString() ?? '',
      'gender': body['gender']?.toString() ?? '',
      'birth_weight': body['birth_weight'],
      'birth_height': body['birth_height'],
      'medical_flags': body['medical_flags'],
      'parent_name': body['parent_name']?.toString() ?? 'Ibu Demo',
      'mother': {
        'id': 'demo-mother-1',
        'name': body['parent_name']?.toString() ?? 'Ibu Demo',
      },
      'last_measurement_date': null,
      'latest_z_score': null,
      'nutritional_status': null,
    };
    children.add(child);
    return child;
  }

  static Map<String, dynamic> updateChild(
    String id,
    Map<String, dynamic> body,
  ) {
    final index = children.indexWhere((c) => c['id'] == id);
    if (index < 0) return {};
    children[index] = {...children[index], ...body};
    return children[index];
  }

  static final Map<String, List<Map<String, dynamic>>> measurements = {
    'demo-child-1': [
      {
        'id': 'meas-demo-child-1-12',
        'child_id': 'demo-child-1',
        'measurement_date': '2026-09-15',
        'weight_kg': 9.5,
        'height_cm': 78.5,
        'head_circumference_cm': 46,
        'age_in_months': 12,
        'z_score_wfa': 0.4,
        'status_gizi': 'Normal',
        'z_score_hfa': -0.3,
        'status_stunting': 'Normal',
        'z_score_bfa': 0.2,
        'status_gizi_imt': 'Normal',
        'z_score_wfh': 0.1,
        'status_wfh': 'Gizi Baik',
        'bmi': 12.48,
      },
      {
        'id': 'meas-demo-child-1-11',
        'child_id': 'demo-child-1',
        'measurement_date': '2026-08-15',
        'weight_kg': 9.8,
        'height_cm': 78.0,
        'head_circumference_cm': 45.5,
        'age_in_months': 11,
        'z_score_wfa': 0.2,
        'status_gizi': 'Normal',
        'z_score_hfa': -0.3,
        'status_stunting': 'Normal',
        'z_score_bfa': 0.2,
        'status_gizi_imt': 'Normal',
        'z_score_wfh': null,
        'status_wfh': null,
        'bmi': 12.83,
      },
    ],
    'demo-child-2': [
      {
        'id': 'meas-demo-child-2-9',
        'child_id': 'demo-child-2',
        'measurement_date': '2026-09-15',
        'weight_kg': 6.5,
        'height_cm': 62.0,
        'head_circumference_cm': 40,
        'age_in_months': 9,
        'z_score_wfa': -0.6,
        'status_gizi': 'Gizi Kurang',
        'z_score_hfa': -0.3,
        'status_stunting': 'Gizi Kurang',
        'z_score_bfa': 0.2,
        'status_gizi_imt': 'Gizi Kurang',
        'z_score_wfh': null,
        'status_wfh': null,
        'bmi': 10.67,
      },
      {
        'id': 'meas-demo-child-2-8',
        'child_id': 'demo-child-2',
        'measurement_date': '2026-08-15',
        'weight_kg': 6.3,
        'height_cm': 62.5,
        'head_circumference_cm': 39.5,
        'age_in_months': 8,
        'z_score_wfa': -0.5,
        'status_gizi': 'Gizi Kurang',
        'z_score_hfa': -0.3,
        'status_stunting': 'Gizi Kurang',
        'z_score_bfa': 0.2,
        'status_gizi_imt': 'Gizi Kurang',
        'z_score_wfh': null,
        'status_wfh': null,
        'bmi': 10.13,
      },
    ],
  };

  static List<Map<String, dynamic>> getMeasurements(String childId) =>
      measurements[childId] ?? [];

  static Map<String, dynamic>? findMeasurement(String id) {
    for (final list in measurements.values) {
      for (final measurement in list) {
        if (measurement['id'] == id) return measurement;
      }
    }
    return null;
  }

  static Map<String, dynamic> addMeasurement(
    String childId, {
    required double weight,
    required double height,
    int? ageInMonths,
    double? headCircumference,
    String? measurementDate,
  }) {
    final age = ageInMonths ?? ageInMonthsFor(childId);
    final bmi = double.parse(
      (weight / ((height / 100) * (height / 100))).toStringAsFixed(2),
    );
    final newMeasurement = <String, dynamic>{
      'id': 'meas-new-$childId-${DateTime.now().millisecondsSinceEpoch}',
      'child_id': childId,
      'measurement_date': measurementDate ?? _today(),
      'weight_kg': weight,
      'height_cm': height,
      'head_circumference_cm': headCircumference ?? 40 + age * 0.5,
      'age_in_months': age,
      'z_score_wfa': 0.0,
      'status_gizi': 'Normal',
      'z_score_hfa': -0.3,
      'status_stunting': 'Normal',
      'z_score_bfa': 0.2,
      'status_gizi_imt': 'Normal',
      'z_score_wfh': age < 24 ? 0.1 : null,
      'status_wfh': age < 24 ? 'Gizi Baik' : null,
      'bmi': bmi,
    };
    measurements.putIfAbsent(childId, () => []).insert(0, newMeasurement);
    updateChild(childId, {
      'last_measurement_date': newMeasurement['measurement_date'],
      'latest_z_score': newMeasurement['z_score_wfa'],
      'nutritional_status': newMeasurement['status_gizi'],
    });
    return newMeasurement;
  }

  static Map<String, dynamic> updateMeasurement(
    String id,
    Map<String, dynamic> body,
  ) {
    for (final list in measurements.values) {
      final index = list.indexWhere((m) => m['id'] == id);
      if (index >= 0) {
        list[index] = {...list[index], ...body};
        return list[index];
      }
    }
    return {};
  }

  static bool deleteMeasurement(String id) {
    for (final list in measurements.values) {
      final index = list.indexWhere((m) => m['id'] == id);
      if (index >= 0) {
        list.removeAt(index);
        return true;
      }
    }
    return false;
  }

  static final List<Map<String, dynamic>> immunizationTypes = [
    {
      'id': 'imm-hb0',
      'code': 'HB',
      'name': 'Hepatitis B',
      'dose_number': 1,
      'target_age_months': 0,
      'interval_months': null,
    },
    {
      'id': 'imm-bcg',
      'code': 'BCG',
      'name': 'BCG',
      'dose_number': 1,
      'target_age_months': 2,
      'interval_months': null,
    },
    {
      'id': 'imm-polio1',
      'code': 'POLIO',
      'name': 'Polio Oral',
      'dose_number': 1,
      'target_age_months': 2,
      'interval_months': null,
    },
    {
      'id': 'imm-mr1',
      'code': 'MR',
      'name': 'Campak-Rubella',
      'dose_number': 1,
      'target_age_months': 9,
      'interval_months': null,
    },
    {
      'id': 'imm-mr2',
      'code': 'MR',
      'name': 'Campak-Rubella',
      'dose_number': 2,
      'target_age_months': 18,
      'interval_months': 9,
    },
  ];

  static Map<String, dynamic>? findImmunizationType(String id) {
    for (final type in immunizationTypes) {
      if (type['id'] == id) return type;
    }
    return null;
  }

  static final Map<String, List<Map<String, dynamic>>> immunizationRecords = {
    'demo-child-1': [
      {
        'id': 'imm-rec-1',
        'child_id': 'demo-child-1',
        'immunization_type_id': 'imm-hb0',
        'date_given': '2025-09-15',
        'batch_number': 'HB-001',
        'notes': null,
        'kader_id': kaderId,
        'kader': {'id': kaderId, 'name': kaderName},
        'created_at': '2025-09-15T08:00:00+07:00',
        'updated_at': '2025-09-15T08:00:00+07:00',
      },
    ],
    'demo-child-2': [],
  };

  static List<Map<String, dynamic>> getImmunizationRecords(String childId) =>
      immunizationRecords[childId] ?? [];

  static Map<String, dynamic>? findImmunizationRecord(String id) {
    for (final list in immunizationRecords.values) {
      for (final record in list) {
        if (record['id'] == id) return record;
      }
    }
    return null;
  }

  static Map<String, dynamic> addImmunizationRecord(
    String childId,
    Map<String, dynamic> body,
  ) {
    final record = <String, dynamic>{
      'id': 'imm-rec-${DateTime.now().millisecondsSinceEpoch}',
      'child_id': childId,
      'immunization_type_id': body['immunization_type_id']?.toString() ?? '',
      'date_given': body['date_given']?.toString() ?? _today(),
      'batch_number': body['batch_number']?.toString(),
      'notes': body['notes']?.toString(),
      'kader_id': kaderId,
      'kader': {'id': kaderId, 'name': kaderName},
      'created_at': _isoNow(),
      'updated_at': _isoNow(),
    };
    immunizationRecords.putIfAbsent(childId, () => []).add(record);
    return record;
  }

  static Map<String, dynamic> updateImmunizationRecord(
    String id,
    Map<String, dynamic> body,
  ) {
    for (final list in immunizationRecords.values) {
      final index = list.indexWhere((r) => r['id'] == id);
      if (index >= 0) {
        list[index] = {...list[index], ...body, 'updated_at': _isoNow()};
        return list[index];
      }
    }
    return {};
  }

  static bool deleteImmunizationRecord(String id) {
    for (final list in immunizationRecords.values) {
      final index = list.indexWhere((r) => r['id'] == id);
      if (index >= 0) {
        list.removeAt(index);
        return true;
      }
    }
    return false;
  }

  static final Map<String, List<Map<String, dynamic>>> medicalNotes = {
    'demo-child-1': [
      {
        'id': 'note-1',
        'child_id': 'demo-child-1',
        'measurement_id': 'meas-demo-child-1-12',
        'kader_id': kaderId,
        'note_date': '2026-09-15',
        'demam': false,
        'rewel': true,
        'diare': false,
        'keluhan': ['Rewel'],
        'catatan': 'Rewel saat malam, masih mau makan.',
        'tindak_lanjut': 'ringan',
        'ringkasan': 'Rewel',
        'kader': {'id': kaderId, 'name': kaderName},
        'created_at': '2026-09-15T08:12:00+07:00',
        'updated_at': '2026-09-15T08:12:00+07:00',
      },
    ],
    'demo-child-2': [],
  };

  static List<Map<String, dynamic>> getMedicalNotes(String childId) =>
      medicalNotes[childId] ?? [];

  static Map<String, dynamic>? findMedicalNote(String id) {
    for (final list in medicalNotes.values) {
      for (final note in list) {
        if (note['id'] == id) return note;
      }
    }
    return null;
  }

  static Map<String, dynamic> addMedicalNote(
    String childId,
    Map<String, dynamic> body,
  ) {
    final keluhan = <String>[];
    if (body['demam'] == true) keluhan.add('Demam');
    if (body['rewel'] == true) keluhan.add('Rewel');
    if (body['diare'] == true) keluhan.add('Diare');
    final catatan = body['catatan']?.toString();
    final note = <String, dynamic>{
      'id': 'note-${DateTime.now().millisecondsSinceEpoch}',
      'child_id': childId,
      'measurement_id': body['measurement_id']?.toString(),
      'kader_id': kaderId,
      'note_date': body['note_date']?.toString() ?? _today(),
      'demam': body['demam'] == true,
      'rewel': body['rewel'] == true,
      'diare': body['diare'] == true,
      'keluhan': keluhan,
      'catatan': catatan,
      'tindak_lanjut': body['tindak_lanjut']?.toString() ?? 'ringan',
      'ringkasan': keluhan.isNotEmpty
          ? keluhan.join('; ')
          : (catatan == null || catatan.isEmpty ? '-' : 'Catatan: $catatan'),
      'kader': {'id': kaderId, 'name': kaderName},
      'created_at': _isoNow(),
      'updated_at': _isoNow(),
    };
    medicalNotes.putIfAbsent(childId, () => []).insert(0, note);
    return note;
  }

  static Map<String, dynamic> updateMedicalNote(
    String id,
    Map<String, dynamic> body,
  ) {
    for (final list in medicalNotes.values) {
      final index = list.indexWhere((n) => n['id'] == id);
      if (index >= 0) {
        list[index] = {...list[index], ...body, 'updated_at': _isoNow()};
        return list[index];
      }
    }
    return {};
  }

  static bool deleteMedicalNote(String id) {
    for (final list in medicalNotes.values) {
      final index = list.indexWhere((n) => n['id'] == id);
      if (index >= 0) {
        list.removeAt(index);
        return true;
      }
    }
    return false;
  }

  static final Map<String, List<Map<String, dynamic>>> referrals = {
    'demo-child-1': [
      {
        'id': 'ref-1',
        'child_id': 'demo-child-1',
        'visit_id': 'visit-1',
        'referral_date': '2026-09-15',
        'referral_type': 'puskesmas',
        'reason': 'Demam tinggi tiga hari',
        'facility_name': 'Puskesmas Sukamaju',
        'status': 'dilaporkan',
        'kader_id': kaderId,
        'kader': {'id': kaderId, 'name': kaderName},
        'created_at': '2026-09-15T08:00:00+07:00',
        'updated_at': '2026-09-15T08:00:00+07:00',
      },
    ],
    'demo-child-2': [],
  };

  static List<Map<String, dynamic>> getReferrals(String childId) =>
      referrals[childId] ?? [];

  static Map<String, dynamic>? findReferral(String id) {
    for (final list in referrals.values) {
      for (final referral in list) {
        if (referral['id'] == id) return referral;
      }
    }
    return null;
  }

  static Map<String, dynamic> addReferral(Map<String, dynamic> body) {
    final childId = body['child_id']?.toString() ?? '';
    final referral = <String, dynamic>{
      'id': 'ref-${DateTime.now().millisecondsSinceEpoch}',
      'child_id': childId,
      'visit_id': body['visit_id']?.toString(),
      'referral_date': body['referral_date']?.toString() ?? _today(),
      'referral_type': body['referral_type']?.toString() ?? 'puskesmas',
      'reason': body['reason']?.toString(),
      'facility_name': body['facility_name']?.toString() ?? '-',
      'status': body['status']?.toString() ?? 'dilaporkan',
      'kader_id': kaderId,
      'kader': {'id': kaderId, 'name': kaderName},
      'created_at': _isoNow(),
      'updated_at': _isoNow(),
    };
    referrals.putIfAbsent(childId, () => []).insert(0, referral);
    return referral;
  }

  static Map<String, dynamic> updateReferral(
    String id,
    Map<String, dynamic> body,
  ) {
    for (final list in referrals.values) {
      final index = list.indexWhere((r) => r['id'] == id);
      if (index >= 0) {
        list[index] = {...list[index], ...body, 'updated_at': _isoNow()};
        return list[index];
      }
    }
    return {};
  }

  static bool deleteReferral(String id) {
    for (final list in referrals.values) {
      final index = list.indexWhere((r) => r['id'] == id);
      if (index >= 0) {
        list.removeAt(index);
        return true;
      }
    }
    return false;
  }

  static final Map<String, List<Map<String, dynamic>>> visits = {
    'demo-child-1': [
      {
        'id': 'visit-1',
        'child_id': 'demo-child-1',
        'schedule_id': null,
        'visit_date': '2026-09-15',
        'visit_type': 'posyandu',
        'kader_id': kaderId,
        'kader': {'id': kaderId, 'name': kaderName},
        'anamnesis': 'Demam sejak dua hari',
        'catatan_kader': null,
        'created_at': '2026-09-15T08:00:00+07:00',
        'updated_at': '2026-09-15T08:00:00+07:00',
        'jumlah_pengukuran': 1,
        'jumlah_imunisasi': 1,
        'jumlah_keluhan': 1,
      },
    ],
    'demo-child-2': [],
  };

  static List<Map<String, dynamic>> getVisits(String childId) =>
      visits[childId] ?? [];

  static Map<String, dynamic>? findVisit(String id) {
    for (final list in visits.values) {
      for (final visit in list) {
        if (visit['id'] == id) return visit;
      }
    }
    return null;
  }

  static Map<String, dynamic> addVisit(Map<String, dynamic> body) {
    final childId = body['child_id']?.toString() ?? '';
    final visit = <String, dynamic>{
      'id': 'visit-${DateTime.now().millisecondsSinceEpoch}',
      'child_id': childId,
      'schedule_id': body['schedule_id']?.toString(),
      'visit_date': body['visit_date']?.toString() ?? _today(),
      'visit_type': body['visit_type']?.toString() ?? 'posyandu',
      'kader_id': kaderId,
      'kader': {'id': kaderId, 'name': kaderName},
      'anamnesis': body['anamnesis']?.toString(),
      'catatan_kader': body['catatan_kader']?.toString(),
      'created_at': _isoNow(),
      'updated_at': _isoNow(),
      'jumlah_pengukuran': 0,
      'jumlah_imunisasi': 0,
      'jumlah_keluhan': 0,
    };
    visits.putIfAbsent(childId, () => []).insert(0, visit);
    return visit;
  }

  static Map<String, dynamic> updateVisit(
    String id,
    Map<String, dynamic> body,
  ) {
    for (final list in visits.values) {
      final index = list.indexWhere((v) => v['id'] == id);
      if (index >= 0) {
        list[index] = {...list[index], ...body, 'updated_at': _isoNow()};
        return list[index];
      }
    }
    return {};
  }

  static final Map<String, List<Map<String, dynamic>>> consents = {
    'demo-child-1': [
      {
        'id': 'consent-1',
        'child_id': 'demo-child-1',
        'granted_by': 'demo-mother-1',
        'consent_type': 'data_processing',
        'granted_at': '2025-09-15T08:00:00+07:00',
        'revoked_at': null,
        'document_version': '1.0',
        'notes': null,
        'created_at': '2025-09-15T08:00:00+07:00',
        'updated_at': '2025-09-15T08:00:00+07:00',
      },
    ],
    'demo-child-2': [],
  };

  static List<Map<String, dynamic>> getConsents(String childId) =>
      (consents[childId] ?? []).where((c) => c['revoked_at'] == null).toList();

  static Map<String, dynamic> grantConsent(
    String childId,
    Map<String, dynamic> body,
  ) {
    final consent = <String, dynamic>{
      'id': 'consent-${DateTime.now().millisecondsSinceEpoch}',
      'child_id': childId,
      'granted_by': 'demo-mother-1',
      'consent_type': body['consent_type']?.toString() ?? 'data_processing',
      'granted_at': _isoNow(),
      'revoked_at': null,
      'document_version': body['document_version']?.toString() ?? '1.0',
      'notes': body['notes']?.toString(),
      'created_at': _isoNow(),
      'updated_at': _isoNow(),
    };
    consents.putIfAbsent(childId, () => []).add(consent);
    return consent;
  }

  static bool revokeConsent(String childId, String consentType) {
    final list = consents[childId] ?? [];
    for (var i = 0; i < list.length; i++) {
      if (list[i]['consent_type'] == consentType &&
          list[i]['revoked_at'] == null) {
        list[i] = {
          ...list[i],
          'revoked_at': _isoNow(),
          'updated_at': _isoNow(),
        };
        return true;
      }
    }
    return false;
  }

  static final List<Map<String, dynamic>> kaderRegistrations = [
    {
      'id': 'reg-1',
      'name': 'Anak Pertama',
      'nik': '3201010101010010',
      'phone_number': '081111111111',
      'place_of_birth': 'Bandung',
      'date_of_birth': '1995-01-10',
      'gender': 'P',
      'address': 'Jl. Melati No. 1',
      'status': 'pending',
      'created_at': '2026-09-20',
      'approved_at': null,
      'rejection_reason': null,
      'approver': null,
      'verifications': [],
    },
    {
      'id': 'reg-2',
      'name': 'Anak Kedua',
      'nik': '3201010101010011',
      'phone_number': '082222222222',
      'place_of_birth': 'Bandung',
      'date_of_birth': '1994-05-12',
      'gender': 'P',
      'address': 'Jl. Melati No. 2',
      'status': 'active',
      'created_at': '2026-09-18',
      'approved_at': '2026-09-19',
      'rejection_reason': null,
      'approver': {'id': kaderId, 'name': kaderName},
      'verifications': [],
    },
    {
      'id': 'reg-3',
      'name': 'Anak Ketiga',
      'nik': '3201010101010012',
      'phone_number': '083333333333',
      'place_of_birth': 'Bandung',
      'date_of_birth': '1993-11-03',
      'gender': 'P',
      'address': 'Jl. Melati No. 3',
      'status': 'rejected',
      'created_at': '2026-09-15',
      'approved_at': '2026-09-16',
      'rejection_reason': 'Dokumen tidak lengkap',
      'approver': {'id': kaderId, 'name': kaderName},
      'verifications': [],
    },
  ];

  static List<Map<String, dynamic>> getKaderRegistrations({String? status}) {
    if (status == null) return kaderRegistrations;
    return kaderRegistrations.where((r) => r['status'] == status).toList();
  }

  static Map<String, dynamic> approveRegistration(String regId) {
    final index = kaderRegistrations.indexWhere((r) => r['id'] == regId);
    if (index >= 0) {
      kaderRegistrations[index] = {
        ...kaderRegistrations[index],
        'status': 'active',
        'approved_at': _isoNow(),
        'rejection_reason': null,
        'approver': {'id': kaderId, 'name': kaderName},
      };
      return kaderRegistrations[index];
    }
    return {};
  }

  static Map<String, dynamic> rejectRegistration(
    String regId, {
    String? reason,
  }) {
    final index = kaderRegistrations.indexWhere((r) => r['id'] == regId);
    if (index >= 0) {
      kaderRegistrations[index] = {
        ...kaderRegistrations[index],
        'status': 'rejected',
        'approved_at': _isoNow(),
        'rejection_reason': reason ?? 'Ditolak',
        'approver': {'id': kaderId, 'name': kaderName},
      };
      return kaderRegistrations[index];
    }
    return {};
  }

  static Map<String, dynamic> registrationStatus() => {
    'status': 'active',
    'total': 3,
    'pending': 1,
    'active': 2,
    'rejected': 1,
  };

  static final List<Map<String, dynamic>> schedules = [
    {
      'id': 'sch-1',
      'title': 'Posyandu Bulanan',
      'scheduled_date': '2026-11-10',
      'start_time': '08:00',
      'end_time': '11:00',
      'location': 'Balai Desa',
      'location_name': 'Balai Desa Sehat',
      'description': 'Posyandu rutin bulanan',
      'status': 'terjadwal',
      'notes': null,
      'created_by': kaderId,
      'creator_name': kaderName,
      'petugas_ids': ['pet-1', 'pet-2'],
      'petugas': [
        {'id': 'pet-1', 'name': 'Bpk. Andi', 'jabatan': 'Kader Utama'},
        {'id': 'pet-2', 'name': 'Ibu Sari', 'jabatan': 'Kader Bantuan'},
      ],
    },
    {
      'id': 'sch-2',
      'title': 'Pemeriksaan Gizi',
      'scheduled_date': '2026-10-15',
      'start_time': '09:00',
      'end_time': '12:00',
      'location': 'Posyandu Melati',
      'location_name': 'Posyandu Melati',
      'description': 'Pemeriksaan gizi rutin anak',
      'status': 'selesai',
      'notes': null,
      'created_by': kaderId,
      'creator_name': kaderName,
      'petugas_ids': ['pet-3'],
      'petugas': [
        {'id': 'pet-3', 'name': 'Bpk. Joko', 'jabatan': 'Kader Koordinator'},
      ],
    },
    {
      'id': 'sch-3',
      'title': 'Rapat Kelompok',
      'scheduled_date': '2026-10-20',
      'start_time': '13:00',
      'end_time': '15:00',
      'location': 'Balai Desa',
      'location_name': 'Balai Desa Sehat',
      'description': 'Rapat kader musyawarah',
      'status': 'dibatalkan',
      'notes': 'Ditunda',
      'created_by': kaderId,
      'creator_name': kaderName,
      'petugas_ids': ['pet-1'],
      'petugas': [
        {'id': 'pet-1', 'name': 'Bpk. Andi', 'jabatan': 'Kader Utama'},
      ],
    },
  ];

  static List<Map<String, dynamic>> getSchedules({String? date}) {
    if (date == null || date.isEmpty) return schedules;
    return schedules.where((s) => s['scheduled_date'] == date).toList();
  }

  static List<Map<String, dynamic>> upcomingSchedules() => schedules
      .where((s) => s['status'] == 'terjadwal' || s['status'] == 'berlangsung')
      .toList();

  static List<Map<String, dynamic>> completedSchedules() =>
      schedules.where((s) => s['status'] == 'selesai').toList();

  static Map<String, dynamic> addSchedule(Map<String, dynamic> body) {
    final petugasIds =
        (body['petugas_ids'] as List?)?.map((e) => e.toString()).toList() ??
        <String>[];
    final petugas = petugasList
        .where((p) => petugasIds.contains(p['id']))
        .toList();
    final schedule = <String, dynamic>{
      'id': 'sch-${DateTime.now().millisecondsSinceEpoch}',
      'title': body['title']?.toString() ?? '',
      'scheduled_date': body['scheduled_date']?.toString() ?? _today(),
      'start_time': body['start_time']?.toString(),
      'end_time': body['end_time']?.toString(),
      'location': body['location']?.toString(),
      'location_name': body['location']?.toString(),
      'description': body['description']?.toString(),
      'status': body['status']?.toString() ?? 'terjadwal',
      'notes': body['notes']?.toString(),
      'created_by': kaderId,
      'creator_name': kaderName,
      'petugas_ids': petugasIds,
      'petugas': petugas,
    };
    schedules.add(schedule);
    return schedule;
  }

  static Map<String, dynamic> updateSchedule(
    String id,
    Map<String, dynamic> body,
  ) {
    final index = schedules.indexWhere((s) => s['id'] == id);
    if (index < 0) return {};
    final petugasIds = body['petugas_ids'] is List
        ? (body['petugas_ids'] as List).map((e) => e.toString()).toList()
        : null;
    final updated = {...schedules[index], ...body};
    if (petugasIds != null) {
      updated['petugas_ids'] = petugasIds;
      updated['petugas'] = petugasList
          .where((p) => petugasIds.contains(p['id']))
          .toList();
    }
    schedules[index] = updated;
    return schedules[index];
  }

  static bool deleteSchedule(String id) {
    final index = schedules.indexWhere((s) => s['id'] == id);
    if (index >= 0) {
      schedules.removeAt(index);
      return true;
    }
    return false;
  }

  static final List<Map<String, dynamic>> petugasList = [
    {
      'id': 'pet-1',
      'name': 'Bpk. Andi',
      'jabatan': 'Kader Utama',
      'phone_number': '081200000001',
    },
    {
      'id': 'pet-2',
      'name': 'Ibu Sari',
      'jabatan': 'Kader Bantuan',
      'phone_number': '081200000002',
    },
    {
      'id': 'pet-3',
      'name': 'Bpk. Joko',
      'jabatan': 'Kader Koordinator',
      'phone_number': '081200000003',
    },
  ];

  static List<Map<String, dynamic>> getPetugas() => petugasList;
}
