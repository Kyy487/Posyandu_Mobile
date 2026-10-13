# Rancangan Entitas Rujukan (Referral)

> **Status:** Rancangan disetujui — diimplementasikan
> **Tanggal:** 13 Oktober 2026
> **Dokumen acuan:** `PERANCANGAN_PERKUATAN.md` §1.2–1.3, §5.1
> **Aturan:** `AI_AGENT_RULES.md`, `posyandu-backend/.ai/rules/`

---

## 1. Tujuan & Ruang Lingkup

Mencatat rujukan anak dari Posyandu ke fasilitas kesehatan (Puskesmas, RS,
faskes lain) sebagai **tindak lanjut** yang terhubung ke satu `visit` dan satu
`child` (`PERANCANGAN_PERKUATAN.md` §1.3 langkah 3). Ini melengkapi alur rekam
medis longitudinal yang sudah dibuka P0-1 (`visits`): sebelumnya rujukan hanya
"ada" sebagai status `visit_type = 'rujukan'`, tanpa alasan, fasilitas tujuan,
dan status tindak lanjut yang bisa dilacak.

**Lingkup:**

1. Tabel `referrals`.
2. Model, relasi, factory, service, controller, route.
3. Endpoint lihat/daftar/buat/koreksi/batalkan.
4. Menampilkan rujukan pada detail kunjungan (`GET /visits/{id}`, aditif).
5. Menampilkan rujukan di **timeline** (`GET /children/{id}/timeline`, aditif) —
   ditambahkan 13 Oktober 2026 lewat perubahan dokumen timeline lebih dulu
   (`RANCANGAN_BUKU_MEDIS.md` 5.2/6.1/7.2/7.3 dan
   `.ai/rules/kontrak-timeline.md`).

**Di luar lingkup (langkah terpisah):**

- Integrasi SIKDA Puskesmas (`PERANCANGAN_PERKUATAN.md` §10.3).
- Notifikasi/reminder tindak lanjut rujukan.
- Integrasi mobile untuk menampilkan daftar/detail rujukan dan rujukan di timeline.

---

## 2. Skema Tabel `referrals`

Migrasi **aditif baru** (`create_referrals_table`). Mengikuti gaya `visits`:
string + CHECK constraint (bukan enum PostgreSQL), `kader_id` nullable
`nullOnDelete`, soft delete.

| Kolom | Tipe | Catatan |
|---|---|---|
| `id` | uuid PK | |
| `visit_id` | foreignUuid → `visits` | `cascadeOnDelete` — rujukan selalu bagian satu kunjungan |
| `child_id` | foreignUuid → `children` | `cascadeOnDelete` |
| `referral_date` | date | boleh berbeda dari `visit_date` (lihat §5.4) |
| `referral_type` | string(20) + CHECK | `puskesmas` / `rs` / `faskes_lain` |
| `reason` | text | alasan rujukan |
| `facility_name` | string(255) | nama fasilitas tujuan |
| `status` | string(20) + CHECK | `dibuat` / `dilaporkan` / `selesai` |
| `kader_id` | foreignUuid → `users`, null | `nullOnDelete()` (riwayat tak hilang) |
| `created_at`, `updated_at` | | |
| `deleted_at` | timestamp, null | SoftDeletes |

**Indeks:**

- `index(['child_id', 'referral_date'])` — daftar rujukan satu anak per periode.
- `index(['visit_id'])` — rujukan per kunjungan (FK memberi index otomatis di
  PostgreSQL, index eksplisit tidak diperlukan; cukup FK).

**CHECK constraint:**

- `referrals_referral_type_check`: `referral_type IN ('puskesmas','rs','faskes_lain')`.
- `referrals_status_check`: `status IN ('dibuat','dilaporkan','selesai')`.

Cerminan konstanta di model `Referral` (`REFERRAL_TYPES`, `STATUSES`), supaya
nilai salah ketik ditolak sebagai `422`, bukan jadi `500` dari error PostgreSQL.

---

## 3. Tautan & Relasi

- `Visit::referrals()` — `HasMany`.
- `Child::referrals()` — `HasMany`.
- `Referral::visit()`, `Referral::child()`, `Referral::kader()` — `BelongsTo`.
- Model `Referral` memakai `Auditable` (trait yang sama dengan `Visit`,
  `Measurement`, `ImmunizationRecord`, `MedicalNote`), `HasUuids`,
  `SoftDeletes`, dan `$fillable` eksplisit.

`kader_id` diisi dari pengguna yang login (`ReferralService::create()`), bukan
dari klien, agar atribusi pencatat tidak bisa dipalsukan — sama seperti
`VisitService::create()` dan `MedicalNoteController@store`.

---

## 4. API

| Method | Path | Peran |
|---|---|---|
| `POST` | `/referrals` | Kader membuat rujukan |
| `GET` | `/children/{id}/referrals` | Ibu (anaknya) / Kader |
| `GET` | `/referrals/{id}` | pemilik anak / Kader |
| `PATCH` | `/referrals/{id}` | Kader |
| `DELETE` | `/referrals/{id}` | Kader (soft delete, batalkan) |

