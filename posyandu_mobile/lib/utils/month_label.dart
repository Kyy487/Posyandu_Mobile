/// Format tanggal dan bulan untuk ditampilkan ke kader dan Ibu.
///
/// Dipisah ke satu file karena label bulan dipakai di lebih dari satu layar
/// (daftar catatan keluhan, rekap imunisasi bulanan). Kalau tiap layar punya
/// daftar namanya sendiri, cepat atau lambat keduanya berbeda untuk bulan yang
/// sama - misalnya "September 2026" di satu layar dan "Sept 2026" di layar lain,
/// dan kader mengira itu dua bulan yang berbeda.
///
/// Paket `intl` sengaja tidak dipakai untuk ini: satu daftar nama bulan
/// statis lebih murah daripada menarik dependensi penuh hanya untuk
/// `DateFormat`, dan tidak ada operasi tanggal lain yang butuh locale.
library;

/// Nama bulan dalam bahasa Indonesia, index 0 = Januari.
const List<String> namaBulan = <String>[
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];

/// Label bulan dari format `YYYY-MM`, mis. "2026-09" -> "September 2026".
///
/// Mengembalikan inputnya apa adanya kalau tidak bisa dibaca, bukan
/// crashed dan bukan string kosong. Layar yang menampilkan "2026-13" apa adanya
/// masih memberi kader informasi bahwa ada yang salah, sedangkan string kosong
/// hanya bikin layar kosong tanpa penjelasan.
String labelBulan(String? month, {String saatKosong = 'Bulan ini'}) {
  if (month == null || month.isEmpty) return saatKosong;

  final bagian = month.split('-');
  if (bagian.length != 2) return month;

  final bulan = int.tryParse(bagian[1]);
  if (bulan == null || bulan < 1 || bulan > 12) return month;

  return '${namaBulan[bulan - 1]} ${bagian[0]}';
}

/// Format tanggal `YYYY-MM-DD` jadi "30 September 2026".
///
/// Dipakai untuk `reference_date` rekap imunisasi, supaya kader tahu laporan
/// ini dihitung sampai tanggal berapa tanpa perlu menghitung sendiri akhir
/// bulan.
String labelTanggal(String? iso, {String jikaKosong = '-'}) {
  if (iso == null || iso.isEmpty) return jikaKosong;

  final bagian = iso.split('-');
  if (bagian.length != 3) return iso;

  final bulan = int.tryParse(bagian[1]);
  if (bulan == null || bulan < 1 || bulan > 12) return iso;

  return '${int.tryParse(bagian[2]) ?? iso} ${namaBulan[bulan - 1]} ${bagian[0]}';
}

/// Geser satu bulan dari `YYYY-MM`, untuk tombol navigasi bulan di layar rekap.
///
/// Sengaja tidak memakai `DateTime` untuk menghindari jebakan overflow:
/// `DateTime(2026, 13)` bergeser ke Januari 2027, dan `DateTime(2026, 0)`
/// bergeser ke Desember 2025 - keduanya diam-diam benar tapi tidak pernah
/// dimaksud. Di sini bulan di luar 1-12 justru dikembalikan apa adanya,
/// bukan dibungkus ke tahun sebelah, supaya input yang rusak tidak pernah
/// berubah jadi tanggal yang lebih meyakinkan daripada aslinya.
String geserBulan(String month, {int delta = 0}) {
  final bagian = month.split('-');
  if (bagian.length != 2) return month;

  final tahun = int.tryParse(bagian[0]);
  final bulan = int.tryParse(bagian[1]);
  if (tahun == null || bulan == null) return month;
  if (bulan < 1 || bulan > 12) return month;

  // Geser ke total bulan absolut supaya pergantian tahun tidak butuh kondisi
  // khusus: Desember - 1 bulan jatuh ke November tahun yang sama, dan
  // Januari - 1 bulan jatuh ke Desember tahun sebelumnya.
  final total = tahun * 12 + (bulan - 1) + delta;
  final tahunBaru = total ~/ 12;
  final bulanBaru = total % 12 + 1;

  return '$tahunBaru-${bulanBaru.toString().padLeft(2, '0')}';
}
