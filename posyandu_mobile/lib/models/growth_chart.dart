/// Model grafik tumbuh kembang satu anak (Opsi D).
///
/// Sumber datanya `GET /api/children/{id}/growth`, yang bentuknya dikunci di
/// `docs/RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md` bagian 7.2 dan di aturan agent
/// `posyandu-backend/.ai/rules/kontrak-growth.md`. Kalau bentuk di sini terasa
/// perlu berubah, dokumennya yang diubah lebih dulu.
///
/// Empat hal yang sengaja TIDAK ada di model ini, dan semuanya sudah ditulis
/// di spesifikasi sebagai aturan normatif:
///
///  1. **Tidak ada rumus z-score, status gizi, atau umur.** Semuanya dibaca apa
///     adanya dari database yang menghitungkannya dengan trigger PostgreSQL.
///     Menghitungnya di Dart hanya membuka pintu untuk dua tampilan yang
///     berbeda antara Ibu dan Kader, dan `age_in_months` bisa `null` karena
///     anak memang belum pernah ditimbang - bukan karena umurnya tidak
///     diketahui.
///  2. **Tidak ada pengurutan ulang.** `points` sudah urut naik dari server,
///     yang ditandai `series.order == "asc"`. Mengurutkan ulang di klien berarti
///     menebak aturan yang sama sekali tidak di tempat yang salah.
///  3. **Tidak ada interpolasi pita WHO.** Kalau `who_reference.points` kosong,
///     pitanya memang tidak ada. Menebaknya dari dua titik yang berdekatan
///     menghasilkan pita yang terlihat meyakinkan tapi tidak benar.
///  4. **Tidak ada fallback nol.** Semua angka nullable, dan `null` berarti
///     "tidak ada" - bukan `0`. `MeasurementModel` yang lama memakai `?? 0`,
///     dan pola itu di sini akan membuat Ibu melihat anak beratnya nol pada
///     kunjungan yang memang tidak menimbang berat badan.
library;

import '../utils/month_label.dart' as bln;

/// Identitas anak di kepala grafik.
///
/// Umurnya adalah umur **pada penimbangan terakhir**, dari server, sama
/// seperti [labelUmur] di `TimelineChild`. Kalau tidak ada, tampilannya "-",
/// bukan "0 Bulan": menampilkan "0 Bulan" untuk anak yang belum pernah ditimbang
/// menyiratkan ada penimbangan dengan hasil nol.
class GrowthChild {
  final String id;
  final String name;
  final String? nik;
  final String? dateOfBirth;
  final String? gender;

  /// Umur pada penimbangan terakhir, bukan umur hari ini.
  final int? ageInMonths;

  /// Teks mentah dari `medical_flags`, apa adanya.
  ///
  /// Tidak dipecah dan tidak diberi arti per baris: daftar jenis kondisi tidak
  /// dikunci di database, jadi menebak meaning-nya hanya membuka pintu ke
  /// tebakan yang salah. Yang boleh dibaca cuma apakah isinya ada.
  final String? medicalFlags;

  const GrowthChild({
    this.id = '',
    this.name = '',
    this.nik,
    this.dateOfBirth,
    this.gender,
    this.ageInMonths,
    this.medicalFlags,
  });

  bool get punyaKondisiKhusus {
    final teks = medicalFlags;
    return teks != null && teks.isNotEmpty;
  }

  /// Umur dalam tahun-desimal, untuk posisi titik di sumbu x.
  ///
  /// Ini hanya konversi satuan dari [ageInMonths] yang sudah benar - bukan
  /// penghitungan ulang umur. Kalau [ageInMonths] `null`, hasilnya `null` dan
  /// titiknya tidak bisa diposisikan, jadi dilewati saat menggambar.
  double? get umurTahun {
    final bulan = ageInMonths;
    if (bulan == null) return null;
    return bulan / 12.0;
  }

  /// Label umur siap tampil, tanpa menghitung ulang apa pun.
  String get labelUmur {
    final bulan = ageInMonths;
    if (bulan == null) return '-';

    if (bulan < 12) return '$bulan Bulan';

    final tahun = bulan ~/ 12;
    final sisa = bulan % 12;
    return sisa == 0 ? '$tahun Tahun' : '$tahun Tahun $sisa Bulan';
  }

