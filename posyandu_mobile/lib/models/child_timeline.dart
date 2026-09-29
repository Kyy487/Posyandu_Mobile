/// Model riwayat medis gabungan satu anak (Opsi B - Buku Medis Digital).
///
/// Sumber datanya `GET /api/children/{id}/timeline`, yang bentuknya dikunci di
/// `docs/RANCANGAN_BUKU_MEDIS.md` bagian 7.2 dan di aturan agent
/// `posyandu-backend/.ai/rules/kontrak-timeline.md`. Kalau bentuk di sini
/// terasa perlu berubah, dokumennya yang diubah lebih dulu.
///
/// Tiga hal yang sengaja TIDAK ada di model ini, dan ketiganya sudah ditulis
/// di spesifikasi sebagai aturan normatif:
///
///  1. **Tidak ada rumus z-score, status gizi, atau umur.** Semuanya dibaca apa
///     adanya dari database yang menghitungkannya dengan trigger PostgreSQL.
///     Menyalin perhitungan itu ke Dart hanya membuka pintu untuk tampilan yang
///     berbeda antara Kader dan Ibu - dan `age_in_months` di respons bisa
///     `null` karena anak memang belum pernah ditimbang, bukan karena umurnya
///     tidak diketahui.
///  2. **Tidak ada pengurutan ulang entri.** Server mengirim tanggal terbaru
///     lebih dulu; hanya server yang tahu urutan itu benar. Client hanya
///     mengelompokkan per bulan tanpa mengubah urutan di dalam bulan.
///  3. **Tidak ada penyaringan.** `deleted_at` sudah difilter server. Entri
///     tanpa penimbangan tetap dipertahankan karena keluhan pada tanggal itu
///     adalah kunjungan yang sah (aturan 3 di bagian 7.3).
library;

import '../utils/month_label.dart';
import 'medical_note.dart';

/// Penanda kondisi khusus anak, dibaca apa adanya dari `children.medical_flags`.
///
/// Teksnya tidak dipecah, tidak dinormalisasi, dan tidak diberi arti per baris:
/// daftar jenis kondisi tidak dikunci di database, jadi menebak meaning-nya
/// hanya membuka pintu ke tebakan yang salah. Yang boleh dibaca cuma dua
/// pertanyaan: adakah isinya, dan apakah ia menyebut alergi (lihat
/// [mentionAlergi]) - itu yang menentukan warna badge di layar.
class TimelineChild {
  final String id;
  final String name;
  final String? nik;
  final String? dateOfBirth;

  /// Umur anak pada penimbangan terakhir, **dari server**.
  ///
  /// `null` berarti anak belum pernah ditimbang. Ini bukan "umur tidak
  /// diketahui": tanggal lahir tetap ada di [dateOfBirth], tapi umur saat
  /// ditimbang memang tidak ada barisnya.
  final int? ageInMonths;

  final String? gender;
  final String? motherName;

  /// Teks mentah dari `medical_flags`, apa adanya.
  final String? medicalFlags;

  final double? latestWeightKg;
  final String? latestStatusGizi;

  const TimelineChild({
    this.id = '',
    this.name = '',
    this.nik,
    this.dateOfBirth,
    this.ageInMonths,
    this.gender,
    this.motherName,
    this.medicalFlags,
    this.latestWeightKg,
    this.latestStatusGizi,
  });

  /// Ada penanda kondisi khusus yang perlu dibaca kader sebelum menimbang.
  bool get punyaKondisiKhusus {
    final teks = medicalFlags;
    return teks != null && teks.isNotEmpty;
  }

  /// Apakah teks penanda menyebut alergi.
  ///
  /// Pencocokan ini hanya untuk memilih WARNA badge, bukan untuk memaknai isi
  /// teks. Daftar jenis kondisi tidak dikunci database, jadi satu-satunya yang
  /// bisa diperiksa adalah kata yang benar-benar ada di sana. Huruf besar-kecil
  /// diabaikan supaya "Alergi" dan "alergi" sama-sama kena.
  bool get mentionAlergi => menyebutAlergi(medicalFlags);

  /// Versi statis dari [mentionAlergi], dipakai layar yang punya teksnya dari
  /// sumber lain - misalnya daftar anak di dashboard yang juga membawa
  /// `medical_flags`.
  static bool menyebutAlergi(String? teks) =>
      teks?.toLowerCase().contains('alergi') ?? false;

