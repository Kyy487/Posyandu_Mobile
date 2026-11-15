# Dokumentasi Utama Smart Posyandu

Dokumen ini adalah titik masuk untuk memahami kondisi proyek, memverifikasi
implementasi Fase 1, melakukan pemeriksaan saat ada masalah, dan melanjutkan
pekerjaan ke Fase 1.5.

**Terakhir diperbarui:** 15 November 2026
**Commit acuan:** `f11cff5` (`feat: retensi audit log dan observability Fase 1.5`)
**Branch:** `riezky`
**Status:** Fase 1 selesai secara teknis; observability & security dasar selesai
di repo. Fase 1.5 belum selesai karena data eksternal (IHS, KFA/CVX, red flags)
dan rehearsal staging belum tersedia.

## 1. Cara Memakai Dokumen Ini

| Kebutuhan | Bagian |
|---|---|
| Memahami proyek dan arsitektur | 2-4 |
| Melihat apa saja yang berubah di Fase 1 | 5 |
| Menjalankan, deploy, atau rollback | 6 |
| Mengecek kondisi saat ada masalah | 7-8 |
| Melanjutkan ke rencana berikutnya | 9 |
| Mencari dokumen teknis lain | 10 |

Dokumen ini merangkum. Sumber kebenaran tetap:

- Schema database: `docs/DATABASE_SCHEMA.md` dan migration.
- Kontrak API: `docs/API_CONTRACT.md`.
- Rancangan Fase 1: `docs/RANCANGAN_STANDARISASI.md`.
- Aturan pengembangan: `posyandu-backend/.ai/rules/` dan `AGENTS.md`.

## 2. Ringkasan Proyek

Smart Posyandu mendigitalkan pencatatan kesehatan ibu dan anak di Posyandu.

| Layer | Teknologi |
|---|---|
| Backend | Laravel 13, PHP 8.4 |
| Database | PostgreSQL |
| Auth | Laravel Sanctum (Bearer token) |
| Mobile | Flutter |
| Integrasi | FHIR R4 untuk SATUSEHAT (draft + validasi) |

Prinsip yang tidak boleh diubah tanpa keputusan eksplisit:

- Primary key UUID (`HasUuids`), foreign key `foreignUuid()`.
- Migration additive; jangan mengedit migration yang sudah dijalankan.
- Perhitungan Z-Score dan status gizi hanya di trigger/function PostgreSQL.
- Envelope respons tetap `success`, `message`, `data`/`errors`.
- NIK tidak boleh dipakai sebagai ID resource FHIR; gunakan IHS.
- Kode lokal imunisasi tidak boleh dikirim sebagai CVX tanpa mapping.

## 3. Status Terverifikasi

Kondisi pada commit acuan:

| Pemeriksaan | Hasil |
|---|---|
| Full test backend | 323 test lulus, 2337 assertion |
| Pint | Lulus |
| Redaksi log | Processor aktif; NIK/token/kredensial disamarkan |
| Migration 1-10 di database dev | Sudah dijalankan |
| Dokumentasi schema, ERD, API | Sudah disinkronkan |
| Branch remote | `origin/riezky` |

### 3.1 Hasil kerja terbaru

| Commit | Hasil |
|---|---|
| `7917057` | Standarisasi Fase 1: IHS anak, role admin, waktu kunjungan/pengukuran, terminologi imunisasi, red flags, mapper/validator FHIR, import CSV IHS. |
| `2c143dc` | Redaksi log global untuk NIK/token/kredensial, ringkasan payload FHIR di `satusehat.log`, test throttle login, dokumentasi utama dan checklist Fase 1.5. |
| `f11cff5` | Perintah `audit:prune`, kebijakan retensi audit 5 tahun, log aplikasi 30 hari, dokumentasi secret manager/`APP_DEBUG`, test retensi audit. |

Test login akun `pending` dan `rejected` ada di
`tests/Feature/LoginStatusTest.php`; keduanya tetap mendapat token dan
`next_action` yang sesuai.

Perintah verifikasi ulang ada di bagian 7.

