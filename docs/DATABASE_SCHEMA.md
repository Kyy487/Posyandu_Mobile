# 🗄️ Database Schema (PostgreSQL)

Diverifikasi terhadap migration dan schema PostgreSQL aktual pada 14 November
2026. Sumber kebenaran tetap migration di
`posyandu-backend/database/migrations/`.

Rancangan perubahan Fase 1 yang sudah dikunci ada di
`docs/RANCANGAN_STANDARISASI.md`. Dokumen ini tetap mencerminkan schema aktual;
kolom yang belum ada ditandai sebagai rencana di bagian 9.

Proyek ini menggunakan UUID untuk hampir seluruh Primary Key dan relasi tabel.
Pengecualian: pivot `posyandu_schedule_petugas` memakai `bigint` autoincrement
karena dibuat dengan `$table->id()`.

## 1. `users` (Master Data)
Menyimpan autentikasi dan profil Ibu serta Kader. Tidak ada kolom `email`.

* `id` (UUID, PK)
* `nik` (Text, Nullable, terenkripsi AES-256-GCM via `$casts`)
* `nik_hash` (String 64, Nullable, **Unique**, **HMAC-SHA256** dengan
  `APP_KEY` — untuk lookup login dan pencegahan NIK ganda). Nilai lama SHA-256
  di-rehash oleh migration
  `2026_11_13_000005_rehash_nik_hash_with_hmac.php`. Migration
  `2026_11_13_000009_normalize_nik_encryption_format.php` juga menormalkan
  ciphertext lama (yang memakai serialisasi PHP) ke format `encryptString`
  agar `$user->nik` mengembalikan NIK asli. Kolom `nik` terenkripsi acak
  sehingga **tidak** bisa dipakai untuk unique.
* `no_kk` (Text, Nullable, terenkripsi AES-256-GCM via `$casts`) — nomor Kartu
  Keluarga. **Tidak unik** karena satu KK dipakai bersama oleh beberapa anggota
  keluarga. Enkripsi dan pelebaran kolom dilakukan migration
  `2026_11_13_000004_encrypt_no_kk_on_users_table.php`.
* `name`, `password`, `phone_number`, `jabatan`
* `role` (String, default `ibu`) — nilai aplikasi: `ibu`, `kader`.
  Rencana Fase 1: tambah `admin` sebagai role internal (lihat bagian 9).
* `status` (String, default `active`) — `pending` / `active` / `rejected`
* `onboarding_status` (String 20, default `need_child_data`, Index) —
  `need_child_data` / `completed`. Ditambahkan migration
  `2026_11_13_000001_...`; seluruh user lama di-backfill menjadi `completed`.
* `place_of_birth`, `date_of_birth`, `gender` (`L`/`P`), `address`
* `blood_type` (String 3, Nullable) — `A` / `B` / `AB` / `O`
* `rt_rw` (String 10, Nullable) — format seperti `001/002`
* `education` (String 20, Nullable) — `SD`/`SMP`/`SMA`/`SMK`/`D3`/`S1`/`S2`/`S3`/`other`
* `occupation` (String 100, Nullable)
* `approved_by` (UUID, FK -> users.id, Nullable, **set null**), `approved_at`,
  `rejection_reason`, `verified_at`
* `verification_status` (String 20, **generated stored**, Index) — turunan dari
  `status`: `pending` -> `pending`, `active` -> `approved`, `rejected` ->
  `rejected`. Dibuat migration
  `2026_11_13_000008_add_verification_status_generated_to_users.php`.
* `remember_token`, `timestamps`

**Index dan constraint:**

* Unique `nik_hash` (`users_nik_hash_unique`)
* Index `status`, `onboarding_status`, `verification_status`
* CHECK `users_onboarding_status_check`, `users_blood_type_check`,
  `users_education_check`, `users_rt_rw_check`
* FK `approved_by` memakai `ON DELETE SET NULL` agar riwayat persetujuan tidak
  ikut hilang saat akun kader dihapus.

> `nik_hash` memakai `APP_KEY` sebagai kunci HMAC. Jangan mengganti `APP_KEY`
> tanpa menghitung ulang seluruh `nik_hash`; jika tidak, login pengguna lama
> akan gagal. `nik_hash` tetap deterministik sehingga aman untuk unique index.

> `verification_status` adalah **kolom generated stored** dari `status`, jadi
> tidak ada dual-write dan nilainya tidak mungkin berbeda. Accessor
> `User::getVerificationStatusAttribute()` selalu menghitung dari `status` agar
> tidak mengembalikan nilai generated yang basi setelah approval, sementara
> kolomnya tetap tersedia untuk filter/reporting SQL. `next_action` tetap
> accessor, bukan kolom.

## 1.1 `user_verifications` (Dokumen Verifikasi Kader)

Migration `2026_10_24_032705_create_user_verifications_table.php`. Satu baris =
satu dokumen pendukung verifikasi akun kader. File disimpan di storage; tabel
ini hanya menyimpan metadata.

* `id` (UUID, PK)
* `user_id` (UUID, FK -> users.id, **cascade delete**, Index)
* `type` (String 255, default `other`) — `self_photo` / `ktp` / `kk` / `other`.
  Migration `2026_11_14_000009_allow_ktp_in_user_verifications_type.php`
  menghapus CHECK constraint lama yang belum mengenal `ktp`; validasi nilai
  tetap dilakukan di FormRequest.
