/// Model untuk agenda kegiatan posyandu dan daftar petugas.
///
/// Satu agenda adalah SATU kegiatan pada tanggal tertentu yang ditangani
/// beberapa petugas (lihat tabel pivot `posyandu_schedule_petugas` di
/// backend), bukan jadwal kunjungan per anak.

/// Status agenda. Cerminan CHECK constraint `posyandu_schedules_status_check`
/// di database - menambah nilai baru harus lewat migration baru.
library;

class ScheduleStatus {
  static const String terjadwal = 'terjadwal';
  static const String berlangsung = 'berlangsung';
  static const String selesai = 'selesai';
  static const String dibatalkan = 'dibatalkan';

  /// Semua status dalam urutan alur: terjadwal -> berlangsung -> selesai,
  /// dengan `dibatalkan` bisa terjadi dari tahap mana pun.
  static const List<String> semua = [
    terjadwal,
    berlangsung,
    selesai,
    dibatalkan,
  ];

  /// Label bahasa manusia untuk ditampilkan ke petugas.
  static String label(String value) {
    switch (value) {
      case terjadwal:
        return 'Terjadwal';
      case berlangsung:
        return 'Berlangsung';
      case selesai:
        return 'Selesai';
      case dibatalkan:
        return 'Dibatalkan';
      default:
        return value;
    }
  }
}

/// Petugas posyandu.
///
/// Sengaja TIDAK punya field `nik`: endpoint `/petugas` tidak pernah mengirim
/// NIK karena daftar ini boleh dilihat orang tua.
class Petugas {
  final String id;
  final String name;
  final String? jabatan;
  final String? phoneNumber;

  Petugas({
    required this.id,
    required this.name,
    this.jabatan,
    this.phoneNumber,
  });

  /// Jabatan bila ada, kalau kosong pakai generic "Petugas".
  String get roleLabel =>
      (jabatan == null || jabatan!.isEmpty) ? 'Petugas' : jabatan!;

  /// Nama depan saja, untuk chip pilihan petugas.
  String get shortName {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? name : parts.first;
  }

  factory Petugas.fromJson(Map<String, dynamic> json) {
    return Petugas(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '-',
      jabatan: _str(json['jabatan']),
      phoneNumber: _str(json['phone_number']),
    );
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}

/// Satu agenda kegiatan posyandu.
class PosyanduSchedule {
  final String id;
  final String title;
  final String? description;
  final String? scheduledDate;
  final String? startTime;
  final String? endTime;
  final String? location;

  /// Nama lokasi siap tampil; server sudah filled dengan nama posyandu dari
  /// config bila kolom `location` kosong.
  final String? locationName;
  final String status;
  final String? notes;
  final String? createdBy;
  final String? creatorName;
  final List<String> petugasIds;
  final List<Petugas> petugas;

  PosyanduSchedule({
    required this.id,
    required this.title,
    this.description,
    this.scheduledDate,
    this.startTime,
    this.endTime,
    this.location,
    this.locationName,
    required this.status,
    this.notes,
    this.createdBy,
    this.creatorName,
    this.petugasIds = const [],
    this.petugas = const [],
  });

  /// Rentang jam, mis. "08:00 - 10:00". Kosong bila tidak ada jam.
  String get timeLabel {
    final s = startTime;
    final e = endTime;
    if (s == null || s.isEmpty) return '';
    return e == null || e.isEmpty ? s : '$s - $e';
  }

  /// Nama petugas dalam satu baris, atau "-" bila belum ada yang ditugaskan.
  String get petugasLabel =>
      petugas.isEmpty ? '-' : petugas.map((p) => p.name).join(', ');

  /// True bila agenda sudah lewat tanggalnya.
  bool get isPast {
    final d = scheduledDate;
    if (d == null) return false;
    final parsed = DateTime.tryParse(d);
    if (parsed == null) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return parsed.isBefore(today);
  }

  factory PosyanduSchedule.fromJson(Map<String, dynamic> json) {
    final rawIds = json['petugas_ids'];
    final rawPetugas = json['petugas'];

    return PosyanduSchedule(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '-',
      description: Petugas._str(json['description']),
      scheduledDate: Petugas._str(json['scheduled_date']),
      startTime: Petugas._str(json['start_time']),
      endTime: Petugas._str(json['end_time']),
      location: Petugas._str(json['location']),
      locationName: Petugas._str(json['location_name']),
      status: json['status']?.toString() ?? ScheduleStatus.terjadwal,
      notes: Petugas._str(json['notes']),
      createdBy: Petugas._str(json['created_by']),
      creatorName: Petugas._str(json['creator_name']),
      petugasIds: rawIds is List
          ? rawIds.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : <String>[],
      petugas: rawPetugas is List
          ? rawPetugas
              .whereType<Map>()
              .map((e) => Petugas.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <Petugas>[],
    );
  }
}
