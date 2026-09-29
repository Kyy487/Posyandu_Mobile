/// Model untuk feature imunisasi.
///
/// Status (`sudah` / `belum` / `terlambat`) DIKIRIM server dan tidak
/// dihitung ulang di sisi ini. Alasannya, definisi "terlambat" memakai
/// ambang toleransi dari config posyandu yang bisa berubah, sehingga
/// menyalin logikanya ke Flutter dijamin tidak sinkron dengan server.
///
/// Yang boleh dilakukan klien hanya memformat ulang untuk tampilan.
library;

/// Status satu dosis untuk satu anak.
class ImmunizationStatus {
  static const String done = 'sudah';
  static const String pending = 'belum';
  static const String overdue = 'terlambat';
}

/// Satu baris checklist: master dosis + status + catatan suntikan bila ada.
class ImmunizationItem {
  final String typeId;
  final String code;
  final String name;

  /// Nama vaksin. Untuk dosis > 1, server sudah menempelkan nomor dosis,
  /// mis. "Hepatitis B (Dosis 2)"; dosis pertama tetap polos. Label inilah
  /// yang dipakai di layar, supaya tidak ada dua tempat memformat nomor dosis.
  final String label;
  final int doseNumber;
  final int? targetAgeMonths;
  final int? intervalMonths;
  final String status;

  /// Sisa bulan menuju status `terlambat`. Negatif = sudah lewat.
  /// Null setelah disuntik, atau bila dosis tidak punya usia target.
  final int? monthsLeft;

  final ImmunizationRecordEntry? record;

  ImmunizationItem({
    required this.typeId,
    required this.code,
    required this.name,
    required this.label,
    required this.doseNumber,
    this.targetAgeMonths,
    this.intervalMonths,
    required this.status,
    this.monthsLeft,
    this.record,
  });

  bool get isDone => status == ImmunizationStatus.done;
  bool get isPending => status == ImmunizationStatus.pending;
  bool get isOverdue => status == ImmunizationStatus.overdue;

  /// Usia target dalam bahasa manusia, mis. "2 bulan" atau "saat lahir".
  String get targetLabel {
    final t = targetAgeMonths;
    if (t == null) return '-';
    if (t == 0) return 'Saat lahir';
    return '$t bulan';
  }

  /// Penjelasan singkat status untuk layar, sudah termasuk sisa waktu.
  String get statusNote {
    switch (status) {
      case ImmunizationStatus.done:
        final tanggal = record?.dateGiven;
        return tanggal == null ? 'Sudah disuntik' : 'Sudah disuntik $tanggal';
      case ImmunizationStatus.overdue:
        final behind = (monthsLeft ?? 0).abs();
        return behind == 0 ? 'Terlambat' : 'Terlambat $behind bulan';
      default:
        final left = monthsLeft;
        if (left == null) return 'Belum disuntik';
        if (left > 0) return 'Belum disuntik ($left bulan lagi)';
        return 'Belum disuntik';
    }
  }

  factory ImmunizationItem.fromJson(Map<String, dynamic> json) {
    final rawRecord = json['record'];
    return ImmunizationItem(
      typeId: json['immunization_type_id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      label: json['label']?.toString() ?? json['name']?.toString() ?? '-',
      doseNumber: _toInt(json['dose_number']) ?? 1,
      targetAgeMonths: _toInt(json['target_age_months']),
      intervalMonths: _toInt(json['interval_months']),
      status: json['status']?.toString() ?? ImmunizationStatus.pending,
      monthsLeft: _toInt(json['sisa_bulan']),
      record: rawRecord is Map
          ? ImmunizationRecordEntry.fromJson(
              Map<String, dynamic>.from(rawRecord),
            )
          : null,
    );
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}

/// Catatan suntikan yang tersimpan di server untuk satu dosis.
class ImmunizationRecordEntry {
  final String id;
  final String? dateGiven;
  final String? batchNumber;
  final String? notes;
  final String? kaderId;

  ImmunizationRecordEntry({
    required this.id,
    this.dateGiven,
    this.batchNumber,
    this.notes,
    this.kaderId,
  });

  factory ImmunizationRecordEntry.fromJson(Map<String, dynamic> json) {
    return ImmunizationRecordEntry(
      id: json['id']?.toString() ?? '',
      dateGiven: _str(json['date_given']),
      batchNumber: _str(json['batch_number']),
      notes: _str(json['notes']),
      kaderId: _str(json['kader_id']),
    );
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}

/// Ringkasan jumlah status, dikirim server supaya klien tidak menghitung ulang.
class ImmunizationSummary {
  final int done;
  final int pending;
  final int overdue;
  final int total;

  ImmunizationSummary({
    required this.done,
    required this.pending,
    required this.overdue,
    required this.total,
  });

  /// Persen kelengkapan, dibulatkan. 0 bila tidak ada dosis sama sekali.
  int get percentDone => total == 0 ? 0 : ((done / total) * 100).round();

  factory ImmunizationSummary.fromJson(Map<String, dynamic> json) {
    int i(String key) => ImmunizationItem._toInt(json[key]) ?? 0;
    return ImmunizationSummary(
      done: i('sudah'),
      pending: i('belum'),
      overdue: i('terlambat'),
      total: i('total'),
    );
  }
}

/// Checklist lengkap satu anak: anak + ringkasan + daftar dosis.
class ImmunizationChecklist {
  final String childId;
  final String childName;
  final ImmunizationSummary summary;
  final List<ImmunizationItem> items;

  ImmunizationChecklist({
    required this.childId,
    required this.childName,
    required this.summary,
    required this.items,
  });

  /// Dosis yang masih bisa dicatat (belum + terlambat).
  List<ImmunizationItem> get pendingItems =>
      items.where((e) => !e.isDone).toList();

  /// Checklist dikelompokkan per vaksin supaya 4 dosis Hepatitis B
  /// tidak terlihat sebagai 4 baris terpisah tanpa konteks.
  Map<String, List<ImmunizationItem>> get groupedByCode {
    final map = <String, List<ImmunizationItem>>{};
    for (final item in items) {
      map.putIfAbsent(item.code, () => <ImmunizationItem>[]).add(item);
    }
    return map;
  }

  factory ImmunizationChecklist.fromJson(Map<String, dynamic> json) {
    final child = json['child'];
    final rawChecklist = json['checklist'];
    return ImmunizationChecklist(
      childId: child is Map ? child['id']?.toString() ?? '' : '',
      childName: child is Map ? child['name']?.toString() ?? '' : '',
      summary: ImmunizationSummary.fromJson(
        Map<String, dynamic>.from(json['summary'] as Map),
      ),
      items: rawChecklist is List
          ? rawChecklist
                .whereType<Map>()
                .map(
                  (e) =>
                      ImmunizationItem.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : <ImmunizationItem>[],
    );
  }
}