* `file_path` (String 255) — path file di storage
* `file_name` (String 255, Nullable)
* `mime_type` (String 50, Nullable)
* `uploaded_at` (Timestamp, default `CURRENT_TIMESTAMP`)
* `timestamps`

**Index dan constraint:**

* Index `user_id` (`user_verifications_user_id_index`)
* FK `user_id` memakai `ON DELETE CASCADE`; dokumen tidak berguna tanpa akun.

## 2. `children` (Data Anak)
* `id` (UUID, PK)
* `user_id` (UUID, FK -> users.id) — acuan resmi relasi ibu
* `nik` (Text, Nullable, terenkripsi AES-256-GCM via `$casts`)
* `nik_hash` (String 64, Nullable, **Unique**, **HMAC-SHA256** dengan
  `APP_KEY` — untuk lookup dan pencegahan NIK ganda). Nilai lama SHA-256
  di-rehash oleh migration
  `2026_11_13_000005_rehash_nik_hash_with_hmac.php`.
* `name`, `gender` ('L', 'P'), `date_of_birth`
* `place_of_birth` (String 100, Nullable), `birth_place` (String 100, Nullable)
  — dua nama untuk field yang sama; service menyinkronkan keduanya.
* `birth_order` (Smallint, Nullable) — urutan kelahiran.
* `birth_weight` (Float, Nullable)
* `birth_height` (Float, **generated stored**, Nullable) — alias baca dari
  `birth_length`; tidak boleh ditulis dari aplikasi. Dibuat migration
  `2026_11_13_000007_make_birth_height_generated_on_children.php`.
* `birth_length` (Numeric(5,2), Nullable) — **nama kanonis** panjang lahir.
  Migration baru mem-backfill nilai dari `birth_height` untuk baris yang belum
  punya `birth_length`, lalu mengubah `birth_height` menjadi generated column.
* `birth_head_circumference` (Numeric(5,2), Nullable) — lingkar kepala lahir.
* `birth_status` (String 20, Nullable) — `normal` / `premature`.
* `buku_kia_id` (String 50, Nullable) — identitas Buku KIA.
* `medical_flags` (Text, Nullable) — kondisi khusus anak (alergi, penyakit
  bawaan), satu penanda per baris. Ditambahkan oleh migration
  `2026_09_29_010000_add_medical_flags_to_children_table.php`. Mobile membaca
  field ini lewat `Child.medicalFlags` dan `TimelineChild.medicalFlags` untuk
  badge di `detail_anak_screen.dart`.
* `timestamps`
* `deleted_at` (Timestamp, Nullable) — soft delete, ditambahkan oleh migration
  `2026_09_26_020000_add_deleted_at_to_children_table.php`

**Index dan constraint:**

* Unique `nik_hash` (`children_nik_hash_unique`)
* Index `deleted_at` (`children_deleted_at_index`) — mempercepat scope soft delete
* CHECK `children_birth_status_check`, `children_birth_order_check`
* `birth_height` adalah generated column dari `birth_length`
* FK `user_id` memakai `ON DELETE CASCADE`


> ⚠️ **Kenapa soft delete?** `measurements.child_id` dan
> `immunization_records.child_id` memakai `ON DELETE CASCADE`. Hard delete pada anak
> akan ikut menghapus seluruh riwayat penimbangan dan imunisasi — data kesehatan yang
> tidak boleh hilang diam-diam. Karena itu `Child` memakai trait `SoftDeletes`.
>
> NIK anak tetap unik **termasuk** baris yang sudah di-soft delete, agar NIK tidak
> pernah dipakai ulang oleh anak yang berbeda.

> ⚠️ **Kenapa `medical_flags` satu kolom, bukan tabel `child_medical_flags`?**
> Untuk MVP, most Posyandu menulis penanda sekali dan jarang mengubahnya. Tabel
> terpisah baru layak kalau nanti ada pertanyaan "alergi ini sejak kapan" atau
> lebih dari satu jenis penanda per anak yang perlu dilacak sejarahnya.
>
> Konsekuensinya: **tidak ada riwayat perubahan penanda**, isinya **tidak
> diparsing** (Kader dan Ibu membaca nilai yang sama apa adanya), dan **tidak ada
> CHECK constraint** — batas 500 karakter divalidasi di `ChildController@update`
> supaya kesalahan ketik jadi 422 yang bisa dibaca, bukan error PostgreSQL.
> Keputusan lengkapnya ada di `docs/arsip/RANCANGAN_BUKU_MEDIS.md` bagian 5.1.

## 3. `measurements` (e-KMS / Riwayat Tumbuh Kembang)

Migration `2026_09_27_020000_prepare_measurements_for_recap.php` menyiapkan
tabel ini untuk rekap bulanan (Opsi E). Opsi D (grafik tumbuh kembang) hanya
membaca tabel ini. Kolom indikator WHO multidimensi ditambahkan P0-2 (10 Oktober
2026) dan perluasan grafik multidimensi (15 Oktober 2026), lihat di bawah.

* `id` (UUID, PK)
* `child_id` (UUID, FK -> children.id, **cascade delete**)
* `kader_id` (UUID, FK -> users.id, nullable, **set null**) — nullable + `ON
  DELETE SET NULL` supaya riwayat penimbangan tetap utuh walau akun kader
  dihapus. Nilai `NULL` berarti "kader tidak diketahui", bukan "riwayat hilang".