  factory GrowthChild.fromJson(Map<String, dynamic> json) {
    return GrowthChild(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      nik: _teks(json['nik']),
      dateOfBirth: _teks(json['date_of_birth']),
      gender: _teks(json['gender']),
      ageInMonths: _bulan(json['age_in_months']),
      medicalFlags: _teks(json['medical_flags']),
    );
  }

  /// Helper baca string: null dan string kosong jadi null.
  ///
  /// String kosong diperlakukan sama dengan tidak ada, supaya kolom yang terisi
  /// tapi kosong tidak muncul sebagai badge kosong di layar.
  static String? _teks(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _bulan(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}

/// Satu titik penimbangan untuk digambar.
///
/// Tidak ada `id`: grafik tidak butuh identitas baris, dan tanggal sudah unik
/// per anak karena ada partial unique index di database.
class GrowthPoint {
  /// Tanggal penimbangan (`Y-m-d`).
  ///
  /// Dipakai untuk label titik yang dipilih, bukan untuk posisinya di sumbu x.
  /// Sumbu x adalah umur, karena pita WHO diindeks umur.
  final String? date;

  /// Umur anak saat ditimbang, dari trigger. `null` berarti titik ini tidak
  /// bisa diposisikan di sumbu x dan tidak digambar.
  final int? ageInMonths;

  /// Tidak ada fallback nol. `null` berarti "tidak ditimbang hari itu".
  final double? weightKg;

  /// Nilai mentah, tanpa pita. Tidak ada acuan WHO TB/U di database, jadi
  /// bagian 5.1 dokumen ini memutuskan tinggi badan digambar tanpa band.
  final double? heightCm;

  final double? headCircumferenceCm;

  /// Dibaca apa adanya dari trigger, tidak dihitung ulang di sini.
  ///
  /// `null` untuk anak di luar rentang WHO 0-60 bulan. Itu berbeda dari "gizi
  /// baik", dan tidak boleh diisi 0 atau teks apa pun.
  final double? zScoreWfa;

  final String? statusGizi;

  const GrowthPoint({
    this.date,
    this.ageInMonths,
    this.weightKg,
    this.heightCm,
    this.headCircumferenceCm,
    this.zScoreWfa,
    this.statusGizi,
  });

  /// Umur dalam tahun-desimal untuk sumbu x.
  double? get umurTahun {
    final bulan = ageInMonths;
    if (bulan == null) return null;
    return bulan / 12.0;
  }

  /// Titik ini bisa digambar di grafik berat badan.
  ///
  /// Syaratnya dua: umurnya diketahui supaya ada posisi di sumbu x, dan
  /// beratnya ada supaya tidak jadi titik di angka nol.
  bool get bisaDigambar => umurTahun != null && weightKg != null;

  /// Titik ini bisa digambar di grafik tinggi badan.
  bool get bisaDigambarTinggi => umurTahun != null && heightCm != null;

  /// Label tanggal siap tampil untuk keterangan titik.
  ///
  /// Memakai `labelTanggal()` yang sudah ada, bukan `DateTime.parse`, supaya
  /// formatnya sama dengan timeline dan tanggal yang tidak pernah ada tidak
  /// berubah jadi tanggal yang lebih meyakinkan daripada aslinya. Alias `bln.`
  /// dipakai karena nama getter-nya sama dengan nama fungsi aslinya.
  String get labelTanggal => bln.labelTanggal(date);

  factory GrowthPoint.fromJson(Map<String, dynamic> json) {
    return GrowthPoint(
      date: _teks(json['date']),
      ageInMonths: _bulan(json['age_in_months']),
      weightKg: _desimal(json['weight_kg']),
      heightCm: _desimal(json['height_cm']),
      headCircumferenceCm: _desimal(json['head_circumference_cm']),
      zScoreWfa: _desimal(json['z_score_wfa']),
      statusGizi: _teks(json['status_gizi']),
    );
  }

  /// Angka desimal dari PostgreSQL bisa datang sebagai string (`"12.40"`),
  /// jadi konversinya diamankan terhadap `num` maupun teks.
  ///
  /// `double.tryParse` mengembalikan `null` untuk teks yang bukan angka, dan itu
  /// memang jawaban yang benar di sini: field yang tidak terbaca tidak boleh
  /// diam-diam jadi `0.0`.
  static double? _desimal(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static String? _teks(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _bulan(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}

/// Deret penimbangan beserta satuan dan arah urutnya.
class GrowthSeries {
  final String weightUnit;
  final String heightUnit;

  /// Arah urut dari server. Selalu `"asc"`.
  ///
  /// Field ini ada supaya klien tidak perlu menebak urutan dan supaya test bisa
  /// membuktikannya. Model ini **tetap tidak mengurutkan ulang** kalau nilainya
  /// berbeda - grafik lebih baik menampilkan urutan yang jujur daripada urutan
  /// yang "diperbaiki" dengan tebakan.
  final String order;

  final List<GrowthPoint> points;

  const GrowthSeries({
    this.weightUnit = 'kg',
    this.heightUnit = 'cm',
    this.order = 'asc',
    this.points = const <GrowthPoint>[],
  });

  bool get kosong => points.isEmpty;

  /// Jumlah titik yang punya berat badan, yaitu yang bisa digambar.
  int get jumlahTitikBerat =>
      points.where((p) => p.weightKg != null && p.umurTahun != null).length;

  /// Jumlah titik yang punya tinggi badan.
  int get jumlahTitikTinggi =>
      points.where((p) => p.heightCm != null && p.umurTahun != null).length;

  /// Umur anak saat penimbangan terakhir, untuk batas kanan sumbu x.
  ///
  /// Dipakai supaya garis anak tidak melebar ke usia yang belum dicapainya.
  /// Kalau `null`, widget mengembalikan `null` dan widget menggambar seluruh
  /// rentang pita saja.
  double? get umurTahunTerakhir {
    for (final p in points.reversed) {
      final umur = p.umurTahun;
      if (umur != null) return umur;
    }
    return null;
  }

  /// Status gizi dan z-score penimbangan terakhir, untuk kartu ringkasan.
  ///
  /// Mengambil titik terakhir yang punya z-score, bukan titik terakhir yang
  /// ada. Dua-duanya bisa berbeda pada anak di luar rentang WHO: titik
  /// terakhirnya `null`, tapi titik sebelumnya masih punya z-score. Menampilkan
  /// "null" padahal masih ada z-score yang diketahui akan membuat Ibu mengira
  /// status terakhirnya hilang.
  GrowthPoint? get titikStatusTerakhir {
    for (final p in points.reversed) {
      if (p.zScoreWfa != null || p.statusGizi != null) return p;
    }
    return null;
  }

  /// Titik terakhir yang punya berat badan, untuk label sumbu y.
  GrowthPoint? get titikBeratTerakhir {
    for (final p in points.reversed) {
      if (p.weightKg != null) return p;
    }
    return null;
  }

  /// Titik terakhir yang punya tinggi badan.
  GrowthPoint? get titikTinggiTerakhir {
    for (final p in points.reversed) {
      if (p.heightCm != null) return p;
    }
    return null;
  }

  factory GrowthSeries.fromJson(Map<String, dynamic> json) {
    final unit = json['unit'];
    final daftar = json['points'];

    return GrowthSeries(
      weightUnit: unit is Map ? _teks(unit['weight']) ?? 'kg' : 'kg',
      heightUnit: unit is Map ? _teks(unit['height']) ?? 'cm' : 'cm',
      order: _teks(json['order']) ?? 'asc',
      points: daftar is List
          ? daftar
                .whereType<Map>()
                .map((e) => GrowthPoint.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const <GrowthPoint>[],
    );
  }

  static String? _teks(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}

/// Satu titik pita acuan WHO BB/U.
class WhoReferencePoint {
  final int ageInMonths;
  final double medianKg;
  final double lowerKg;
  final double upperKg;

  const WhoReferencePoint({
    required this.ageInMonths,
    required this.medianKg,
    required this.lowerKg,
    required this.upperKg,
  });

  double get umurTahun => ageInMonths / 12.0;

  factory WhoReferencePoint.fromJson(Map<String, dynamic> json) {
    // Default `-1` supaya field yang hilang atau tidak terbaca tidak pernah
    // menjadi 0: median 0 akan menarik sumbu y dan membuat pita terlihat benar
    // padahal salah. Bandingkan dengan `null` di [GrowthPoint], yang nullable
    // karena berat badan memang boleh kosong.
    return WhoReferencePoint(
      ageInMonths: _bulan(json['age_in_months']) ?? -1,
      medianKg: _desimal(json['median_kg']) ?? -1,
      lowerKg: _desimal(json['lower_kg']) ?? -1,
      upperKg: _desimal(json['upper_kg']) ?? -1,
    );
  }

  static double? _desimal(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _bulan(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}

/// Pita acuan WHO untuk berat badan menurut umur.
///
/// Hanya untuk BB/U. Tidak ada pita tinggi badan, dan tidak akan pernah ada di
/// kelas ini selama database tidak punya acuan TB/U.
class WhoReference {
  /// Selalu `"weight_for_age"`. Dicek di test supaya kelas ini tidak diam-diam
  /// dipakai untuk metrik lain.
  final String metric;
  final String source;
  final String? gender;
  final int? ageFrom;
  final int? ageTo;
  final List<WhoReferencePoint> points;

  const WhoReference({
    this.metric = 'weight_for_age',
    this.source = '',
    this.gender,
    this.ageFrom,
    this.ageTo,
    this.points = const <WhoReferencePoint>[],
  });

  /// Pita tidak ada. Layar harus menampilkan catatan, bukan mengarang pita.
  bool get kosong => points.isEmpty;

  /// Pita ada tapi tidak menutup seluruh rentang 0-60 bulan.
  ///
  /// `who_wfa_standards` punya 61 baris per gender. Kalau jumlahnya kurang, ada
  /// bagian sumbu x yang tidak punya acuan, dan grafik harus mengatakannya
  /// daripada menebak batasnya.
  bool get tidakLengkap => !kosong && points.length != 61;

  /// Rentang umur dalam tahun, siap dipakai sebagai batas sumbu x.
  List<double>? get rentangTahun {
    if (kosong) return null;
    return <double>[points.first.umurTahun, points.last.umurTahun];
  }

  factory WhoReference.fromJson(Map<String, dynamic> json) {
    final rentang = json['age_range'];
    final daftar = json['points'];

    return WhoReference(
      metric: _teks(json['metric']) ?? 'weight_for_age',
      source: _teks(json['source']) ?? '',
      gender: _teks(json['gender']),
      ageFrom: rentang is Map ? _bulan(rentang['from']) : null,
      ageTo: rentang is Map ? _bulan(rentang['to']) : null,
      points: daftar is List
          ? daftar
                .whereType<Map>()
                .map(
                  (e) =>
                      WhoReferencePoint.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const <WhoReferencePoint>[],
    );
  }

  static String? _teks(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _bulan(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}

/// Hasil satu pembacaan grafik tumbuh kembang.
class GrowthChart {
  final GrowthChild child;
  final GrowthSeries series;
  final WhoReference whoReference;

  const GrowthChart({
    this.child = const GrowthChild(),
    this.series = const GrowthSeries(),
    this.whoReference = const WhoReference(),
  });

  /// Belum ada penimbangan sama sekali.
  ///
  /// Bukan error: anak terdaftar di Posyandu, tapi belum pernah ditimbang.
  /// Layar harus menampilkan kanvas dengan pita WHO dan pesan yang jelas, bukan
  /// pesan gagal.
  bool get tanpaData => series.kosong;

  /// Tidak ada acuan WHO untuk gender anak ini, jadi pitanya tidak digambar.
  bool get tanpaPita => whoReference.kosong;

  /// Label ringkas untuk layar: "Siti - 2 Tahun 6 Bulan".
  String get judulLayar => '$child.name - ${child.labelUmur}';

  factory GrowthChart.fromJson(Map<String, dynamic> json) {
    final anak = json['child'];
    final deret = json['series'];
    final pita = json['who_reference'];

    return GrowthChart(
      child: anak is Map
          ? GrowthChild.fromJson(Map<String, dynamic>.from(anak))
          : const GrowthChild(),
      series: deret is Map
          ? GrowthSeries.fromJson(Map<String, dynamic>.from(deret))
          : const GrowthSeries(),
      whoReference: pita is Map
          ? WhoReference.fromJson(Map<String, dynamic>.from(pita))
          : const WhoReference(),
    );
  }
}
