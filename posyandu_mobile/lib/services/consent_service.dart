import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/consent.dart';
import '../utils/constants.dart';
import 'auth_service.dart';

/// Akses endpoint persetujuan (consent) pemrosesan data anak.
///
/// Ibu/wali pemilik anak boleh membaca, memberi, dan mencabut persetujuan.
/// Kader hanya boleh membaca (`GET`), jadi layar kader memakai
/// [getByChild] saja dan tidak pernah menyentuh [grant]/[revoke].
///
/// Bentuk respons mengikuti JSON Envelope backend: `{success, message, data,
/// errors}`. Empat helper di bawah sengaja disalin apa adanya dari
/// `ReferralService` supaya perilaku error di semua layar seragam.
class ConsentService {
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

  /// `status: 401` dipakai layar untuk mengarahkan user login ulang.
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

  Uri _childConsentsUri(String childId) => Uri.parse(
    '$baseUrl${ApiConstants.childrenEndpoint}/$childId'
    '${ApiConstants.childConsentsEndpoint}',
  );

  /// Consent AKTIF milik satu anak.
  ///
  /// Server hanya mengirim baris yang belum dicabut. `data` di hasil sudah jadi
  /// `List<Consent>` supaya layar tidak parsing di dua tempat.
  Future<Map<String, dynamic>> getByChild(String childId) async {
    final headers = await _authHeaders();

    if (headers == null) {
      return _sessionEnded();
    }

    try {
      final response = await http.get(
        _childConsentsUri(childId),
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
          'data': _parseList(body['data']),
        };
      }

      return {
        'success': false,
        'message':
            body['message']?.toString() ?? 'Gagal memuat data persetujuan.',
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

  /// Memberi (atau memberi ulang) satu jenis persetujuan. Hanya Ibu/wali.
  ///
  /// Server membalas 201 saat baru, 200 saat memberi ulang setelah dicabut, dan
  /// 409 bila consent tipe itu memang sudah aktif.
  Future<Map<String, dynamic>> grant({
    required String childId,
    required String consentType,
    String documentVersion = kConsentDocumentVersion,
    String? notes,
  }) async {
    final headers = await _authHeaders(json: true);

    if (headers == null) {
      return _sessionEnded();
    }

    try {
      final response = await http.post(
        _childConsentsUri(childId),
        headers: headers,
        body: json.encode({
          'consent_type': consentType,
          'document_version': documentVersion,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        }),
      );

      if (response.statusCode == 401) {
        await _auth.logout();
        return _sessionEnded();
      }

      return _consentResult(response, 'Gagal menyimpan persetujuan.');
    } on SocketException {
      return _offlineError();
    } on http.ClientException {
      return _offlineError();
    }
  }

  /// Mencabut satu jenis persetujuan. Hanya Ibu/wali.
  ///
  /// Pencabutan tidak menghapus riwayat medis, hanya mengisi `revoked_at`.
  /// `consent_type` tetap dikirim di body karena `DELETE` di sini memakai body,
  /// sama seperti yang dibaca `ConsentController@destroy`.
  Future<Map<String, dynamic>> revoke({
    required String childId,
    required String consentType,
  }) async {
    final headers = await _authHeaders(json: true);

    if (headers == null) {
      return _sessionEnded();
    }

    try {
      final response = await http.delete(
        _childConsentsUri(childId),
        headers: headers,
        body: json.encode({'consent_type': consentType}),
      );

      if (response.statusCode == 401) {
        await _auth.logout();
        return _sessionEnded();
      }

      final body = _decode(response);

      if (response.statusCode == 200 && body['success'] == true) {
        return {
          'success': true,
          'message':
              body['message']?.toString() ?? 'Persetujuan berhasil dicabut.',
          'data': body['data'] is Map
              ? Consent.fromJson(Map<String, dynamic>.from(body['data'] as Map))
              : null,
        };
      }

      return {
        'success': false,
        'message':
            body['message']?.toString() ?? 'Gagal mencabut persetujuan.',
        'data': null,
        'errors': body['errors'],
      };
    } on SocketException {
      return _offlineError();
    } on http.ClientException {
      return _offlineError();
    }
  }

  List<Consent> _parseList(dynamic data) {
    if (data is! List) return const <Consent>[];
    return data
        .whereType<Map>()
        .map((e) => Consent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Bentuk hasil seragam, dengan `data` sudah jadi [Consent].
  ///
  /// 201 diterima sama seperti 200 supaya perubahan kecil di backend tidak
  /// membuat layar mengira gagal.
  Map<String, dynamic> _consentResult(
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
            ? Consent.fromJson(Map<String, dynamic>.from(body['data'] as Map))
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
