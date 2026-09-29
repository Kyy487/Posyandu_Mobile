import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/medical_note.dart';
import '../utils/constants.dart';
import 'auth_service.dart';

/// Akses endpoint catatan keluhan (Opsi C).
///
/// Bentuk respons mengikuti JSON Envelope backend: `{success, message, data,
/// errors}`. Empat helper di bawah (offline / sesi habis / decode / result)
/// sengaja disalin apa adanya dari `ImmunizationService` supaya perilaku
/// error di semua layar seragam.
class MedicalNoteService {
  final String baseUrl = ApiConstants.baseUrl;
  final AuthService _auth = AuthService();

  static const _offline =
      'Tidak dapat terhubung ke server. Pastikan backend Laravel berjalan.';

  Map<String, dynamic> _offlineError() => {
    'success': false,
    'message': _offline,
    'data': null,
    'errors': null,
  };

  /// Hasil error sesi habis. `status: 401` dipakai layar untuk mengarahkan
  /// user login ulang, sama seperti service lain.
  Map<String, dynamic> _sessionEnded() => {
    'success': false,
    'status': 401,
    'message': 'Sesi telah berakhir. Silakan login kembali.',
    'data': null,
    'errors': null,
  };

  Future<Map<String, String>?> _authHeaders({bool json = false}) async {
    final token = await _auth.getToken();

    if (token == null || token.isEmpty) {
      return null;
    }

    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {
        'success': false,
        'message':
            'Respons server tidak valid (bukan JSON). '
            'Status code: ${response.statusCode}',
        'data': null,
        'errors': null,
      };
    }
  }

  /// Daftar catatan keluhan satu anak.
  ///
  /// [month] berformat `YYYY-MM`. Null berarti server memakai bulan
  /// berjalan, jadi layar cukup mengirim filter kalau Ibu benar-benar
  /// memilih bulan lain.
  ///
  /// Endpoint ini dibaca Ibu maupun Kader. Pembatasan "Ibu hanya boleh melihat
  /// anaknya sendiri" ditegakkan server, bukan di sini.
  Future<Map<String, dynamic>> getNotes(
    String childId, {
    String? month,
    bool all = false,
  }) async {
    final headers = await _authHeaders();

    if (headers == null) {
      return _sessionEnded();
    }

    final query = <String, String>{
      if (month != null && month.isNotEmpty) 'month': month,
      if (all) 'all': '1',
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';

    try {
      final response = await http.get(
        Uri.parse(
          '$baseUrl${ApiConstants.childrenEndpoint}'
          '/$childId/medical-notes$suffix',
        ),
        headers: headers,
      );

      if (response.statusCode == 401) {
        await _auth.logout();
        return _sessionEnded();
      }

      final body = _decode(response);

      if (response.statusCode == 200 && body['success'] == true) {
        return {
          'success': true,
          'message': body['message'],
          'data': MedicalNoteList.fromJson(
            Map<String, dynamic>.from(body['data'] as Map),
          ),
        };
      }

      return {
        'success': false,
        'message':
            body['message']?.toString() ?? 'Gagal memuat catatan keluhan.',
        'data': null,
        'errors': body['errors'],
      };
    } on SocketException {
      return _offlineError();
    } on FormatException {
      return {
        'success': false,
        'message': 'Format data JSON dari server rusak atau tidak valid.',
        'data': null,
        'errors': null,
      };
    }
  }

  /// Mencatat keluhan baru. Hanya Kader yang boleh memanggilnya.
  ///
  /// [noteDate] harus format `YYYY-MM-DD`. Server menolak format lain dengan
  /// 422 (bukan 500) karena rules `date_format:Y-m-d`.
  ///
  /// Server membalas 422 dengan `errors.note_date` bila anak itu sudah punya
  /// catatan pada tanggal tersebut. Kader harus mengoreksi catatan yang lama
  /// lewat [updateNote], bukan mencatat ulang.
  Future<Map<String, dynamic>> addNote({
    required String childId,
    required String noteDate,
    bool demam = false,
    bool rewel = false,
    bool diare = false,
    String? catatan,
    String? tindakLanjut,
    String? measurementId,
  }) async {
    final headers = await _authHeaders(json: true);

    if (headers == null) {
      return _sessionEnded();
    }

    try {
      final response = await http.post(
        Uri.parse(
          '$baseUrl${ApiConstants.kaderChildrenEndpoint}'
          '/$childId/medical-notes',
        ),
        headers: headers,
        body: json.encode({
          'note_date': noteDate,
          'demam': demam,
          'rewel': rewel,
          'diare': diare,
          'catatan': ?catatan,
          'tindak_lanjut': ?tindakLanjut,
          'measurement_id': ?measurementId,
        }),
      );

      if (response.statusCode == 401) {
        return _sessionEnded();
      }

      return _noteResult(response, 'Gagal menyimpan catatan keluhan.');
    } on SocketException {
      return _offlineError();
    }
  }

  /// Koreksi satu catatan keluhan.
  ///
  /// Partial update: hanya field yang tidak null yang dikirim. `catatan`
  /// kosong TETAP diteruskan sebagai string kosong, supaya kader bisa
  /// mengosongkan field itu - server yang memutuskan apakah catatan sisa
  /// itu masih punya isi atau tidak.
  ///
  /// `noteDate` boleh diubah, berbeda dari koreksi suntikan yang mengunci
  /// tanggal. Kesalahan tanggal pada catatan keluhan adalah salah pilih hari
  /// di kalender, bukan keputusan yang perlu dibatalkan lalu diulang.
  Future<Map<String, dynamic>> updateNote({
    required String noteId,
    String? noteDate,
    bool? demam,
    bool? rewel,
    bool? diare,
    String? catatan,
    String? tindakLanjut,
  }) async {
    final headers = await _authHeaders(json: true);

    if (headers == null) {
      return _sessionEnded();
    }

    final body = <String, dynamic>{};
    if (noteDate != null && noteDate.isNotEmpty) {
      body['note_date'] = noteDate;
    }
    if (demam != null) body['demam'] = demam;
    if (rewel != null) body['rewel'] = rewel;
    if (diare != null) body['diare'] = diare;
    if (catatan != null) body['catatan'] = catatan;
    if (tindakLanjut != null) body['tindak_lanjut'] = tindakLanjut;

    if (body.isEmpty) {
      return {
        'success': false,
        'message': 'Tidak ada data yang diperbarui.',
        'data': null,
        'errors': null,
      };
    }

    try {
      final response = await http.patch(
        Uri.parse('$baseUrl${ApiConstants.kaderMedicalNotesEndpoint}/$noteId'),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode == 401) {
        return _sessionEnded();
      }

      return _noteResult(response, 'Gagal memperbarui catatan keluhan.');
    } on SocketException {
      return _offlineError();
    }
  }

  /// Membatalkan catatan keluhan (soft delete di server).
  ///
  /// Baris tidak hilang dari database, jadi riwayat kesehatan anak tetap
  /// bisa diaudit. Tanggal yang sama boleh dicatat ulang setelahnya.
  Future<Map<String, dynamic>> cancelNote(String noteId) async {
    final headers = await _authHeaders();

    if (headers == null) {
      return _sessionEnded();
    }

    try {
      final response = await http.delete(
        Uri.parse('$baseUrl${ApiConstants.kaderMedicalNotesEndpoint}/$noteId'),
        headers: headers,
      );

      if (response.statusCode == 401) {
        return _sessionEnded();
      }

      return _noteResult(response, 'Gagal membatalkan catatan keluhan.');
    } on SocketException {
      return _offlineError();
    }
  }

  /// Bentuk hasil seragam, dengan `data` sudah jadi [MedicalNote].
  ///
  /// Berbeda dari service lain yang mengembalikan `data` mentah, di sini
  /// selalu dikonversi supaya layar cukup memakai objek [MedicalNote] tanpa
  /// melakukan parsing di dua tempat.
  Map<String, dynamic> _noteResult(
    http.Response response,
    String fallbackMessage,
  ) {
    final body = _decode(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      if (body['success'] == true) {
        return {
          'success': true,
          'message': body['message']?.toString() ?? fallbackMessage,
          'data': body['data'] is Map
              ? MedicalNote.fromJson(
                  Map<String, dynamic>.from(body['data'] as Map),
                )
              : null,
        };
      }
    }

    return {
      'success': false,
      'message': body['message']?.toString() ?? fallbackMessage,
      'data': null,
      'errors': body['errors'],
    };
  }
}
