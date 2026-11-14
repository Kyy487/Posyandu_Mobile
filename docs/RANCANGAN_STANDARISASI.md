# Rancangan Standardisasi Data Posyandu

Status: **terkunci pada 14 November 2026**. Dokumen ini adalah rancangan kerja
Fase 1. Implementasi Fase 1 sudah dijalankan pada 14 November 2026; migration
sudah diterapkan dan test suite sudah lulus.

## 1. Keputusan yang dikunci

| No | Topik | Keputusan |
|---|---|---|
| 1 | Scope | Anak saja. Kehamilan/ANC, persalinan, KB, LILA, vitamin A, obat cacing, dan PMT di luar Fase 1. |
| 2 | Target integrasi | Kesiapan payload FHIR, bukan pengiriman produksi. Tidak ada OAuth, outbox, retry, atau API call SATUSEHAT di Fase 1. |
| 3 | IHS number | `children.ihs_number` saja. Fase 1 lewat import CSV admin dan edit manual admin. Otomatis API + queue masuk Fase 2 setelah data anak dibuat. |
| 4 | Role admin | Role `admin` terpisah di `users.role` (`ibu`, `kader`, `admin`). Tidak digabung ke `kader`. |
| 5 | Red flags | `medical_notes.red_flags` bertipe `JSONB`, nullable, divalidasi allowlist di aplikasi. |
| 6 | Edukasi gizi | `visits.edukasi_gizi` bertipe text, nullable. |
| 7 | Waktu | `timestamptz` disimpan UTC. Payload FHIR memakai UTC. UI menampilkan `Asia/Jakarta`. Data lama di-backfill dari tanggal + 00:00 Asia/Jakarta. |
| 8 | Z-Score | Logika Z-Score tidak diubah. Backfill waktu hanya menghilangkan NULL, bukan menambah presisi perhitungan. |
| 9 | Sosial media | Simpan handle bersih. Backend menormalisasi `@username` dan URL penuh. |
| 10 | Catatan medis | Tanpa ICD-10/SNOMED wajib. `icd10_code` hanya nullable untuk persiapan. |
| 11 | Posyandu | Satu Posyandu dulu. Tidak ada tabel `health_facilities` di Fase 1. |
| 12 | Terminologi imunisasi | Kolom eksplisit di `immunization_types`, bukan tabel mapping generik. |

## 2. Prinsip rancangan

1. Database lokal adalah sumber kebenaran operasional.
2. FHIR adalah lapisan pertukaran, bukan struktur database.
3. Semua perubahan schema bersifat additive; tidak rename/ubah field lama.
4. UUID lokal tetap identitas internal. NIK tidak dipakai sebagai ID resource.
5. IHS number disimpan eksplisit dan nullable.
6. Waktu disimpan UTC; tampilan lokal dihitung di lapisan presentasi.
7. Kode lokal tidak dikirim sebagai kode terminologi standar tanpa mapping.
8. Tidak ada diagnosis medis dari kader; red flags hanya skrining awal.
9. Data sensitif tidak masuk log mentah.
10. Setiap fase punya kriteria selesai dan rollback.

## 3. Ruang lingkup Fase 1

### Termasuk

- Schema identity: IHS anak, role admin, sosial media.
- Waktu kunjungan dan pengukuran.
- Terminologi imunisasi.
- Red flags dan edukasi gizi.
- Mapper dan validasi payload FHIR untuk `Patient`, `Encounter`,
  `Observation`, dan `Immunization`.
- Import CSV IHS khusus admin.
- Edit manual IHS khusus admin.
- Dokumentasi, test, dan rencana migrasi.

### Tidak termasuk

- Pengiriman ke SATUSEHAT.
- OAuth, queue, outbox, retry.
- Pembuatan IHS otomatis.
- `RelatedPerson`, `Practitioner`, `ServiceRequest`, `Consent`, dan
  `DocumentReference`.
- Kehamilan/ANC dan layanan ibu lainnya.
- Notifikasi WhatsApp.
- ICD-10/SNOMED wajib.

## 4. Target data model Fase 1

Tidak ada tabel baru. Semua perubahan berupa kolom baru atau constraint baru.

