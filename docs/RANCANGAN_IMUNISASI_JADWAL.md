# Rancangan Pembaruan Jadwal Imunisasi (P0-3)

> **Status:** **Diimplementasikan** (12 Oktober 2026) — opsi **A (`is_active`)**
> **Tanggal:** 12 Oktober 2026
> **Dokumen acuan:** `PERANCANGAN_PERKUATAN.md` §3, `STATUS_PENGEMBANGAN.md` §3.1
> **Aturan:** `AI_AGENT_RULES.md`, `posyandu-backend/.ai/rules/yang-jangan-diubah.md`
>
> **Keputusan §10 yang dipakai:** total 21 dosis aktif (16 lama + PCV 3, Rotavirus
> 3, IPV 2, JE 1; HB 2–4 & Polio 5 dinonaktifkan); Rotavirus 3 dosis (2/3/4);
> IPV-2 di 9 bulan; JE di 10 bulan (wilayah endemis, lewat `notes`).

---

## 1. Tujuan & Ruang Lingkup

Menyesuaikan **master imunisasi** dengan jadwal Program Imunisasi Rutin
Kemenkes RI yang berlaku, lalu memakai master itu untuk checklist anak, rekap
bulanan, dan export CSV.

**Termasuk:**
1. Membarui isi `immunization_types` (tambah/ubah hentikan baris).
2. Menyesuaikan seeder, test, dan dokumentasi yang menyebut "16 dosis".

**Tidak termasuk (sengaja):**
- Endpoint baru. `GET /api/immunization-types` sudah ada dan sudah menjadi
  daftar master.
- Tabel/model baru. `immunization_types` sudah menyediakan seluruh kolom yang
  dibutuhkan.
- Validasi "usia minimum per dosis" (§3.3 `PERANCANGAN_PERKUATAN.md`) —
  kandidat pekerjaan terpisah.
- Mengubah `ImmunizationChecklistService` selain yang diperlukan agar baris
  non-aktif tidak ikut checklist.

---

## 2. Kondisi Saat Ini

Master 16 dosis di `immunization_types` (di-seed oleh
`DatabaseSeeder::seedImmunizationTypes()`, **bukan** hardcode):

| Vaksin | Kode | Dosis | Usia target (bulan) |
|---|---|---|---|
| Hepatitis B | `HB` | 4 | 0, 2, 4, 6 |
| BCG | `BCG` | 1 | 2 |
| Polio Oral | `POLIO` | 5 | 0, 2, 3, 4, 6 |
| DPT-HB-Hib | `DPT-HB-HIB` | 4 | 2, 3, 4, 6 |
| Campak-Rubella | `MR` | 2 | 9, 18 |
| **Total** | | **16** | |

**Dipakai di:**
- Checklist anak — `ImmunizationChecklistService`
- Dropdown pencatatan suntikan — `GET /api/immunization-types`
- Rekap bulanan + CSV — `ImmunizationController@recap`
- Test — `ImmunizationTypeOrderTest` (menyalin master apa adanya)

Aturan urutan yang **tidak boleh diubah**: `scopeOrderedForDosing()` —
`target_age_months ASC NULLS LAST, code, dose_number`.

---

## 3. Masalah

Master saat ini memakai jadwal lama. Jadwal Kemenkes RI yang lebih baru
menambahkan **PCV**, **Rotavirus**, **IPV (polio suntik)**, dan **JE**, serta
memindahkan beberapa dosis (BCG 2→1 bulan, OPV 0/2/3/4/6 → 1/2/3/4, dosis HBV
digabung dalam DPT-HB-Hib). Akibatnya checklist, rekap, dan CSV menampilkan
dosis yang **tidak sama** dengan buku KIA / jadwal puskesmas.

Prinsip kerja (`.ai/rules/yang-jangan-diubah.md`): **tambah, jangan duplikasi**.
Karena itu tidak dibuat tabel/model/endpoint baru — cukup memperbarui **data**
master dan menyesuaikan komponen yang membacanya.

---

## 4. Jadwal Acuan yang Diusulkan

Sumber: **Program Imunisasi Rutin Kemenkes RI** (Jadwal Imunisasi Nasional;
lihat `Strategi Komunikasi Nasional Imunisasi 2022–2025`, kemkes.go.id).

