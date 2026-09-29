# ⚙️ Setup & Configuration Log

Dokumen ini mencatat langkah-langkah instalasi dan fitur yang **SUDAH SELESAI** dikerjakan dan distabilkan. AI tidak boleh mengulang instruksi instalasi untuk poin-poin di bawah ini.

## Lingkungan Pengembangan (Environment)
- [x] Instalasi Laravel 13.33.0 (`posyandu-backend`).
- [x] Konfigurasi Laragon: Ekstensi `pdo_pgsql` dan `pgsql` telah diaktifkan di `php.ini` (PHP 8.4.25).
- [x] Pembuatan Database lokal `posyandu_db` (PostgreSQL via HeidiSQL).
- [x] Integrasi koneksi `.env` Laravel ke PostgreSQL.

## Database Migrations & Models (Selesai)
Seluruh tabel menggunakan arsitektur **UUID**.
- [x] `users` (Penambahan kolom nik, role 'ibu'/'kader', phone_number).
- [x] `children` (Relasi ke `users` melalui kolom `user_id`).
- [x] `measurements` (Pencatatan e-KMS harian).
- [x] `immunization_records` (Riwayat vaksinasi).
- [x] `who_wfa_standards` (Referensi Median/SD WHO Weight-for-Age, 122 baris).
- [x] Function `calculate_measurement_who_zscore()` + trigger `trg_measurements_who_zscore` pada `measurements` (`BEFORE INSERT OR UPDATE`).
- [x] Pembuatan Model Eloquent (`User`, `Child`, `Measurement`, `ImmunizationRecord`) beserta relasi `HasMany` dan `BelongsTo`.

## API & Authentication (Selesai)
- [x] Instalasi Laravel Sanctum (`php artisan install:api`).
- [x] Pembuatan `AuthController` (Register, Login, Logout).
- [x] Pendaftaran Public & Protected Routes di `routes/api.php`.
- [x] Pembuatan `ChildController` (Fungsi CRUD untuk Profil Anak dengan relasi `user_id` dari token otentikasi).

## Keamanan Auth & Kontrak Error (Selesai — 26 Sep 2026)
Perbaikan ini menutup lubang privilege escalation dan menhomogenkan JSON envelope.
- [x] **`role` tidak lagi dipercaya dari body request.** `POST /api/register` selalu
      membuat akun `ibu`; akun `kader` hanya bisa dibuat bila klien mengirim
      `kader_code` yang cocok dengan `KADER_REGISTRATION_CODE` (env).
      Sebelumnya siapa pun bisa mengirim `role=kader` dan langsung mendapat akses
      hapus semua data anak.
- [x] `config/posyandu.php` — `kader_registration_code`, `login_throttle`,
      `register_throttle`. Env kosong = pendaftaran kader dimatikan (403).
- [x] Dropdown "Peran (Role)" dihapus dari `register_screen.dart`; diganti kolom
      **"Kode kader posyandu (opsional)"**. Tidak ada lagi pemilihan role.
