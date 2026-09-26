class MeasurementModel {
  final String id;
  final String childId;
  final String measurementDate;
  final double weightKg;
  final double heightCm;
  final int? ageInMonths;
  final double? zScoreWfa;
  final String? statusGizi;
  final double? headCircumferenceCm;

  MeasurementModel({
    required this.id,
    required this.childId,
    required this.measurementDate,
    required this.weightKg,
    required this.heightCm,
    this.ageInMonths,
    this.zScoreWfa,
    this.statusGizi,
    this.headCircumferenceCm,
  });

  factory MeasurementModel.fromJson(Map<String, dynamic> json) {
    return MeasurementModel(
      id: json['id']?.toString() ?? '',
      childId: json['child_id']?.toString() ?? '',
      measurementDate: json['measurement_date']?.toString() ?? '',
      weightKg: _parseDouble(json['weight_kg']) ?? 0,
      heightCm: _parseDouble(json['height_cm']) ?? 0,
      ageInMonths: _parseInt(json['age_in_months']),
      zScoreWfa: _parseDouble(json['z_score_wfa']),
      statusGizi: _parseStatus(json['status_gizi']),
      headCircumferenceCm: _parseDouble(json['head_circumference_cm']),
    );
  }

  /// Z-Score & angka desimal bisa datang sebagai num maupun String
  /// (tergantung driver database), jadi selalu amankan konversinya.
  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static String? _parseStatus(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
