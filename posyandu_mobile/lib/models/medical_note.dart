/// Model untuk catatan keluhan anak (Opsi C).
///
/// Keluhan disimpan sebagai TIGA KOLOM BOOLEAN TERPISAIN - `demam`, `rewel`,
/// `diare` - bukan satu daftar. Alasannya ada di sisi server (lihat migration
/// `2026_09_27_010000_create_medical_notes_table.php`): rekap bulanan nanti
/// perlu menghitung "berapa anak bulan ini punya demam" dengan satu
/// aggregate di database. Kalau keluhan disimpan sebagai array, atau satu
/// baris per keluhan, hitungan itu jadi jauh lebih mahal dan tidak bisa
/// dijawab lewat index.
///
/// Konsekuensi di sisi ini: menambah kolom keluhan baru berarti menambah
/// kolom boolean baru di database, bukan menambah item ke daftar. Itu
/// trade-off yang disengaja.
///
/// Yang DIKIRIM server dan TIDAK dihitung ulang di sini: `keluhan` (daftar
/// nama keluhan siap tampil) dan `ringkasan` (satu baris ringkas). Keduanya
/// dihitung dari tiga kolom yang sama, jadi menghitungnya lagi di Flutter
/// hanya membuka pintu untuk tampilan yang berbeda antara Kader dan Ibu.
library;

import '../utils/month_label.dart';

class TindakLanjut {
  /// Keluhan ditangani dengan observasi dan saran saja.
  static const String ringan = 'ringan';

  /// Perlu tindakan lebih aktif, misalnya perawatan atau pemberian obat.
  static const String sedang = 'sedang';

  /// Perlu dirujuk ke fasilitas yang lebih lengkap.
  static const String rujuk = 'rujuk';

  /// Cerminan CHECK constraint `medical_notes_tindak_lanjut_check` di
  /// database. Menambah nilai baru harus lewat migration baru.
  static const List<String> semua = [ringan, sedang, rujuk];

  /// Label bahasa manusia untuk ditampilkan ke kader dan Ibu.
  static String label(String? value) {
    switch (value) {
      case ringan:
        return 'Observasi dan saran';
      case sedang:
        return 'Perawatan aktif';
      case rujuk:
        return 'Perlu rujukan';
      default:
        // null = kader belum memutuskan tindak lanjut. Bukan kondisi error,
        // jadi ditampilkan sebagai "-" dan bukan "Tidak diketahui".
        return '-';
    }
  }

  /// Keterangan singkat untuk form pencatatan, supaya kader paham
  /// konsekuensi tiap pilihan sebelum memilih.
  static String petunjuk(String value) {
    switch (value) {
      case ringan:
        return 'Pantau di kunjungan berikutnya, beri saran sederhana.';
      case sedang:
        return 'Perlu tindakan lebih aktif, misalnya pemberian obat atau perawatan.';
      case rujuk:
        return 'Rujuk ke fasilitas kesehatan atau puskesmas rujukan.';
      default:
        return '';
    }
  }
}

/// Satu catatan keluhan.
class MedicalNote {
  final String id;
  final String childId;
  final String? measurementId;
  final String? kaderId;
  final String? kaderName;
  final String noteDate;
  final bool demam;
  final bool rewel;
  final bool diare;
  final List<String> keluhan;
  final String? catatan;
  final String? tindakLanjut;
  final String ringkasan;

  const MedicalNote({
    required this.id,
    required this.childId,
    required this.noteDate,
    this.measurementId,
    this.kaderId,
    this.kaderName,
    this.demam = false,
    this.rewel = false,
    this.diare = false,
    this.keluhan = const <String>[],
    this.catatan,
    this.tindakLanjut,
    this.ringkasan = '',
  });

  /// Ada keluhan yang dicentang, bukan cuma catatan teks bebas.
  bool get punyaKeluhan => keluhan.isNotEmpty;

  /// Perlu rujukan. Dicek dari nilai server, bukan dari `keluhan`, karena
  /// kader bisa memilih "rujuk" untuk catatan saran tanpa keluhan.
  bool get perluRujukan => tindakLanjut == TindakLanjut.rujuk;

  /// Jumlah keluhan yang dicentang, untuk badge ringkas.
  int get jumlahKeluhan => (demam ? 1 : 0) + (rewel ? 1 : 0) + (diare ? 1 : 0);

