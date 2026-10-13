/// Model rujukan anak ke fasilitas kesehatan (lihat
/// `docs/RANCANGAN_RUJUKAN.md`).
///
/// Rujukan adalah catatan tindak lanjut: kader memutuskan anak perlu ditangani
/// di Puskesmas, Rumah Sakit, atau fasilitas lain, lalu mencatat statusnya
/// sampai selesai. Rujukan selalu menempel pada satu kunjungan (`visit_id`),
/// jadi tanggalnya mengikuti kunjungan itu.
///
/// Dua daftar nilai di bawah (`ReferralTipe` dan `ReferralStatus`) adalah
/// cerminan CHECK constraint di database. Nilainya dikirim server apa adanya,
/// dan yang dilakukan di sini hanya menerjemahkannya ke label bahasa manusia -
/// sama seperti `TindakLanjut` pada catatan keluhan. Menambah nilai baru harus
/// lewat migration, bukan di sini.
///
/// Yang sengaja TIDAK ada di model ini:
///  - Tidak ada perhitungan tanggal. `referral_date` dibaca apa adanya; kalau
///    tanggalnya rusak, tampil apa adanya daripada "diperbaiki" menjadi tanggal
///    yang terlihat lebih meyakinkan daripada aslinya.
///  - Tidak ada pembuatan rujukan dari layar mobile. Membuat rujukan butuh
///    memilih kunjungan (`visit_id`) yang belum ada di aplikasi ini, jadi ruang
///    lingkupnya masih baca saja.
library;

import '../utils/month_label.dart';

/// Jenis fasilitas yang menjadi tujuan rujukan.
class ReferralTipe {
  static const String puskesmas = 'puskesmas';
  static const String rs = 'rs';
  static const String faskesLain = 'faskes_lain';

  /// Cerminan CHECK `referrals_referral_type_check`.
  static const List<String> semua = [puskesmas, rs, faskesLain];

  /// Label bahasa manusia untuk ditampilkan ke kader dan Ibu.
  static String label(String? value) {
    switch (value) {
      case puskesmas:
        return 'Puskesmas';
      case rs:
        return 'Rumah Sakit';
      case faskesLain:
        return 'Fasilitas Kesehatan Lain';
      default:
        // null = server mengirim baris tanpa jenis. Bukan kondisi error yang
        // perlu ditakuti, jadi teksnya netral alih-alih "Tidak diketahui".
        return 'Fasilitas Kesehatan';
    }
  }
}

/// Status perjalanan rujukan.
class ReferralStatus {
  /// Rujukan dibuat, belum disampaikan ke fasilitas tujuan.
  static const String dibuat = 'dibuat';

  /// Sudah dilaporkan/diserahkan ke fasilitas tujuan.
  static const String dilaporkan = 'dilaporkan';

  /// Sudah selesai ditangani.
  static const String selesai = 'selesai';

  /// Cerminan CHECK `referrals_status_check`.
  static const List<String> semua = [dibuat, dilaporkan, selesai];

  static String label(String? value) {
    switch (value) {
      case dibuat:
        return 'Dibuat';
      case dilaporkan:
        return 'Dilaporkan';
      case selesai:
        return 'Selesai';
      default:
        return 'Tidak diketahui';
    }
  }
}

/// Satu rujukan anak.
class Referral {
  final String id;
  final String childId;
  final String visitId;
  final String referralDate;
  final String? referralType;
  final String? reason;
  final String? facilityName;
  final String? status;

  /// Kader pencatat. `null` itu sah: `kader_id` bisa null karena
  /// `ON DELETE SET NULL`, dan riwayat anak tidak boleh hilang hanya karena
  /// akun kadernya dihapus.
  final String? kaderId;
  final String? kaderName;

  final String? createdAt;
  final String? updatedAt;

  const Referral({
    required this.id,
    required this.childId,
    required this.visitId,
    this.referralDate = '',
    this.referralType,
    this.reason,
    this.facilityName,
    this.status,
    this.kaderId,
    this.kaderName,
    this.createdAt,
    this.updatedAt,
  });

  String get tipeLabel => ReferralTipe.label(referralType);
  String get statusLabel => ReferralStatus.label(status);

  /// Tanggal siap tampil, memakai helper yang sama dengan layar lain.
  String get tanggalLabel => labelTanggal(referralDate);

  bool get selesai => status == ReferralStatus.selesai;
  bool get adaCatatan => reason != null && reason!.isNotEmpty;

  factory Referral.fromJson(Map<String, dynamic> json) {
    final kader = json['kader'];

    return Referral(
      id: json['id']?.toString() ?? '',
      childId: json['child_id']?.toString() ?? '',
      visitId: json['visit_id']?.toString() ?? '',
      referralDate: json['referral_date']?.toString() ?? '',
      referralType: _teks(json['referral_type']),
      reason: _teks(json['reason']),
      facilityName: _teks(json['facility_name']),
      status: _teks(json['status']),
      kaderId: _teks(json['kader_id']),
      kaderName: kader is Map ? _teks(kader['name']) : null,
      createdAt: _teks(json['created_at']),
      updatedAt: _teks(json['updated_at']),
    );
  }

  /// Helper baca string: null dan string kosong jadi null.
  static String? _teks(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}

/// Hasil endpoint daftar rujukan: info anak + daftar rujukan.
class ReferralList {
  final String childId;
  final String childName;
  final List<Referral> referrals;

  const ReferralList({
    this.childId = '',
    this.childName = '',
    this.referrals = const <Referral>[],
  });

  bool get kosong => referrals.isEmpty;
  int get jumlah => referrals.length;

  /// Berapa rujukan yang belum selesai, untuk badge ringkas.
  int get jumlahBelumSelesai =>
      referrals.where((r) => !r.selesai).length;

  factory ReferralList.fromJson(Map<String, dynamic> json) {
    final child = json['child'];
    final daftar = json['referrals'];

    return ReferralList(
      childId: child is Map ? child['id']?.toString() ?? '' : '',
      childName: child is Map ? child['name']?.toString() ?? '' : '',
      referrals: daftar is List
          ? daftar
                .whereType<Map>()
                .map((e) => Referral.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const <Referral>[],
    );
  }
}