* `visit_id` (UUID, FK -> visits.id, nullable, **set null**) — kunjungan tempat
  penimbangan dicatat. Ditambahkan migration
  `2026_10_11_233501_add_visit_id_to_measurements_table.php` (P0-1). `NULL`
  berarti penimbangan tidak terkait kunjungan (alur lama tetap sah).
* `measurement_date` (Date)
* `weight_kg`, `height_cm`, `head_circumference_cm` (Decimal)
* `age_in_months` (Int), `z_score_wfa` (Decimal), `status_gizi` (String) — BB/U.
  `status_gizi` **khusus BB/U**, bukan status komposit terburuk (dipulihkan
  migration `2026_10_12_000000_restore_wfa_only_status_gizi_trigger.php`).
* `z_score_hfa` (Decimal, Nullable), `status_stunting` (String 20, Nullable) —
  TB/U. Ditambahkan migration
  `2026_10_10_104713_add_who_multidim_columns_to_measurements.php`
* `z_score_bfa` (Decimal, Nullable), `status_gizi_imt` (String 30, Nullable) —
  IMT/U. Migration yang sama
* `z_score_wfh` (Decimal, Nullable) — BB/TB (`< 24` bulan, indeks `length_cm`).
  Ditambahkan migration `2026_10_10_112842_create_who_wfh_standards_table.php`
* `status_wfh` (String 20, Nullable) — status BB/TB. Ditambahkan migration
  `2026_10_15_052851_add_status_wfh_to_measurements_and_trigger.php` (Opsi A)
* `deleted_at` (Timestamp, nullable) — soft delete
* `created_at`, `updated_at`

Semua kolom turunan (`age_in_months`, `z_score_*`, `status_*`) diisi trigger
`calculate_measurement_who_zscore`: dikosongkan lebih dulu, lalu hanya diisi
bila acuan WHO yang cocok ditemukan. Di luar rentang (mis. umur > 60 bulan, atau
BB/TB untuk umur ≥ 24 bulan), nilainya `NULL` — bukan `"Normal"`.

**Index dan constraint:**

* **Partial unique** `(child_id, measurement_date) WHERE deleted_at IS NULL` —
  satu anak satu penimbangan per tanggal, tapi penimbangan yang dibatalkan
  tidak menghalangi pencatatan ulang tanggal yang sama
* Index `(deleted_at, measurement_date)` — Serving rekap bulanan. Diuji dengan
  36.000 baris: tanpa index `Seq Scan` 2.132 ms, dengan index 0,245 ms
* Index `(kader_id)` — melayani lookup FK `ON DELETE SET NULL`
* Index `(visit_id)` — melayani lookup kunjungan dan FK `ON DELETE SET NULL`
* **Tidak** ada index `status_gizi`; planner tidak memakainya, jadi dibuang

> **Kenapa soft delete?** Tanpa itu, satu anak bisa punya dua penimbangan pada
> tanggal yang sama begitu ada pembatalan dan pencatatan ulang, dan rekap
> bulanan tidak bisa menentukan mana yang berlaku. `deleted_at` +
> partial unique index menyelesaikan keduanya sekaligus.

## 4. `who_wfa_standards` (Referensi Z-Score WHO BB/U)
Tabel acuan perhitungan Z-Score berat badan menurut umur. Dihasilkan oleh migration
`2026_09_26_010000_create_who_wfa_standards_and_fix_zscore_trigger.php`.
* `id` (UUID, PK)
* `age_in_months` (Int) — 0 sampai 60
* `gender` (Char(1): 'L', 'P')
* `median_kg` (Decimal), `sd_kg` (Decimal)
* Unique `(age_in_months, gender)` — 122 baris (61 usia × 2 jenis kelamin)

`lower_kg` dan `upper_kg` diturunkan dari `median_kg` dan `sd_kg` di SQL saat
query, bukan disimpan sebagai kolom.

Tabel acuan WHO lain (semua ditambahkan P0-2, 10 Oktober 2026):

* `who_hfa_standards` — TB/U, kolom `age_in_months`, `gender`, `l`, `m`, `s`;
  unique `(age_in_months, gender)`. Migration
  `2026_10_10_104330_create_who_hfa_standards_table.php`.
* `who_bfa_standards` — IMT/U, bentuk sama dengan HFA. Migration
  `2026_10_10_104404_create_who_bfa_standards_table.php`.
* `who_wfh_standards` — BB/TB, diindeks `length_cm` (bukan umur), kolom `l`,
  `m`, `s`; unique `(length_cm, gender)`. Migration
  `2026_10_10_112842_create_who_wfh_standards_table.php`.

Pita TB/U dan IMT/U dihitung dari `(l, m, s)` dengan rumus inverse LMS WHO di
SQL (bukan disimpan sebagai kolom), dan grafis multidimensi membacanya lewat
satu `UNION ALL` bersama BB/U. Lihat `docs/arsip/RANCANGAN_WHO_MULTIDIM.md` bagian
4.4–4.6.

## 4.1 `immunization_types` (Master Dosis Imunisasi)

Migration `2026_09_26_031000_create_immunization_types_table.php`. Satu baris =
satu dosis. Ini **data referensi** program nasional yang dibaca seluruh anak
untuk menyusun checklist; tidak ada data anak di tabel ini.

