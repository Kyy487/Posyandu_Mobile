import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/referral.dart';
import '../utils/constants.dart';
import 'auth_service.dart';

/// Akses endpoint rujukan anak (lihat `docs/RANCANGAN_RUJUKAN.md`).
///
/// Ruang lingkup service ini BACA saja. Membuat dan mengubah rujukan belum
/// dipakai di aplikasi karena rujukan selalu menempel pada satu kunjungan
/// (`visit_id`), dan layar mobile belum punya cara memilih kunjungan.
///
/// Bentuk respons mengikuti JSON Envelope backend: `{success, message, data,
/// errors}`. Empat helper di bawah (offline / sesi habis / decode / result)
/// sengaja disalin apa adanya dari `ChildTimelineService` supaya perilaku error
/// di semua layar seragam.
class ReferralService {
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

  /// Daftar rujukan satu anak, terbaru lebih dulu.
  ///
  /// Endpoint ini dibaca Ibu maupun Kader. Pembatasan "Ibu hanya boleh melihat
  /// anaknya sendiri" ditegakkan server, bukan di sini.
  ///
  /// `data` di hasil sudah jadi [ReferralList] supaya layar tidak melakukan
  /// parsing di dua tempat. Anak yang belum pernah dirujuk tetap 200 dengan
  /// daftar kosong - itu jawaban yang benar, bukan error.
  ///
  /// Endpoint ini tidak berpaginasi: server mengirim seluruh rujukan anak
  /// sekaligus, jadi klien juga tidak menambah query string apa pun.
  Future<Map<String, dynamic>> getByChild(String childId) async {
    final headers = await _authHeaders();

    if (headers == null) {
      return _sessionEnded();
    }

    try {
      final response = await http.get(
        Uri.parse(
          '$baseUrl${ApiConstants.childrenEndpoint}/$childId'
          '${ApiConstants.childReferralsEndpoint}',
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
          'data': ReferralList.fromJson(
            Map<String, dynamic>.from(body['data'] as Map),
          ),
        };
      }

      return {
        'success': false,
        'message': body['message']?.toString() ?? 'Gagal memuat daftar rujukan.',
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

  /// Membuat rujukan baru. Hanya Kader yang boleh memanggilnya.
  ///
  /// [visitId] WAJIB milik anak yang sama dengan [childId]; server membalas
  /// 422 bila tidak. `kader_id` diisi server dari token, klien tidak
  /// mengirimnya.
  ///
  /// [referralDate] dan [visitDate] berformat `YYYY-MM-DD`; server menolak
  /// tanggal setelah hari ini dengan 422 (`before_or_equal:today`).
  ///
  /// Status boleh dikosongkan - server memakai `dibuat` sebagai default.
  Future<Map<String, dynamic>> create({
    required String childId,
    required String visitId,
    required String referralDate,
    required String referralType,
    required String reason,
    required String facilityName,
    String? status,
  }) async {
    final headers = await _authHeaders(json: true);

    if (headers == null) {
      return _sessionEnded();
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl${ApiConstants.kaderReferralsEndpoint}'),
        headers: headers,
        body: json.encode({
          'child_id': childId,
          'visit_id': visitId,
          'referral_date': referralDate,
          'referral_type': referralType,
          'reason': reason,
          'facility_name': facilityName,
          if (status != null && status.isNotEmpty) 'status': status,
        }),
      );

      if (response.statusCode == 401) {
        await _auth.logout();
        return _sessionEnded();
      }

      return _referralResult(response, 'Gagal menyimpan rujukan.');
    } on SocketException {
      return _offlineError();
    } on http.ClientException {
      return _offlineError();
    }
  }

  /// Mengoreksi satu rujukan (partial update). Hanya Kader.
  ///
  /// Hanya field yang tidak null yang dikirim. `child_id` dan `visit_id`
  /// sengaja tidak bisa diubah: rujukan yang salah anak/kunjungan dibatalkan
  /// lalu dibuat ulang (lihat `ReferralController@update`).
  ///
  /// `reason` dan `facilityName` boleh dikosongkan di UI, tapi server menolak
  /// teks kosong (`sometimes|required`) - jadi layar wajib menjaga keduanya
  /// terisi sebelum mengirim, bukan mengirim string kosong.
  Future<Map<String, dynamic>> update({
    required String referralId,
    String? referralDate,
    String? referralType,
    String? reason,
    String? facilityName,
    String? status,
  }) async {
    final headers = await _authHeaders(json: true);

    if (headers == null) {
      return _sessionEnded();
    }

    final body = <String, dynamic>{};
    if (referralDate != null) body['referral_date'] = referralDate;
    if (referralType != null) body['referral_type'] = referralType;
    if (reason != null) body['reason'] = reason;
    if (facilityName != null) body['facility_name'] = facilityName;
    if (status != null) body['status'] = status;

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
        Uri.parse('$baseUrl${ApiConstants.kaderReferralsEndpoint}/$referralId'),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode == 401) {
        await _auth.logout();
        return _sessionEnded();
      }

      return _referralResult(response, 'Gagal memperbarui rujukan.');
    } on SocketException {
      return _offlineError();
    } on http.ClientException {
      return _offlineError();
    }
  }

  /// Membatalkan rujukan (soft delete di server). Hanya Kader.
  ///
  /// Baris tidak hilang dari database, jadi tindak lanjutnya tetap bisa
  /// diaudit. Setelah dibatalkan, rujukan itu hilang dari daftar dan timeline.
  Future<Map<String, dynamic>> cancel(String referralId) async {
    final headers = await _authHeaders();

    if (headers == null) {
      return _sessionEnded();
    }

    try {
      final response = await http.delete(
        Uri.parse('$baseUrl${ApiConstants.kaderReferralsEndpoint}/$referralId'),
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
          'message': body['message']?.toString() ?? 'Rujukan dibatalkan.',
          'data': null,
        };
      }

      return {
        'success': false,
        'message': body['message']?.toString() ?? 'Gagal membatalkan rujukan.',
        'data': null,
        'errors': body['errors'],
      };
    } on SocketException {
      return _offlineError();
    } on http.ClientException {
      return _offlineError();
    }
  }

  /// Bentuk hasil seragam, dengan `data` sudah jadi [Referral].
  ///
  /// Server membalas 201 saat sukses, tapi 200 tetap diterima supaya perubahan
  /// di sisi backend tidak membuat layar mengira gagal.
  Map<String, dynamic> _referralResult(
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
            ? Referral.fromJson(Map<String, dynamic>.from(body['data'] as Map))
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
}
