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

  // Jadwal posyandu: Ibu read-only, Kader boleh tulis.
  static const String schedulesEndpoint = '/schedules';
  static const String kaderSchedulesEndpoint = '/kader/schedules';

  // Daftar petugas. NIK tidak pernah ikut respons.
  static const String petugasEndpoint = '/petugas';
}