* `id` (UUID, PK)
* `code` (String 20) — mis. `HB`, `BCG`, `POLIO`, `DPT-HB-HIB`, `MR`, `IPV`,
  `ROTAVIRUS`, `PCV`, `JE`
* `name` (String)
* `dose_number` (Smallint, default 1)
* `target_age_months` (Smallint, nullable) — usia target dalam bulan; `0` = saat lahir
* `interval_months` (Smallint, nullable) — jarak dari dosis sebelumnya. Hanya
  dikirim ke klien untuk tampilan; **tidak** dipakai server untuk validasi
  tanggal (validasi membandingkan tanggal dosis tetangga yang benar-benar dicatat)
* `notes` (Text, nullable)
* `is_active` (Boolean, default `true`) — ditambahkan migration
  `2026_10_12_011440_add_is_active_to_immunization_types_table.php`
* `timestamps`
* Unique `(code, dose_number)` (`immunization_types_code_dose_unique`)

**Kenapa `is_active`, bukan `DELETE`?** `immunization_records.immunization_type_id`
memakai `restrictOnDelete` (lihat bagian 5), sehingga menghapus baris master yang
sudah dipakai akan gagal. Karena itu dosis yang sudah tidak dipakai (mis. jadwal
lama berganti) di-`is_active = false`, bukan dihapus. Checklist, rekap, dan
`GET /immunization-types` hanya membaca dosis aktif (scope
`ImmunizationType::active()`), sementara catatan lama tetap utuh. Seeder master
mengikuti kebijakan ini (lihat `DatabaseSeeder::seedImmunizationTypes()`).

> Jadwal master terkini (jumlah dosis dan target usia) ada di
> `docs/API_CONTRACT.md` bagian `GET /immunization-types`.

## 5. `immunization_records`
* `id` (UUID, PK)
* `child_id` (UUID, FK -> children.id)
* `visit_id` (UUID, FK -> visits.id, nullable, **set null**) — kunjungan tempat
  suntikan dicatat. Migration
  `2026_10_11_233502_add_visit_id_to_immunization_records_table.php` (P0-1).
* `immunization_type_id` (UUID, FK -> immunization_types.id, **restrict on delete**)
* `kader_id` (UUID, FK -> users.id, ON DELETE SET NULL, nullable)
* `date_given` (Date)
* `batch_number` (String, nullable), `notes` (Text, nullable)
* `deleted_at` + partial unique `(child_id, immunization_type_id)`

## 5.1 `medical_notes` (Catatan Keluhan Kader — Opsi C)

Migration `2026_09_27_010000_create_medical_notes_table.php`. Satu anak punya
**satu baris per tanggal**.

* `id` (UUID, PK)
* `child_id` (UUID, FK -> children.id, **cascade delete**)
* `measurement_id` (UUID, FK -> measurements.id, nullable, **set null**) — boleh kosong karena keluhan bisa dicatat tanpa menimbang. Lihat catatan penting di bawah soal soft delete.
* `visit_id` (UUID, FK -> visits.id, nullable, **set null**) — kunjungan tempat
  keluhan dicatat. Migration
  `2026_10_11_233503_add_visit_id_to_medical_notes_table.php` (P0-1).
* `kader_id` (UUID, FK -> users.id, nullable, **set null**) — nullable agar catatan lama tetap utuh walau akun kader dihapus
* `note_date` (Date)
* `demam`, `rewel`, `diare` (Boolean, default `false`)
* `catatan` (Text, nullable)
* `tindak_lanjut` (String(20), nullable) — enum `ringan` / `sedang` / `rujuk`
* `deleted_at` (Timestamp, nullable) — soft delete
* `created_at`, `updated_at`

**Index dan constraint:**

* Index biasa `(child_id, note_date)`
* Index `(visit_id)` — melayani lookup kunjungan dan FK `ON DELETE SET NULL`
* **Partial unique** `(child_id, note_date) WHERE deleted_at IS NULL` — satu
  anak satu catatan per tanggal, tapi catatan yang sudah dibatalkan tidak
  menghalangi pencatatan ulang tanggal yang sama
* CHECK `tindak_lanjut IN ('ringan','sedang','rujuk')` bila tidak null
* CHECK isi: minimal satu dari `demam`/`rewel`/`diare` true, **atau** `catatan`
  tidak kosong. Ini mencegah baris kosong tanpa perlu memvalidasi di aplikasi

> Keluhan disimpan sebagai **tiga kolom boolean terpisah**, bukan array/string
> dan bukan satu baris per keluhan, supaya rekap bulanan nanti bisa dijawab
> dengan satu aggregate yang memakai index. Lihat penjelasan di
> `docs/API_CONTRACT.md` bagian Catatan Keluhan.

> **PENTING - perilaku `measurement_id` berubah.** Tabel `measurements`
> sekarang memakai soft delete, jadi pembatalan penimbangan tidak lagi
> menghapus barisnya. Akibatnya FK `ON DELETE SET NULL` **tidak** menyala dan
> `medical_notes.measurement_id` **tetap** menunjuk penimbangan yang sudah
> dibatalkan. Sebelum itu, nilainya jadi `null`.
>
> Ini disengaja: "keluhan ini dicatat saat penimbangan 18 Sep, yang lalu
> dibatalkan" lebih berguna untuk audit daripada tautan yang hilang, dan
> Mobile hanya memakai `measurement_id` sebagai field opsional. Yang tetap
> dijamin adalah isi catatan tidak ikut terhapus.
>
> FK-nya sendiri tidak dihapus, jadi penghapusan fisik (`forceDelete`) tetap
> melepas tautan seperti biasa. Kalau suatu saat tautan perlu dilepas saat
> pembatalan, itu harus dilakukan eksplisit — bukan diharapkan dari efek
> samping `delete()`.