  factory MedicalNote.fromJson(Map<String, dynamic> json) {
    final kader = json['kader'];
    final rawKeluhan = json['keluhan'];

    return MedicalNote(
      id: json['id']?.toString() ?? '',
      childId: json['child_id']?.toString() ?? '',
      measurementId: _str(json['measurement_id']),
      kaderId: _str(json['kader_id']),
      kaderName: kader is Map ? _str(kader['name']) : null,
      noteDate: json['note_date']?.toString() ?? '',
      // Boolean harus dibaca dengan `_toBool`, bukan `json['demam'] == true`.
      // Driver database bisa mengirim `true` maupun `"true"`, dan string
      // `"true" == true` bernilai false - artinya checkbox di UI tercentang
      // terbalik. Ini bug yang harus dihindari sejak awal.
      demam: _toBool(json['demam']),
      rewel: _toBool(json['rewel']),
      diare: _toBool(json['diare']),
      keluhan: rawKeluhan is List
          ? rawKeluhan.map((e) => e.toString()).toList()
          : const <String>[],
      catatan: _str(json['catatan']),
      tindakLanjut: _str(json['tindak_lanjut']),
      ringkasan: json['ringkasan']?.toString() ?? '',
    );
  }

  static String? _str(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Menangani `true`, `1`, `"true"`, `"1"`, dan `"yes"`.
  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value == null) return false;
    switch (value.toString().trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
        return true;
      default:
        return false;
    }
  }
}

/// Ringkasan jumlah di header daftar.
///
/// Angkanya dikirim server supaya Kader dan Ibu melihat angka yang sama,
/// dan supaya Flutter tidak perlu menghitung ulang dari daftar.
class MedicalNoteSummary {
  final int total;
  final int demam;
  final int rewel;
  final int diare;
  final int perluRujuk;

  const MedicalNoteSummary({
    this.total = 0,
    this.demam = 0,
    this.rewel = 0,
    this.diare = 0,
    this.perluRujuk = 0,
  });

  factory MedicalNoteSummary.fromJson(Map<String, dynamic> json) {
    int i(String key) => _toInt(json[key]) ?? 0;

    return MedicalNoteSummary(
      total: i('total'),
      demam: i('demam'),
      rewel: i('rewel'),
      diare: i('diare'),
      perluRujuk: i('perlu_rujuk'),
    );
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}

/// Hasil endpoint daftar: info anak + filter aktif + ringkasan + catatan.
class MedicalNoteList {
  final String childId;
  final String childName;
  final String? month;
  final bool all;
  final MedicalNoteSummary summary;
  final List<MedicalNote> notes;

  const MedicalNoteList({
    required this.childId,
    required this.childName,
    this.month,
    this.all = false,
    this.summary = const MedicalNoteSummary(),
    this.notes = const <MedicalNote>[],
  });

  /// Label filter untuk ditampilkan di layar, mis. "September 2026".
  ///
  /// Memakai helper bersama di `utils/month_label.dart` supaya rekap
  /// imunisasi menampilkan nama bulan yang sama persis dengan layar ini.
  /// Kalau dua layar punya daftar nama bulan masing-masing, keduanya pasti
  /// berbeda suatu saat dan kader akan mengira itu dua bulan yang berbeda.
  String get labelFilter {
    if (all) return 'Semua bulan';
    return labelBulan(month);
  }

  factory MedicalNoteList.fromJson(Map<String, dynamic> json) {
    final child = json['child'];
    final filter = json['filter'];
    final summary = json['summary'];
    final rawNotes = json['notes'];

    return MedicalNoteList(
      childId: child is Map ? child['id']?.toString() ?? '' : '',
      childName: child is Map ? child['name']?.toString() ?? '' : '',
      month: filter is Map ? _str(filter['month']) : null,
      all: filter is Map ? filter['all'] == true : false,
      summary: summary is Map
          ? MedicalNoteSummary.fromJson(Map<String, dynamic>.from(summary))
          : const MedicalNoteSummary(),
      notes: rawNotes is List
          ? rawNotes
                .whereType<Map>()
                .map((e) => MedicalNote.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const <MedicalNote>[],
    );
  }

  static String? _str(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }
}
