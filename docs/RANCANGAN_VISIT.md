# Rancangan Entitas Kunjungan (Visit) — P0-1

> **Status:** Selesai diimplementasikan (P0-1)
> **Tanggal:** 10 Oktober 2026 (rancangan) — diimplementasikan 12 Oktober 2026
> **Dokumen acuan:** `PERANCANGAN_PERKUATAN.md` §1.2–1.3, §6.2
> **Aturan:** `AI_AGENT_RULES.md`, `posyandu-backend/.ai/rules/`

> **Catatan implementasi (12 Okt 2026):**
> - Semua migrasi, model, service, controller, route, dan test sudah ada.
>   Test: `posyandu-backend/tests/Feature/VisitTest.php` (26 test, semua lulus).
> - **Tidak memakai `StoreVisitRequest`.** Validasi ditulis inline dengan
>   `$request->validate()`, mengikuti konvensi controller lain di proyek ini
>   (tidak ada FormRequest di codebase). Langkah §8.7 disesuaikan.
> - **`GET /children/{id}/visits` tinggal di `ChildController@visits`**, bukan
>   `VisitController`, mengikuti preseden `timeline` dan `growth`. Otorisasi
>   memakai `ChildController::findChildForUser()` yang sudah ada. Lihat kotak di
>   §5.
> - `POST /visits` dan `PATCH /visits/{id}` ada di `VisitController`; keduanya
>   di group `RoleCheck:kader`. `GET /visits/{id}` di group `ibu,kader` dengan
>   otorisasi per-kunjungan.
> - Endpoint pencatatan (`/kader/measurements`, `/kader/children/{child}/immunizations`,
>   `/kader/children/{child}/medical-notes`) menerima `visit_id` **opsional**;
>   `visit_id` harus milik anak yang sama (validasi 422). Respons menambahkan
>   field `visit_id`.

---

## 1. Tujuan & Ruang Lingkup

Menyatukan pengukuran, imunisasi, keluhan, dan rujukan di bawah satu
`visit` agar rekam medis longitudinal dan pelaporan **per-kunjungan**
mungkin (§1.3 langkah 4).

**MVP P0-1 hanya:**
1. Tabel `visits`.
2. Tautan `visit_id` pada `measurements`, `immunization_records`, `medical_notes`.

**Di luar lingkup P0-1:** `referrals`, `consents`, `audit_logs` (P1), serta
mengubah timeline dari per-tanggal menjadi per-kunjungan (butuh perubahan
kontrak lebih dulu, lihat §6).

---

## 2. Skema Tabel `visits`

Migrasi **aditif baru** (`create_visits_table`).

| Kolom | Tipe | Catatan |
|---|---|---|
| `id` | uuid PK | `default gen_random_uuid()` |
| `child_id` | foreignUuid → `children` | `cascadeOnDelete` |
| `schedule_id` | foreignUuid → `posyandu_schedules`, null | kunjungan terjadwal |
| `visit_date` | date | |
| `visit_type` | enum `posyandu` / `kunjungan_rumah` / `rujukan` | ikut gaya `$table->enum()` existing |
| `kader_id` | foreignUuid → `users`, null | `nullOnDelete()` (riwayat tak hilang) |
| `anamnesis` | text, null | keluhan utama |
| `catatan_kader` | text, null | |
| `created_at`, `updated_at`, `deleted_at` | | SoftDeletes |

**Indeks:**
- `index(['child_id', 'visit_date'])`.
- Pertimbangkan `unique(['child_id', 'visit_date', 'visit_type'])` — tergantung keputusan §7.1.

---

## 3. Tautan Balik (3 migrasi aditif terpisah)

| Migrasi | Perubahan |
|---|---|
| `add_visit_id_to_measurements` | `visit_id` foreignUuid → `visits`, nullable, `nullOnDelete` |
| `add_visit_id_to_immunization_records` | idem |
| `add_visit_id_to_medical_notes` | idem |

**Nullable** agar baris lama dan alur lama tidak rusak; penimbangan tanpa
kunjungan tetap valid.

---

## 4. Model & Relasi