## 4. Arsitektur dan Alur Utama

```text
Flutter mobile
    |
    v
Laravel API (/api)
    |
    +-- Middleware: auth:sanctum, role, kader.verification,
    |   child.onboarding, ibu.active, admin
    |
    +-- Controller
    |       +-- validasi request
    |       +-- otorisasi kepemilikan anak/kunjungan
    |
    +-- Service
    |       +-- aturan bisnis
    |       +-- audit log
    |       +-- mapper FHIR
    |
    +-- Model Eloquent
            +-- PostgreSQL
            +-- trigger Z-Score WHO
```

### Peran

| Peran | Akses |
|---|---|
| `ibu` | Profil, pendaftaran, data anak sendiri, imunisasi (baca), catatan keluhan (baca), jadwal |
| `kader` | Data semua anak, kunjungan, penimbangan, imunisasi, catatan keluhan, rujukan, audit, FHIR |
| `admin` | Hanya endpoint `/api/admin/*` untuk IHS; tidak otomatis mendapat akses kader |

Admin tidak bisa mendaftar lewat `/register`. Akun admin dibuat lewat
`AdminUserSeeder`.

### Alur IHS

```text
CSV admin
  -> ChildIhsImportService
  -> validasi baris + cari anak
  -> ChildIhsService
  -> update children.ihs_number
  -> audit_logs (event updated, alasan di new_values.reason)
```

### Alur FHIR

```text
Model lokal
  -> SatusehatFhirService
  -> payload FHIR R4
  -> validatePayload()
  -> sendToSatusehat()
       - kredensial kosong: tulis storage/logs/satusehat.log
       - kredensial ada: kirim ke SATUSEHAT
```

Pengiriman otomatis, queue, retry, dan outbox belum termasuk Fase 1.

## 5. Perubahan Fase 1

### 5.1 Migration

| No | File | Fungsi |
|---|---|---|
| 1 | `add_admin_role_to_users_table` | Role `admin`; rollback ditolak bila masih ada admin |
| 2 | `add_social_media_columns_to_users_table` | `whatsapp`, `instagram`, `facebook` |
| 3 | `add_ihs_number_to_children_table` | `children.ihs_number` unique nullable |
| 4 | `add_visit_timing_and_edukasi_gizi_to_visits_table` | Waktu kunjungan + edukasi gizi |
| 5 | `add_measured_at_to_measurements_table` | Waktu pengukuran |
| 6 | `add_fhir_terminology_to_immunization_types_table` | KFA/CVX dan metadata terminologi |
| 7 | `add_red_flags_and_icd10_to_medical_notes_table` | `red_flags` JSONB + `icd10_code` |
| 8 | `backfill_visit_and_measurement_timestamps` | Backfill waktu dari tanggal lokal; `down()` no-op |
| 9 | `allow_ktp_in_user_verifications_type` | Menerima unggah ulang KTP |
| 10 | `allow_red_flags_as_medical_note_content` | Red flag saja dianggap isi catatan |

Catatan penting:

- Migration 8 mengisi `visit_started_at` dan `measured_at` pukul 00:00
  `Asia/Jakarta`, hanya untuk baris NULL, dan mematikan trigger Z-Score
  sementara agar nilai klinis tidak berubah.
- Migration 8 tidak mengisi `visit_ended_at` karena durasi lama tidak diketahui.
- Migration 9 penting untuk database fresh karena migration lama membuat CHECK
  dari `$table->enum()`.
- Migration 10 memperbarui `medical_notes_isi_check` agar catatan berisi red
  flag saja tidak ditolak database.

### 5.2 Admin IHS

Endpoint:

| Method | Endpoint | Fungsi |
|---|---|---|
| `GET` | `/api/admin/children/ihs/template` | Unduh template CSV |
| `POST` | `/api/admin/children/ihs/import` | Import CSV; mendukung `dry_run` dan `correct_existing` |
| `PATCH` | `/api/admin/children/{child}/ihs` | Koreksi IHS manual + alasan |

Aturan:

