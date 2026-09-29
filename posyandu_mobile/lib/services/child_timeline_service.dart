import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/child_timeline.dart';
import '../utils/constants.dart';
import 'auth_service.dart';

/// Akses endpoint riwayat medis gabungan (Opsi B - Buku Medis Digital).
///
/// Endpoint ini mengembalikan penimbangan, suntikan, dan catatan keluhan satu
/// anak dalam satu respons, dikelompokkan per tanggal kunjungan. Bentuk
/// responsnya dikunci di `docs/RANCANGAN_BUKU_MEDIS.md` bagian 7.2; service ini
/// tidak mengubah apa pun di dalamnya.
///
/// Tiga keputusan yang tidak boleh dibalik di sini:
///
///  1. **Tidak ada perhitungan ulang.** Z-score, status gizi, dan
///     `age_in_months` dibaca apa adanya dari server. Client yang menghitung
///     lagi hanya membuka pintu untuk dua layar yang berbeda.
///  2. **Tidak ada batas waktu dan tidak ada penyaringan tanggal.** Riwayat
///     dibaca tanpa batas; pemotongan halaman sepenuhnya urusan cursor
///     `before` milik server.
///  3. **Cursor tidak dikarang.** Halaman berikutnya hanya diminta memakai
///     `meta.next_before` dari halaman sebelumnya, apa adanya. Mengarang
///     cursor dari tanggal entri terakhir sendiri mudah bergeser satu hari.
class ChildTimelineService {
  final String baseUrl = ApiConstants.baseUrl;
  final AuthService _auth = AuthService();

  /// Jumlah tanggal kunjungan per halaman.
  ///
  /// Sama dengan default server. Nilai 1-200 kalau layar butuh mengatur
  /// sendiri; di luar itu server membalas 422 dan layar harus menampilkan
  /// pesan validasi, bukan daftar kosong.
  static const int limitHalaman = 50;

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

  /// Riwayat medis satu anak, terbaru lebih dulu.
  ///
  /// [before] diisi dengan `meta.next_before` dari halaman sebelumnya untuk
  /// mengambil halaman berikutnya, dan `null` untuk halaman pertama. Cursor
  /// harus berformat `Y-m-d`; server menolak format lain dengan 422 supaya
  /// tanggal yang tidak pernah ada tidak ikut terisi riwayat.
  ///
  /// Endpoint ini dibaca Ibu maupun Kader. Pembatasan "Ibu hanya boleh melihat
  /// anaknya sendiri" ditegakkan server, bukan di sini.
  ///
  /// `data` di hasil sudah jadi [ChildTimeline] supaya layar tidak melakukan
  /// parsing di dua tempat. Anak yang belum pernah ditimbang tetap 200 dengan
  /// `entries` kosong - itu jawaban yang benar, bukan error.
  Future<Map<String, dynamic>> getTimeline(
    String childId, {
    String? before,
    int limit = limitHalaman,
  }) async {
    final headers = await _authHeaders();

    if (headers == null) {
      return _sessionEnded();
    }

    final query = <String, String>{
      'limit': '$limit',
      if (before != null && before.isNotEmpty) 'before': before,
    };

    try {
      final response = await http.get(
        Uri.parse(
          '$baseUrl${ApiConstants.childrenEndpoint}/$childId'
          '${ApiConstants.childTimelineEndpoint}'
          '?${Uri(queryParameters: query).query}',
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
          'data': ChildTimeline.fromJson(
            Map<String, dynamic>.from(body['data'] as Map),
          ),
        };
      }

      return {
        'success': false,
        'message':
            body['message']?.toString() ?? 'Gagal memuat riwayat medis anak.',
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