- `Visit` — `HasUuids`, `SoftDeletes`, `$fillable` eksplisit
  (`child_id`, `schedule_id`, `visit_date`, `visit_type`, `kader_id`,
  `anamnesis`, `catatan_kader`).
- `Child::visits()`, `Visit::child()`, `Visit::schedule()`, `Visit::kader()`,
  `Visit::measurements()`, `Visit::immunizationRecords()`, `Visit::medicalNotes()`.
- `Measurement`, `ImmunizationRecord`, `MedicalNote` → `belongsTo(Visit)`.

---

## 5. API (draft)

| Method | Path | Peran |
|---|---|---|
| POST | `/visits` | Kader membuat kunjungan |
| GET | `/children/{id}/visits` | Ibu (anaknya) / Kader |
| GET | `/visits/{id}` | pemilik / kader |
| PATCH | `/visits/{id}` | Kader |

`VisitController` + `VisitService`; otorisasi reuse pola
`ChildController::findChildForUser()`.

> **Catatan:** §1.3 langkah 1 berbunyi "saat kader membuka detail anak →
> buat visit baru". Usul: kunjungan dibuat **eksplisit** lewat `POST /visits`
> saat kader menekan "Mulai kunjungan", bukan otomatis di `GET` (GET harus
> idempoten).

---

## 6. Risiko / Titik Sensitif

- **Timeline** — `GET /children/{id}/timeline` kini mengelompokkan **per
  tanggal** dan dikunci di `.ai/rules/kontrak-timeline.md`. Mengubahnya menjadi
  per-kunjungan = perubahan dokumen/rule lebih dulu, **langkah terpisah** dari
  P0-1.
- **`measurements_child_date_unique`** — partial unique index membatasi satu
  baris penimbangan per anak per tanggal. Bila satu anak bisa punya
  `posyandu` + `kunjungan_rumah` di hari sama, index ini menghalangi. Lihat §7.1.
- **Backfill** — 7 baris `measurements` lama tanpa `visit_id`. Opsi: biarkan
  `NULL` (aman) atau buat "legacy visit" per `(child, tanggal)`.
- **Trigger** `calculate_measurement_who_zscore` tidak perlu tahu `visit_id` →
  tidak diubah.

---

## 7. Pertanyaan Terbuka (sudah ditutup)

Semua pertanyaan di bawah sudah diputuskan sebelum implementasi (12 Okt 2026):

1. Boleh satu kunjungan punya >1 tipe di tanggal yang sama? → **Ya.**
   Keputusan: **tidak ada** unique `(child_id, visit_date)`.
2. Kunjungan dibuat eksplisit (`POST`) atau otomatis? → **Eksplisit** lewat
   `POST /visits`; `GET` tetap idempoten.
3. Backfill baris lama: `NULL` atau legacy visit? → **Legacy visit** per
   `(anak, tanggal)` dari `measurements`.
4. `visit_date` vs tanggal data anak — boleh berbeda? → **Boleh.** Tanggal data
   anak (mis. `measurement_date`) tidak diikat sama dengan `visit_date`.

---

## 8. Urutan Langkah Implementasi

> Ditandai `[x]` bila sudah dikerjakan.

1. `[x]` `create_visits_table`
2. `[x]` `add_visit_id_to_measurements`
3. `[x]` `add_visit_id_to_immunization_records`
4. `[x]` `add_visit_id_to_medical_notes`
5. `[x]` Model + relasi
6. `[x]` `VisitService` / `VisitController` / routes
7. `[x]` Validasi inline di controller (bukan `StoreVisitRequest`, lihat catatan di atas)
8. `[x]` Feature test `tests/Feature/VisitTest.php` (PostgreSQL, nama test Bahasa Indonesia)
9. `[x]` `vendor\bin\pint --dirty`
10. `[x]` Perbarui `docs/DATABASE_SCHEMA.md` dan `docs/STATUS_PENGEMBANGAN.md`

Semua migrasi bersifat **aditif** (tidak menyentuh migrasi lama), mengikuti
`.ai/rules/yang-jangan-diubah.md`.
