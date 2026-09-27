import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../utils/constants.dart';
import 'auth_service.dart';

/// Agenda kegiatan posyandu + daftar petugas.
///
/// [getSchedules] dan [getPetugas] dipakai Ibu maupun Kader. Method yang
/// menulis hanya relevan untuk Kader; backend menolak Ibu dengan 403.
class ScheduleService {
  final String baseUrl = ApiConstants.baseUrl;
  final AuthService _auth = AuthService();

  static const _offline =
      'Tidak dapat terhubung ke server. Pastikan backend Laravel berjalan.';

  Map<String, dynamic> _offlineError() =>
      {'success': false, 'message': _offline, 'data': null, 'errors': null};

  Map<String, dynamic> _sessionEnded() => {
        'success': false,
        'status': 401,
        'message': 'Sesi telah berakhir. Silakan login kembali.',
        'data': null,
        'errors': null,
      };

  Future<Map<String, String>?> _authHeaders({bool json = false}) async {
    final token = await _auth.getToken();
    if (token == null || token.isEmpty) return null;

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
        'message': 'Respons server tidak valid (bukan JSON). '
            'Status code: ${response.statusCode}',
        'data': null,
        'errors': null,
      };
    }
  }

  /// Daftar agenda, opsional difilter per tanggal (`YYYY-MM-DD`).
  Future<Map<String, dynamic>> getSchedules({String? date}) async {
    final headers = await _authHeaders();
    if (headers == null) return _sessionEnded();

    try {
      var url = '$baseUrl${ApiConstants.schedulesEndpoint}';
      if (date != null && date.isNotEmpty) {
        url = '$url?date=$date';
      }

      final response = await http.get(Uri.parse(url), headers: headers);

      if (response.statusCode == 401) {
        await _auth.logout();
        return _sessionEnded();
      }

      return _listResult(response, 'Gagal memuat jadwal posyandu.');
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

  /// Daftar petugas posyandu. NIK tidak pernah ikut respons.
  Future<Map<String, dynamic>> getPetugas() async {
    final headers = await _authHeaders();
    if (headers == null) return _sessionEnded();

    try {
      final response = await http.get(
        Uri.parse('$baseUrl${ApiConstants.petugasEndpoint}'),
        headers: headers,
      );

      if (response.statusCode == 401) {
        await _auth.logout();
        return _sessionEnded();
      }

      return _listResult(response, 'Gagal memuat daftar petugas.');
    } on SocketException {
      return _offlineError();
    }
  }

  /// Membuat agenda baru. [petugasIds] boleh null atau kosong.
  Future<Map<String, dynamic>> createSchedule({
    required String title,
    required String scheduledDate,
    String? description,
    String? startTime,
    String? endTime,
    String? location,
    String? status,
    String? notes,
    List<String>? petugasIds,
  }) async {
    final headers = await _authHeaders(json: true);
    if (headers == null) return _sessionEnded();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl${ApiConstants.kaderSchedulesEndpoint}'),
        headers: headers,
        body: json.encode({
          'title': title,
          'scheduled_date': scheduledDate,
          'description': ?description,
          'start_time': ?startTime,
          'end_time': ?endTime,
          'location': ?location,
          'status': ?status,
          'notes': ?notes,
          'petugas_ids': ?petugasIds,
        }),
      );

      if (response.statusCode == 401) return _sessionEnded();

      return _singleResult(response, 'Gagal menyimpan agenda posyandu.');
    } on SocketException {
      return _offlineError();
    }
  }

  /// Mengubah agenda. Hanya field yang diisi yang dikirim.
  ///
  /// Mengirim `petugasIds: []` berarti MENGOSONGKAN seluruh penugasan -
  /// backend memakai `sync`, bukan `syncWithoutDetaching`.
  Future<Map<String, dynamic>> updateSchedule({
    required String scheduleId,
    String? title,
    String? scheduledDate,
    String? description,
    String? startTime,
    String? endTime,
    String? status,
    String? location,
    String? notes,
    List<String>? petugasIds,
  }) async {
    final headers = await _authHeaders(json: true);
    if (headers == null) return _sessionEnded();

    // Partial update. Field yang tidak ikut dikirim tidak berubah di server,
    // jadi form edit cukup mengirim yang memang disentuh petugas.
    final body = <String, dynamic>{};
    if (title != null && title.isNotEmpty) body['title'] = title;
    if (scheduledDate != null && scheduledDate.isNotEmpty) {
      body['scheduled_date'] = scheduledDate;
    }
    if (description != null) body['description'] = description;
    if (startTime != null) body['start_time'] = startTime;
    if (endTime != null) body['end_time'] = endTime;
    if (status != null && status.isNotEmpty) body['status'] = status;
    if (location != null) body['location'] = location;
    if (notes != null) body['notes'] = notes;

    // `[]` berarti mengosongkan semua penugasan, jadi daftar kosong tetap
    // dikirim - yang menentukan adalah apakah nil atau bukan.
    if (petugasIds != null) body['petugas_ids'] = petugasIds;

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
        Uri.parse('$baseUrl${ApiConstants.kaderSchedulesEndpoint}/$scheduleId'),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode == 401) return _sessionEnded();

      return _singleResult(response, 'Gagal memperbarui agenda posyandu.');
    } on SocketException {
      return _offlineError();
    }
  }

  /// Menghapus agenda. Penugasan petugas ikut terhapus di server.
  Future<Map<String, dynamic>> deleteSchedule(String scheduleId) async {
    final headers = await _authHeaders();
    if (headers == null) return _sessionEnded();

    try {
      final response = await http.delete(
        Uri.parse('$baseUrl${ApiConstants.kaderSchedulesEndpoint}/$scheduleId'),
        headers: headers,
      );

      if (response.statusCode == 401) return _sessionEnded();

      return _singleResult(response, 'Gagal menghapus agenda posyandu.');
    } on SocketException {
      return _offlineError();
    }
  }

  // -----------------------------------------------------------------
  // Parser hasil
  // -----------------------------------------------------------------

  /// Endpoint yang `data`-nya berupa daftar objek.
  Map<String, dynamic> _listResult(
    http.Response response,
    String fallbackMessage,
  ) {
    final body = _decode(response);

    if (response.statusCode == 200 && body['success'] == true) {
      final data = body['data'];
      final items = <dynamic>[];
      if (data is List) {
        for (final item in data) {
          if (item is Map) items.add(Map<String, dynamic>.from(item));
        }
      }
      return {
        'success': true,
        'message': body['message']?.toString() ?? fallbackMessage,
        'data': items,
      };
    }

    return {
      'success': false,
      'message': body['message']?.toString() ?? fallbackMessage,
      'data': <dynamic>[],
      'errors': body['errors'],
    };
  }

  /// Endpoint yang `data`-nya berupa satu objek.
  Map<String, dynamic> _singleResult(
    http.Response response,
    String fallbackMessage,
  ) {
    final body = _decode(response);

    if ((response.statusCode == 200 || response.statusCode == 201) &&
        body['success'] == true) {
      return {
        'success': true,
        'message': body['message']?.toString() ?? fallbackMessage,
        'data': body['data'],
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