- Maksimal 5.000 baris per unggahan.
- Parser mendukung koma, titik koma, BOM, dan error per baris.
- Anak dicari lewat `child_id`, atau `nik_anak` + `tanggal_lahir`.
- `nik_ibu` opsional dan harus cocok dengan ibu anak.
- IHS duplikat ditolak.
- Menimpa IHS lama wajib `correct_existing=true`.
- Setiap perubahan dicatat ke `audit_logs`.

### 5.3 FHIR R4

Endpoint:

| Method | Endpoint | Fungsi |
|---|---|---|
| `GET` | `/api/kader/fhir/{resourceType}/{id}` | Draft payload |
| `GET` | `/api/kader/fhir/{resourceType}/{id}/validate` | Validasi payload |
| `POST` | `/api/kader/fhir/{resourceType}/{id}/send` | Kirim atau catat ke log |
| `GET` | `/api/kader/fhir/Observation/{id}/bundle` | Bundle BB, TB, lingkar kepala, IMT |
| `GET` | `/api/kader/fhir/Observation/{id}/bundle/validate` | Validasi seluruh Observation |

Resource yang didukung: `Patient`, `Encounter`, `Observation`, `Immunization`.

Aturan:

- `Patient.id` memakai `children.ihs_number`.
- `Patient.identifier` memakai NIK dengan system
  `https://fhir.kemkes.go.id/id/nik`.
- Referensi resource memakai `Patient/{ihs_number}`, bukan NIK.
- Waktu dikirim dalam UTC.
- `Observation` tunggal tetap tinggi badan untuk kompatibilitas.
- Bundle memuat nilai yang tersedia: BB (`29463-7`), TB (`8302-2`), lingkar
  kepala (`9843-4`), dan IMT (`39156-5`, dihitung dari BB/TB).
- `Immunization` hanya valid bila ada mapping KFA atau CVX.
- Validasi mengembalikan `valid`, `errors`, `warnings`, dan `payload`.

### 5.4 Red Flags dan ICD-10

- `medical_notes.red_flags` bertipe JSONB array.
- Allowlist ada di `App\Support\RedFlagCodes`.
- Database hanya memastikan bentuk array, bukan isi kode.
- `icd10_code` nullable dan tidak wajib.
- Kader tidak menegakkan diagnosis; red flag adalah tanda bahaya untuk
  skrining dan rujukan.
- Daftar red flags harus disetujui tenaga kesehatan sebelum produksi.

### 5.5 Sosial Media

- Disimpan sebagai handle bersih, bukan URL.
- `whatsapp` disimpan dalam format E.164, contoh `+6281234567890`.
- `instagram` dan `facebook` disimpan tanpa `@` dan tanpa URL.
- Normalisasi ada di `App\Support\SocialMediaNormalizer`.

### 5.6 Waktu dan Zona Waktu

- Database menyimpan `timestamptz`; aplikasi memakai UTC.
- Input tanggal lokal dianggap `Asia/Jakarta`.
- `FhirDateTime` mengubah waktu ke UTC untuk payload FHIR.
- `measured_at` diisi dari `measurement_date` saat input, dan diisi ulang saat
  koreksi tanggal.

### 5.7 Registrasi dan Unggah Ulang

- Ibu `pending` dan `rejected` tetap bisa mengakses status pendaftaran,
  melengkapi pendaftaran, profil, dan logout.
- Ibu `rejected` bisa mengunggah ulang `ktp`/`kk` lewat
  `/api/registration/complete`.
- `RegistrationCompletionController::resolveUser` menerima user dari guard
  default atau `sanctum`, sehingga Bearer token bekerja di route tanpa
  middleware `auth:sanctum`.

### 5.8 Redaksi Log

- `App\Support\SensitiveDataRedactor` menyamarkan NIK 16 digit, password,
  token, `client_secret`, dan header `Authorization`.
- `App\Logging\RedactSensitiveData` dipasang sebagai processor Monolog pada
  channel `single`, `daily`, `monthly`, `slack`, `satusehat`, `papertrail`,
  `stderr`, `syslog`, dan `errorlog`.