| Tabel | Kolom/Perubahan | Tipe | Nullable | Aturan |
|---|---|---|---|---|
| `users` | `role` constraint | check | tidak | Nilai menjadi `ibu`, `kader`, `admin`. |
| `users` | `whatsapp` | varchar(20) | ya | E.164, contoh `+628123456789`. |
| `users` | `instagram` | varchar(50) | ya | Handle tanpa `@`, huruf kecil. |
| `users` | `facebook` | varchar(100) | ya | Handle tanpa URL. |
| `children` | `ihs_number` | varchar(50) | ya | Unique, format divalidasi setelah IG dikonfirmasi. |
| `visits` | `visit_started_at` | timestamptz | ya | Waktu mulai kunjungan. |
| `visits` | `visit_ended_at` | timestamptz | ya | Waktu selesai; null bila belum selesai. |
| `visits` | `edukasi_gizi` | text | ya | Edukasi yang diberikan saat kunjungan. |
| `measurements` | `measured_at` | timestamptz | ya | Waktu pengukuran. |
| `immunization_types` | `kfa_code` | varchar(50) | ya | Kode produk KFA. |
| `immunization_types` | `cvx_code` | varchar(20) | ya | Kode CVX. |
| `immunization_types` | `cvx_display` | varchar(255) | ya | Nama CVX. |
| `immunization_types` | `cvx_group_code` | varchar(20) | ya | Hanya bila IG membutuhkan. |
| `immunization_types` | `target_disease_code` | varchar(20) | ya | Kode penyakit target, opsional. |
| `medical_notes` | `red_flags` | jsonb | ya | Array kode dari allowlist aplikasi. |
| `medical_notes` | `icd10_code` | varchar(10) | ya | Persiapan; tidak wajib. |

### Catatan field lama

- `visits.visit_date` tetap dipertahankan.
- `measurements.measurement_date` tetap dipertahankan.
- `medical_notes.demam`, `rewel`, dan `diare` tetap dipertahankan.
- `visits.anamnesis` tetap menjadi keluhan utama.
- `visits.catatan_kader` tetap catatan kader.
- `users.phone_number` tetap kontak utama/login.
- `immunization_types.code` tetap kode lokal internal.

## 5. Aturan waktu

### Penyimpanan

- Semua kolom waktu baru memakai `timestamptz`.
- PostgreSQL menyimpan nilai dalam UTC.
- Aplikasi menampilkan waktu dalam `Asia/Jakarta`.

### Backfill data lama

- `visits.visit_started_at` diisi dari `visit_date` + `00:00:00`
  `Asia/Jakarta` bila `visit_date` tidak null.
- `measurements.measured_at` diisi dari `measurement_date` + `00:00:00`
  `Asia/Jakarta` bila `measurement_date` tidak null.
- Bila tanggal historis benar-benar tidak ada, nilai tetap null.
- `visit_ended_at` tetap null karena durasi lama tidak diketahui.
- Backfill tidak mengubah `visit_date` atau `measurement_date`.
- Backfill tidak mengubah trigger Z-Score.

### Output FHIR

- Semua `dateTime` dikirim dalam UTC, misalnya `2026-11-14T00:00:00+00:00`.
- Jika IG SATUSEHAT ternyata mewajibkan format tertentu, aturan output
  mengikuti IG, bukan asumsi aplikasi.
- Jangan hardcode `+07:00` di payload.

## 6. Desain IHS number

### Fase 1

- Hanya `children.ihs_number`.
- Diisi lewat import CSV admin atau edit manual admin.
- Tidak ada pemanggilan API SATUSEHAT.
- Tidak ada input IHS oleh kader.
- `users.ihs_number` belum dibuat.

### Validasi

- Trim spasi.
- Tolak nilai kosong yang dikirim eksplisit.
- Format final menunggu konfirmasi IG SATUSEHAT.
- Unique di database.
- Satu anak hanya boleh punya satu IHS.
- IHS tidak boleh dipakai dua anak.

### Import CSV admin

Format minimal:

```text
child_id,nik_anak,nama_anak,tanggal_lahir,nik_ibu,ihs_number
```

Aturan:

- `ihs_number` wajib.
- Anak dicari lewat `child_id` bila diisi.
- Bila `child_id` kosong, cari lewat `nik_anak` + `tanggal_lahir`.
- `nik_ibu` opsional untuk verifikasi tambahan.
- Baris dengan anak tidak ditemukan menjadi error baris.
- Baris dengan IHS duplikat menjadi error baris.
- Baris dengan anak sudah punya IHS berbeda menjadi error, kecuali mode
  koreksi eksplisit.
