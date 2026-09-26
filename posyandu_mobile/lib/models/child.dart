class Child {
  final String id; // UUID
  final String nik;
  final String name;
  final String parentName;
  final String? dateOfBirth;
  final String? gender;
  final String? lastMeasurementDate;
  final double? latestZScore; // Mampu menangani int, double, num, atau null dari JSON
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

  factory Child.fromJson(Map<String, dynamic> json) {
    // API Laravel mengirim relasi ibu sebagai nested object: "mother": { "id": ..., "name": ... }
    // Field ini harus tetap kompatibel dengan "parent_name" agar data lama tidak rusak.
    final mother = json['mother'];
    final String parentName = _parseString(json['parent_name']) ??
        (mother is Map ? _parseString(mother['name']) : null) ??
        '-';

    return Child(
      id: json['id'] as String,
      nik: _parseString(json['nik']) ?? '-',
      name: _parseString(json['name']) ?? '-',
      parentName: parentName,
      dateOfBirth: _parseString(json['date_of_birth']),
      gender: _parseString(json['gender']),
      lastMeasurementDate: _parseString(json['last_measurement_date']),
      // Penanganan aman untuk konversi angka (int/double/string) ke double
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