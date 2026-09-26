import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  final String baseUrl = 'http://10.0.2.2:8000/api'; 
  final storage = const FlutterSecureStorage();

  // FUNGSI LOGIN (Menggunakan NIK)
  Future<Map<String, dynamic>> login(String nik, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'nik': nik,
          'password': password,
        }),
      );

      final Map<String, dynamic> responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        if (responseData['data'] != null && responseData['data']['token'] != null) {
          await storage.write(key: 'token', value: responseData['data']['token']);
        }
        return responseData;
      }

      return {
        'success': false,
        'message': responseData['message'] ?? 'Login gagal',
        'errors': responseData['errors'] ?? responseData['data'],
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Terjadi kesalahan koneksi jaringan. Cek server lokal.',
        'errors': null
      };
    }
  }

  // FUNGSI REGISTER (Menggunakan NIK)
  Future<Map<String, dynamic>> register({
    required String name,
    required String nik, // Email diganti dengan NIK
    required String password,
    required String passwordConfirmation,
    required String role,
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
          'nik': nik, // Parameter untuk Laravel dikirim sebagai NIK
          'password': password,
          'password_confirmation': passwordConfirmation,
          'role': role,
        }),
      );

      final Map<String, dynamic> responseData = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (responseData['success'] == true) {
          if (responseData['data'] != null && responseData['data']['token'] != null) {
            await storage.write(key: 'token', value: responseData['data']['token']);
          }
          return responseData;
        }
      }

      return {
        'success': false,
        'message': responseData['message'] ?? 'Registrasi gagal',
        'errors': responseData['errors'] ?? responseData['data'],
      };

    } catch (e) {
      return {
        'success': false,
        'message': 'Terjadi kesalahan koneksi jaringan. Cek server lokal.',
        'errors': null
      };
    }
  }
  // Tambahkan fungsi ini di dalam class AuthService
Future<Map<String, dynamic>> logout() async {
  try {
    // Ambil token dari storage
    final token = await storage.read(key: 'token');
    
    if (token != null) {
      // Hit API Logout Laravel
      final response = await http.post(
        Uri.parse('$baseUrl/logout'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token', // Wajib untuk rute yang diproteksi Sanctum
        },
      );

      // Selalu hapus token di storage lokal agar user bisa keluar 
      // meskipun server sedang error/down
      await storage.delete(key: 'token');

      final Map<String, dynamic> responseData = jsonDecode(response.body);
      return responseData;
    }
    
    return {'success': false, 'message': 'Tidak ada sesi aktif (token kosong)'};

  } catch (e) {
    // Jika terjadi error jaringan (misal server mati), paksa hapus token lokal
    await storage.delete(key: 'token');
    return {
      'success': false,
      'message': 'Koneksi gagal, tetapi sesi lokal telah dihapus.',
      'errors': null
    };
  }
}

  // Fungsi untuk mendapatkan token dari storage
  Future<String?> getToken() async {
    return await storage.read(key: 'token');
  } 
}