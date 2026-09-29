/// Model untuk rekap imunisasi bulanan (Opsi E).
///
/// Endpoint `GET /api/kader/immunizations/recap` mengirim DUA bagian yang
/// jawab pertanyaan berbeda, dan keduanya tidak boleh dijumlahkan:
///
/// * `activity` - berapa dosis yang disuntik bulan itu. Dipakai untuk stok
///   vaksin.
/// * `coverage` - kelengkapan tiap anak di AKHIR bulan itu. Dipakai untuk
///   laporan ke BIDAN dan menyiapkan kunjungan rumah.
///
/// Posyandu bisa saja aktivitasnya tinggi (40 suntikan) sementara
/// kelengkapannya tetap jelek, karena 40 suntikan itu bisa saja untuk 5 anak
/// saja. Menjumlahkan atau menggabung kedua angka di layar akan menghasilkan
/// angka yang tidak berarti.
///
/// Semua angka dikirim server dan TIDAK dihitung ulang di sini. Alasannya sama
/// dengan checklist imunisasi: aturan status `terlambat` memakai ambang
/// toleransi dari config posyandu yang bisa berubah, jadi menyalin logikanya
/// ke Flutter dijamin akan menyimpang dari server.
///
/// Yang boleh dilakukan klien hanya memformat ulang untuk tampilan.
library;

import '../utils/month_label.dart';

/// Satu baris `activity.by_type`: satu dosis master + berapa kali disuntik
/// pada bulan itu.
///
/// Server SELALU mengirim seluruh 16 master, termasuk yang `count`-nya 0.
/// Baris nol sengaja tidak disembunyikan: kader perlu membedakan "tidak ada
/// yang disuntik bulan ini" dari "tidak sempat dicatat", dan kalau baris nol
/// hilang keduanya terlihat sama.
class RecapDoseCount {
  final String typeId;
  final String code;
  final String name;

  /// Nama dosis siap tampil. Untuk dosis > 1 sudah termasuk nomornya,
  /// mis. "Hepatitis B (Dosis 2)", jadi tidak ada penomoran di sisi klien.
  final String label;
  final int doseNumber;
  final int count;

  const RecapDoseCount({
    required this.typeId,
    required this.code,
    required this.name,
    required this.label,
    required this.doseNumber,
    required this.count,
  });

  /// Dosis ini tidak pernah disuntik pada bulan yang dipilih.
  bool get kosong => count == 0;

  factory RecapDoseCount.fromJson(Map<String, dynamic> json) {
    return RecapDoseCount(
      typeId: _str(json['immunization_type_id']) ?? '',
      code: _str(json['code']) ?? '',
      name: _str(json['name']) ?? '',
      label: _str(json['label']) ?? _str(json['name']) ?? '-',
      doseNumber: _toInt(json['dose_number']) ?? 1,
      count: _toInt(json['count']) ?? 0,
    );
  }
}

/// Bagian `activity`: suntikan yang terjadi pada bulan itu.
class RecapActivity {
  final int totalDoses;

  /// Berapa anak berbeda yang menerima suntikan bulan itu. BEDA dari
  /// `coverage.total_children` yang menghitung semua anak aktif.
  final int totalChildren;
  final List<RecapDoseCount> byType;

  const RecapActivity({
    this.totalDoses = 0,
    this.totalChildren = 0,
    this.byType = const <RecapDoseCount>[],
  });

  /// Dosis yang benar-benar disuntik bulan itu, tanpa baris `count: 0`.
  ///
  /// Dipakai layar untuk menampilkan "vaksin yang terpakai" secara ringkas.
  /// Total keseluruhan tetap pakai [totalDoses] dari server.
  List<RecapDoseCount> get terpakai => byType.where((e) => !e.kosong).toList();

  /// Jumlahkan `count` per vaksin (`code`), supaya 4 dosis Hepatitis B
  /// tampil sebagai satu baris "Hepatitis B" dan bukan 4 baris terpisah.
  ///
  /// Urutan baris mengikuti urutan server supaya tampilan stabil. Urutan
  /// server adalah urutan master, bukan urutan suntikan - jangan dipakai
  /// untuk menyusun jadwal minum vaksin.
  Map<String, int> get totalPerVaksin {
    final map = <String, int>{};
    for (final dosis in byType) {
      map[dosis.code] = (map[dosis.code] ?? 0) + dosis.count;
    }
    return map;
  }

