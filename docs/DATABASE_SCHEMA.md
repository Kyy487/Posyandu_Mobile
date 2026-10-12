# 🗄️ Database Schema (PostgreSQL)

Proyek ini menggunakan UUID untuk seluruh Primary Key dan relasi tabel.

## 1. `users` (Master Data)
Menyimpan autentikasi Ibu dan Kader.
* `id` (UUID, PK)
* `nik` (String 16, Unique)
* `name`, `email`, `password`, `phone_number`
* `role` (Enum: 'ibu', 'kader')

## 2. `children` (Data Anak)
* `id` (UUID, PK)
* `user_id` (UUID, FK -> users.id) — acuan resmi relasi ibu
* `nik` (String 16, Unique, Nullable)
* `name`, `gender` ('L', 'P'), `date_of_birth`
* `birth_weight` (Float), `birth_height` (Float)
* `medical_flags` (Text, Nullable) — kondisi khusus anak (alergi, penyakit
  bawaan), satu penanda per baris. Ditambahkan oleh migration
  `2026_09_29_010000_add_medical_flags_to_children_table.php`. Mobile membaca
  field ini lewat `Child.medicalFlags` dan `TimelineChild.medicalFlags` untuk
  badge di `detail_anak_screen.dart`.
* `timestamps`
* `deleted_at` (Timestamp, Nullable) — soft delete, ditambahkan oleh migration
  `2026_09_26_020000_add_deleted_at_to_children_table.php`

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
> Keputusan lengkapnya ada di `docs/RANCANGAN_BUKU_MEDIS.md` bagian 5.1.

## 3. `measurements` (e-KMS / Riwayat Tumbuh Kembang)

Migration `2026_09_27_020000_prepare_measurements_for_recap.php` menyiapkan
tabel ini untuk rekap bulanan (Opsi E). Opsi D (grafik tumbuh kembang) hanya
membaca tabel ini dan tidak menambah kolom.

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
* `age_in_months` (Int), `z_score_wfa` (Decimal), `status_gizi` (String)
* `deleted_at` (Timestamp, nullable) — soft delete
* `created_at`, `updated_at`

**Index dan constraint:**

* **Partial unique** `(child_id, measurement_date) WHERE deleted_at IS NULL` —
  satu anak satu penimbangan per tanggal, tapi penimbangan yang dibatalkan
  tidak menghalangi pencatatan ulang tanggal yang sama
* Index `(deleted_at, measurement_date)` — Serving rekap bulanan. Diuji dengan
  36.000 baris: tanpa index `Seq Scan` 2.132 ms, dengan index 0,245 ms
* Index `(kader_id)` — melayani lookup FK `ON DELETE SET NULL`
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

Tabel ini **satu-satunya** acuan WHO di database. Belum ada acuan TB/U
(`who_hfa_standards`), jadi `measurements.z_score_hfa` dan status stunting
tidak ada. Lihat `RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md` bagian 5.1.

Opsi D (grafik tumbuh kembang) membaca tabel ini untuk pita ±2 SD, dan **tidak
mengubah apa pun**: tidak ada tabel baru, tidak ada kolom baru, dan trigger
`trg_measurements_who_zscore` tetap sama. `lower_kg` dan `upper_kg` diturunkan
dari `median_kg` dan `sd_kg` di SQL saat query, bukan disimpan sebagai kolom.
Jadi `GET /children/{id}/growth` tidak menambah migration apa pun.

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
ada di `docs/RANCANGAN_VISIT.md`.

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
> rumah sore). Keputusan ini sudah ditutup di `docs/RANCANGAN_VISIT.md` §7.1.
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

## 6. `spatial_zones` (Pemetaan - PostGIS) *Coming Soon*
* `id` (UUID, PK), `child_id` (UUID, FK)
* `coordinate` (Geometry/Point)
* `risk_level` (String)

## 7. Objek Database (Function & Trigger)
Objek berikut dibuat oleh migration yang sama dan **tidak** diubah oleh migration berikutnya.
* Function `calculate_measurement_who_zscore()` — menghitung `age_in_months`, `z_score_wfa`, dan `status_gizi` secara SQL murni.
* Trigger `trg_measurements_who_zscore` — `BEFORE INSERT OR UPDATE` pada `measurements`, sehingga revisi data otomatis di-recalc.

> Detail perhitungan, klasifikasi status, dan cara rollback ada di
> `docs/LAPORAN_ZSCORE_TRIGGER.md`.
