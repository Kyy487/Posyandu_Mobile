import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/child.dart';
import '../utils/constants.dart';
import 'auth_service.dart';

class ChildService {
  final String baseUrl = ApiConstants.baseUrl;
  final AuthService _auth = AuthService();

  /// Pesan baku saat server tidak bisa dihubungi.
  static const _offline =
      'Terjadi kesalahan koneksi jaringan. Cek server lokal.';

  /// Meminta header dengan token Sanctum, atau null bila tidak ada sesi.
  Future<Map<String, String>?> _authHeaders({bool json = false}) async {
    final token = await _auth.getToken();
    if (token == null || token.isEmpty) return null;

    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _offlineError() =>
      {'success': false, 'message': _offline, 'errors': null};

  Map<String, dynamic> _sessionEnded() => {
        'success': false,
        'status': 401,
        'message': 'Sesi telah berakhir. Silakan login kembali.',
        'data': null,
        'errors': null,
      };

  Map<String, dynamic> _decode(http.Response response) {
    try {
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {
        'success': false,
        'message': 'Respons server tidak valid (bukan JSON). '
            'Status code: ${response.statusCode}',
        'errors': null,
      };
    }
  }

  /// Daftar anak milik Ibu yang sedang login.
  ///
  /// Setiap anak sudah membawa `lastMeasurementDate`, `latestZScore`, dan
  /// `nutritionalStatus` dari penimbangan terakhir (lihat `Child.fromJson`).
  ///
  /// Mengembalikan `401` pada `result['status']` bila sesi sudah habis supaya
  /// layar bisa mengarahkan user login ulang.
  Future<Map<String, dynamic>> getChildren() async {
    final headers = await _authHeaders();
    if (headers == null) return _sessionEnded();

    try {
      final response = await http.get(
        Uri.parse('$baseUrl${ApiConstants.childrenEndpoint}'),
        headers: headers,
      );

      if (response.statusCode == 401) {
        await _auth.logout();
        return _sessionEnded();
      }

      return _decode(response);
    } catch (e) {
      return {
        'success': false,
        'message': _offline,
        'data': null,
        'errors': null,
      };
    }
  }

  /// Mendaftarkan anak milik Ibu sendiri.
  ///
  /// Ibu tidak perlu menyebut siapa ibunya - backend mengaitkan anak ke akun
  /// yang sedang login (lihat `ChildController@resolveMother`).
  Future<Map<String, dynamic>> addChild({
    required String name,
    required String dateOfBirth,
    required String gender,
    String? nik,
  }) async {
    final headers = await _authHeaders(json: true);
    if (headers == null) return _sessionEnded();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl${ApiConstants.childrenEndpoint}'),
        headers: headers,
        body: json.encode({
          'name': name,
          'date_of_birth': dateOfBirth,
          'gender': gender,
          if (nik != null && nik.isNotEmpty) 'nik': nik,
        }),
      );

      final body = _decode(response);
      if (response.statusCode == 401) return _sessionEnded();

      return {
        'success': body['success'] == true,
        'message': body['message']?.toString() ?? 'Gagal menambahkan data anak.',
        'errors': body['errors'],
        'data': body['data'] == null
            ? null
            : Child.fromJson(Map<String, dynamic>.from(body['data'] as Map)),
      };
    } catch (e) {
      return _offlineError();
    }
  }
}