- `QueryException` tidak lagi menulis NIK dari binding query karena pesan
  exception ikut disaring.
- `satusehat.log` hanya menyimpan ringkasan payload: `resourceType`,
  `payload_hash`, `payload_keys`, `identifier_systems`, dan `has_subject`.
- Log penuh tetap berguna untuk debugging, tetapi tidak boleh memuat NIK,
  password, token, atau kredensial.

## 6. Operasional

### 6.1 Prasyarat

- PHP 8.4
- Composer
- PostgreSQL dengan database pengembangan dan `posyandu_test`
- Ekstensi PHP `pdo_pgsql`, `fileinfo`, dan `gd`
- Bila `php -m` tidak menampilkan `fileinfo`/`gd`, aktifkan di `php.ini`
  atau gunakan PHP Laragon yang sudah mengaktifkannya

### 6.2 Setup Awal

```powershell
cd C:\laragon\www\posyandu\posyandu-backend
composer install
copy .env.example .env
php artisan key:generate
php artisan migrate
php artisan serve
```

Sesuaikan `.env` dengan PostgreSQL. `.env.example` masih memakai SQLite sebagai
default Laravel; aplikasi ini membutuhkan PostgreSQL.

### 6.3 Environment Penting

```dotenv
DB_CONNECTION=pgsql
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DATABASE=posyandu_db
DB_USERNAME=postgres
DB_PASSWORD=

KADER_REGISTRATION_CODE=

POSYANDU_ADMIN_NIK=
POSYANDU_ADMIN_PASSWORD=
POSYANDU_ADMIN_NAME="Admin Posyandu"

SATUSEHAT_ENV=sandbox
SATUSEHAT_BASE_URL=https://api-satusehat-stg.dto.kemkes.go.id/fhir-r4/v1
SATUSEHAT_AUTH_URL=
SATUSEHAT_CLIENT_ID=dummy
SATUSEHAT_CLIENT_SECRET=dummy
SATUSEHAT_ORG_ID=
```

Catatan:

- `KADER_REGISTRATION_CODE` kosong berarti pendaftaran kader nonaktif.
- `POSYANDU_ADMIN_*` hanya dipakai `AdminUserSeeder`.
- `SATUSEHAT_ORG_ID` dipakai untuk `serviceProvider` Encounter dan identifier
  Immunization.
- Jangan commit `.env` asli atau kredensial.

### 6.4 Membuat Admin

```powershell
php artisan db:seed --class=AdminUserSeeder
```

Seeder tidak melakukan apa pun bila NIK/password admin kosong.

### 6.5 Test dan Lint

```powershell
php artisan test
vendor\bin\pint --test
```

Test wajib memakai PostgreSQL `posyandu_test`, bukan SQLite. Database test akan
dihapus dan dibuat ulang oleh `RefreshDatabase`.

### 6.6 Checklist Deploy

1. Backup database.
2. Pastikan `.env` produksi benar dan `APP_DEBUG=false`.
3. Jalankan `php artisan migrate --force`.
4. Jalankan `php artisan db:seed --class=AdminUserSeeder` bila admin baru perlu
   dibuat.
5. Jalankan `php artisan config:cache` dan `php artisan route:cache`.
6. Smoke test: login, profil, data anak, import IHS dry-run, FHIR validate.
7. Cek `storage/logs/laravel.log` dan `storage/logs/satusehat.log`.
8. Simpan hasil `php artisan migrate:status`.

### 6.7 Rollback

- Migration 1 `down()` menolak rollback bila masih ada user `admin`.
- Migration 8 `down()` sengaja no-op; data backfill tidak dibalik.
- Migration 9 `down()` hanya memasang ulang CHECK lama bila tidak ada baris
  `ktp`.
- Migration 10 `down()` memakai constraint `NOT VALID` agar data lama tidak
  memblokir rollback.
- Selalu uji rollback di staging, bukan langsung di produksi.

### 6.8 Log, Retensi, dan Secret