- Tidak menimpa data tanpa flag koreksi.
- Mendukung mode dry-run.
- Maksimal 5.000 baris per unggahan, diproses per chunk.
- Setiap perubahan dicatat ke `audit_logs` dengan event `updated`. Jangan
  memakai event baru seperti `ihs_imported` karena constraint `audit_logs`
  hanya menerima `created`, `updated`, `deleted`, dan `restored`.
- Respons berisi ringkasan sukses, gagal, dan daftar error per baris.
- Tidak perlu tabel batch import di Fase 1; laporan cukup di respons.

### Edit manual admin

- Admin dapat mengoreksi IHS satu anak.
- Perubahan dicatat ke `audit_logs`.
- Alasan koreksi wajib diisi.
- Admin tidak dapat mengubah NIK atau tanggal lahir lewat endpoint ini.

### Fase 2

- Otomatis API + queue setelah data anak dibuat/dilengkapi.
- Butuh kredensial SATUSEHAT, OAuth, queue worker, retry, idempotency, dan
  monitoring.
- Tidak masuk Fase 1.

## 7. Role admin

### Schema

- `users.role` menerima `ibu`, `kader`, `admin`.
- Constraint lama `users_role_check` diganti lewat migration baru.
- Admin tidak bisa mendaftar sendiri lewat `POST /register`.
- Admin dibuat lewat seeder atau perintah CLI internal.

### Middleware

- Gunakan middleware role yang sudah ada (`RoleCheck:admin`) atau alias
  `admin` yang memanggil pengecekan yang sama.
- Admin hanya mendapat route `/admin/*` pada Fase 1.
- Admin tidak otomatis mendapat akses ke seluruh route `/kader/*`.
- Endpoint admin Fase 1:
  - `POST /admin/children/ihs/import`
  - `PATCH /admin/children/{child}/ihs`
  - `GET /admin/children/ihs/template`

## 8. Sosial media

### Normalisasi

| Input | Disimpan |
|---|---|
| `@username` | `username` |
| `username` | `username` |
| `https://instagram.com/username` | `username` |
| `https://www.instagram.com/username/?hl=id` | `username` |
| `https://m.facebook.com/username` | `username` |
| `081234567890` untuk WhatsApp | `+628123456789` |

Aturan:

- Instagram dan Facebook disimpan sebagai handle tanpa `@`, tanpa scheme,
  tanpa host, tanpa query, dan tanpa trailing slash.
- WhatsApp disimpan dalam format E.164.
- Normalisasi dilakukan di satu service/FormRequest, bukan di controller.
- Input yang tidak bisa dinormalisasi menjadi 422 dengan pesan yang jelas.
- Data sosial media tidak ditampilkan di endpoint publik.
- Hanya pemilik akun, kader berwenang, dan admin yang boleh melihat.

## 9. Catatan medis dan red flags

### Struktur

- `visits.anamnesis` = keluhan utama.
- `visits.catatan_kader` = catatan kader.
- `visits.edukasi_gizi` = edukasi gizi saat kunjungan.
- `medical_notes.catatan` = catatan tambahan keluhan.
- `medical_notes.red_flags` = array kode red flag.
- `medical_notes.icd10_code` = persiapan, nullable, tidak wajib.

### Red flags

- Disimpan sebagai `JSONB` array, bukan kolom boolean baru.
- Validasi allowlist di aplikasi.
- Daftar awal harus disetujui tenaga kesehatan sebelum dipakai produksi.
- Contoh kode awal:
  - `demam_tinggi`
  - `kejang`
  - `sesak_napas`
  - `dehidrasi`
  - `muntah_berulang`
  - `tidak_mau_makan`
  - `lemas`
  - `bb_tidak_naik`
  - `bblr`
  - `ikterus`
- Jangan menambah kode baru tanpa memperbarui allowlist dan dokumentasi.
- Database hanya memvalidasi bahwa nilainya array JSON, bukan isi kode.

### Batas klinis

- Kader tidak menegakkan diagnosis.
- Red flags adalah tanda bahaya untuk skrining dan rujukan.
- `icd10_code` tidak diisi otomatis dan tidak wajib.

## 10. Pemetaan payload FHIR Fase 1

| Lokal | FHIR | Status Fase 1 |
|---|---|---|
| `children` | `Patient` | mapper + validasi |
| `visits` | `Encounter` | mapper + validasi |
| `measurements` | `Observation` | mapper + validasi |
| `immunization_records` | `Immunization` | mapper + validasi |
| `users` ibu | `RelatedPerson` | ditunda |
| `users` kader | `Practitioner` | ditunda |
| `referrals` | `ServiceRequest` | ditunda |
| `consents` | `Consent` | ditunda |
| `medical_notes` | `Condition`/`Observation` | ditunda |
| `user_verifications` | `DocumentReference` | ditunda |

