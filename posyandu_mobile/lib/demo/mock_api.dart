import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'demo_mode.dart';
import 'mock_store.dart';

class MockApiClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final method = request.method.toUpperCase();
    final uri = request.url;
    final rawBody = await request.finalize().bytesToString();
    final body = _tryMap(rawBody);
    final seg = _segments(uri);

    if (seg.isEmpty) return _fail('Endpoint tidak dikenal', 404);

    if (seg.length == 1) {
      if (seg[0] == 'login' && method == 'POST') {
        return _ok({
          'token': DemoMode.token,
          'user': DemoMode.currentUser,
        }, message: 'Login demo berhasil');
      }
      if (seg[0] == 'register' && method == 'POST') {
        return _ok({
          'token': DemoMode.token,
          'user': DemoMode.currentUser,
        }, message: 'Registrasi demo berhasil');
      }
      if (seg[0] == 'logout' && method == 'POST') {
        DemoMode.disable();
        return _ok(null, message: 'Logout berhasil');
      }
      if (seg[0] == 'user' && method == 'GET') {
        return _ok(DemoMode.currentUser);
      }
      if (seg[0] == 'profile' && (method == 'GET' || method == 'PUT')) {
        return _ok(DemoMode.currentUser);
      }
      if (seg[0] == 'immunization-types' && method == 'GET') {
        return _ok(MockStore.immunizationTypes);
      }
      if (seg[0] == 'petugas' && method == 'GET') {
        return _ok(MockStore.getPetugas());
      }
      if (seg[0] == 'schedules' && method == 'GET') {
        return _ok(MockStore.getSchedules(date: uri.queryParameters['date']));
      }
      if (seg[0] == 'children' && method == 'GET') {
        return _ok(MockStore.children);
      }
      if (seg[0] == 'children' && method == 'POST') {
        return _ok(MockStore.addChild(body), status: 201);
      }
      if (seg[0] == 'referrals' && method == 'POST') {
        return _ok(MockStore.addReferral(body), status: 201);
      }
      if (seg[0] == 'visits' && method == 'POST') {
        return _ok(MockStore.addVisit(body), status: 201);
      }
      return _fail('Endpoint tidak dikenal: ${seg[0]}', 404);
    }

    if (seg[0] == 'children') {
      if (seg.length == 2) {
        final childId = seg[1];
        if (method == 'PATCH') {
          return _ok(MockStore.updateChild(childId, body));
        }
        if (method == 'GET') {
          return _ok(MockStore.getChild(childId));
        }
      }

      if (seg.length == 3) {
        final childId = seg[1];
        final resource = seg[2];

        if (resource == 'detail' && method == 'GET') {
          return _ok(MockStore.getChild(childId));
        }
        if (resource == 'measurements') {
          if (method == 'GET') {
            return _ok(MockStore.getMeasurements(childId));
          }
          if (method == 'POST') {
            return _ok(
              MockStore.addMeasurement(
                childId,
                weight: _double(body['weight_kg']),
                height: _double(body['height_cm']),
                ageInMonths: _intOrNull(body['age_in_months']),
                headCircumference: _doubleOrNull(body['head_circumference_cm']),
                measurementDate: _strOrNull(body['measurement_date']),
              ),
              status: 201,
            );
          }
        }
        if (resource == 'timeline' && method == 'GET') {
          return _ok(_buildTimeline(childId));
        }
        if (resource == 'growth' && method == 'GET') {
          return _ok(_buildGrowth(childId));
        }
        if (resource == 'immunizations' && method == 'GET') {
          return _ok(_buildChecklist(childId));
        }
        if (resource == 'medical-notes' && method == 'GET') {
          return _ok(_buildMedicalNotes(childId, uri));
        }
        if (resource == 'referrals' && method == 'GET') {
          return _ok(_buildReferrals(childId));
        }
        if (resource == 'visits' && method == 'GET') {
          return _ok(_buildVisits(childId));
        }
        if (resource == 'consents') {
          if (method == 'GET') {
            return _ok(MockStore.getConsents(childId));
          }
          if (method == 'POST') {
            return _ok(MockStore.grantConsent(childId, body), status: 201);
          }
          if (method == 'DELETE') {
            return _ok(
              MockStore.revokeConsent(
                childId,
                body['consent_type']?.toString() ?? '',
              ),
            );
          }
        }
      }
    }

    if (seg[0] == 'kader') {
      if (seg.length == 2) {
        if (seg[1] == 'children') {
          if (method == 'GET') return _ok(MockStore.children);
          if (method == 'POST') {
            return _ok(MockStore.addChild(body), status: 201);
          }
        }
        if (seg[1] == 'measurements') {
          if (method == 'GET') {
            final childId = uri.queryParameters['child_id'] ?? '';
            return _ok(MockStore.getMeasurements(childId));
          }
          if (method == 'POST') {
            final childId = body['child_id']?.toString() ?? '';
            return _ok(
              MockStore.addMeasurement(
                childId,
                weight: _double(body['weight_kg']),
                height: _double(body['height_cm']),
                measurementDate: _strOrNull(body['measurement_date']),
              ),
              status: 201,
            );
          }
        }
        if (seg[1] == 'schedules') {
          if (method == 'GET') return _ok(MockStore.getSchedules());
          if (method == 'POST') {
            return _ok(MockStore.addSchedule(body), status: 201);
          }
        }
        if (seg[1] == 'registrations' && method == 'GET') {
          return _ok(
            MockStore.getKaderRegistrations(
              status: uri.queryParameters['status'],
            ),
          );
        }
      }

      if (seg.length == 3) {
        if (seg[1] == 'measurements') {
          if (method == 'PATCH') {
            return _ok(MockStore.updateMeasurement(seg[2], body));
          }
          if (method == 'DELETE') {
            return _ok(MockStore.deleteMeasurement(seg[2]));
          }
        }
        if (seg[1] == 'immunizations' && seg[2] == 'recap' && method == 'GET') {
          return _ok(_buildRecap(uri));
        }
        if (seg[1] == 'immunizations') {
          if (method == 'PATCH') {
            return _ok(MockStore.updateImmunizationRecord(seg[2], body));
          }
          if (method == 'DELETE') {
            return _ok(MockStore.deleteImmunizationRecord(seg[2]));
          }
        }
        if (seg[1] == 'medical-notes') {
          if (method == 'PATCH') {
            return _ok(MockStore.updateMedicalNote(seg[2], body));
          }
          if (method == 'DELETE') {
            return _ok(MockStore.deleteMedicalNote(seg[2]));
          }
        }
        if (seg[1] == 'schedules') {
          if (method == 'PATCH') {
            return _ok(MockStore.updateSchedule(seg[2], body));
          }
          if (method == 'DELETE') {
            return _ok(MockStore.deleteSchedule(seg[2]));
          }
        }
      }

      if (seg.length == 4 && seg[1] == 'children') {
        final childId = seg[2];
        final resource = seg[3];
        if (resource == 'immunizations' && method == 'POST') {
          return _ok(
            MockStore.addImmunizationRecord(childId, body),
            status: 201,
          );
        }
        if (resource == 'medical-notes' && method == 'POST') {
          return _ok(MockStore.addMedicalNote(childId, body), status: 201);
        }
      }

      if (seg.length == 4 && seg[1] == 'registrations' && method == 'POST') {
        final id = seg[2];
        final action = seg[3];
        if (action == 'approve') {
          return _ok(MockStore.approveRegistration(id));
        }
        if (action == 'reject') {
          return _ok(
            MockStore.rejectRegistration(
              id,
              reason: body['rejection_reason']?.toString(),
            ),
          );
        }
      }
    }

    if (seg[0] == 'referrals' && seg.length == 2) {
      if (method == 'PATCH') {
        return _ok(MockStore.updateReferral(seg[1], body));
      }
      if (method == 'DELETE') {
        return _ok(MockStore.deleteReferral(seg[1]));
      }
    }

    if (seg[0] == 'visits' && seg.length == 2 && method == 'PATCH') {
      return _ok(MockStore.updateVisit(seg[1], body));
    }

    if (seg[0] == 'registration') {
      if (seg.length == 2 && seg[1] == 'status' && method == 'GET') {
        return _ok(MockStore.registrationStatus());
      }
      if (seg.length == 2 && seg[1] == 'complete' && method == 'POST') {
        return _ok({'message': 'Registrasi lengkap', 'status': 'active'});
      }
      if (seg.length == 2 && seg[1] == 'child' && method == 'POST') {
        return _ok({
          'child': MockStore.addChild(body),
          'user': DemoMode.currentUser,
        }, status: 201);
      }
    }

    return _fail('Endpoint tidak dikenal: ${uri.path}', 404);
  }

  static Map<String, dynamic> _buildChecklist(String childId) {
    final child = MockStore.getChild(childId);
    final age = MockStore.ageInMonthsFor(childId);
    final records = MockStore.getImmunizationRecords(childId);
    final items = <Map<String, dynamic>>[];

    for (final type in MockStore.immunizationTypes) {
      final matching = records
          .where((r) => r['immunization_type_id'] == type['id'])
          .toList();
      final target = _int(type['target_age_months']);
      final monthsLeft = target - age;
      final status = matching.isNotEmpty
          ? 'sudah'
          : (monthsLeft < 0 ? 'terlambat' : 'belum');
      items.add({
        'immunization_type_id': type['id'],
        'code': type['code'],
        'name': type['name'],
        'label': _immunizationLabel(type),
        'dose_number': type['dose_number'],
        'target_age_months': target,
        'interval_months': type['interval_months'],
        'status': status,
        'sisa_bulan': monthsLeft,
        'record': matching.isEmpty ? null : matching.first,
      });
    }

    return {
      'child': {
        'id': child['id'],
        'name': child['name'],
        'date_of_birth': child['date_of_birth'],
        'gender': child['gender'],
      },
      'summary': {
        'sudah': items.where((e) => e['status'] == 'sudah').length,
        'belum': items.where((e) => e['status'] == 'belum').length,
        'terlambat': items.where((e) => e['status'] == 'terlambat').length,
        'total': items.length,
      },
      'checklist': items,
    };
  }

  static Map<String, dynamic> _buildTimeline(String childId) {
    final child = MockStore.getChild(childId);
    final measurements = [...MockStore.getMeasurements(childId)]
      ..sort(
        (a, b) => (b['measurement_date'] ?? '').toString().compareTo(
          (a['measurement_date'] ?? '').toString(),
        ),
      );
    final records = MockStore.getImmunizationRecords(childId);
    final notes = MockStore.getMedicalNotes(childId);
    final refs = MockStore.getReferrals(childId);

    final dates = <String>{};
    for (final measurement in measurements) {
      dates.add(measurement['measurement_date']?.toString() ?? '');
    }
    for (final record in records) {
      dates.add(record['date_given']?.toString() ?? '');
    }
    for (final note in notes) {
      dates.add(note['note_date']?.toString() ?? '');
    }
    for (final referral in refs) {
      dates.add(referral['referral_date']?.toString() ?? '');
    }
    dates.remove('');

    final sortedDates = dates.toList()..sort((a, b) => b.compareTo(a));
    final entries = <Map<String, dynamic>>[];

    for (final date in sortedDates) {
      final measurement = _firstOrNull(
        measurements.where((m) => m['measurement_date'] == date),
      );
      final note = _firstOrNull(notes.where((n) => n['note_date'] == date));
      final entryReferrals = refs
          .where((r) => r['referral_date'] == date)
          .toList();
      final entryRecords = records
          .where((r) => r['date_given'] == date)
          .toList();

      entries.add({
        'date': date,
        'measurement': measurement == null
            ? null
            : {
                'weight_kg': measurement['weight_kg'],
                'height_cm': measurement['height_cm'],
                'head_circumference_cm': measurement['head_circumference_cm'],
                'z_score_wfa': measurement['z_score_wfa'],
                'status_gizi': measurement['status_gizi'],
                'kader': {'id': MockStore.kaderId, 'name': MockStore.kaderName},
              },
        'immunizations': entryRecords.map((record) {
          final type = MockStore.findImmunizationType(
            record['immunization_type_id']?.toString() ?? '',
          );
          return {
            'type': type?['code'] ?? record['immunization_type_id'],
            'date_given': record['date_given'],
          };
        }).toList(),
        'medical_note': note == null
            ? null
            : {
                'demam': note['demam'],
                'rewel': note['rewel'],
                'diare': note['diare'],
                'catatan': note['catatan'],
                'tindak_lanjut': note['tindak_lanjut'],
              },
        'referrals': entryReferrals.map((referral) {
          return {
            'id': referral['id'],
            'referral_date': referral['referral_date'],
            'referral_type': referral['referral_type'],
            'reason': referral['reason'],
            'facility_name': referral['facility_name'],
            'status': referral['status'],
            'kader': referral['kader'],
          };
        }).toList(),
      });
    }

    final latest = _firstOrNull(measurements);

    return {
      'child': {
        'id': child['id'],
        'name': child['name'],
        'nik': child['nik'],
        'date_of_birth': child['date_of_birth'],
        'age_in_months': MockStore.ageInMonthsFor(childId),
        'gender': child['gender'],
        'mother': child['mother'],
        'medical_flags': child['medical_flags'],
        'latest_measurement': latest == null
            ? null
            : {
                'weight_kg': latest['weight_kg'],
                'status_gizi': latest['status_gizi'],
              },
      },
      'entries': entries,
      'meta': {'has_more': false, 'next_before': null},
    };
  }

  static Map<String, dynamic> _buildGrowth(String childId) {
    final child = MockStore.getChild(childId);
    final measurements = [...MockStore.getMeasurements(childId)]
      ..sort(
        (a, b) => (a['measurement_date'] ?? '').toString().compareTo(
          (b['measurement_date'] ?? '').toString(),
        ),
      );

    final points = measurements.map((measurement) {
      return {
        'date': measurement['measurement_date'],
        'age_in_months': measurement['age_in_months'],
        'weight_kg': measurement['weight_kg'],
        'height_cm': measurement['height_cm'],
        'head_circumference_cm': measurement['head_circumference_cm'],
        'bmi': measurement['bmi'],
        'z_score_wfa': measurement['z_score_wfa'],
        'status_gizi': measurement['status_gizi'],
        'z_score_hfa': measurement['z_score_hfa'],
        'status_stunting': measurement['status_stunting'],
        'z_score_bfa': measurement['z_score_bfa'],
        'status_gizi_imt': measurement['status_gizi_imt'],
        'z_score_wfh': measurement['z_score_wfh'],
        'status_wfh': measurement['status_wfh'],
      };
    }).toList();

    final ages = points
        .map((p) => _intOrNull(p['age_in_months']))
        .whereType<int>()
        .toList();
    final minAge = ages.isEmpty ? 0 : ages.reduce((a, b) => a < b ? a : b);
    final maxAge = ages.isEmpty ? 24 : ages.reduce((a, b) => a > b ? a : b);

    final bands = <Map<String, dynamic>>[];
    if (ages.isNotEmpty) {
      final uniqueAges = ages.toSet().toList()..sort();
      bands.add({
        'metric': 'weight_for_age',
        'label': 'BB/U',
        'unit': 'kg',
        'x_axis': 'age_in_months',
        'source': 'WHO Child Growth Standards 2006',
        'gender': child['gender'],
        'age_range': {'from': minAge, 'to': maxAge},
        'points': uniqueAges
            .map(
              (age) => {
                'age_in_months': age,
                'median': 10.0,
                'lower': 8.0,
                'upper': 12.0,
              },
            )
            .toList(),
      });
      bands.add({
        'metric': 'height_for_age',
        'label': 'TB/U',
        'unit': 'cm',
        'x_axis': 'age_in_months',
        'source': 'WHO Child Growth Standards 2006',
        'gender': child['gender'],
        'age_range': {'from': minAge, 'to': maxAge},
        'points': uniqueAges
            .map(
              (age) => {
                'age_in_months': age,
                'median': 75.0,
                'lower': 70.0,
                'upper': 82.0,
              },
            )
            .toList(),
      });
      bands.add({
        'metric': 'bmi_for_age',
        'label': 'IMT/U',
        'unit': 'kg/m2',
        'x_axis': 'age_in_months',
        'source': 'WHO Child Growth Standards 2006',
        'gender': child['gender'],
        'age_range': {'from': minAge, 'to': maxAge},
        'points': uniqueAges
            .map(
              (age) => {
                'age_in_months': age,
                'median': 16.0,
                'lower': 14.0,
                'upper': 19.0,
              },
            )
            .toList(),
      });
    }

    return {
      'child': {
        'id': child['id'],
        'name': child['name'],
        'nik': child['nik'],
        'gender': child['gender'],
        'date_of_birth': child['date_of_birth'],
        'age_in_months': MockStore.ageInMonthsFor(childId),
        'medical_flags': child['medical_flags'],
      },
      'series': {
        'unit': {'weight': 'kg', 'height': 'cm', 'bmi': 'kg/m2'},
        'order': 'asc',
        'points': points,
      },
      'who_reference': bands.isEmpty ? null : bands.first,
      'who_references': bands,
    };
  }

  static Map<String, dynamic> _buildMedicalNotes(String childId, Uri uri) {
    final child = MockStore.getChild(childId);
    final month = uri.queryParameters['month'];
    final all = uri.queryParameters['all'] == 'true';
    final notes = MockStore.getMedicalNotes(childId).where((note) {
      if (all || month == null || month.isEmpty) return true;
      return (note['note_date'] ?? '').toString().startsWith(month);
    }).toList();

    return {
      'child': {'id': child['id'], 'name': child['name']},
      'filter': {'month': month, 'all': all},
      'summary': {
        'total': notes.length,
        'demam': notes.where((n) => n['demam'] == true).length,
        'rewel': notes.where((n) => n['rewel'] == true).length,
        'diare': notes.where((n) => n['diare'] == true).length,
        'perlu_rujuk': notes.where((n) => n['tindak_lanjut'] == 'rujuk').length,
      },
      'notes': notes,
    };
  }

  static Map<String, dynamic> _buildReferrals(String childId) {
    final child = MockStore.getChild(childId);
    return {
      'child': {'id': child['id'], 'name': child['name']},
      'referrals': MockStore.getReferrals(childId),
    };
  }

  static Map<String, dynamic> _buildVisits(String childId) {
    final child = MockStore.getChild(childId);
    return {
      'child': {'id': child['id'], 'name': child['name']},
      'visits': MockStore.getVisits(childId),
    };
  }

  static Map<String, dynamic> _buildRecap(Uri uri) {
    final month = uri.queryParameters['month'] ?? _currentMonth();
    final byType = <Map<String, dynamic>>[];
    var totalDoses = 0;
    final childIdsWithDoses = <String>{};

    for (final type in MockStore.immunizationTypes) {
      var count = 0;
      for (final entry in MockStore.immunizationRecords.entries) {
        final records = entry.value
            .where((r) => r['immunization_type_id'] == type['id'])
            .toList();
        count += records.length;
        if (records.isNotEmpty) childIdsWithDoses.add(entry.key);
      }
      totalDoses += count;
      byType.add({
        'immunization_type_id': type['id'],
        'code': type['code'],
        'name': type['name'],
        'label': _immunizationLabel(type),
        'dose_number': type['dose_number'],
        'count': count,
      });
    }

    final overdueChildren = <Map<String, dynamic>>[];
    for (final child in MockStore.children) {
      final childId = child['id'].toString();
      final age = MockStore.ageInMonthsFor(childId);
      final records = MockStore.getImmunizationRecords(childId);
      final overdue = <Map<String, dynamic>>[];
      for (final type in MockStore.immunizationTypes) {
        final target = _int(type['target_age_months']);
        final hasRecord = records.any(
          (r) => r['immunization_type_id'] == type['id'],
        );
        if (!hasRecord && target < age) {
          overdue.add({
            'immunization_type_id': type['id'],
            'code': type['code'],
            'name': type['name'],
            'label': _immunizationLabel(type),
            'dose_number': type['dose_number'],
            'target_age_months': target,
            'sisa_bulan': target - age,
          });
        }
      }
      if (overdue.isNotEmpty) {
        overdueChildren.add({
          'child_id': childId,
          'name': child['name'],
          'date_of_birth': child['date_of_birth'],
          'age_in_months': age,
          'overdue_doses': overdue,
        });
      }
    }

    return {
      'filter': {'month': month, 'reference_date': _today()},
      'activity': {
        'total_doses': totalDoses,
        'total_children': childIdsWithDoses.length,
        'by_type': byType,
      },
      'coverage': {
        'total_children': MockStore.children.length,
        'complete': 0,
        'incomplete': MockStore.children.length,
        'overdue': overdueChildren.length,
        'excluded_archived': 0,
        'overdue_children': overdueChildren,
      },
    };
  }

  static T? _firstOrNull<T>(Iterable<T> items) {
    for (final item in items) {
      return item;
    }
    return null;
  }

  static String _immunizationLabel(Map<String, dynamic> type) {
    final name = type['name']?.toString() ?? '-';
    final dose = _int(type['dose_number']);
    return dose > 1 ? '$name (Dosis $dose)' : name;
  }

  static String _currentMonth() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  static String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static int _int(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _intOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static double _double(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _doubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static String? _strOrNull(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static List<String> _segments(Uri uri) {
    final segments = <String>[];
    if (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'api') {
      segments.addAll(uri.pathSegments.sublist(1));
    } else {
      segments.addAll(uri.pathSegments);
    }
    return segments;
  }

  static Map<String, dynamic> _tryMap(String? body) {
    if (body == null || body.isEmpty) return {};
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  static http.StreamedResponse _ok(
    dynamic json, {
    int status = 200,
    String message = 'OK',
  }) {
    final body = jsonEncode({
      'success': true,
      'message': message,
      'data': json,
    });
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      status,
      reasonPhrase: message,
    );
  }

  static http.StreamedResponse _fail(String message, int status) {
    final body = jsonEncode({'success': false, 'message': message});
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      status,
    );
  }
}
