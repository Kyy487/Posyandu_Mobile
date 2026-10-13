/// Model kunjungan layanan anak (P0-1, lihat `docs/RANCANGAN_VISIT.md`).
///
/// Kunjungan adalah "wadah" satu sesi layanan: penimbangan, imunisasi, keluhan,
/// dan rujukan menempel padanya. Rujukan tidak bisa dibuat tanpa memilih
/// kunjungan, jadi daftar ini juga yang dipakai form rujukan.
///
/// Bentuknya `GET /api/children/{id}/visits`. Tiap baris sudah membawa jumlah
/// anak-data yang tertaut (`jumlah_pengukuran`, `jumlah_imunisasi`,
/// `jumlah_keluhan`) - dihitung server lewat `withCount`, bukan dijumlah ulang
/// di sini, supaya formulir dan daftar tidak pernah berbeda angka.
///
/// Yang sengaja TIDAK ada di model ini:
///  - Tidak ada perhitungan tanggal. `visit_date` dibaca apa adanya.
///  - Tidak ada pemetaan `schedule_id` ke jadwal posyandu: daftar ini hanya
///    butuh tahu kunjungannya kapan dan jenisnya apa.
library;

import '../utils/month_label.dart';

/// Jenis kunjungan. Cerminan CHECK `visits_visit_type_check` di database.
class VisitTipe {
  /// Kunjungan rutin di Posyandu.
  static const String posyandu = 'posyandu';

  /// Kunjungan rumah oleh kader.
  static const String kunjunganRumah = 'kunjungan_rumah';

  /// Kunjungan tindak lanjut rujukan.
  static const String rujukan = 'rujukan';

  static const List<String> semua = [posyandu, kunjunganRumah, rujukan];

  /// Label bahasa manusia untuk ditampilkan ke kader.
  static String label(String? value) {
    switch (value) {
      case posyandu:
        return 'Posyandu';
      case kunjunganRumah:
        return 'Kunjungan Rumah';
      case rujukan:
        return 'Tindak Lanjut Rujukan';
      default:
        return 'Kunjungan';
    }
  }
}

/// Satu kunjungan anak.
class Visit {
  final String id;
  final String childId;
  final String? scheduleId;
  final String visitDate;
  final String? visitType;
  final String? kaderId;
  final String? kaderName;
  final String? anamnesis;
  final String? catatanKader;

  /// Jumlah baris yang tertaut, dari server (`withCount`).
  final int jumlahPengukuran;
  final int jumlahImunisasi;
  final int jumlahKeluhan;

  const Visit({
    required this.id,
    required this.childId,
    this.scheduleId,
    this.visitDate = '',
    this.visitType,
    this.kaderId,
    this.kaderName,
    this.anamnesis,
    this.catatanKader,
    this.jumlahPengukuran = 0,
    this.jumlahImunisasi = 0,
    this.jumlahKeluhan = 0,
  });

  String get tipeLabel => VisitTipe.label(visitType);
  String get tanggalLabel => labelTanggal(visitDate);

  /// Jumlah total data yang tertaut. Dipakai untuk menandai kunjungan yang
  /// masih kosong di form.
  int get jumlahDataTertaut =>
      jumlahPengukuran + jumlahImunisasi + jumlahKeluhan;

  bool get adaDataTertaut => jumlahDataTertaut > 0;

  /// Satu baris ringkas untuk dropdown pemilihan kunjungan.
  String get ringkasan =>
      '$tanggalLabel · $tipeLabel'
      '${adaDataTertaut ? ' · $jumlahDataTertaut data' : ''}';

  factory Visit.fromJson(Map<String, dynamic> json) {
    final kader = json['kader'];

    return Visit(
      id: json['id']?.toString() ?? '',
      childId: json['child_id']?.toString() ?? '',
      scheduleId: _teks(json['schedule_id']),
      visitDate: json['visit_date']?.toString() ?? '',
      visitType: _teks(json['visit_type']),
      kaderId: _teks(json['kader_id']),
      kaderName: kader is Map ? _teks(kader['name']) : null,
      anamnesis: _teks(json['anamnesis']),
      catatanKader: _teks(json['catatan_kader']),
      jumlahPengukuran: _int(json['jumlah_pengukuran']),
      jumlahImunisasi: _int(json['jumlah_imunisasi']),
      jumlahKeluhan: _int(json['jumlah_keluhan']),
    );
  }

  static String? _teks(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

/// Hasil endpoint daftar kunjungan: info anak + daftar kunjungan.
class VisitList {
  final String childId;
  final String childName;
  final List<Visit> visits;

  const VisitList({
    this.childId = '',
    this.childName = '',
    this.visits = const <Visit>[],
  });

  bool get kosong => visits.isEmpty;
  int get jumlah => visits.length;

  factory VisitList.fromJson(Map<String, dynamic> json) {
    final child = json['child'];
    final daftar = json['visits'];

    return VisitList(
      childId: child is Map ? child['id']?.toString() ?? '' : '',
      childName: child is Map ? child['name']?.toString() ?? '' : '',
      visits: daftar is List
          ? daftar
                .whereType<Map>()
                .map((e) => Visit.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const <Visit>[],
    );
  }
}