  /// Tidak ada suntikan sama sekali di bulan itu. Menampilkan angka nol lebih
  /// jujur daripada menampilkan layar kosong yang terlihat seperti error.
  bool get kosong => totalDoses == 0;

  factory RecapActivity.fromJson(Map<String, dynamic> json) {
    final raw = json['by_type'];
    return RecapActivity(
      totalDoses: _toInt(json['total_doses']) ?? 0,
      totalChildren: _toInt(json['total_children']) ?? 0,
      byType: raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (e) => RecapDoseCount.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const <RecapDoseCount>[],
    );
  }
}

/// Satu dosis yang belum disuntik dan sudah lewat target + toleransi.
class RecapOverdueDose {
  final String typeId;
  final String code;
  final String name;
  final String label;
  final int doseNumber;

  /// Usia target dosis ini dalam bulan, atau null bila master tidak
  /// menetapkannya.
  final int? targetAgeMonths;

  /// Sisa bulan menuju status terlambat. Selalu terisi di sini (dosis yang
  /// terlambat pasti punya batas), tapi tetap nullable supaya parser tidak
  /// crash kalau someday server mengirim null.
  ///
  /// Perhatikan bedanya dengan checklist anak: di checklist, `sisa_bulan` null
  /// untuk dosis berstatus `sudah`. Di rekap tidak ada dosis `sudah`.
  final int? monthsLeft;

  const RecapOverdueDose({
    required this.typeId,
    required this.code,
    required this.name,
    required this.label,
    required this.doseNumber,
    this.targetAgeMonths,
    this.monthsLeft,
  });

  /// Berapa bulan dosis ini lewat dari targetnya.
  int get bulanTerlambat => (monthsLeft ?? 0).abs();

  /// Penjelasan singkat untuk layar, pakai kalimat yang sama dengan
  /// `ImmunizationItem.statusNote` supaya kader membaca "Terlambat 12 bulan"
  /// dengan cara yang sama di kedua layar.
  String get statusNote {
    final behind = bulanTerlambat;
    return behind == 0 ? 'Terlambat' : 'Terlambat $behind bulan';
  }

  /// Target dalam bahasa manusia, sama formatnya dengan checklist.
  String get targetLabel {
    final t = targetAgeMonths;
    if (t == null) return '-';
    if (t == 0) return 'Saat lahir';
    return '$t bulan';
  }

  factory RecapOverdueDose.fromJson(Map<String, dynamic> json) {
    return RecapOverdueDose(
      typeId: _str(json['immunization_type_id']) ?? '',
      code: _str(json['code']) ?? '',
      name: _str(json['name']) ?? '',
      label: _str(json['label']) ?? _str(json['name']) ?? '-',
      doseNumber: _toInt(json['dose_number']) ?? 1,
      targetAgeMonths: _toInt(json['target_age_months']),
      monthsLeft: _toInt(json['sisa_bulan']),
    );
  }
}

/// Satu anak yang punya minimal satu dosis terlambat.
class RecapOverdueChild {
  final String childId;
  final String name;
  final String? dateOfBirth;
  final int? ageInMonths;
  final List<RecapOverdueDose> overdueDoses;

  const RecapOverdueChild({
    required this.childId,
    required this.name,
    this.dateOfBirth,
    this.ageInMonths,
    this.overdueDoses = const <RecapOverdueDose>[],
  });

  int get jumlahDosis => overdueDoses.length;

  /// Dosis terlambat paling lama, dipakai untuk kalimat ringkas di header
  /// kartu. Server sudah mengurutkan anak berdasarkan ini, jadi mengambil
  /// nilai pertama tidak mengubah urutan apa pun.
  int get terlambatTerlama => overdueDoses.isEmpty
      ? 0
      : overdueDoses
            .map((e) => e.bulanTerlambat)
            .reduce((a, b) => a > b ? a : b);

  String get ageLabel {
    final bulan = ageInMonths;
    if (bulan == null) return '-';
    if (bulan < 12) return '$bulan bulan';
    return '${bulan ~/ 12} Tahun ${bulan % 12} Bulan';
  }