  /// Label umur siap tampil, tanpa menghitung ulang apa pun.
  ///
  /// Sumbernya [ageInMonths] dari server. Kalau tidak ada, teksnya tetap "-":
  /// menampilkan "0 Bulan" untuk anak yang belum pernah ditimbang akan
  /// menyiratkan ada penimbangan dengan hasil nol.
  String get labelUmur {
    final bulan = ageInMonths;
    if (bulan == null) return '-';

    if (bulan < 12) return '$bulan Bulan';

    final tahun = bulan ~/ 12;
    final sisa = bulan % 12;
    return sisa == 0 ? '$tahun Tahun' : '$tahun Tahun $sisa Bulan';
  }

  factory TimelineChild.fromJson(Map<String, dynamic> json) {
    final mother = json['mother'];
    final terbaru = json['latest_measurement'];

    return TimelineChild(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      nik: _teks(json['nik']),
      dateOfBirth: _teks(json['date_of_birth']),
      ageInMonths: _bulan(json['age_in_months']),
      gender: _teks(json['gender']),
      motherName: mother is Map ? _teks(mother['name']) : null,
      // Teks mentah, termasuk spasi dan baris baru di dalamnya. Kader menulis
      // formatnya sendiri ("alergi: penisilin" lalu "asma") dan itu memang
      // yang harus dibaca kembali.
      medicalFlags: _teks(json['medical_flags']),
      latestWeightKg: terbaru is Map ? _desimal(terbaru['weight_kg']) : null,
      latestStatusGizi: terbaru is Map ? _teks(terbaru['status_gizi']) : null,
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

  /// Angka desimal dari PostgreSQL datang sebagai string, jadi konversinya
  /// diamankan terhadap `num` maupun teks.
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

/// Penimbangan pada satu tanggal kunjungan.
///
/// Tidak membawa `id` maupun `age_in_months`: timeline menampilkan riwayat per
/// tanggal, dan umur saat ditimbang sudah ada di blok anak
/// ([TimelineChild.ageInMonths]) supaya tidak dibaca dua kali di layar.
class TimelineMeasurement {
  final double? weightKg;
  final double? heightCm;
  final double? headCircumferenceCm;

  /// Dibaca apa adanya dari trigger, tidak dihitung ulang di sini.
  final double? zScoreWfa;
  final String? statusGizi;

  /// Kader yang mencatat. `null` itu sah: `kader_id` bisa null karena
  /// `ON DELETE SET NULL`, dan riwayat anak tidak boleh hilang hanya karena
  /// akun kadernya dihapus.
  final String? kaderId;
  final String? kaderName;

  const TimelineMeasurement({
    this.weightKg,
    this.heightCm,
    this.headCircumferenceCm,
    this.zScoreWfa,
    this.statusGizi,
    this.kaderId,
    this.kaderName,
  });

  /// Z-Score untuk ditampilkan, dua angka di belakang koma.
  String get labelZScore => zScoreWfa?.toStringAsFixed(2) ?? '-';

  /// Status gizi siap tampil. Anak di luar rentang WHO tidak punya status, dan
  /// itu berbeda dari "gizi baik" - karena itu teksnya tidak diganti tanda hubung.
  String get labelStatus => statusGizi ?? 'Di luar rentang WHO';

  factory TimelineMeasurement.fromJson(Map<String, dynamic> json) {
    final kader = json['kader'];

    return TimelineMeasurement(
      weightKg: _desimal(json['weight_kg']),
      heightCm: _desimal(json['height_cm']),
      headCircumferenceCm: _desimal(json['head_circumference_cm']),
      zScoreWfa: _desimal(json['z_score_wfa']),
      statusGizi: _teks(json['status_gizi']),
      kaderId: kader is Map ? _teks(kader['id']) : null,
      kaderName: kader is Map ? _teks(kader['name']) : null,
    );
  }

  static String? _teks(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static double? _desimal(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

/// Satu suntikan pada tanggal kunjungan.
///
/// Hanya `type` dan `date_given` yang dikirim timeline; rincian dosis lengkap
/// (label, batch, catatan) tetap dibaca dari `GET /children/{id}/immunizations`
/// supaya tidak ada dua salinan data suntikan yang bisa berbeda.
class TimelineImmunization {
  final String type;
  final String dateGiven;

  const TimelineImmunization({this.type = '', this.dateGiven = ''});

  /// Kode dosis, misalnya "HB-0". Kalau server mengirim baris tanpa kode,
  /// teksnya diganti "Tanpa kode" supaya tidak terlihat seperti baris kosong
  /// yang tidak sengaja tertinggal.
  String get label => type.isEmpty ? 'Tanpa kode' : type;

  factory TimelineImmunization.fromJson(Map<String, dynamic> json) {
    return TimelineImmunization(
      type: json['type']?.toString() ?? '',
      dateGiven: json['date_given']?.toString() ?? '',
    );
  }
}

/// Keluhan pada satu tanggal kunjungan.
///
/// Bentuknya lebih tipis daripada `MedicalNote`: tanpa `id`, tanpa `keluhan`
/// siap tampil, dan tanpa `ringkasan`. Yang ada hanya tiga boolean dan dua
/// teks. [keluhan] tetap bisa disusun karena itu hanya menerjemahkan boolean ke
/// label, bukan menghitung ulang apa pun.
class TimelineNote {
  final bool demam;
  final bool rewel;
  final bool diare;
  final String? catatan;
  final String? tindakLanjut;

  const TimelineNote({
    this.demam = false,
    this.rewel = false,
    this.diare = false,
    this.catatan,
    this.tindakLanjut,
  });

  /// Nama keluhan yang dicentang, dalam urutan tetap.
  ///
  /// Urutannya dibuang dari `demam, rewel, diare` supaya dua catatan dengan
  /// keluhan yang sama selalu tampil dengan urutan yang sama.
  List<String> get keluhan => <String>[
    if (demam) 'Demam',
    if (rewel) 'Rewel',
    if (diare) 'Diare',
  ];

  /// Perlu rujukan. Dibaca dari [tindakLanjut], bukan dari keluhan, karena
  /// kader bisa memilih "rujuk" untuk catatan saran tanpa keluhan.
  bool get perluRujukan => tindakLanjut == TindakLanjut.rujuk;

  /// Baris ringkas untuk ditampilkan: keluhan yang dicentang, lalu catatan
  /// bebas kalau ada.
  String get ringkasan {
    final bagian = <String>[
      if (keluhan.isNotEmpty) keluhan.join(', '),
      if (catatan != null && catatan!.isNotEmpty) catatan!,
    ];
    return bagian.isEmpty ? '-' : bagian.join(' - ');
  }

  factory TimelineNote.fromJson(Map<String, dynamic> json) {
    return TimelineNote(
      // Boolean tidak boleh dibaca dengan `json['demam'] == true`: driver
      // database bisa mengirim string, dan `"true" == true` bernilai false -
      // artinya keluhan yang benar tampil tidak tercentang.
      demam: _bool(json['demam']),
      rewel: _bool(json['rewel']),
      diare: _bool(json['diare']),
      catatan: _teks(json['catatan']),
      tindakLanjut: _teks(json['tindak_lanjut']),
    );
  }

  static String? _teks(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  /// Menangani `true`, `1`, `"true"`, `"1"`, dan `"yes"`.
  static bool _bool(dynamic value) {
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

/// Satu tanggal kunjungan: penimbangan, suntikan, dan keluhan di tanggal itu.
///
/// Tiga kunci boleh `null` atau kosong di server. Kunjungan dengan keluhan tapi
/// tanpa penimbangan tetap entri yang sah, jadi kelas ini sengaja tidak
/// menyembunyikannya (aturan 3 di bagian 7.3).
class TimelineEntry {
  /// Tanggal kunjungan `Y-m-d`, sama persis dengan kunci pengelompokan yang
  /// dipakai server.
  final String date;

  final TimelineMeasurement? measurement;
  final List<TimelineImmunization> immunizations;
  final TimelineNote? medicalNote;

  const TimelineEntry({
    required this.date,
    this.measurement,
    this.immunizations = const <TimelineImmunization>[],
    this.medicalNote,
  });

  bool get adaPenimbangan => measurement != null;
  bool get adaSuntikan => immunizations.isNotEmpty;
  bool get adaKeluhan => medicalNote != null;

  /// Kunci bulan `YYYY-MM` untuk pengelompokan tampilan.
  ///
  /// Diambil dengan potongan string, bukan `DateTime.parse`: tanggal yang tidak
  /// bisa dibaca harus tetap tampil apa adanya. `DateTime` justru akan
  /// "memperbaiki" tanggal rusak menjadi tanggal yang lebih meyakinkan daripada
  /// aslinya, dan riwayat yang salah lebih berbahaya daripada yang membingungkan.
  String get bulan => date.length >= 7 ? date.substring(0, 7) : date;

  /// "24 September 2026", memakai helper yang sama dengan layar lain.
  String get tanggalLabel => labelTanggal(date);

  /// Entri yang benar-benar kosong tidak pernah dikirim server, tapi kalau
  /// terjadi layar harus tetap bisa menampilkannya tanpa crash.
  bool get kosong => !adaPenimbangan && !adaSuntikan && !adaKeluhan;

  factory TimelineEntry.fromJson(Map<String, dynamic> json) {
    final penimbangan = json['measurement'];
    final catatan = json['medical_note'];
    final suntikan = json['immunizations'];

    return TimelineEntry(
      date: json['date']?.toString() ?? '',
      measurement: penimbangan is Map
          ? TimelineMeasurement.fromJson(Map<String, dynamic>.from(penimbangan))
          : null,
      immunizations: suntikan is List
          ? suntikan
                .whereType<Map>()
                .map(
                  (e) => TimelineImmunization.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .toList()
          : const <TimelineImmunization>[],
      medicalNote: catatan is Map
          ? TimelineNote.fromJson(Map<String, dynamic>.from(catatan))
          : null,
    );
  }
}

/// Penanda halaman: masih ada halaman berikutnya atau tidak.
class TimelineMeta {
  final bool hasMore;

  /// Cursor untuk halaman berikutnya, `null` di halaman terakhir.
  ///
  /// Nilainya dibaca apa adanya dari server. Client tidak mengarang cursor dari
  /// tanggal entri terakhir sendiri, karena itu mudah bergeser satu hari dan
  /// membuat satu kunjungan hilang atau tampil dua kali.
  final String? nextBefore;

  const TimelineMeta({this.hasMore = false, this.nextBefore});

  /// Cursor yang aman dikirim.
  ///
  /// `hasMore` benar tapi `nextBefore` null berarti server tidak memberi cara
  /// maju, jadi layar tidak boleh menampilkan tombol yang mengirim halaman
  /// pertama lagi.
  String? get cursorValid => hasMore ? nextBefore : null;

  factory TimelineMeta.fromJson(Map<String, dynamic> json) {
    return TimelineMeta(
      hasMore: _bool(json['has_more']),
      nextBefore: _teks(json['next_before']),
    );
  }

  static String? _teks(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static bool _bool(dynamic value) {
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

/// Hasil satu halaman timeline.
class ChildTimeline {
  final TimelineChild child;
  final List<TimelineEntry> entries;
  final TimelineMeta meta;

  const ChildTimeline({
    this.child = const TimelineChild(),
    this.entries = const <TimelineEntry>[],
    this.meta = const TimelineMeta(),
  });

  bool get kosong => entries.isEmpty;

  /// Jumlah kunjungan yang sudah dimuat, bukan jumlah baris. Satu tanggal
  /// dengan tiga suntikan tetap dihitung satu.
  int get jumlahKunjungan => entries.length;

  /// Entri dikelompokkan per bulan, **tanpa mengubah urutan**.
  ///
  /// Kunci bulan di urutan kemunculan pertama, jadi bulan terbaru selalu di
  /// atas - urutan tanggal sudah benar dari server dan tidak perlu dihitung
  /// ulang. Map Dart bersifat insertion-ordered, jadi itu otomatis berlaku.
  Map<String, List<TimelineEntry>> get perBulan {
    final hasil = <String, List<TimelineEntry>>{};
    for (final entry in entries) {
      hasil.putIfAbsent(entry.bulan, () => <TimelineEntry>[]).add(entry);
    }
    return hasil;
  }

  /// Menambah halaman berikutnya ke hasil yang sudah ada.
  ///
  /// Dipakai saat kader menekan "Muat lebih banyak". Halaman [berikutnya]
  /// diminta dengan cursor dari server, dan `meta` diambil dari halaman
  /// TERAKHIR - bukan dari yang lama, kalau tidak tombol "Muat lebih banyak"
  /// akan tetap muncul padahal riwayatnya sudah habis.
  ChildTimeline gabung(ChildTimeline berikutnya) {
    return ChildTimeline(
      // Blok anak dari halaman berikutnya lebih segar: `medical_flags` bisa
      // saja sudah diperbarui kader di antara dua request.
      child: berikutnya.child.id.isEmpty ? child : berikutnya.child,
      entries: <TimelineEntry>[...entries, ...berikutnya.entries],
      meta: berikutnya.meta,
    );
  }

  factory ChildTimeline.fromJson(Map<String, dynamic> json) {
    final anak = json['child'];
    final daftar = json['entries'];
    final meta = json['meta'];

    return ChildTimeline(
      child: anak is Map
          ? TimelineChild.fromJson(Map<String, dynamic>.from(anak))
          : const TimelineChild(),
      entries: daftar is List
          ? daftar
                .whereType<Map>()
                .map(
                  (e) => TimelineEntry.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const <TimelineEntry>[],
      meta: meta is Map
          ? TimelineMeta.fromJson(Map<String, dynamic>.from(meta))
          : const TimelineMeta(),
    );
  }
}