### Patient

- `identifier` NIK memakai system `https://fhir.kemkes.go.id/id/nik`.
- `id` memakai `children.ihs_number` bila tersedia.
- `name`, `gender`, `birthDate` dari data anak.
- Jangan memakai NIK sebagai `id` atau referensi resource.
- Bila IHS kosong, payload ditandai draft dan tidak valid untuk dikirim.

### Encounter

- `subject.reference` memakai `Patient/{ihs_number}`.
- `period.start` dari `visit_started_at`.
- `period.end` dari `visit_ended_at` bila ada.
- `status` minimal `finished` untuk kunjungan yang sudah selesai.
- `serviceProvider` dari config organisasi Posyandu.

### Observation

Satu penimbangan dapat menghasilkan beberapa `Observation`:

| Pengukuran | LOINC | Unit UCUM |
|---|---|---|
| Berat badan | `29463-7` | `kg` |
| Tinggi/panjang badan | `8302-2` | `cm` |
| Lingkar kepala | `9843-4` | `cm` |
| IMT | `39156-5` | `kg/m2` |

- `subject.reference` memakai `Patient/{ihs_number}`.
- `encounter.reference` memakai `Encounter/{id}`.
- `effectiveDateTime` dari `measured_at` dalam UTC.
- Z-score/status gizi tidak dipaksakan menjadi LOINC. Bila diperlukan,
  gunakan CodeSystem lokal yang disepakati atau tunda sampai ada mapping resmi.
- Endpoint lama tetap mengembalikan satu `Observation` tinggi badan.
  Endpoint `Observation/{id}/bundle` mengembalikan semua nilai yang tersedia
  dalam `Bundle` bertipe `collection`.

### Immunization

- `vaccineCode.coding` memakai KFA dan CVX dari mapping.
- Kode lokal `code` tidak dikirim sebagai CVX.
- `patient.reference` memakai `Patient/{ihs_number}`.
- `encounter.reference` memakai `Encounter/{id}`.
- `occurrenceDateTime` dari `date_given` + waktu yang disepakati, dalam UTC.
- `lotNumber` dari `batch_number`.
- `primarySource` sesuai sumber data.

### Validasi payload

- Validasi wajib: IHS ada, referensi ada, waktu ada, unit benar, kode
  terminologi ada.
- `GET /kader/fhir/{resourceType}/{id}` tetap mengembalikan draft payload.
- Endpoint validasi baru:
  - `GET /kader/fhir/{resourceType}/{id}/validate`
- Respons validasi berisi `valid`, `errors`, `warnings`, dan `payload`.
- `POST /kader/fhir/{resourceType}/{id}/send` tetap ada untuk kompatibilitas,
  tetapi bukan bagian dari target Fase 1 dan tidak boleh dianggap integrasi
  produksi.

## 11. Urutan file migration

Semua migration baru, tidak mengedit migration lama. Urutan wajib dijaga.

| Urutan | File | Isi | Catatan |
|---|---|---|---|
| 1 | `2026_11_14_000001_add_admin_role_to_users_table.php` | Ganti `users_role_check` agar menerima `admin`. | Down harus gagal bila masih ada user `admin`. |
| 2 | `2026_11_14_000002_add_social_media_columns_to_users_table.php` | Tambah `whatsapp`, `instagram`, `facebook`. | Nullable. |
| 3 | `2026_11_14_000003_add_ihs_number_to_children_table.php` | Tambah `children.ihs_number` unique nullable. | Index unique. |
| 4 | `2026_11_14_000004_add_visit_timing_and_edukasi_gizi_to_visits_table.php` | Tambah `visit_started_at`, `visit_ended_at`, `edukasi_gizi`. | Belum backfill. |
| 5 | `2026_11_14_000005_add_measured_at_to_measurements_table.php` | Tambah `measured_at`. | Belum backfill. |
| 6 | `2026_11_14_000006_add_fhir_terminology_to_immunization_types_table.php` | Tambah kolom KFA/CVX. | Nullable. |
| 7 | `2026_11_14_000007_add_red_flags_and_icd10_to_medical_notes_table.php` | Tambah `red_flags` JSONB dan `icd10_code`. | Check array JSON. |
| 8 | `2026_11_14_000008_backfill_visit_and_measurement_timestamps.php` | Backfill waktu dari tanggal + 00:00 Asia/Jakarta. | Idempoten; hanya isi yang null. |
| 9 | `2026_11_14_000009_allow_ktp_in_user_verifications_type.php` | Hapus CHECK constraint lama `user_verifications_type_check`. | Agar `ktp` diterima saat unggah ulang. |
| 10 | `2026_11_14_000010_allow_red_flags_as_medical_note_content.php` | Perbarui `medical_notes_isi_check`. | Red flag saja dianggap isi. |

