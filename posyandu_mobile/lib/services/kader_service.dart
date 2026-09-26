import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/child.dart';
import 'auth_service.dart';

class KaderService {
  final String baseUrl = 'http://10.0.2.2:8000/api'; 

  // --- Fungsi 1: Mengambil Daftar Anak ---
  Future<List<Child>> getChildrenList() async {
    // ... (kode fungsi getChildrenList yang sudah ada sebelumnya) ...
    try {
      final String? token = await AuthService().getToken();

      if (token == null || token.isEmpty) {
        throw Exception('Sesi telah habis atau token tidak ditemukan. Silakan login kembali.');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/kader/children'), 
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.headers['content-type']?.contains('application/json') != true) {
        throw Exception('Respons server tidak valid (Bukan JSON). Status Code: ${response.statusCode}');
      }

      final Map<String, dynamic> decoded = json.decode(response.body);

      if (response.statusCode == 200 && decoded['success'] == true) {
        if (decoded['data'] is List) {
          List<dynamic> data = decoded['data'];
          return data.map((item) => Child.fromJson(item as Map<String, dynamic>)).toList();
        } else {
          throw Exception('Format respons salah: Key "data" harus berupa Array/List.');
        }
      } else {
        throw Exception(decoded['message'] ?? 'Gagal mengambil data dari server.');
      }

    } on SocketException {
      throw Exception('Tidak dapat terhubung ke server.');
    } on FormatException {
      throw Exception('Format data JSON dari server rusak atau tidak valid.');
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  // --- Fungsi 2: Menambahkan Anak Baru (FUNGSI YANG HILANG/ERROR) ---
Future<Map<String, dynamic>> addChild({
    required String nik,
    required String name,
    required String dateOfBirth,
    required String gender,
    required double birthWeight,
    required double birthHeight,
    required String ibuNik,
  }) async {
    try {
      final String? token = await AuthService().getToken();

      // Tambahkan print ini untuk memastikan token benar-benar terbaca sebelum dikirim
      print('Token yang akan dikirim: $token'); 

      if (token == null || token.isEmpty) {
        return {'success': false, 'message': 'Sesi habis. Silakan logout dan login kembali.'};
      }

      final response = await http.post(
        Uri.parse('$baseUrl/kader/children'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          // Pastikan 'Bearer ' dieja dengan B besar dan ada satu spasi setelahnya
          'Authorization': 'Bearer $token', 
        },
        body: json.encode({
          'nik': nik,
          'name': name,
          'date_of_birth': dateOfBirth,
          'gender': gender,
          'birth_weight': birthWeight,
          'birth_height': birthHeight,
          'ibu_nik': ibuNik,
        }),
      );

      // Print status code dan body respons dari server untuk mempermudah debugging
      print('Status Code: ${response.statusCode}');
      print('Response Body: ${response.body}');

      final Map<String, dynamic> decoded = json.decode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (decoded['success'] == true) {
          return {'success': true, 'message': decoded['message'] ?? 'Berhasil menambah data'};
        }
      }

      // Jika error 401 (Unauthenticated), kembalikan pesan yang jelas
      if (response.statusCode == 401) {
         return {'success': false, 'message': 'Akses ditolak (Unauthenticated). Coba login ulang.'};
      }

      return {
        'success': false,
        'message': decoded['message'] ?? 'Gagal menambahkan data anak.',
        'errors': decoded['errors'] 
      };
    } catch (e) {
      print('Error Exception: $e'); // Print error jaringan jika ada
      return {'success': false, 'message': 'Terjadi kesalahan. Cek koneksi atau server.'};
    }
  }
  // Tambahkan fungsi ini di dalam class KaderService
  Future<Map<String, dynamic>> addMeasurement({
    required String childId, // UUID Anak
    required String measurementDate,
    required double weight,
    required double height,
  }) async {
    try {
      final String? token = await AuthService().getToken();

      if (token == null || token.isEmpty) {
        return {'success': false, 'message': 'Sesi habis. Silakan login kembali.'};
      }

      final response = await http.post(
        Uri.parse('$baseUrl/kader/measurements'), // Rute ini akan kita buat di Laravel nanti
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'child_id': childId, // Relasi ke UUID tabel children
          'measurement_date': measurementDate,
          'weight_kg': weight, // Berat badan (kg)
          'height_cm': height, // Tinggi/Panjang badan (cm)
        }),
      );

      final Map<String, dynamic> decoded = json.decode(response.body);

      print('Status Code (Input BB): ${response.statusCode}');
      print('Response Body (Input BB): ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (decoded['success'] == true) {
          return {
            'success': true,
            'message': decoded['message'] ?? 'Data penimbangan berhasil disimpan',
            // Data ini berisi age_in_months, z_score_wfa, dan status_gizi
            // yang dihitung otomatis oleh Database Trigger di sisi server.
            'data': decoded['data'],
          };
        }
      }

      if (response.statusCode == 401) {
         return {'success': false, 'message': 'Akses ditolak (Unauthenticated). Coba login ulang.'};
      }

      return {
        'success': false,
        'message': decoded['message'] ?? 'Gagal menyimpan penimbangan.',
        'errors': decoded['errors'] 
      };
    } catch (e) {
      return {'success': false, 'message': 'Terjadi kesalahan jaringan atau server.'};
    }
  }
  Future<List<dynamic>> getMeasurements(String childId) async {
    try {
      final String? token = await AuthService().getToken();
      if (token == null || token.isEmpty) throw Exception('Sesi habis.');

      final response = await http.get(
        Uri.parse('$baseUrl/kader/measurements?child_id=$childId'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Status Code History: ${response.statusCode}');
      print('Response Body History: ${response.body}');


      final Map<String, dynamic> decoded = json.decode(response.body);
      if (response.statusCode == 200 && decoded['success'] == true) {
        return decoded['data'] ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }
  

  // Menghapus data penimbangan
  Future<bool> deleteMeasurement(String measurementId) async {
    try {
      final String? token = await AuthService().getToken();
      if (token == null || token.isEmpty) return false;

      final response = await http.delete(
        Uri.parse('$baseUrl/kader/measurements/$measurementId'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );


      final Map<String, dynamic> decoded = json.decode(response.body);
      return response.statusCode == 200 && decoded['success'] == true;
    } catch (e) {
      return false;
    }
  }
}