| Usia | Vaksin (usulan) |
|---|---|
| 0 bulan | Hepatitis B (HB-0) |
| 1 bulan | BCG; Polio Tetes 1 |
| 2 bulan | DPT-HB-Hib 1; Polio Tetes 2; Rotavirus 1; PCV 1 |
| 3 bulan | DPT-HB-Hib 2; Polio Tetes 3; Rotavirus 2; PCV 2 |
| 4 bulan | DPT-HB-Hib 3; Polio Tetes 4; Polio Suntik (IPV) 1; Rotavirus 3 |
| 9 bulan | Campak-Rubella 1; Polio Suntik (IPV) 2 |
| 10 bulan | JE (hanya wilayah endemis) |
| 12 bulan | PCV 3 |
| 18 bulan | DPT-HB-Hib Lanjutan; Campak-Rubella 2 |

> **Catatan sumber (perlu konfirmasi):** PCV program nasional = 2, 3, 12 bulan
> (3 dosis). Jadwal Rotavirus (2 atau 3 dosis) dan IPV kedua (9 bulan) berbeda
> antar-sumber Kemenkes vs IDAI. JE hanya di provinsi tertentu. Nilai di tabel
> mengikuti usulan pengguna + program nasional; **lihat §10**.

---

## 5. Perubahan Master (Tambah / Ubah / Hentikan)

| Vaksin | Dosis baru (usia) | Tindakan vs saat ini |
|---|---|---|
| `HB` | 1 (0) | **Hentikan** HB-2 (2), HB-3 (4), HB-4 (6) |
| `BCG` | 1 (**1**) | **Ubah** target 2 → 1 |
| `POLIO` | 4 (**1, 2, 3, 4**) | **Ubah** target dosis 1–4; **hentikan** POLIO-5 (6) |
| `DPT-HB-HIB` | 4 (2, 3, 4, **18**) | **Ubah** target dosis 4: 6 → 18 |
| `MR` | 2 (9, 18) | tidak berubah |
| `PCV` | 3 (2, 3, 12) | **baru** |
| `ROTAVIRUS` | 2–3 (2, 3, 4) | **baru** |
| `IPV` | 1–2 (4; 9) | **baru** |
| `JE` | 1 (10) | **baru** (regional) |

Total usulan: **21 dosis** (dengan Rotavirus 3 dan IPV 2), dari **16** sekarang.

Perubahan bersifat **data**, bukan migrasi skema. `target_age_months` dan
`interval_months` diisi mengikuti jadwal di atas.

---

## 6. Keputusan Kunci — Penanganan Baris Lama

FK `immunization_records.immunization_type_id` memakai **`restrictOnDelete()`**
(migration `2026_09_26_032000_rework_immunization_records_table.php`). Artinya
baris master yang sudah punya catatan suntikan **tidak bisa dihapus**. Maka
baris yang "dihentikan" (HB-2/3/4, POLIO-5) tidak boleh lewat `delete()`.

**Opsi yang diusulkan:**

| Opsi | Cara | Kelebihan | Kekurangan |
|---|---|---|---|
| **A (dipilih)** | Tambah kolom boolean `is_active` (migrasi aditif, default `true`); seeder menandai baris lama `false`; checklist & `GET /immunization-types` hanya membaca `is_active = true` | Catatan lama tetap valid; master lama tetap tersimpan untuk audit | Tambah 1 kolom + saring di service/controller |
| B | Biarkan baris lama ada tanpa flag, hanya "tidak dipakai" | tanpa skema | checklist menampilkan dosis lama + baru (dobel) |
| C | Hapus baris lama | paling bersih | **gagal** jika sudah ada catatan (`restrictOnDelete`); risiko data hilang |

**Opsi A** dipilih karena aman untuk data yang sudah berjalan dan tetap
mematuhi aturan aditif. Seeder tetap memakai `updateOrCreate(['code',
'dose_number'])` sebagai kunci alami.

---

## 7. Rencana Perubahan per Komponen

| Komponen | Perubahan |
|---|---|
| Migrasi | **baru**: `add_is_active_to_immunization_types_table` (kolom boolean, default `true`) |
| `DatabaseSeeder::seedImmunizationTypes()` | Perbarui daftar 16 → usulan; set `is_active` |
| `ImmunizationType` (model) | Tambah `is_active` ke `$fillable`; `scopeOrderedForDosing()` atau scope baru menyaring aktif |
| `ImmunizationChecklistService` | Hanya memproses tipe `is_active = true` |
| `ImmunizationController@types` | Hanya mengirim tipe `is_active = true` |
| `ImmunizationController@recap` + CSV | `by_type` mengikuti master aktif |
| `docs/API_CONTRACT.md`, `docs/DATABASE_SCHEMA.md` | Perbarui "16 dosis" → jumlah baru + catatan `is_active` |
| `ImmunizationTypeOrderTest` | Perbarui fixture master + urutan yang diharapkan |
| Dokumen lain (`SETUP_LOG.md`, `DOKUMEN_LAPORAN_APLIKASI.md`, `LAPORAN_*`, `PERANCANGAN_PERKUATAN.md`) | Perbarui penyebutan "16 dosis" |
| Mobile (`posyandu_mobile`) | **Tidak ada perubahan kode** — jumlah dosis dibaca dinamis dari `summary.total`. Fixture test boleh disamakan (opsional) |