### Aturan migration

- Jangan mengubah migration lama.
- Jangan menghapus kolom lama.
- Jangan mengubah response envelope API.
- Backfill harus idempoten.
- Gunakan `$table->timestampTz(...)->nullable()`, bukan `timestamp` tanpa zona.
- Backfill dapat memakai ekspresi `tanggal::timestamp AT TIME ZONE
  'Asia/Jakarta'`.
- Migration role harus `DROP CONSTRAINT IF EXISTS users_role_check` lalu
  membuat ulang constraint dengan nilai `ibu`, `kader`, dan `admin`.
- Migration harus aman dijalankan pada database kosong dan database berisi data.
- Down migration harus jelas; untuk role admin, down tidak boleh merusak data
  admin yang masih ada.
- Uji di `posyandu_test` sebelum database utama.

## 12. Struktur kode yang diusulkan

### Model

- `app/Models/User.php`
  - tambah `isAdmin()`.
  - pastikan `whatsapp`, `instagram`, `facebook` ada di `$fillable`.
- `app/Models/Child.php`
  - tambah `ihs_number` ke `$fillable`.
- `app/Models/Visit.php`
  - tambah `visit_started_at`, `visit_ended_at`, `edukasi_gizi`.
  - cast waktu ke `datetime`.
- `app/Models/Measurement.php`
  - tambah `measured_at`.
  - cast waktu ke `datetime`.
- `app/Models/ImmunizationType.php`
  - tambah kolom mapping ke `$fillable`.
- `app/Models/MedicalNote.php`
  - tambah `red_flags`, `icd10_code`.
  - cast `red_flags` ke `array`.

### Support

- `app/Support/SocialMediaNormalizer.php`
  - normalisasi WhatsApp, Instagram, Facebook.
- `app/Support/FhirDateTime.php`
  - konversi waktu ke UTC dan format ISO 8601.
- `app/Support/RedFlagCodes.php`
  - allowlist kode red flag.
- `app/Support/IhsNumber.php`
  - validasi format IHS setelah IG dikonfirmasi.

### Service

- `app/Services/ChildIhsImportService.php`
  - baca CSV, validasi baris, dry-run, chunk, laporan error.
- `app/Services/ChildIhsService.php`
  - edit manual IHS dan audit.
- `app/Services/Fhir/FhirPayloadValidator.php`
  - validasi payload Patient/Encounter/Observation/Immunization.
- `app/Services/Fhir/FhirPayloadBuilder.php`
  - orkestrasi pembuatan payload.
- `app/Services/SatusehatFhirService.php`
  - mapper existing diperbaiki; jangan menambah pengiriman produksi.

### HTTP

- `app/Http/Controllers/Api/Admin/ChildIhsImportController.php`
- `app/Http/Controllers/Api/Admin/ChildIhsController.php`
- `app/Http/Requests/Admin/ImportChildIhsRequest.php`
- `app/Http/Requests/Admin/UpdateChildIhsRequest.php`
- `app/Http/Requests/Profile/UpdateProfileRequest.php` bila validasi profil
  dipindahkan dari controller.
- `app/Http/Middleware/EnsureAdmin.php` atau alias `admin` yang memakai
  `RoleCheck`.

### Route

- Group `/admin` dengan middleware `auth:sanctum` dan role `admin`.
- Route kader yang ada tidak diubah.
- Endpoint validasi FHIR ditambahkan tanpa menghapus endpoint lama.
- Route `send` tetap ada untuk kompatibilitas, tetapi tidak dipakai di Fase 1.

### Test

- `tests/Feature/AdminChildIhsTest.php` — akses admin, koreksi IHS, audit,
  import CSV, dry-run, duplikat, koreksi eksplisit, template.
- `tests/Feature/ProfileSocialMediaTest.php` — normalisasi WhatsApp/Instagram/
  Facebook lewat endpoint profil.
