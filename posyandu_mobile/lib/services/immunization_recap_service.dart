import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/immunization_recap.dart';
import '../utils/constants.dart';
import 'auth_service.dart';

/// Akses endpoint rekap imunisasi bulanan (Opsi E).
///
/// Hanya satu method, [getRecap], dan hanya untuk baca. Kader tidak pernah
/// menulis rekap: angkanya diturunkan dari suntikan yang sudah tercatat di
/// endpoint lain, jadi tidak ada form di layar ini.
///
/// Bentuk respons mengikuti JSON Envelope backend: `{success, message, data,
/// errors}`. Empat helper di bawah (offline / sesi habis / decode / result)
/// sengaja disalin apa adanya dari `MedicalNoteService` supaya perilaku
/// error di semua layar seragam.
class ImmunizationRecapService {
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

  Future<Map<String, String>?> _authHeaders() async {
    final token = await _auth.getToken();

    if (token == null || token.isEmpty) {
      return null;
    }

    return {'Accept': 'application/json', 'Authorization': 'Bearer $token'};
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

  /// Rekap satu bulan: aktivitas suntikan + kelengkapan anak.
  ///
  /// [month] berformat `YYYY-MM`. Null berarti server memakai bulan berjalan,
  /// jadi layar boleh mengirim filter hanya saat Kader memilih bulan lain.
  ///
  /// Endpoint ini Kader-only karena mengekspos seluruh Posyandu, bukan hanya
  /// anak sendiri. Role `ibu` ditolak middleware `RoleCheck` sebelum sampai ke
  /// controller, jadi layar tidak perlu menyembunyikan apa pun - Ibu punya
  /// `GET /children/{id}/immunizations` untuk anaknya sendiri.
  ///
  /// Server membalas 422 (bukan 500) kalau [month] tidak berbentuk
  /// `YYYY-MM` atau bulan tidak ada, dan tidak pernah 404 untuk bulan yang
  /// kosong aktivitasnya. Layar boleh menganggap 200 dengan angka nol sebagai
  /// jawaban yang valid, bukan kondisi gagal.
  Future<Map<String, dynamic>> getRecap({String? month}) async {
    final headers = await _authHeaders();

    if (headers == null) {
      return _sessionEnded();
    }

    final query = <String, String>{
      if (month != null && month.isNotEmpty) 'month': month,
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';

    try {
      final response = await http.get(
        Uri.parse(
          '$baseUrl${ApiConstants.kaderImmunizationRecapEndpoint}'
          '$suffix',
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
          'data': body['data'] is Map
              ? ImmunizationRecap.fromJson(
                  Map<String, dynamic>.from(body['data'] as Map),
                )
              : null,
        };
      }

      return {
        'success': false,
        'message':
            body['message']?.toString() ?? 'Gagal memuat rekap imunisasi.',
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
}