---

## 8. Risiko & Mitigasi

| Risiko | Dampak | Mitigasi |
|---|---|---|
| Mengubah `target_age_months` dosis lama mengubah status `terlambat` anak yang sudah ada secara retroaktif | Status bisa berubah tanpa pencatatan baru | Sama seperti keputusan `status_gizi`: status memang dihitung ulang, bukan disimpan; catat di dokumentasi/user manual |
| Menghapus baris master | Catatan suntikan rusak / gagal FK | Pakai `is_active` (§6), jangan `delete()` |
| Menambah 4 kode mengubah jumlah master | Test & dokumen "16 dosis" jadi salah | Perbarui `ImmunizationTypeOrderTest` + dokumen (§7) |
| Jadwal Rotavirus/IPV/JE berbeda antar-sumber | Data bisa tidak sesuai puskesmas | Konfirmasi dulu (§10), JE ditandai regional |
| Seeder dijalankan pada DB lama | Baris lama tetap ada tapi `is_active=false` | Seeder idempotent; baris lama otomatis dinonaktifkan |

---

## 9. Yang Tidak Diubah

- Bentuk envelope respons (`success`/`message`/`data`).
- Route & nama endpoint.
- `scopeOrderedForDosing()` tetap urutan `target_age_months, code, dose_number`.
- Primary key UUID & `foreignUuid()`.
- Kontrak timeline & growth (`.ai/rules/`).

---

## 10. Keputusan yang Dibutuhkan Sebelum Implementasi

1. **"16 imunisasi" = 16 dosis atau 16 jenis?** (usulan: 16 dosis, lalu naik ke
   jumlah baru).
2. **Jadwal Rotavirus:** 2 atau 3 dosis, pada usia berapa?
3. **IPV kedua (9 bulan):** dimasukkan atau cukup 1 dosis di 4 bulan?
4. **JE:** dimasukkan sebagai master universal (10 bulan) atau regional/opsional?
5. **Penanganan baris lama:** setuju memakai opsi **A (`is_active`)**?

> Pertanyaan 1–3 sudah tercatat untuk dosen di `PERANCANGAN_PERKUATAN.md` §10.
> Bila keputusan dosen lama, implementasi tetap bisa jalan dengan usulan §4 dan
> mudah disesuaikan karena hanya berupa data seeder.

---

## 11. Urutan Langkah Implementasi

> Ditandai `[x]` bila sudah dikerjakan.

1. `[x]` Migrasi `add_is_active_to_immunization_types_table`
2. `[x]` Model `ImmunizationType`: `$fillable` + scope/saringan `is_active`
3. `[x]` Perbarui `DatabaseSeeder::seedImmunizationTypes()` (16 → usulan; `is_active`)
4. `[x]` Saring aktif di `ImmunizationChecklistService`, `@types`, `@recap`
5. `[x]` Perbarui `ImmunizationTypeOrderTest` (fixture + urutan) + test non-aktif
6. `[x]` `php artisan test` + full suite lulus (161 → 162)
7. `[x]` `vendor\bin\pint --dirty --format agent`
8. `[x]` Perbarui `docs/API_CONTRACT.md`, `docs/DATABASE_SCHEMA.md`, dan
   penyebutan "16 dosis" di dokumen lain
9. `[ ]` Commit + push

---

## 12. Referensi

- `PERANCANGAN_PERKUATAN.md` §3 — Reformasi "16 imunisasi"
- `STATUS_PENGEMBANGAN.md` §3.1 — P0-3
- `LAPORAN_IMUNISASI_JADWAL.md` §3 — master 16 dosis saat ini
- `posyandu-backend/database/seeders/DatabaseSeeder.php`
- `posyandu-backend/app/Models/ImmunizationType.php`
- Sumber jadwal: Kemenkes RI, `Strategi Komunikasi Nasional Imunisasi 2022–2025`