- Log aplikasi: `storage/logs/laravel.log`.
- Log FHIR: `storage/logs/satusehat.log`.
- Kedua channel memakai `App\Logging\RedactSensitiveData`, sehingga NIK,
  password, token, dan `client_secret` disamarkan sebelum ditulis.
- Untuk produksi, gunakan `LOG_CHANNEL=daily` dan `LOG_DAILY_DAYS=30` agar file
  log tidak tumbuh tanpa batas. Nilai ini dapat diubah lewat `.env`.
- `audit_logs` adalah data audit terpisah dan tidak ikut rotasi file log.
  Kebijakan default: retensi 5 tahun (1825 hari), tidak dihapus otomatis.
  Penghapusan hanya manual setelah backup dan persetujuan koordinator:
  `php artisan audit:prune --dry-run`, lalu `php artisan audit:prune --force`.
- Jangan commit `.env`. Kredensial SATUSEHAT wajib diinjeksi dari secret
  manager atau environment terenkripsi di server (mis. systemd
  `EnvironmentFile`, Docker secret, atau cloud secret manager), bukan dari file
  yang ikut repository. Rotasi kredensial bila pernah terekspos.
- Log lama yang dibuat sebelum processor redaksi dipasang bisa memuat NIK.
  Rotasi atau hapus setelah backup, lalu pastikan log baru sudah bersih.
- Setelah deploy, cek log dan pastikan tidak ada NIK 16 digit, password, token,
  atau `client_secret`.

## 7. Pemeriksaan Cepat

Jalankan dari `posyandu-backend`:

```powershell
git branch --show-current
git log --oneline -1
php artisan migrate:status
php artisan route:list --path=api
php artisan audit:prune --dry-run
php artisan test
vendor\bin\pint --test
```

Cek data penting di PostgreSQL:

```sql
SELECT count(*) FROM users WHERE role = 'admin';
SELECT count(*) FROM children WHERE ihs_number IS NOT NULL;
SELECT count(*) FROM visits WHERE visit_started_at IS NULL;
SELECT count(*) FROM measurements WHERE measured_at IS NULL;
SELECT count(*) FROM medical_notes WHERE red_flags IS NOT NULL;
```

Cek constraint:

```sql
SELECT conname
FROM pg_constraint
WHERE conrelid = 'users'::regclass
  AND conname = 'users_role_check';

SELECT conname
FROM pg_constraint
WHERE conrelid = 'medical_notes'::regclass
  AND conname IN ('medical_notes_isi_check', 'medical_notes_red_flags_array_check');
```

Cek endpoint FHIR tanpa mengirim data:

```text
GET /api/kader/fhir/Patient/{id}/validate
GET /api/kader/fhir/Encounter/{id}/validate
GET /api/kader/fhir/Observation/{id}/bundle/validate
GET /api/kader/fhir/Immunization/{id}/validate
```

## 8. Troubleshooting

| Gejala | Penyebab umum | Tindakan |
|---|---|---|
| Test gagal koneksi database | `posyandu_test` belum ada atau `.env.testing` salah | Buat database test, cek kredensial |
| Test menghapus data dev | `DB_DATABASE` test sama dengan dev | Hentikan; perbaiki `.env.testing` |
| Import IHS 422 | Header tidak ada, file kosong, atau >5.000 baris | Cek pesan `errors.file` |
| Baris import gagal | IHS invalid, duplikat, anak tidak ditemukan, IHS lama | Cek `data.errors[].message` |
| Admin 403 | Role bukan `admin` atau seeder belum jalan | Cek role dan jalankan seeder |
| Kader bisa mengubah IHS | Route admin tidak memakai middleware `admin` | Cek `routes/api.php` |
| FHIR Patient invalid | `ihs_number` kosong | Isi IHS lewat admin |
| FHIR Immunization invalid | Mapping KFA/CVX kosong | Isi `immunization_types` |
| Red flag saja ditolak DB | Migration 10 belum jalan | Jalankan migrate |
| Waktu backfill terlihat beda | Ditampilkan dalam zona waktu lokal | Bandingkan dengan `utc()` atau nilai UTC |
| `registration/complete` 401 | Token tidak terbaca | Pastikan Bearer token dan `resolveUser` |
| Log FHIR kosong | Kredensial kosong | Cek `storage/logs/satusehat.log` |
| Log masih memuat NIK | Processor redaksi tidak aktif atau config ter-cache | Jalankan `php artisan config:clear`, cek `logging.channels.*.tap` |
| `satusehat.log` tidak memuat payload penuh | Memang disengaja | Hanya ringkasan; payload penuh tidak ditulis |
| Audit log lama tidak terhapus | Perintah berjalan `--dry-run` atau belum lewat retensi | Cek `php artisan audit:prune --dry-run`, lalu `--force` setelah backup |
| Rollback role admin gagal | Masih ada user admin | Pindahkan/hapus admin dulu |

