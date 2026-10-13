import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/visit.dart';
import '../utils/constants.dart';
import 'auth_service.dart';

/// Akses endpoint kunjungan anak (P0-1, lihat `docs/RANCANGAN_VISIT.md`).
///
/// Ruang lingkup service ini:
///  - BACA daftar kunjungan satu anak (`getByChild`).
///  - BUAT kunjungan baru (`create`, Kader).
///  - KOREKSI kunjungan (`update`, Kader).
///
/// Bentuk respons mengikuti JSON Envelope backend: `{success, message, data,
/// errors}`. Helper di bawah sengaja sama dengan `ReferralService` supaya
/// perilaku error di semua layar seragam.
class VisitService {
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

  /// Daftar kunjungan satu anak, terbaru lebih dulu.
  ///
  /// Endpoint ini dibaca Ibu maupun Kader. Pembatasan "Ibu hanya boleh melihat
  /// anaknya sendiri" ditegakkan server, bukan di sini.
  ///
  /// `data` di hasil sudah jadi [VisitList]. Anak tanpa kunjungan tetap 200
  /// dengan daftar kosong - itu jawaban yang benar, bukan error.
  Future<Map<String, dynamic>> getByChild(String childId) async {
    final headers = await _authHeaders();

    if (headers == null) {
      return _sessionEnded();
    }

    try {
      final response = await http.get(
        Uri.parse(
          '$baseUrl${ApiConstants.childrenEndpoint}/$childId'
          '${ApiConstants.childVisitsEndpoint}',
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
          'data': VisitList.fromJson(
            Map<String, dynamic>.from(body['data'] as Map),
          ),
        };
      }

      return {
        'success': false,
        'message':
            body['message']?.toString() ?? 'Gagal memuat daftar kunjungan.',
        'data': null,
        'errors': body['errors'],
      };
    } on SocketException {
      return _offlineError();
    } on http.ClientException {
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

  /// Membuat kunjungan baru. Hanya Kader.
  ///
  /// `kader_id` diisi server dari token, klien tidak mengirimnya. `schedule_id`
  /// sengaja tidak dikirim: form mobile membuat kunjungan bebas (bukan
  /// terikat jadwal posyandu).
  Future<Map<String, dynamic>> create({
    required String childId,
    required String visitDate,
    required String visitType,
    String? anamnesis,
    String? catatanKader,
  }) async {
    final headers = await _authHeaders(json: true);

    if (headers == null) {
      return _sessionEnded();
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl${ApiConstants.kaderVisitsEndpoint}'),
        headers: headers,
        body: json.encode({
          'child_id': childId,
          'visit_date': visitDate,
          'visit_type': visitType,
          'anamnesis': _teksAtauNull(anamnesis),
          'catatan_kader': _teksAtauNull(catatanKader),
        }),
      );

      if (response.statusCode == 401) {
        await _auth.logout();
        return _sessionEnded();
      }

      return _visitResult(response, 'Gagal menyimpan kunjungan.');
    } on SocketException {
      return _offlineError();
    } on http.ClientException {
      return _offlineError();
    }
  }

  /// Mengoreksi kunjungan (partial update). Hanya Kader.
  ///
  /// `child_id` tidak dikirim: kunjungan yang salah anak dibatalkan lalu dibuat
  /// ulang (lihat `VisitController@update`).
  Future<Map<String, dynamic>> update({
    required String visitId,
    String? visitDate,
    String? visitType,
    String? anamnesis,
    String? catatanKader,
  }) async {
    final headers = await _authHeaders(json: true);

    if (headers == null) {
      return _sessionEnded();
    }

    final body = <String, dynamic>{};
    if (visitDate != null) body['visit_date'] = visitDate;
    if (visitType != null) body['visit_type'] = visitType;
    if (anamnesis != null) body['anamnesis'] = _teksAtauNull(anamnesis);
    if (catatanKader != null) body['catatan_kader'] = _teksAtauNull(catatanKader);

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
        Uri.parse('$baseUrl${ApiConstants.kaderVisitsEndpoint}/$visitId'),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode == 401) {
        await _auth.logout();
        return _sessionEnded();
      }

      return _visitResult(response, 'Gagal memperbarui kunjungan.');
    } on SocketException {
      return _offlineError();
    } on http.ClientException {
      return _offlineError();
    }
  }

  /// Bentuk hasil seragam, dengan `data` sudah jadi [Visit].
  Map<String, dynamic> _visitResult(
    http.Response response,
    String fallbackMessage,
  ) {
    final body = _decode(response);

    if ((response.statusCode == 200 || response.statusCode == 201) &&
        body['success'] == true) {
      return {
        'success': true,
        'message': body['message']?.toString() ?? fallbackMessage,
        'data': body['data'] is Map
            ? Visit.fromJson(Map<String, dynamic>.from(body['data'] as Map))
            : null,
      };
    }

    return {
      'success': false,
      'message': body['message']?.toString() ?? fallbackMessage,
      'data': null,
      'errors': body['errors'],
    };
  }

  /// Teks kosong/spasi jadi `null` supaya konsisten dengan `normalizeText` di
  /// backend - field `nullable` yang diisi "" hanya membingungkan pembaca.
  String? _teksAtauNull(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