## 5.2 `visits` (Kunjungan Layanan — P0-1)

Migration `2026_10_11_233500_create_visits_table.php`. Satu kunjungan
merepresentasikan **satu sesi layanan** untuk satu anak dan menjadi payung bagi
pengukuran, imunisasi, dan keluhan yang terjadi di dalamnya. Spesifikasi penuh
ada di `docs/arsip/RANCANGAN_VISIT.md`.

* `id` (UUID, PK)
* `child_id` (UUID, FK -> children.id, **cascade delete**)
* `schedule_id` (UUID, FK -> posyandu_schedules.id, nullable, **set null**) —
  agenda posyandu bila kunjungan terjadi pada sesi terjadwal
* `visit_date` (Date)
* `visit_type` (String(20)) — `posyandu` / `kunjungan_rumah` / `rujukan`
* `kader_id` (UUID, FK -> users.id, nullable, **set null**) — nullable agar
  riwayat kunjungan tetap utuh walau akun kader dihapus
* `anamnesis` (Text, nullable) — keluhan utama
* `catatan_kader` (Text, nullable)
* `deleted_at` (Timestamp, nullable) — soft delete
* `created_at`, `updated_at`

**Index dan constraint:**

* Index `(child_id, visit_date)` (`visits_child_date_index`) — melayani daftar
  kunjungan per anak per periode
* CHECK `visit_type IN ('posyandu','kunjungan_rumah','rujukan')`
  (`visits_visit_type_check`)

> **Tidak ada unique `(child_id, visit_date)`.** Satu anak boleh punya lebih
> dari satu kunjungan di tanggal yang sama (mis. posyandu pagi lalu kunjungan
> rumah sore). Keputusan ini sudah ditutup di `docs/arsip/RANCANGAN_VISIT.md` §7.1.
>
> **`visit_type` memakai string + CHECK, bukan enum PostgreSQL**, konsisten
> dengan `medical_notes.tindak_lanjut` dan `posyandu_schedules.status`. Menambah
> tipe baru cukup migration biasa.
>
> **Backfill.** Penimbangan lama yang belum punya `visit_id` dibuatkan satu
> kunjungan "legacy" per `(anak, tanggal)` oleh migration
> `2026_10_11_233504_backfill_legacy_visits_for_measurements.php`
> (keputusan §7.3). Migration ini tidak melakukan apa pun di driver non-pgsql.

## 5.3 `audit_logs` (Riwayat Audit)

Migration `2026_10_12_013352_create_audit_logs_table.php`. Satu baris = satu
perubahan yang dilakukan aplikasi pada entitas audited (`Child`, `Visit`,
`Measurement`, `ImmunizationRecord`, `MedicalNote`).

* `id` (UUID, PK)
* `auditable_type` (String) — class model, mis. `App\Models\Child`
* `auditable_id` (UUID) — primary key entitas yang diubah
* `event` (String 20) — `created` / `updated` / `deleted` / `restored`
* `actor_id` (UUID, FK -> users.id, nullable, **set null**) — pelaku perubahan;
  null bila dilakukan sistem (seeder, backfill)
* `old_values` (JSONB, nullable) — nilai sebelum perubahan
* `new_values` (JSONB, nullable) — nilai sesudah perubahan
* `ip_address` (String 45, nullable) — alamat IP asal permintaan
* `timestamps`

**Index dan constraint:**

* Index `(auditable_type, auditable_id)` — riwayat per entitas
* Index `(created_at)` — urut kronologis
* Index `(actor_id)` — riwayat per pelaku
* CHECK `event IN ('created','updated','deleted','restored')`

> **Tidak ada penghapusan riwayat.** Baris audit tidak bisa dihapus lewat API.
> Riwayat hanya bertambah.

## 5.4 `consents` (Persetujuan UU PDP)

Migration `2026_10_13_000003_create_consents_table.php`. Satu baris = satu
persetujuan (consent) untuk satu anak dan satu `consent_type`. Wajib diisi saat
pendaftaran anak (`ChildController@store`).

* `id` (UUID, PK)
* `child_id` (UUID, FK -> children.id, **cascade**)
* `granted_by` (UUID, FK -> users.id, **cascade**) — Ibu/wali yang memberi persetujuan
* `consent_type` (String 20) — `data_processing` / `data_sharing` / `research`
* `granted_at` (Timestamp) — kapan persetujuan diberikan
* `revoked_at` (Timestamp, nullable) — diisi saat consent dicabut; `null` = aktif
* `document_version` (String 20) — versi formulir consent yang disetujui
* `notes` (Text, nullable)
* `timestamps`

**Index dan constraint:**

* Unique `(child_id, consent_type)` — satu baris per tipe consent per anak;
  memberi ulang consent yang sudah dicabut memakai ulang baris yang sama
  (reset `revoked_at`), bukan membuat baris baru.