## 9. Rancangan Fase 1.5

Tujuan: memastikan Fase 1 aman dipakai di produksi sebelum masuk otomasi
SATUSEHAT Fase 2.

Checklist kerja dan kolom bukti ada di `docs/CHECKLIST_FASE_1_5.md`.

Status per 15 November 2026: observability & security dasar selesai (redaksi
log, test rate limit, test admin guard, kebijakan retensi audit 5 tahun, log
aplikasi 30 hari). `APP_DEBUG=false` dan secret manager diverifikasi saat
deploy staging/produksi.

### 9.1 Prinsip

- Tidak menambah fitur besar.
- Fokus pada data final, rehearsal migrasi, pilot admin, dan keamanan.
- Gate Fase 2 hanya terbuka setelah semua kriteria di 9.7 lulus.

### 9.2 Alur Kerja

| Workstream | Deliverable | Kriteria lulus |
|---|---|---|
| Data IHS | Format final + validasi + data lama | IHS valid menurut IG, duplikat nol |
| Terminologi imunisasi | Mapping KFA/CVX terisi | Semua imunisasi aktif punya mapping atau alasan eksplisit |
| Red flags | Daftar disetujui tenaga kesehatan | Allowlist, dokumentasi, dan test sinkron |
| Rehearsal migrasi | Hasil uji di staging | Data utuh, Z-Score tidak berubah, waktu terisi |
| Pilot admin | Import data nyata + audit review | Semua baris terhitung, error bisa diunduh/dilacak |
| Observability | Log aman + alert dasar | Tidak ada NIK/kredensial di log |
| Handover | Runbook dan checklist | Developer lain bisa deploy dari dokumen |

### 9.3 Data IHS

1. Dapatkan format final dari IG SATUSEHAT.
2. Perbarui `App\Support\IhsNumber` dan test terkait.
3. Validasi ulang data IHS yang sudah masuk.
4. Siapkan koreksi massal lewat CSV `correct_existing=true` bila perlu.

### 9.4 Terminologi Imunisasi

1. Kumpulkan mapping KFA/CVX resmi.
2. Isi `immunization_types.kfa_code`, `cvx_code`, `cvx_display`,
   `cvx_group_code`, dan `target_disease_code`.
3. Jalankan validasi FHIR untuk semua tipe imunisasi aktif.
4. Dokumentasikan tipe yang sengaja belum punya mapping.

### 9.5 Red Flags

1. Review daftar `RedFlagCodes` bersama tenaga kesehatan.
2. Hapus/tambah kode sesuai keputusan klinis.
3. Perbarui dokumentasi dan test.
4. Pastikan kader memahami red flag bukan diagnosis.

### 9.6 Rehearsal Migrasi dan Pilot Admin

1. Salin database produksi ke staging.
2. Backup sebelum migrate.
3. Jalankan migration dan catat durasi.
4. Bandingkan jumlah baris dan nilai Z-Score sebelum/sesudah.
5. Jalankan import IHS mode `dry_run`, lalu import nyata di staging.
6. Review audit log dan laporan error.
7. Uji rollback di staging.

### 9.7 Exit Criteria Fase 1.5