- `GET /children/{id}/referrals` tinggal di `ChildController@referrals`,
  mengikuti preseden `timeline`, `growth`, dan `visits`; otorisasi memakai
  `ChildController::findChildForUser()` yang sudah ada.
- `POST`/`PATCH`/`GET`/`DELETE` `/referrals...` ada di `ReferralController`.
  `POST`/`PATCH`/`DELETE` didaftarkan di group `RoleCheck:kader`; `GET` di group
  `ibu,kader` dengan otorisasi per-rujukan.
- Bentuk respons memakai envelope baku (`success`, `message`, `data`).

### Field rujukan pada respons

`id`, `child_id`, `visit_id`, `referral_date` (`Y-m-d`), `referral_type`,
`reason`, `facility_name`, `status`, `kader_id`, `kader` (`{id, name}` atau
`null`), `created_at`, `updated_at`.

### Detail kunjungan (aditif)

`GET /visits/{id}` menambah kunci `rujukan` pada `data` — daftar rujukan yang
tertaut ke kunjungan itu. Menambah kunci baru aman dan tidak merusak klien
(`.ai/rules/yang-jangan-diubah.md`).

---

## 5. Keputusan Desain

1. **`visit_id` wajib.** Rujukan selalu dicatat sebagai bagian satu kunjungan
   (§1.3 langkah 3). Klien yang mengirim `visit_id` bukan milik `child_id`
   mendapat `422` — pola validasi yang sama dengan endpoint pencatatan
   penimbangan/imunisasi/keluhan.
2. **`child_id` wajib** dan harus merujuk anak yang ada.
3. **`kader_id` dari token**, bukan dari body.
4. **`status` default `dibuat`.** Transisi yang wajar: `dibuat` → `dilaporkan`
   → `selesai`. Perubahan status lewat `PATCH /referrals/{id}`.
5. **Bukan unique per (child, tanggal).** Satu anak bisa dirujuk ke lebih dari
   satu fasilitas, atau dirujuk ulang dengan alasan berbeda.
6. **Soft delete, bukan hapus fisik.** Rujukan yang salah input dibatalkan agar
   tetap bisa diaudit.
7. **`kader_id` nullable + `nullOnDelete`.** Menghapus akun kader tidak boleh
   menghapus riwayat rujukan.
8. **Timeline diperluas (aditif).** `entries[]` mendapat kunci `referrals`.
   Rujukan dikelompokkan pada `referral_date` (boleh beda dari `visit_date`),
   rujukan yang dibatalkan disembunyikan, dan tanggal yang hanya punya rujukan
   tetap muncul sebagai entri. Perubahan kontrak ditulis di dokumen timeline
   lebih dulu (lihat §1 poin 5).

---

## 6. Risiko / Titik Sensitif

- **Timeline** — rujukan masuk ke `entries[].referrals`. Karena timeline
  dikunci (`kontrak-timeline.md`), dokumen timeline dan aturan agent diperbarui
  lebih dulu, dan test bentuk respons serta penghitung query ikut disesuaikan.
- **`visit_id` vs `child_id` tidak sinkron** — harus ditolak `422`, bukan
  menyimpan rujukan yang menggantung ke anak lain.
- **CHECK constraint** — `referral_type`/`status` yang lolos validasi PHP tapi
  ditolak database dibalas `422` (pola `VisitController` untuk kode `23514`).
- **Detail kunjungan** — menambah kunci `rujukan` bersifat aditif; jangan
  mengganti nama kunci lama (`pengukuran`, `imunisasi`, `catatan_keluhan`).

---

## 7. Pertanyaan Terbuka (diputuskan sebelum implementasi)

1. Rujukan tanpa kunjungan? → **Tidak.** `visit_id` wajib; kunjungan dibuat
   dulu, seperti alur §1.3.
2. Boleh >1 rujukan per anak per hari? → **Ya**, tanpa unique index.
3. `referral_date` sama dengan `visit_date`? → **Tidak harus**; tanggal rujukan
   boleh berbeda (mis. kunjungan hari ini, surat rujukan dibuat besok).
4. Batalkan fisik atau soft delete? → **Soft delete** (`deleted_at`).

---

## 8. Urutan Langkah Implementasi

> Ditandai `[x]` bila sudah dikerjakan.

1. `[x]` `create_referrals_table`
2. `[x]` Model `Referral` + relasi `Visit`/`Child`
3. `[x]` `ReferralFactory`
4. `[x]` `ReferralService`
5. `[x]` `ReferralController` + `ChildController@referrals` + routes
6. `[x]` Sertakan `rujukan` di detail kunjungan (aditif)
7. `[x]` Feature test `tests/Feature/ReferralTest.php` (PostgreSQL, nama test Bahasa Indonesia)
8. `[x]` `vendor\bin\pint --dirty`
9. `[x]` Perbarui `docs/DATABASE_SCHEMA.md`, `docs/API_CONTRACT.md`, `docs/STATUS_PENGEMBANGAN.md`
10. `[x]` Sertakan `referrals` di timeline (aditif; dokumen timeline diperbarui lebih dulu)

Semua migrasi bersifat **aditif** (tidak menyentuh migrasi lama), mengikuti
`.ai/rules/yang-jangan-diubah.md`.