> **Pencabutan tidak menghapus baris.** `DELETE` mengisi `revoked_at`, sehingga
> jejak persetujuan tetap tersimpan untuk audit (audit trail menyusul lewat
> `audit_logs`).

## 5.5 `referrals` (Rujukan ke Fasilitas Kesehatan)

Migration `2026_10_13_152047_create_referrals_table.php`. Satu baris = satu
rujukan anak ke fasilitas kesehatan, selalu terhubung ke satu kunjungan
(`visit_id`) dan satu anak (`child_id`). Lihat `docs/arsip/RANCANGAN_RUJUKAN.md`.

* `id` (UUID, PK)
* `visit_id` (UUID, FK -> visits.id, **cascade**) — rujukan adalah bagian satu kunjungan
* `child_id` (UUID, FK -> children.id, **cascade**)
* `referral_date` (Date) — boleh berbeda dari `visits.visit_date`
* `referral_type` (String 20) — `puskesmas` / `rs` / `faskes_lain`
* `reason` (Text) — alasan rujukan
* `facility_name` (String 255) — nama fasilitas tujuan
* `status` (String 20) — `dibuat` / `dilaporkan` / `selesai`
* `kader_id` (UUID, FK -> users.id, nullable, **set null**) — pencatat; null bila akun dihapus
* `created_at`, `updated_at`
* `deleted_at` (Timestamp, nullable) — soft delete

**Index dan constraint:**

* Index `(child_id, referral_date)` (`referrals_child_date_index`) — daftar rujukan satu anak per periode
* CHECK `referral_type IN ('puskesmas','rs','faskes_lain')` (`referrals_referral_type_check`)
* CHECK `status IN ('dibuat','dilaporkan','selesai')` (`referrals_status_check`)

> **Pembatalan tidak menghapus baris.** `DELETE /referrals/{id}` mengisi
> `deleted_at`, sehingga tindak lanjut tetap tersimpan untuk audit.

## 5.6 `posyandu_schedules` (Agenda Posyandu)

Migration `2026_09_26_033000_create_posyandu_schedules_table.php`. Satu baris =
satu **acara** posyandu (mis. penimbangan rutin, imunisasi, kunjungan rumah),
bukan jadwal per anak.

* `id` (UUID, PK)
* `title` (String 255)
* `description` (Text, Nullable)
* `scheduled_date` (Date)
* `start_time`, `end_time` (Time, Nullable)
* `location` (String 160, Nullable) — nama lokasi acara; bila kosong, API
  memakai `config('posyandu.posyandu_name')` lewat accessor, bukan kolom
  `location_name`
* `status` (String 20, default `terjadwal`) — `terjadwal` / `berlangsung` /
  `selesai` / `dibatalkan`
* `notes` (Text, Nullable)
* `created_by` (UUID, FK -> users.id, Nullable, **set null**)
* `timestamps`

**Index dan constraint:**

* Index `(scheduled_date, status)` (`posyandu_schedules_scheduled_date_status_index`)
* CHECK `posyandu_schedules_status_check`

## 5.7 `posyandu_schedule_petugas` (Pivot Petugas Agenda)

Migration `2026_09_26_034000_create_posyandu_schedule_petugas_table.php`. Pivot
many-to-many antara agenda dan petugas (kader/bidan).

* `id` (Bigint, PK, autoincrement) — **satu-satunya tabel dengan PK non-UUID**
* `schedule_id` (UUID, FK -> posyandu_schedules.id, **cascade delete**)
* `petugas_id` (UUID, FK -> users.id, **cascade delete**)
* `timestamps`

**Index dan constraint:**

* Unique `(schedule_id, petugas_id)` (`schedule_petugas_unique`)
* Index `petugas_id` (`posyandu_schedule_petugas_petugas_id_index`)
* Kedua FK memakai `ON DELETE CASCADE`.

## 6. `spatial_zones` (Pemetaan - PostGIS) *Coming Soon*
* `id` (UUID, PK), `child_id` (UUID, FK)
* `coordinate` (Geometry/Point)
* `risk_level` (String)

## 7. Objek Database (Function & Trigger)
Objek berikut dibuat oleh migration yang sama dan **tidak** diubah oleh migration berikutnya.
* Function `calculate_measurement_who_zscore()` — menghitung `age_in_months`, `z_score_wfa`, dan `status_gizi` secara SQL murni.
* Trigger `trg_measurements_who_zscore` — `BEFORE INSERT OR UPDATE` pada `measurements`, sehingga revisi data otomatis di-recalc.

> Detail perhitungan, klasifikasi status, dan cara rollback ada di
> `docs/arsip/LAPORAN_ZSCORE_TRIGGER.md`.

## 8. Pemetaan Standar FHIR R4/SATUSEHAT dan Posyandu/Kemenkes

Bagian ini adalah **gap analysis dokumentatif**, bukan schema yang sudah
diimplementasikan. Jangan menambah kolom hanya berdasarkan tabel di bagian ini
tanpa migration baru dan persetujuan scope.

### 8.1 Acuan

* HL7 FHIR R4: <https://hl7.org/fhir/R4/>
* SATUSEHAT FHIR R4 Implementation Guide:
  <https://simplifier.net/guide/SATUSEHAT-FHIR-R4-Implementation-Guide>
* Permenkes No. 2 Tahun 2020 tentang Standar Antropometri Anak:
  <https://jdih.kemkes.go.id/storage/documents/pdfs/2020permenkes002.pdf>
