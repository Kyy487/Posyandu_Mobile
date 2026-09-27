import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/immunization.dart';
import '../utils/constants.dart';
import 'auth_service.dart';

/// Checklist imunisasi + pencatatan suntikan.
///
/// Dipakai bersama oleh layar Kader (bisa mencatat) dan layar Ibu (hanya
/// membaca), jadi endpoint `GET` di sini tidak memfilter role. Backend yang
/// membatasi siapa boleh menulis lewat route `/kader/...`.
class ImmunizationService {
  final String baseUrl = ApiConstants.baseUrl;
  final AuthService _auth = AuthService();

  static const _offline =
      'Tidak dapat terhubung ke server. Pastikan backend Laravel berjalan.';

  Map<String, dynamic> _offlineError() =>
      {'success': false, 'message': _offline, 'data': null, 'errors': null};

  /// Hasil error sesi habis. `status: 401` dipakai layar untuk mengarahkan
  /// user login ulang, sama seperti `ChildService`.
  Map<String, dynamic> _sessionEnded() => {
        'success': false,
        'status': 401,
        'message': 'Sesi telah berakhir. Silakan login kembali.',
        'data': null,
        'errors': null,
      };

  Future<Map<String, String>?> _authHeaders({bool json = false}) async {
    final token = await _auth.getToken();
    if (token == null || token.isEmpty) return null;

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
        'message': 'Respons server tidak valid (bukan JSON). '
            'Status code: ${response.statusCode}',
        'data': null,
        'errors': null,
      };
    }
  }

  /// Checklist imunisasi satu anak.
  ///
  /// Status tidak dihitung di sini - server sudah mengirim `sudah` / `belum` /
  /// `terlambat` per dosis beserta ringkasan jumlahnya.
  Future<Map<String, dynamic>> getChecklist(String childId) async {
    final headers = await _authHeaders();
    if (headers == null) return _sessionEnded();

    try {
      final response = await http.get(
        Uri.parse('$baseUrl${ApiConstants.childrenEndpoint}'
            '/$childId/immunizations'),
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
          'data': ImmunizationChecklist.fromJson(
              Map<String, dynamic>.from(body['data'] as Map)),
        };
      }

      return {
        'success': false,
        'message': body['message']?.toString() ?? 'Gagal memuat status imunisasi.',
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

  /// Mencatat suntikan baru. Hanya Kader yang boleh memanggilnya.
  ///
  /// [dateGiven] harus format `YYYY-MM-DD`; server menolak format lain dengan
  /// 422 (bukan 500) karena rules `date_format:Y-m-d`.
  Future<Map<String, dynamic>> addRecord({
    required String childId,
    required String immunizationTypeId,
    required String dateGiven,
    String? batchNumber,
    String? notes,
  }) async {
    final headers = await _authHeaders(json: true);
    if (headers == null) return _sessionEnded();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl${ApiConstants.kaderChildrenEndpoint}'
            '/$childId/immunizations'),
        headers: headers,
        body: json.encode({
          'immunization_type_id': immunizationTypeId,
          'date_given': dateGiven,
          'batch_number': ?batchNumber,
          'notes': ?notes,
        }),
      );

      if (response.statusCode == 401) return _sessionEnded();

      return _result(response, 'Gagal menyimpan imunisasi.');
    } on SocketException {
      return _offlineError();
    }
  }

  /// Mengoreksi tanggal/batch/notes suntikan yang sudah tercatat.
  ///
  /// Dosis tidak bisa diganti lewat endpoint ini. Memindahkan catatan ke dosis
  /// lain berarti membatalkan satu dosis dan mencatat yang lain - dua operasi
  /// terpisah di lapangan, jadi tidak digabung jadi satu PATCH.
  Future<Map<String, dynamic>> updateRecord({
    required String recordId,
    String? dateGiven,
    String? batchNumber,
    String? notes,
  }) async {
    final headers = await _authHeaders(json: true);
    if (headers == null) return _sessionEnded();

    // Partial update: hanya field yang dikirim yang berubah. String kosong
    // sengaja diteruskan apa adanya supaya Kader bisa mengosongkan batch
    // atau catatan tanpa endpoint khusus "hapus field".
    final body = <String, dynamic>{};
    if (dateGiven != null && dateGiven.isNotEmpty) {
      body['date_given'] = dateGiven;
    }
    if (batchNumber != null) body['batch_number'] = batchNumber;
    if (notes != null) body['notes'] = notes;

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
        Uri.parse('$baseUrl${ApiConstants.kaderImmunizationsEndpoint}'
            '/$recordId'),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode == 401) return _sessionEnded();

      return _result(response, 'Gagal memperbarui imunisasi.');
    } on SocketException {
      return _offlineError();
    }
  }

  /// Membatalkan suntikan yang tercatat, misalnya karena salah pilih dosis.
  ///
  /// Record tidak dihapus fisik di server, hanya ditandai tidak aktif
  /// (soft delete). Karena itu dosis yang sama bisa dicatat ulang tanpa
  /// bentrok dengan unique constraint.
  Future<Map<String, dynamic>> deleteRecord({
    required String recordId,
  }) async {
    final headers = await _authHeaders(json: true);
    if (headers == null) return _sessionEnded();

    try {
      final response = await http.delete(
        Uri.parse('$baseUrl${ApiConstants.kaderImmunizationsEndpoint}'
            '/$recordId'),
        headers: headers,
      );

      if (response.statusCode == 401) return _sessionEnded();

      return _result(response, 'Gagal membatalkan imunisasi.');
    } on SocketException {
      return _offlineError();
    }
  }

  /// Bentuk hasil seragam dari respons server.
  Map<String, dynamic> _result(
    http.Response response,
    String fallbackMessage,
  ) {
    final body = _decode(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      if (body['success'] == true) {
        return {
          'success': true,
          'message': body['message']?.toString() ?? fallbackMessage,
          'data': body['data'],
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