  factory RecapOverdueChild.fromJson(Map<String, dynamic> json) {
    final raw = json['overdue_doses'];
    return RecapOverdueChild(
      childId: _str(json['child_id']) ?? '',
      name: _str(json['name']) ?? '-',
      dateOfBirth: _str(json['date_of_birth']),
      ageInMonths: _toInt(json['age_in_months']),
      overdueDoses: raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (e) =>
                      RecapOverdueDose.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const <RecapOverdueDose>[],
    );
  }
}

/// Bagian `coverage`: kelengkapan tiap anak di akhir bulan yang diminta.
class RecapCoverage {
  final int totalChildren;
  final int complete;
  final int incomplete;
  final int overdue;

  /// Anak yang di-soft delete dan TIDAK ikut dihitung. Dilaporkan supaya
  /// angka utama tidak menyembunyikan ada anak yang keluar dari hitungan.
  final int excludedArchived;
  final List<RecapOverdueChild> overdueChildren;

  const RecapCoverage({
    this.totalChildren = 0,
    this.complete = 0,
    this.incomplete = 0,
    this.overdue = 0,
    this.excludedArchived = 0,
    this.overdueChildren = const <RecapOverdueChild>[],
  });

  /// Persen anak yang imunisasinya lengkap.
  ///
  /// Ini turunan dari `complete / total_children`, BUKAN penjumlahan dosis.
  /// Menjumlahkan dosis akan menghitung satu anak lima kali kalau dia punya
  /// lima dosis terlambat.
  int get percentComplete =>
      totalChildren == 0 ? 0 : ((complete / totalChildren) * 100).round();

  /// Tidak ada anak yang perlu dikunjungi. `incomplete` yang dicek, bukan
  /// `overdueChildren.isEmpty`, karena daftar anak bisa kosong sementara
  /// statusnya belum lengkap.
  bool get semuaLengkap => incomplete == 0;

  factory RecapCoverage.fromJson(Map<String, dynamic> json) {
    final raw = json['overdue_children'];
    return RecapCoverage(
      totalChildren: _toInt(json['total_children']) ?? 0,
      complete: _toInt(json['complete']) ?? 0,
      incomplete: _toInt(json['incomplete']) ?? 0,
      overdue: _toInt(json['overdue']) ?? 0,
      excludedArchived: _toInt(json['excluded_archived']) ?? 0,
      overdueChildren: raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (e) =>
                      RecapOverdueChild.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const <RecapOverdueChild>[],
    );
  }
}

/// Hasil endpoint rekap: filter + activity + coverage.
class ImmunizationRecap {
  /// Bulan yang direkap, format `YYYY-MM`. Diambil dari `filter.month`, bukan
  /// dari tanggal perangkat, supaya layar menampilkan bulan yang benar-benar
  /// dihitung server.
  final String? month;

  /// Akhir bulan yang dipakai server sebagai acuan, mis. "2026-09-30".
  ///
  /// Penting untuk laporan historis: rekap September yang dibuka di November
  /// angkanya sama dengan yang dibuka di Oktober, karena server mengabaikan
  /// suntikan setelah tanggal ini.
  final String? referenceDate;
  final RecapActivity activity;
  final RecapCoverage coverage;

  const ImmunizationRecap({
    this.month,
    this.referenceDate,
    this.activity = const RecapActivity(),
    this.coverage = const RecapCoverage(),
  });

  /// "September 2026".
  String get labelBulanRekap => labelBulan(month);

  /// "30 September 2026", dipakai sebagai keterangan di bawah judul.
  String get labelAcuan => labelTanggal(referenceDate);

  /// Tidak ada suntikan dan tidak ada anak terlambat di bulan ini. Layar
  /// menampilkan penjelasan, bukan layar kosong yang disalahartikan error.
  bool get kosong => activity.kosong && coverage.overdueChildren.isEmpty;

  factory ImmunizationRecap.fromJson(Map<String, dynamic> json) {
    final filter = json['filter'];
    final activity = json['activity'];
    final coverage = json['coverage'];

    return ImmunizationRecap(
      month: filter is Map ? _str(filter['month']) : null,
      referenceDate: filter is Map ? _str(filter['reference_date']) : null,
      activity: activity is Map
          ? RecapActivity.fromJson(Map<String, dynamic>.from(activity))
          : const RecapActivity(),
      coverage: coverage is Map
          ? RecapCoverage.fromJson(Map<String, dynamic>.from(coverage))
          : const RecapCoverage(),
    );
  }
}

String? _str(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}

int? _toInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