* WHO Child Growth Standards (0–5 tahun) dan WHO Growth Reference (5–18 tahun)
* SATUSEHAT memakai **IHS number** sebagai referensi resource, bukan NIK.
  Identifier NIK memakai system `https://fhir.kemkes.go.id/id/nik`; IHS number
  pasien memakai `https://fhir.kemkes.go.id/id/patient-ihs-number`.
* Waktu SATUSEHAT memakai format UTC+00. Tanggal lokal tanpa zona waktu tidak
  cukup untuk `effectiveDateTime`, `occurrenceDateTime`, atau `Encounter.period`.

### 8.2 Ringkasan pemetaan resource

Status: **sebagian** = mapper ada tetapi belum sesuai IG; **belum** = belum ada
mapper.

| Entitas lokal | Resource FHIR R4 | Status | Catatan utama |
|---|---|---|---|
| `children` | `Patient` | sebagian | Identifier memakai system NIK yang salah; belum ada IHS number, address, telecom, contact, dan `meta.profile` SATUSEHAT. |
| `users` (ibu/wali) | `RelatedPerson` + `Patient` bila ibu juga pasien | belum | Perlu relasi `MTH`/`FTH`, IHS number, dan keputusan apakah ibu dibuat sebagai `Patient` terpisah. |
| `users` (kader/bidan) | `Practitioner` + `PractitionerRole` | belum | Perlu IHS number dan organisasi/posyandu. |
| `visits` | `Encounter` | sebagian | `status` selalu `finished`; belum ada `period.end`, `participant`, `location`, `serviceProvider`, dan diagnosis. |
| `measurements` | beberapa `Observation` | sebagian | Mapper hanya mengirim tinggi (`8302-2`); belum BB (`29463-7`), lingkar kepala (`9843-4`), IMT (`39156-5`), kategori, interpretasi, dan z-score. |
| `immunization_records` + `immunization_types` | `Immunization` | sebagian | `vaccineCode` memakai kode lokal di system CVX; belum ada KFA, CVX group/name, performer, protocolApplied, reasonCode, dan `recorded`. |
| `medical_notes` | `Condition` / `Observation` / `CarePlan` | belum | Perlu terminologi klinis (ICD-10/SNOMED CT/LOINC) dan keputusan resource per jenis catatan. |
| `referrals` | `ServiceRequest` (+ `Task`/`Encounter`) | belum | `facility_name` masih teks bebas; perlu referensi `Organization`/`Location`. Di FHIR R4 tidak ada `ReferralRequest` (itu R3). |
| `consents` | `Consent` | belum | Perlu mapping `consent_type` ke `scope`/`category`, policy, dan provision. |
| `user_verifications` | `DocumentReference` | belum | Dokumen KTP/KK/foto diri; subject ke `Patient`/`RelatedPerson`. |
| `audit_logs` | `AuditEvent` / `Provenance` | belum | Audit internal; pemetaan opsional dan perlu kebijakan retensi. |
| `posyandu_schedules` | `Appointment` / `HealthcareService` / `Location` | belum | Perlu keputusan: agenda acara atau appointment per pasien. |
| `who_*_standards` | tidak dipetakan | internal | Data acuan perhitungan, bukan resource FHIR. |

### 8.3 Keputusan Fase 1

Keputusan lengkap dan urutan migration ada di
`docs/RANCANGAN_STANDARISASI.md`. Ringkasnya:

1. **IHS number.** Fase 1 hanya `children.ihs_number`. IHS untuk ibu/kader
   (`users.ihs_number`) ditunda sampai `RelatedPerson`/`Practitioner` masuk
   scope. Jangan memakai NIK sebagai ID resource.
2. **Mapping imunisasi.** Tambah kolom eksplisit di `immunization_types`:
   `kfa_code`, `cvx_code`, `cvx_display`, `cvx_group_code` bila perlu, dan
   `target_disease_code` opsional. Tidak memakai tabel mapping generik. Kode
   lokal `HB`, `BCG`, `POLIO`, `DPT-HB-HIB`, `MR` tidak valid sebagai CVX.
3. **Waktu pengukuran/kunjungan.** Tambah `measured_at`,
   `visit_started_at`, dan `visit_ended_at` bertipe `timestamptz`. Simpan UTC;
   UI memakai Asia/Jakarta. Data lama di-backfill dari tanggal + 00:00
   Asia/Jakarta; data tanpa tanggal tetap null.
4. **Fasilitas rujukan.** Tabel `health_facilities` dan ID fasilitas ditunda.
   Fase 1 memakai satu konfigurasi Posyandu. `facility_name` tetap teks.
5. **Alamat pasien.** Fase 1 tidak menambah kolom alamat anak.
   `Patient.address` memakai alamat ibu/wali sampai ada keputusan terpisah.
6. **Catatan medis.** Tambah `medical_notes.red_flags` JSONB dengan allowlist
   aplikasi dan `medical_notes.icd10_code` nullable sebagai persiapan. ICD-10/
   SNOMED tidak wajib. Jangan mengarang kode LOINC untuk z-score/status gizi.
7. **Sosial media.** Tambah `users.whatsapp`, `users.instagram`, dan
   `users.facebook`; simpan handle bersih dan normalisasi di service.
8. **Di luar scope.** LILA, kehamilan/ANC, persalinan, KB, vitamin A, obat
   cacing, dan PMT tidak dimodelkan di Fase 1.
