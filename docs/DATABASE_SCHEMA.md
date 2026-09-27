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

## 3. `measurements` (e-KMS / Riwayat Tumbuh Kembang)
* `id` (UUID, PK)
* `child_id` (UUID, FK -> children.id)
* `kader_id` (UUID, FK -> users.id)
* `measurement_date` (Date)
* `weight_kg`, `height_cm`, `head_circumference_cm` (Decimal)
* `age_in_months` (Int), `z_score_wfa` (Decimal), `status_gizi` (String)

## 4. `who_wfa_standards` (Referensi Z-Score WHO BB/U)
Tabel acuan perhitungan Z-Score berat badan menurut umur. Dihasilkan oleh migration
`2026_09_26_010000_create_who_wfa_standards_and_fix_zscore_trigger.php`.
* `id` (UUID, PK)
* `age_in_months` (Int) — 0 sampai 60
* `gender` (Enum: 'L', 'P')
* `median_weight_kg` (Decimal), `sd_weight_kg` (Decimal)
* Unique `(age_in_months, gender)` — 122 baris (61 usia × 2 jenis kelamin)

## 5. `immunization_records`
* `id` (UUID, PK)
* `child_id` (UUID, FK -> children.id)
* `kader_id` (UUID, FK -> users.id)
* `vaccine_name` (String), `date_given` (Date)

## 5.1 `medical_notes` (Catatan Keluhan Kader — Opsi C)

Migration `2026_09_27_010000_create_medical_notes_table.php`. Satu anak punya
**satu baris per tanggal**.

* `id` (UUID, PK)
* `child_id` (UUID, FK -> children.id, **cascade delete**)
* `measurement_id` (UUID, FK -> measurements.id, nullable, **set null**) — boleh kosong karena keluhan bisa dicatat tanpa menimbang
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