- [x] `AuthController` sekarang punya `try-catch` + `Log::error()` (Aturan #10),
      memvalidasi `password_confirmation`, dan mensyaratkan NIK 16 digit saat
      login (sebelumnya tidak, sehingga inkonsisten dengan register).
- [x] `bootstrap/app.php` — exception handler untuk `401`, `403`, `404`, `405`,
      `422`, `429`. Sebelumnya `401` membalas `{"message":"Unauthenticated."}`
      sehingga Flutter tidak bisa membaca `success`.
- [x] `throttle` pada `POST /login` (10/menit) dan `POST /register` (30/menit)
      untuk menutup brute force NIK + password.
- [x] `uji-api.ps1` — kadernya dibuat lewat kode (bukan lewat lubang role), plus
      2 pemeriksaan baru: daftar kader tanpa kode → `403`, kode salah → `403`.
      Total 108 pemeriksaan, seluruhnya lulus.


## Cleanup API Anak (Selesai — 26 Sep 2026)
- [x] `routes/api.php` dirapikan: 12 route unik, duplikat & `auth:sanctum` bersarang dihapus.
- [x] `ChildController@indexKader()` memuat relasi `mother` agar nama ibu terkirim.
- [x] `ChildController@index()` juga memuat relasi `mother` untuk Ibu (dashboard tidak lagi menampilkan `-`).
- [x] `ChildController@show()` menolak Ibu yang mengakses anak orang lain (`403`).
- [x] Kontrak tambah data anak disatukan: `store()` menggantikan `store()` + `storeKader()`; terima `ibu_nik` (preferred) atau `user_id`.
- [x] Pesan exception internal tidak lagi dikirim ke klien; `Log::error()` dipakai sebagai gantinya.
- [x] `ChildController@update()` — partial update (`PUT`/`PATCH`), otorisasi kepemilikan, hitung ulang Z-Score bila DOB/gender berubah.
- [x] `ChildController@destroy()` — soft delete, khusus Kader.
- [x] Migration `2026_09_26_020000_add_deleted_at_to_children_table.php` (kolom `deleted_at` + index).
- [x] `Child` memakai trait `SoftDeletes` agar riwayat penimbangan/imunisasi tidak ikut terhapus.
- [x] ID anak divalidasi sebagai UUID sebelum query (`Str::isUuid()`) agar URL rusak membalas `404`, bukan `500`.

## Z-Score WHO Weight-for-Age (Selesai)
- [x] Migration `2026_09_26_010000_create_who_wfa_standards_and_fix_zscore_trigger.php` (tabel referensi, function, trigger, backfill).
- [x] Perbaikan relasi Eloquent: `User::children()` dan `Child::parent()` memakai `user_id`.
- [x] `MeasurementController@store()` memakai `$measurement->refresh()` agar nilai dari trigger ikut dikembalikan pada response API.
- [x] Respon API `POST /api/kader/measurements` mengirim `age_in_months`, `z_score_wfa`, dan `status_gizi`.
- [x] Rincian lengkap: `docs/LAPORAN_ZSCORE_TRIGGER.md`.

## Mobile / Flutter (`posyandu_mobile`, Selesai)
- [x] `kader_service.dart` mengembalikan objek `data` pada respons penimbangan.
- [x] `child.dart` membaca nama ibu dari nested object `mother`.
- [x] `measurement_model.dart` aman terhadap nilai `string`, `number`, dan `null` (kolom bertipe `decimal`).
- [x] `input_penimbangan_screen.dart` menampilkan dialog Z-Score dan status gizi setelah simpan.
- [x] `detail_anak_screen.dart` memakai data API (tanpa hardcode) dan mengaktifkan tombol "Input Bulan Ini".

## Kebersihan Mobile (Selesai — 26 Sep 2026)
- [x] **8 `print()` debug dihapus** dari `kader_service.dart`, termasuk
      `print('Token yang akan dikirim: $token')` yang membocorkan token Sanctum
      ke log device.
- [x] `baseUrl` tidak lagi di-hardcode di 3 file. Semua service memakai
      `ApiConstants.baseUrl` yang bisa di-override saat run:
      `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000/api`
      (default tetap `10.0.2.2` untuk emulator Android).
- [x] Penanganan `401` (sesi habis) ditambahkan di `auth_service.dart`,
      `child_service.dart`, dan `kader_service.dart`; user diarahkan login ulang.
- [x] `MeasurementModel.heightKg` → `heightCm` (nama sebelumnya salah satuan;
      isinya `height_cm` dalam cm).
- [x] `test/widget_test.dart` — test counter bawaan Flutter yang selalu gagal
      diganti uji yang benar (aplikasi menampilkan layar login).
- [x] `test/kontrak_api_test.dart` — file diperbaiki encoding-nya, ditambah 3 test
      kontrak error envelope (`401`, `422`, `403`).
- [x] 29 lint/info di semua file diperbaiki: `withOpacity` → `withValues(alpha:)`,
      `super.key`, dan `BuildContext` lintas async gap pada tombol logout.
- [x] **`flutter analyze`: No issues found** (dari 32 issue).
      **`flutter test`: 11/11 lulus** (dari 6 lulus + 1 gagal).

## Imunisasi & Jadwal Posyandu (Selesai — 26 Sep 2026, commit `23d0702`)
- [x] Migration `2026_09_26_030000` s.d. `034000`: kolom `jabatan` pada
      `users`, master `immunization_types` (16 dosis), penataan ulang
      `immunization_records`, tabel `posyandu_schedules`, dan pivot
      `posyandu_schedule_petugas`.
- [x] `immunization_records.kader_id` jadi nullable + `ON DELETE SET NULL`:
      riwayat suntikan tidak lagi ikut terhapus saat akun petugas dihapus.
- [x] Unique `immunization_child_type_unique (child_id, immunization_type_id)`.
      Koreksi salah input lewat `PATCH`, bukan hapus-lalu-simpan.
- [x] `ImmunizationChecklistService` — status `sudah`/`belum`/`terlambat`
      **dihitung tiap request, tidak disimpan** (karena bergantung pada
      tanggal lahir anak). Toleransi default 2 bulan dari
      `config('posyandu.immunization.terlambat_setelah_bulan')`.
- [x] 9 endpoint baru; total API jadi 23 route. `GET /petugas` tidak pernah
      mengirim NIK.
- [x] **Tidak ada `GET /kader/schedules`** — baca agenda memakai
      `GET /api/schedules` yang sama untuk Ibu dan Kader.
- [x] `bootstrap/app.php` — tamu API tanpa `Accept: application/json` kini
      dapat JSON 401, bukan 500 dari `route('login')` yang tidak ada.
- [x] Seeder idempotent. Kunci agenda = `title` (bukan `title` +
      `scheduled_date`) supaya `db:seed` pada hari berbeda tidak menambah
      baris. Diverifikasi pada selisih `+0`/`+3`/`+30` hari.
- [x] Mobile: checklist imunisasi (Kader catat/koreksi, Ibu read-only),
      CRUD agenda dengan penugasan banyak petugas, navigasi dashboard.
- [x] `uji-api.ps1` +4 pemeriksaan tamu tanpa header JSON.
      **210/210 lulus**, DB kembali ke baseline.
- [x] **`flutter test`: 49/49 lulus**, `flutter analyze`: No issues found.
- [x] Rincian lengkap: `docs/LAPORAN_IMUNISASI_JADWAL.md`.

## Opsi A - Rapikan Kualitas (Selesai — 27 Sep 2026)
- [x] Migration `2026_09_26_035000`: kolom `deleted_at` pada
      `immunization_records`, unique penuh diganti **partial unique index**
      `WHERE deleted_at IS NULL`. Rollback + apply ulang diverifikasi.
- [x] Validasi urutan dosis di `ImmunizationController`: dosis N tidak boleh
      lebih awal dari N-1, tidak boleh lebih baru dari N+1. Berlaku pada
      `POST` dan `PATCH`. Error `422` + `errors.date_given`.
- [x] `DELETE /kader/immunizations/{record}` (Kader-only, Ibu dapat `403`).
      `ImmunizationRecord` memakai `SoftDeletes`, jadi pembatalan berjejak
      audit dan dosing yang dibatalkan bisa dicatat ulang.
- [x] Tombol "Batalkan suntikan" di form koreksi Kader, dengan dialog
      konfirmasi. Endpoint saja tidak menyelesaikan masalah lapangan.
- [x] `vendor/bin/pint` dijalankan repo-wide: 22 file dirapikan,
      `pint --test` sekarang `passed`.
- [x] `laravel/boost` v2.10.0 terpasang (`--dev`). `AGENTS.md` berisi guideline
      tailored; MCP + 5 skill untuk OpenCode dan Claude Code.
- [x] Data uji yang tertinggal di DB lokal dihapus (akun `Haji haji`, sisa
      user `uji-api.ps1`, dan anak manual di luar whitelist seeder).
      DB kembali ke baseline: **7 user, 3 anak, 0 archived, 0 suntikan, 3 agenda**.
      DB kembali ke baseline: **7 user, 3 anak, 0 archived, 0 suntikan, 3 agenda**.
- [x] `uji-api.ps1` +18 pemeriksaan (urutan dosis & pembatalan suntikan).
      **228/228 lulus**, total API jadi **24 route**.
- [x] **`flutter test`: 52/52 lulus** (3 contract test baru untuk respons
      DELETE), `flutter analyze`: No issues found.
- [x] `php -l` 53 file `app/database/config/routes/bootstrap`: 0 error.
- [x] Scan karakter rusak 77 file: bersih.
- [x] Scan karakter rusak: 7 sekuens mojibake diperbaiki di `Cara_menjalankan.md`
      (`—`, `→`, `⋮` yang sebelumnya salah decode), 2 BOM UTF-8 dibuang, dan
      working copy dinormalkan sesuai `.gitattributes`.
- [x] `git push` — `main` sinkron dengan `origin/main`. Commit Opsi A:
      `b856618` (fitur), `38d762b` (Pint), `4e15140` (Boost).

---

## Opsi C - Catatan Keluhan Kader (Selesai — 27 Sep 2026)

- [x] Migration `2026_09_27_010000_create_medical_notes_table.php`. Tabel
      `medical_notes` satu baris per anak per tanggal. Partial unique index
      `(child_id, note_date) WHERE deleted_at IS NULL`, plus dua CHECK
      (nilai `tindak_lanjut`, dan isi tidak boleh kosong). Rollback + apply
      ulang diverifikasi.
- [x] Empat endpoint (`GET` bersama Ibu/Kader, `POST`/`PATCH`/`DELETE`
      khusus Kader). Catatan **boleh diperbarui** - `note_date` tidak dikunci
      seperti pada koreksi suntikan, karena salah pilih hari di kalender adalah
      kesalahan yang wajar.
- [x] `kader_id` selalu berasal dari user login, tidak pernah diambil dari
      request. Ibu hanya bisa membaca catatan anaknya sendiri.
- [x] Model `MedicalNote` + relasi di `Child`, `User`, `Measurement`.
      Factory `MedicalNoteFactory` (5 state) dan `ChildFactory`.
- [x] Seeder 3 catatan demo, idempotent: dua kali `db:seed` tetap 3 baris.
- [x] `uji-api.ps1` +60 pemeriksaan (grup 9e). **288/288 lulus**,
      total API jadi **28 route** (34 termasuk non-API).
- [x] Mobile: `MedicalNote`, `MedicalNoteList`, `MedicalNoteSummary`,
      `TindakLanjut`, `MedicalNoteService`, widget
      `medical_note_list_view.dart`, layar Kader (tulis) dan Ibu (read-only
      + filter bulan).
- [x] `flutter analyze`: No issues found. **`flutter test`: 67/67 lulus**
      (15 contract test baru).
- [x] `vendor/bin/pint` bersih; `php -l` 63 file 0 error.
- [x] Dokumentasi: `API_CONTRACT.md`, `DATABASE_SCHEMA.md`,
      `LAPORAN_MEDICAL_NOTES.md`, `RENCANA_SELANJUTNYA.md`.

### Masih terbuka
- Notifikasi/pengingat agenda untuk Ibu (butuh push service).
- Rekap keluhan per bulan lintas anak - `summary` di
  `GET /children/{id}/medical-notes` masih per satu anak, aggregate lintas anak
  belum ada. (Rekap suntikan bulanan untuk Kader sudah selesai pada Opsi E.)
- Paginasi pada daftar catatan keluhan.
- Riwayat perubahan catatan (siapa mengubah apa) belum ada; `updated_at` hanya
  menyimpan waktu terakhir.

Rincian lengkap: `docs/LAPORAN_IMUNISASI_JADWAL.md` bagian 11.

---

## Opsi B - Buku Medis Digital, Fase 0 (Selesai — 29 Sep 2026)

Fase ini tidak menulis satu baris kode fitur. Tujuannya mengunci spesifikasi
sebelum ada kode, supaya implementasi tidak menyimpang dan tidak merusak yang
sudah jalan.

- [x] `docs/RANCANGAN_BUKU_MEDIS.md` dinaikkan dari "rancangan" jadi
      **spesifikasi normatif**. Dua keputusan ditutup: kondisi khusus memakai
      **kolom `children.medical_flags`** (bukan tabel `child_medical_flags`),
      dan timeline dikelompokkan **per kunjungan** (bukan per kejadian).
- [x] Tiga pertanyaan yang tadinya terbuka ikut dijawab: Ibu boleh membaca
      `medical_flags` anaknya sendiri, **Kader saja** yang boleh menulis, dan
      timeline tanpa batas waktu.
- [x] Tujuh aturan timeline dipetakan ke **nama test** di bagian 7.3, jadi
      "sudah dipatuhi" bisa dibuktikan dan bukan diklaim.
- [x] **Bagian 7.5 baru: inventaris kompatibilitas** - 29 route API, envelope
      respons, privasi NIK petugas, z-score hanya dari trigger, urutan master
      suntikan, partial unique index, `kader_id` nullable, dan penjaga database
      test. Semua tidak boleh berubah oleh Opsi B.
- [x] Dua koreksi fakta yang ditemukan saat menulis: `detail_anak_screen.dart`
      **tidak punya** pull-to-refresh (refresh lewat `IconButton`), dan
      penulisan `medical_flags` harus dibatasi Kader saja.
- [x] **Aturan agent dibuat di `posyandu-backend/.ai/rules/`** -
      `kontrak-timeline.md`, `yang-jangan-diubah.md`, `pengujian.md`, plus
      `index.md` yang ditulis sendiri oleh `RuleRepository` Boost. Format
      frontmatter diverifikasi dengan memanggil `writeIndex()`: ketiga file
      muncul di tabel, jadi tidak ada yang gagal parse.
- [x] Indeks dokumentasi di `docs/README.md` dilengkapi; sebelumnya sudah
      tertinggal 9 dokumen.

---

## Opsi B - Buku Medis Digital, Fase 1 (Selesai — 29 Sep 2026)

Implementasi backend. Mobile belum disentuh; itu fase berikutnya.

- [x] Migration `children.medical_flags` (`text`, nullable). Tanpa CHECK
      constraint: batas 500 karakter divalidasi di controller supaya kesalahan
      ketik jadi 422 yang bisa dibaca kader, bukan error PostgreSQL.
- [x] `GET /children/{id}/timeline` di group yang sama dengan `GET /children/{id}`,
      jadi aturan aksesnya tidak berbeda: Ibu hanya anaknya sendiri, Kader semua.
- [x] `ChildTimelineService` - 4 query, tidak bertambah. Satu `UNION` mengambil
      daftar tanggal lebih dulu, lalu tiga query mengisi isinya. Alternatifnya
      (ambil `limit` baris per tabel) memotong timeline di tengah satu kunjungan.
- [x] Validasi `limit` (1-200) dan `before` (`date_format:Y-m-d`, **tanpa**
      `before_or_equal:today` supaya riwayat lama tetap bisa dibaca).
- [x] `medical_flags` hanya bisa ditulis Kader; Ibu membaca anaknya sendiri.
      Penolakan Ibu sengaja `403` yang terbaca, bukan diam-diam diabaikan -
      jawaban 200 padahal tidak tersimpan membuat kader mengira sudah tercatat.
- [x] `ChildTimelineTest` - 21 test, memetakan seluruh aturan 1-7 di
      `RANCANGAN_BUKU_MEDIS.md` bagian 7.3 ke nama test yang sama.
- [x] Tiga jebakan ditutup test: `limit` menghitung tanggal bukan baris; baris
      soft-deleted tidak muncul lagi; penimbangan tanpa kader tetap tampil
      (`leftJoin`, karena `kader_id` nullable dengan `ON DELETE SET NULL`).
- [x] Dokumentasi: `API_CONTRACT.md` (dua endpoint + kode error),
      `DATABASE_SCHEMA.md` (kolom baru + alasannya), laporan baru
      `docs/LAPORAN_BUKU_MEDIS.md`.
- [x] **Verifikasi:** 96 test / 364 assertion hijau, Pint lulus, 30 route
      `api/`, `periksa-teks.ps1` bersih.
- [ ] **Fase 2:** mobile — model, service, perubahan `detail_anak_screen.dart`.
- [ ] Grup `uji-api.ps1` untuk aturan 1-7 belum ditulis.

**Push masih tertunda.** Environment ini tidak punya kredensial GitHub: tidak ada
`gh`, tidak ada `GH_TOKEN`, tidak ada `credential.helper`, dan tidak ada `/dev/tty`
untuk dialog password. `main` sekarang 6 commit di depan `origin/main`. Push
begitu kredensial tersedia; tidak ada konflik yang mungkin muncul karena belum
ada yang lain menyentuh repo ini.

---

## Catatan Environment

| Config | Nilai |
| :--- | :--- |
| `API_BASE_URL` | `http://10.0.2.2:8000/api` (default emulator) |
| `KADER_REGISTRATION_CODE` | isi di `.env` |
| `POSYANDU_NAME` | `Posyandu Desa Sukamaju` |
| `IMMUNIZATION_LATE_AFTER_MONTHS` | `2` |

`php` dan `composer` **tidak ada di `PATH`** pada mesin ini. Path yang dipakai
selama pengerjaan:

| Tool | Path |
| :--- | :--- |
| PHP 8.4.25 | `C:\laragon\bin\php\php-8.4.25-Win32-vs17-x64\php.exe` |
| Composer 2.4.1 | `C:\laragon\bin\composer\composer.phar` |
| Flutter | `C:\src\flutter\bin\flutter.bat` |

Akibatnya `vendor/bin/pint.bat` gagal dengan `'php' is not recognized`. Jalankan
lewat path penuh, bukan `vendor/bin/pint.bat`.

Efek sama untuk MCP server Boost: `.mcp.json` memanggil `php artisan boost:mcp`
dengan command `php`, jadi PHP harus ada di `PATH` atau MCP tidak akan start.