- Format IHS final dan seluruh data IHS valid.
- Mapping KFA/CVX lengkap untuk imunisasi aktif.
- Daftar red flags disetujui dan tersinkron dengan kode.
- Migration + backfill lulus di staging tanpa mengubah Z-Score.
- Import CSV pilot lulus, audit log lengkap, error dapat dilacak.
- Tidak ada NIK atau kredensial di log.
- Runbook deploy dan rollback tersedia.
- Full test dan Pint lulus.

Setelah semua lulus, baru masuk **Fase 2A**: OAuth SATUSEHAT, outbox/queue,
retry, idempotency, pengiriman resource, dan rekonsiliasi.

### 9.8 Rancangan Fase 2A (setelah Fase 1.5)

Fase 2A adalah pengiriman nyata ke SATUSEHAT, bukan lagi draft/validasi.

1. **OAuth dan konfigurasi**
   - Ambil token dari endpoint OAuth SATUSEHAT.
   - Simpan `client_id`, `client_secret`, dan `org_id` di secret manager.
   - Token tidak boleh masuk log atau database dalam bentuk plaintext.
2. **Outbox dan queue**
   - Setiap perubahan yang perlu dikirim menulis satu baris outbox.
   - Worker mengirim resource secara asinkron.
   - Retry dengan backoff, idempotency key, dan status akhir yang bisa diaudit.
3. **Resource yang dikirim**
   - `Patient` memakai `ihs_number`, bukan NIK.
   - `Encounter`, `Observation` (BB/TB/LK/IMT), dan `Immunization`.
   - Lanjutan: `RelatedPerson`, `Practitioner`, `ServiceRequest`, `Consent`,
     dan `DocumentReference`.
4. **Rekonsiliasi dan monitoring**
   - Bandingkan resource lokal dengan respons SATUSEHAT.
   - Alert untuk kegagalan berulang, token kedaluwarsa, dan antrean menumpuk.
   - Dashboard operasional tanpa menampilkan NIK atau kredensial.
5. **Lingkup yang tetap ditunda**
   - WhatsApp dengan opt-in dan template.
   - ICD-10/SNOMED wajib.
   - Multi-Posyandu dan `health_facilities`.
   - Offline-first sync dan AI Food Scanner.

### 9.9 Urutan eksekusi berikutnya

1. Finalkan data eksternal: format IHS, mapping KFA/CVX, dan daftar red flags.
2. Rehearsal migrasi di staging dan pilot import IHS dengan data nyata.
3. Tutup seluruh item A-G di `docs/CHECKLIST_FASE_1_5.md`.
4. Mulai Fase 2A: OAuth, outbox, queue, retry, idempotency, pengiriman resource,
   dan rekonsiliasi.
5. Setelah Fase 2A stabil, lanjut notifikasi WhatsApp dan perluasan resource.

## 10. Rujukan Dokumen

| Dokumen | Isi |
|---|---|
| `docs/API_CONTRACT.md` | Kontrak endpoint dan envelope respons |
| `docs/DATABASE_SCHEMA.md` | Schema aktual dan daftar migration |
| `docs/ERD_POSYANDU.mermaid.md` | ERD Mermaid |
| `docs/RENCANA_UNIFIED_SATU_PINTU.md` | Rencana induk lintas fase dan status fitur |
| `docs/RANCANGAN_STANDARISASI.md` | Rancangan Fase 1 dan keputusan teknis |
| `docs/CHECKLIST_FASE_1_5.md` | Checklist kerja dan bukti Fase 1.5 |
| `docs/KEAMANAN_APLIKASI.md` | Catatan keamanan |
| `docs/Cara_menjalankan.md` | Panduan menjalankan backend/mobile |
| `docs/SETUP_LOG.md` | Riwayat setup lingkungan |
| `posyandu-backend/.ai/rules/` | Aturan wajib untuk perubahan kode |

Jika dokumen ini berbeda dengan migration atau test, migration dan test adalah
sumber kebenaran. Perbarui dokumen ini setiap kali ada perubahan schema,
endpoint, atau keputusan arsitektur.
