/// Model persetujuan (consent) pemrosesan data anak.
///
/// Ini bagian kepatuhan UU PDP No. 27/2022 (lihat `docs/PERANCANGAN_PERKUATAN.md`
/// §5.1). Ibu/wali memberi izin memproses data anaknya, dan izin itu bisa
/// dicabut kapan saja tanpa menghapus riwayat medis yang sudah tercatat.
///
/// Daftar tipe di bawah adalah cerminan `CONSENT_TYPES` di
/// `app/Http/Controllers/Api/ConsentController.php`. Menambah tipe baru harus
/// lewat migration + controller, bukan di sini.
library;

import '../utils/month_label.dart';

/// Versi formulir persetujuan yang dikirim mobile.
///
/// Dikirim apa adanya sebagai `document_version` (saat mendaftar anak:
/// `consent_document_version`). Kalau teks formulir berubah, naikkan nilai ini
/// supaya baris consent lama tetap menunjuk versi yang benar-benar disetujui.
const String kConsentDocumentVersion = '1.0';

/// Tipe persetujuan yang diakui server.
class ConsentTipe {
  /// Pemrosesan data untuk layanan Posyandu. Ini yang diminta saat mendaftar.
  static const String dataProcessing = 'data_processing';

  /// Berbagi data dengan pihak lain (mis. dinas kesehatan).
  static const String dataSharing = 'data_sharing';

  /// Pemakaian data untuk penelitian.
  static const String research = 'research';

  /// Cermin `ConsentController::CONSENT_TYPES`.
  static const List<String> semua = [dataProcessing, dataSharing, research];

  static String label(String? value) {
    switch (value) {
      case dataProcessing:
        return 'Pemrosesan Data';
      case dataSharing:
        return 'Berbagi Data';
      case research:
        return 'Penelitian';
      default:
        return 'Persetujuan';
    }
  }

  /// Penjelasan singkat tiap tipe, dipakai di layar persetujuan.
  static String deskripsi(String? value) {
    switch (value) {
      case dataProcessing:
        return 'Data anak dipakai untuk pencatatan tumbuh kembang dan layanan '
            'Posyandu.';
      case dataSharing:
        return 'Data anak boleh dibagikan ke pihak lain seperti dinas '
            'kesehatan.';
      case research:
        return 'Data anak boleh dipakai untuk penelitian, tanpa identitas.';
      default:
        return '';
    }
  }
}

/// Satu baris persetujuan.
///
/// Server hanya mengirim consent yang masih AKTIF di `GET /children/{id}/consents`
/// (yang `revoked_at`-nya terisi tidak ikut), tapi model tetap menyimpan
/// `revokedAt` supaya respons tulis bisa dibaca apa adanya.
class Consent {
  final String id;
  final String childId;
  final String? grantedBy;
  final String? consentType;

  /// Waktu persetujuan diberikan, ISO 8601.
  final String? grantedAt;

  /// Waktu dicabut. Null berarti masih aktif.
  final String? revokedAt;

  final String? documentVersion;
  final String? notes;
  final String? createdAt;
  final String? updatedAt;

  const Consent({
    required this.id,
    required this.childId,
    this.grantedBy,
    this.consentType,
    this.grantedAt,
    this.revokedAt,
    this.documentVersion,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  String get tipeLabel => ConsentTipe.label(consentType);
  String get tipeDeskripsi => ConsentTipe.deskripsi(consentType);

  /// Aktif berarti belum dicabut.
  bool get aktif => revokedAt == null;

  /// Tanggal diberikan dalam format "13 Oktober 2026".
  ///
  /// `granted_at` datang sebagai ISO 8601 lengkap ("2026-10-13T08:00:00Z"),
  /// sedangkan `labelTanggal` hanya paham `YYYY-MM-DD` - jadi 10 karakter
  /// pertama diambil lebih dulu. String yang lebih pendek dikembalikan apa
  /// adanya supaya tanggal rusak tidak jadi crash.
  String get tanggalLabel {
    final g = grantedAt;
    if (g == null || g.isEmpty) return '-';
    return labelTanggal(g.length >= 10 ? g.substring(0, 10) : g);
  }

  factory Consent.fromJson(Map<String, dynamic> json) {
    return Consent(
      id: json['id']?.toString() ?? '',
      childId: json['child_id']?.toString() ?? '',
      grantedBy: _teks(json['granted_by']),
      consentType: _teks(json['consent_type']),
      grantedAt: _teks(json['granted_at']),
      revokedAt: _teks(json['revoked_at']),
      documentVersion: _teks(json['document_version']),
      notes: _teks(json['notes']),
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
