/// Konfigurasi alamat server API.
///
/// Nilai baseUrl bisa diganti saat build/run tanpa menyentuh kode:
///
/// ```
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000/api
/// ```
///
/// Default `10.0.2.2` adalah alias localhost dari emulator Android, jadi
/// aplikasi langsung nyambung ke `php artisan serve` di komputer sendiri.
/// Untuk device fisik, ganti dengan IP komputer di jaringan Wi-Fi.
class ApiConstants {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api',
  );

  static const String loginEndpoint = '/login';
  static const String registerEndpoint = '/register';
  static const String childrenEndpoint = '/children';
  static const String kaderChildrenEndpoint = '/kader/children';
  static const String kaderMeasurementsEndpoint = '/kader/measurements';

  // Imunisasi: checklist dibaca Ibu maupun Kader, pencatatan hanya Kader.
  static const String immunizationTypesEndpoint = '/immunization-types';
  static const String kaderImmunizationsEndpoint = '/kader/immunizations';

  // Rekap imunisasi bulanan (Opsi E): {kaderImmunizationsEndpoint}/recap
  //
  // Kader-only, tidak pernah dibuka untuk Ibu karena eksposisinya seluruh
  // Posyandu. Hanya baca - tidak ada endpoint tulis rekap, angkanya
  // diturunkan dari suntikan yang sudah tercatat.
  static const String kaderImmunizationRecapEndpoint =
      '/kader/immunizations/recap';

  // Jadwal posyandu: Ibu read-only, Kader boleh tulis.
  static const String schedulesEndpoint = '/schedules';
  static const String kaderSchedulesEndpoint = '/kader/schedules';

  // Catatan keluhan: Ibu read-only, Kader boleh tulis.
  //
  // Path BACA dipakai bersama Ibu dan Kader, mengikuti pola yang sama dengan
  // `/children/{id}/immunizations`. Path TULIS memakai prefix `/kader/`
  // sehingga role `ibu` ditolak oleh middleware sebelum sampai ke controller.
  //
  // Bentuk lengkapnya:
  //   baca  : {childrenEndpoint}/{id}/medical-notes
  //   tulis : {kaderChildrenEndpoint}/{id}/medical-notes
  //           {kaderMedicalNotesEndpoint}/{id}
  static const String kaderMedicalNotesEndpoint = '/kader/medical-notes';

  // Riwayat medis gabungan (Opsi B - Buku Medis Digital).
  //
  // Satu endpoint untuk tiga tabel: penimbangan, suntikan, dan catatan
  // keluhan, dikelompokkan per tanggal kunjungan. Path BACA dipakai bersama Ibu
  // dan Kader, mengikuti pola `/children/{id}/...`, karena Ibu berhak melihat
  // riwayat anaknya sendiri:
  //   baca : {childrenEndpoint}/{id}{childTimelineEndpoint}
  //
  // Dipisah ke konstanta supaya path-nya bisa diuji. Salah ketik di sini hanya
  // muncul sebagai 404 "Data balita tidak ditemukan." di layar, tanpa jejak
  // di `flutter analyze`.
  static const String childTimelineEndpoint = '/timeline';

  // Daftar petugas. NIK tidak pernah ikut respons.
  static const String petugasEndpoint = '/petugas';
}
