import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/child.dart';
import '../utils/constants.dart';
import 'auth_service.dart';

class KaderService {
  final String baseUrl = ApiConstants.baseUrl;
  final AuthService _auth = AuthService();

  /// Pesan baku saat server tidak bisa dihubungi.
  static const _offline =
      'Tidak dapat terhubung ke server. Pastikan backend Laravel berjalan.';

  Map<String, dynamic> _offlineError() => {
    'success': false,
    'message': _offline,
    'errors': null,
  };

  Map<String, dynamic> _unauthenticated() => {
    'success': false,
    'message': 'Sesi telah berakhir. Silakan login kembali.',
    'errors': null,
    'status': 401,
  };

  /// Header dengan token Sanctum. Mengembalikan null bila tidak ada sesi.
  Future<Map<String, String>?> _authHeaders({bool json = false}) async {
    final token = await _auth.getToken();
    if (token == null || token.isEmpty) return null;

    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // --- Mengambil daftar anak ---
  Future<List<Child>> getChildrenList() async {
    final headers = await _authHeaders();
    if (headers == null) throw Exception('Sesi habis. Silakan login kembali.');

    try {
      final response = await http.get(
        Uri.parse('$baseUrl${ApiConstants.kaderChildrenEndpoint}'),
        headers: headers,
      );

      final Map<String, dynamic> body = _decode(response);

      if (response.statusCode == 401) {
        throw Exception(_unauthenticated()['message']);
      }
      if (response.statusCode == 200 && body['success'] == true) {
        final data = body['data'];
        if (data is List) {
          return data
              .map((e) => Child.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        }
        throw Exception('Format respons salah: "data" harus berupa daftar.');
      }

      throw Exception(
        body['message']?.toString() ?? 'Gagal mengambil data anak.',
      );
    } on SocketException {
      throw Exception(_offline);
    } on FormatException {
      throw Exception('Format data JSON dari server rusak atau tidak valid.');
    }
  }

  // --- Menambah anak baru ---
  Future<Map<String, dynamic>> addChild({
    required String nik,
    required String name,
    required String dateOfBirth,
    required String gender,
    required double birthWeight,
    required double birthHeight,
    required String ibuNik,
  }) async {
    final headers = await _authHeaders(json: true);
    if (headers == null) return _offlineError();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl${ApiConstants.kaderChildrenEndpoint}'),
        headers: headers,
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

      return _authAwareResult(response, 'Gagal menambahkan data anak.');
    } on SocketException {
      return _offlineError();
    }
  }

  // --- Mencatat penimbangan (e-KMS) ---
  Future<Map<String, dynamic>> addMeasurement({
    required String childId,
    required String measurementDate,
    required double weight,
    required double height,
  }) async {
    final headers = await _authHeaders(json: true);
    if (headers == null) return _offlineError();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl${ApiConstants.kaderMeasurementsEndpoint}'),
        headers: headers,
        body: json.encode({
          'child_id': childId,
          'measurement_date': measurementDate,
          'weight_kg': weight,
          'height_cm': height,
        }),
      );

      return _authAwareResult(response, 'Gagal menyimpan penimbangan.');
    } on SocketException {
      return _offlineError();
    }
  }

  // --- Riwayat penimbangan anak ---
  Future<List<dynamic>> getMeasurements(String childId) async {
    final headers = await _authHeaders();
    if (headers == null) return [];

    try {
      final response = await http.get(
        Uri.parse(
          '$baseUrl${ApiConstants.kaderMeasurementsEndpoint}'
          '?child_id=$childId',
        ),
        headers: headers,
      );

      if (response.statusCode == 401) return [];
      final body = _decode(response);
      if (response.statusCode == 200 && body['success'] == true) {
        final data = body['data'];
        return data is List ? data : [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // --- Menghapus data penimbangan ---
  Future<bool> deleteMeasurement(String measurementId) async {
    final headers = await _authHeaders();
    if (headers == null) return false;

    try {
      final response = await http.delete(
        Uri.parse(
          '$baseUrl${ApiConstants.kaderMeasurementsEndpoint}/$measurementId',
        ),
        headers: headers,
      );

      if (response.statusCode == 401) return false;
      return _decode(response)['success'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Mengubah data anak (PATCH /children/{id}).
  ///
  /// [name], [dateOfBirth], dan [gender] wajib dikirim karena form edit selalu
  /// mengirim seluruh isian yang dikelola, bukan bandage per-field.
  ///
  /// [birthWeight], [birthHeight], dan [medicalFlags] nullable, dan `null` di
  /// sini berarti **kosongkan** field itu, bukan "jangan sentuh". Ini penting:
  /// backend membedakan "tidak dikirim" (`:294` `ChildController`) dari
  /// "dikirim null" (nilai dihapus). Versi sebelumnya memakai spread
  /// null-aware `?birthWeight`, yang diam-diam DROPS key saat null - sehingga
  /// kadar yang salah ketik tidak pernah bisa dikoreksi jadi kosong.
  Future<Map<String, dynamic>> updateChild({
    required String childId,
    required String name,
    required String dateOfBirth,
    required String gender,
    double? birthWeight,
    double? birthHeight,
    String? medicalFlags,
  }) async {
    final headers = await _authHeaders(json: true);
    if (headers == null) return _offlineError();

    // Key nullable sengaja TIDAK memakai `?field`: null di sini adalah
    // instruksi untuk mengosongkan, jadi key tetap dikirim sebagai null.
    final body = <String, dynamic>{
      'name': name,
      'date_of_birth': dateOfBirth,
      'gender': gender,
      'birth_weight': birthWeight,
      'birth_height': birthHeight,
      'medical_flags': medicalFlags,
    };

    try {
      final response = await http.patch(
        Uri.parse('$baseUrl${ApiConstants.childrenEndpoint}/$childId'),
        headers: headers,
        body: json.encode(body),
      );

      return _authAwareResult(response, 'Gagal memperbarui data anak.');
    } on SocketException {
      return _offlineError();
    }
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
        'errors': null,
      };
    }
  }

  /// Membentuk hasil seragam, termasuk penanganan 401 (sesi habis).
  Map<String, dynamic> _authAwareResult(
    http.Response response,
    String fallbackMessage,
  ) {
    final body = _decode(response);

    if (response.statusCode == 401) return _unauthenticated();

    if (response.statusCode == 200 || response.statusCode == 201) {
      if (body['success'] == true) {
        return {
          'success': true,
          'message': body['message']?.toString() ?? fallbackMessage,
          // Penting untuk addMeasurement: `data` berisi age_in_months,
          // z_score_wfa, dan status_gizi dari trigger database.
          'data': body['data'],
        };
      }
    }

    return {
      'success': false,
      'message': body['message']?.toString() ?? fallbackMessage,
      'errors': body['errors'],
    };
  }
}
