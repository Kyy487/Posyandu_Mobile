import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/growth_chart.dart';
import '../utils/constants.dart';
import 'auth_service.dart';

/// Akses endpoint grafik tumbuh kembang (Opsi D).
///
/// Endpoint ini mengembalikan seluruh riwayat penimbangan satu anak urut naik,
/// ditambah pita acuan WHO BB/U. Bentuk responsnya dikunci di
/// `docs/RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md` bagian 7.2; service ini tidak
/// mengubah apa pun di dalamnya.
///
/// Tiga keputusan yang tidak boleh dibalik di sini:
///
///  1. **Tidak ada query string.** Server sengaja tidak punya paginasi untuk
///     endpoint ini, dan menambahkannya dari sisi klien akan membuat layar
///     menampilkan garis yang terpotong di tengah - lebih menyesatkan daripada
///     grafik penuh yang sedikit padat. Partial unique index di database
///     membatasi satu baris per tanggal, jadi anak 0-60 bulan paling banyak 61
///     titik.
///  2. **Tidak ada perhitungan ulang.** Z-score, status gizi, dan
///     `age_in_months` dibaca apa adanya dari server. Client yang menghitung
///     lagi hanya membuka pintu untuk dua tampilan yang berbeda.
///  3. **Tidak ada penyaringan.** `points: []` adalah jawaban yang benar untuk
///     anak yang belum pernah ditimbang, bukan kegagalan - jadi service ini
///     meneruskannya sebagai sukses supaya layar bisa menampilkan pita WHO-nya
///     sebagai arah tumbuh anak, bukan menampilkan pesan error.
class GrowthChartService {
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

  /// Grafik tumbuh kembang satu anak.
  ///
  /// Path-nya disusun dari `ApiConstants` supaya bisa diuji tanpa benar-benar
  /// memanggil server: salah ketik di path hanya muncul sebagai 404
  /// "Data balita tidak ditemukan." di layar, tanpa jejak di `flutter analyze`.
  ///
  /// Endpoint ini dibaca Ibu maupun Kader. Pembatasan "Ibu hanya boleh melihat
  /// anaknya sendiri" ditegakkan server, bukan di sini.
  ///
  /// `data` di hasil sudah jadi [GrowthChart] supaya layar tidak melakukan
  /// parsing di dua tempat. Anak yang belum pernah ditimbang tetap 200 dengan
  /// `points` kosong dan pita WHO yang utuh.
  Future<Map<String, dynamic>> getGrowthChart(String childId) async {
    final headers = await _authHeaders();

    if (headers == null) {
      return _sessionEnded();
    }

    final uri = Uri.parse(
      '$baseUrl${ApiConstants.childrenEndpoint}/$childId'
      '${ApiConstants.childGrowthEndpoint}',
    );

    try {
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 401) {
        await _auth.logout();
        return _sessionEnded();
      }

      final body = _decode(response);

      if (response.statusCode == 200 && body['success'] == true) {
        return {
          'success': true,
          'message': body['message'],
          'data': GrowthChart.fromJson(
            Map<String, dynamic>.from(body['data'] as Map),
          ),
        };
      }

      return {
        'success': false,
        'message':
            body['message']?.toString() ??
            'Gagal memuat grafik tumbuh kembang.',
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
}
