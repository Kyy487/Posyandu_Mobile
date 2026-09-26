class Child {
  final String id; // UUID
  final String nik;
  final String name;
  final String parentName;
  final String? dateOfBirth;
  final String? gender;
  final String? lastMeasurementDate;
  final double? latestZScore;
  final String? nutritionalStatus;

  Child({
    required this.id,
    required this.nik,
    required this.name,
    required this.parentName,
    this.dateOfBirth,
    this.gender,
    this.lastMeasurementDate,
    this.latestZScore,
    this.nutritionalStatus,
  });

  /// True bila anak sudah pernah ditimbang setidaknya sekali.
  bool get hasMeasurement => lastMeasurementDate != null;

  /// Nama panggilan saja (bagian sebelum spasi pertama), untuk chip selector.
  String get shortName {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? name : parts.first;
  }

  /// Umur dalam bulan, dihitung dari `date_of_birth`.
  ///
  /// Mengembalikan null bila tanggal lahir tidak ada atau tidak bisa diparse.
  /// Mengembalikan 0 bila tanggal lahir di masa depan (data salah input).
  int? get ageInMonths {
    final dob = dateOfBirth;
    if (dob == null) return null;

    final lahir = DateTime.tryParse(dob);
    if (lahir == null) return null;

    final now = DateTime.now();
    var bulan = (now.year - lahir.year) * 12 + (now.month - lahir.month);
    if (now.day < lahir.day) bulan--;
    return bulan < 0 ? 0 : bulan;
  }

  /// Umur dalam bahasa manusia, mis. "2 Tahun 3 Bulan" atau "8 Bulan".
  String get ageLabel {
    final bulan = ageInMonths;
    if (bulan == null) return '-';

    if (bulan < 12) return '$bulan Bulan';

    final tahun = bulan ~/ 12;
    final sisa = bulan % 12;
    return sisa == 0 ? '$tahun Tahun' : '$tahun Tahun $sisa Bulan';
  }

  /// Label status gizi yang enak dibaca, atau null bila belum ada data.
  String? get nutritionLabel {
    if (nutritionalStatus == null || nutritionalStatus!.isEmpty) return null;
    return nutritionalStatus;
  }

  factory Child.fromJson(Map<String, dynamic> json) {
    // API Laravel mengirim relasi ibu sebagai nested object: "mother": { "id": ..., "name": ... }
    // Field ini harus tetap kompatibel dengan "parent_name" agar data lama tidak rusak.
    final mother = json['mother'];
    final String parentName = _parseString(json['parent_name']) ??
        (mother is Map ? _parseString(mother['name']) : null) ??
        '-';

    return Child(
      id: json['id']?.toString() ?? '',
      nik: _parseString(json['nik']) ?? '-',
      name: _parseString(json['name']) ?? '-',
      parentName: parentName,
      dateOfBirth: _parseString(json['date_of_birth']),
      gender: _parseString(json['gender']),
      lastMeasurementDate: _parseString(json['last_measurement_date']),
      // latest_z_score dikirim sebagai float oleh API, tapi parser ini tetap
      // aman terhadap string/null karena kolom sumbernya bertipe decimal.
      latestZScore: _parseDouble(json['latest_z_score']),
      nutritionalStatus: _parseString(json['nutritional_status']),
    );
  }

  // Helper baca string yang aman terhadap nilai null
  static String? _parseString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  // Helper konversi aman dari tipe JSON apapun (num, double, int, String) ke double?
  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nik': nik,
      'name': name,
      'parent_name': parentName,
      'date_of_birth': dateOfBirth,
      'gender': gender,
      'last_measurement_date': lastMeasurementDate,
      'latest_z_score': latestZScore,
      'nutritional_status': nutritionalStatus,
    };
  }
}
