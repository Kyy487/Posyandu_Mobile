import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../utils/constants.dart';

class AuthService {
  final String baseUrl = ApiConstants.baseUrl;
  final storage = const FlutterSecureStorage();

  /// Memeriksa NIK + password.
  Future<Map<String, dynamic>> login(String nik, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'nik': nik, 'password': password}),
      );

      return await _handleAuthResponse(response, 'Login gagal');
    } catch (e) {
      return _networkError();
    }
  }

  /// Mendaftarkan akun baru.
  ///
  /// [kaderCode] opsional. Bila kosong, server membuat akun `ibu`. Bila diisi
  /// dan cocok dengan kode di server, akun menjadi `kader`. Role tidak pernah
  /// dipilih dari layar — server yang memutuskan.
  Future<Map<String, dynamic>> register({
    required String name,
    required String nik,
    required String password,
    required String passwordConfirmation,
    String kaderCode = '',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/register'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'name': name,
          'nik': nik,
          'password': password,
          'password_confirmation': passwordConfirmation,
          if (kaderCode.isNotEmpty) ...{
            'role': 'kader',
            'kader_code': kaderCode,
          },
        }),
      );

      return await _handleAuthResponse(response, 'Registrasi gagal');
    } catch (e) {
      return _networkError();
    }
  }

  /// Keluar dan mencabut token di server.
  Future<Map<String, dynamic>> logout() async {
    final token = await storage.read(key: 'token');

    if (token == null) {
      return {'success': false, 'message': 'Tidak ada sesi aktif (token kosong)'};
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/logout'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      // Selalu hapus token lokal, walau server sedang error.
      await storage.delete(key: 'token');

      return jsonDecode(response.body);
    } catch (e) {
      // Server mati? Tetap keluarkan user dari aplikasi.
      await storage.delete(key: 'token');
      return {
        'success': false,
        'message': 'Koneksi gagal, tetapi sesi lokal telah dihapus.',
        'errors': null,
      };
    }
  }

  Future<String?> getToken() => storage.read(key: 'token');

  Future<bool> hasSession() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// NIK terakhir yang user pilih untuk diingat ("Ingat NIK" di login).
  ///
  /// Disimpan di secure storage, bukan di preferences biasa, supaya tidak
  /// bocor lewat backup aplikasi.
  Future<String?> getRememberedNik() => storage.read(key: 'remembered_nik');

  Future<void> saveRememberedNik(String nik) async {
    if (nik.isEmpty) {
      await storage.delete(key: 'remembered_nik');
      return;
    }
    await storage.write(key: 'remembered_nik', value: nik);
  }

  /// Data user yang sedang login (`GET /api/user`).
  ///
  /// Dipakai dashboard Ibu untuk menampilkan nama asli, bukan nama hardcode.
  /// Mengembalikan `null` bila sesi habis atau server tidak bisa dihubungi.
  Future<Map<String, dynamic>?> getProfile() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return null;

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 401) {
        await logout();
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['success'] == true && body['data'] is Map) {
        return Map<String, dynamic>.from(body['data'] as Map);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Membaca respons auth dan menyimpan token bila ada.
  Future<Map<String, dynamic>> _handleAuthResponse(
    http.Response response,
    String fallbackMessage,
  ) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {
        'success': false,
        'message': 'Respons server tidak valid (bukan JSON). '
            'Pastikan backend Laravel sedang berjalan.',
        'errors': null,
      };
    }

    final token = body['data'] is Map ? (body['data'] as Map)['token'] : null;
    if (token is String && token.isNotEmpty) {
      await storage.write(key: 'token', value: token);
    }

    if (body['success'] == true) {
      return body;
    }

    return {
      'success': false,
      'message': body['message']?.toString() ?? fallbackMessage,
      'errors': body['errors'],
    };
  }

  Map<String, dynamic> _networkError() => {
        'success': false,
        'message': 'Terjadi kesalahan koneksi jaringan. Cek server lokal.',
        'errors': null,
      };
}