9. **Batasan WHO.** Data WHO 0-60 bulan dan BB/TB hanya <24 bulan tetap
   menjadi batasan yang diketahui; perluasan data acuan bukan bagian Fase 1.

### 8.4 Kepatuhan standar Posyandu/Kemenkes

| Cakupan standar | Status data saat ini | Catatan |
|---|---|---|
| Identitas anak (NIK, KK, lahir) | sudah | NIK/KK terenkripsi; `birth_length` kanonis, `birth_height` generated. |
| Antropometri BB/U, PB/U atau TB/U, BB/PB atau BB/TB, IMT/U | sebagian | BB/U, TB/U, IMT/U ada; BB/TB hanya <24 bulan. |
| Imunisasi rutin | sebagian | Master dosis dan riwayat ada; mapping KFA/CVX belum. |
| Buku KIA | sebagian | `buku_kia_id` ada; isi Buku KIA belum dimodelkan. |
| Rujukan | sebagian | Tabel rujukan ada; tujuan masih teks bebas. |
| Jadwal Posyandu | sudah | Agenda dan petugas sudah dimodelkan. |
| Persetujuan UU PDP | sudah | `consents` ada. |
| Kesehatan ibu hamil/ANC, KB, gizi ibu | belum | Di luar schema saat ini; perlu keputusan scope. |

### 8.5 Aturan perubahan

* Jangan mengubah tipe/nama kolom lama hanya untuk menyesuaikan FHIR.
* Perubahan schema harus lewat migration baru, bukan edit migration lama.
* Jangan mengirim NIK sebagai resource ID SATUSEHAT; simpan IHS number secara
  eksplisit.
* Jangan memakai kode lokal sebagai kode terminologi standar tanpa mapping.
* Field baru harus additive dan tidak mengubah response envelope API lama.

## 9. Rencana Perubahan Fase 1 (Terkunci, Belum Diterapkan)

Rancangan lengkap, alasan, dan struktur kode ada di
`docs/RANCANGAN_STANDARISASI.md`. Ringkasan kolom yang akan ditambahkan:

| Tabel | Kolom | Tipe | Nullable | Catatan |
|---|---|---|---|---|
| `users` | `role` constraint | check | tidak | Nilai menjadi `ibu`, `kader`, `admin`. |
| `users` | `whatsapp` | varchar(20) | ya | E.164. |
| `users` | `instagram` | varchar(50) | ya | Handle tanpa `@`. |
| `users` | `facebook` | varchar(100) | ya | Handle tanpa URL. |
| `children` | `ihs_number` | varchar(50) | ya | Unique; diisi admin dulu. |
| `visits` | `visit_started_at` | timestamptz | ya | Backfill dari `visit_date` + 00:00 Asia/Jakarta. |
| `visits` | `visit_ended_at` | timestamptz | ya | Null bila durasi tidak diketahui. |
| `visits` | `edukasi_gizi` | text | ya | Edukasi saat kunjungan. |
| `measurements` | `measured_at` | timestamptz | ya | Backfill dari `measurement_date` + 00:00 Asia/Jakarta. |
| `immunization_types` | `kfa_code` | varchar(50) | ya | Kode produk KFA. |
| `immunization_types` | `cvx_code` | varchar(20) | ya | Kode CVX. |
| `immunization_types` | `cvx_display` | varchar(255) | ya | Nama CVX. |
| `immunization_types` | `cvx_group_code` | varchar(20) | ya | Bila IG membutuhkan. |
| `immunization_types` | `target_disease_code` | varchar(20) | ya | Opsional. |
| `medical_notes` | `red_flags` | jsonb | ya | Array kode allowlist aplikasi. |
| `medical_notes` | `icd10_code` | varchar(10) | ya | Persiapan, tidak wajib. |

Urutan migration Fase 1:

1. `2026_11_14_000001_add_admin_role_to_users_table.php`
2. `2026_11_14_000002_add_social_media_columns_to_users_table.php`
3. `2026_11_14_000003_add_ihs_number_to_children_table.php`
4. `2026_11_14_000004_add_visit_timing_and_edukasi_gizi_to_visits_table.php`
5. `2026_11_14_000005_add_measured_at_to_measurements_table.php`
6. `2026_11_14_000006_add_fhir_terminology_to_immunization_types_table.php`
7. `2026_11_14_000007_add_red_flags_and_icd10_to_medical_notes_table.php`
8. `2026_11_14_000008_backfill_visit_and_measurement_timestamps.php`
9. `2026_11_14_000009_allow_ktp_in_user_verifications_type.php`
10. `2026_11_14_000010_allow_red_flags_as_medical_note_content.php`

Catatan:

* Tidak ada tabel baru di Fase 1.
* `timestamptz` disimpan UTC; UI menampilkan Asia/Jakarta.
* Backfill tidak mengubah logika Z-Score.
* `children.ihs_number` hanya untuk anak; `users.ihs_number` ditunda.
* Role `admin` dibuat internal, tidak lewat `POST /register`.
* `user_verifications.type` menerima `ktp`; constraint lama dihapus karena
  dibuat oleh `$table->enum()` sebelum alur unggah ulang KTP ada.
* `medical_notes_isi_check` menganggap `red_flags` tidak kosong sebagai isi
  catatan, sehingga catatan red-flag saja tidak ditolak database.