- `tests/Unit/SocialMediaNormalizerTest.php` — variasi handle dan URL.
- `tests/Feature/RegistrationCompletionTest.php` — drop-off status dan unggah
  ulang KTP/KK.
- `tests/Feature/MedicalNoteRedFlagsTest.php` — red flags dan ICD-10.
- `tests/Feature/FhirTest.php` — mapper, IHS, KFA/CVX, Observation bundle,
  dan endpoint validasi.
- `tests/Feature/MigrationBackfillTest.php` — backfill waktu dan Z-Score tetap.

## 13. Kontrak API yang direncanakan

### Admin

| Method | Endpoint | Fungsi |
|---|---|---|
| `GET` | `/admin/children/ihs/template` | Unduh template CSV. |
| `POST` | `/admin/children/ihs/import` | Import CSV, mendukung dry-run. |
| `PATCH` | `/admin/children/{child}/ihs` | Koreksi IHS manual. |

Semua endpoint admin memakai envelope response yang sama:
`success`, `message`, `data`/`errors`.

### FHIR

| Method | Endpoint | Fungsi |
|---|---|---|
| `GET` | `/kader/fhir/{resourceType}/{id}` | Draft payload (tetap). |
| `GET` | `/kader/fhir/{resourceType}/{id}/validate` | Validasi payload. |
| `POST` | `/kader/fhir/{resourceType}/{id}/send` | Kompatibilitas; bukan target Fase 1. |
| `GET` | `/kader/fhir/Observation/{id}/bundle` | Bundle Observation: BB, TB, lingkar kepala, IMT. |
| `GET` | `/kader/fhir/Observation/{id}/bundle/validate` | Validasi seluruh Observation dalam bundle. |

## 14. Kriteria selesai Fase 1

- Semua migration berjalan di database kosong dan database berisi data.
- Backfill mengisi waktu dari tanggal yang ada dan tidak mengubah Z-Score.
- Role admin tidak bisa mendaftar sendiri.
- Admin dapat import CSV dan edit IHS manual.
- Kader tidak dapat mengubah IHS.
- Normalisasi sosial media lolos test untuk handle dan URL.
- Payload Patient/Encounter/Observation/Immunization tervalidasi.
- Tidak ada NIK yang dipakai sebagai ID resource.
- Tidak ada kode lokal yang dikirim sebagai CVX tanpa mapping.
- Test backend lama tetap lulus.
- Dokumentasi schema, ERD, dan rancangan ini konsisten.

## 15. Risiko dan mitigasi

| Risiko | Mitigasi |
|---|---|
| IHS duplikat | Unique index dan validasi import. |
| Data lama tidak punya tanggal | Biarkan null, jangan mengarang waktu. |
| Timezone salah | Simpan UTC, test konversi Asia/Jakarta. |
| Kode CVX salah | Mapping eksplisit, validasi, review tenaga kesehatan. |
| Admin role terlalu luas | Route `/admin` terbatas dan audit log. |
| Red flags tidak seragam | Allowlist terpusat dan dokumentasi. |
| Perubahan schema memutus API | Additive, test kompatibilitas, response envelope tetap. |
| Backfill mengunci tabel | Jalankan di luar jam sibuk, chunk, uji di test DB. |

## 16. Fase 2

- Otomatis API IHS setelah data anak dibuat.
- Queue, retry, idempotency, monitoring.
- `users.ihs_number` untuk RelatedPerson/Practitioner.
- `ServiceRequest`, `Consent`, `DocumentReference`.
- Notifikasi WhatsApp dengan opt-in dan template.
- ICD-10/SNOMED bila alur coding klinis sudah siap.
- Evaluasi `health_facilities` bila multi-Posyandu.

## 17. Referensi

- `docs/DATABASE_SCHEMA.md`
- `docs/ERD_POSYANDU.mermaid.md`
- `docs/API_CONTRACT.md`
- `docs/arsip/RANCANGAN_VISIT.md`
- `docs/arsip/RANCANGAN_BUKU_MEDIS.md`
- `docs/arsip/LAPORAN_MEDICAL_NOTES.md`
- `docs/arsip/RANCANGAN_IMUNISASI_JADWAL.md`
- HL7 FHIR R4: <https://hl7.org/fhir/R4/>
- SATUSEHAT FHIR R4 IG:
  <https://simplifier.net/guide/SATUSEHAT-FHIR-R4-Implementation-Guide>
- Permenkes No. 2 Tahun 2020:
  <https://jdih.kemkes.go.id/storage/documents/pdfs/2020permenkes002.pdf>
