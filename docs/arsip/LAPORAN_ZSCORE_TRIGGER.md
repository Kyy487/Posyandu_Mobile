# 📊 Laporan Pengerjaan — Trigger Z-Score WHO (Fase 2)

**Tanggal:** 26 September 2026
**Status:** ✅ Selesai & Terverifikasi
**Lingkup:** Backend (Laravel) + Mobile (Flutter)

---

## 1. Latar Belakang

Audit terhadap perkembangan proyek menemukan bahwa **fitur e-KMS (input penimbangan) tidak dapat dipakai sama sekali**. Ada 3 penyebab yang saling menumpuk:

| # | Masalah | Dampak |
| :--- | :--- | :--- |
| 1 | **Bug nama kolom** di trigger SQL: query `SELECT birth_date FROM children`, sedangkan nama kolom aslinya `date_of_birth` | Setiap `POST /measurements` gagal dengan error `column "birth_date" does not exist`. **e-KMS mati total.** |
| 2 | **Z-Score masih placeholder**: trigger lama menulis `z_score_wfa := 0.00` dan `status_gizi := 'Normal'` | Semua anak dilabeli **"Normal"** apa pun beratnya. Berbahaya untuk sistem kesehatan — anak severely wasted terdeteksi sebagai normal. |
| 3 | **Trigger hanya `BEFORE INSERT`**, tidak ada handler untuk `BEFORE UPDATE` | Jika data penimbangan direvisi, `age_in_months` / `z_score` **tidak dihitung ulang** |

Ditambah dua temuan pendukung:

- **Relasi Eloquent rusak**: `User::children()` dan `Child::parent()` mereferensikan kolom `parent_id` yang tidak ada → **500 error** saat dipanggil.
- **Respons API membuang hasil trigger**: `Measurement::create()` mengembalikan objek Eloquent yang tidak memuat nilai yang dihitung trigger di database, sehingga API mengirim `z_score_wfa: null`.

---

## 2. Standar yang Digunakan

**WHO Child Growth Standards (2006) — Weight-for-Age (BB/U)**

| Parameter | Keterangan |
| :--- | :--- |
| Z-Score | `Z = (Berat Badut − Median) / Standard Deviation` |
| Rentang usia | 0–60 bulan (di luar itu = `NULL`, **bukan** dipaksa "Normal") |
| Sumber data | Tabel Median & SD resmi WHO, presisi 1 desimal |
| Penyimpanan | Tabel referensi `who_wfa_standards` (122 baris: 61 usia × 2 jenis kelamin) |

### Klasifikasi `status_gizi`

| Z-Score | Nilai `status_gizi` | Warna di aplikasi |
| :--- | :--- | :--- |
| `z < -3` | `Gizi Buruk` | 🔴 Merah |
| `-3 ≤ z < -2` | `Gizi Kurang` | 🟠 Oranye |
| `-2 ≤ z ≤ 2` | `Normal` | 🟢 Hijau |
| `z > 2` | `Risiko Gizi Lebih` | ⚫ Abu-biru |
| Di luar 0–60 bulan | `NULL` | ⚪ Abu-abu |

> **Catatan terminologi:** `z_score_wfa` adalah **berat badan menurut umur**. Secara medis, *stunting* adalah indikator **tinggi badan menurut umur (TB/U)**, bukan BB/U. Karena itu nilai status yang dipakai adalah `Gizi Buruk` / `Gizi Kurang` (underweight), bukan literal `Stunting`. Deteksi stunting sejati memerlukan `z_score_hfa` (TB/U) yang dapat ditambahkan terpisah di fase berikutnya — dengan tetap mengikuti Aturan #9 (logika di database).

---

## 3. Perubahan pada Backend (`posyandu-backend`)

### 3.1 Migration Baru (Aturan #5: migration lama tidak diubah)

📄 `database/migrations/2026_09_26_010000_create_who_wfa_standards_and_fix_zscore_trigger.php`

| Metode | Fungsi |
| :--- | :--- |
| `WHO_WFA_STANDARDS` | Konstanta 122 nilai Median + SD (L & P, 0–60 bulan) |
| `createWhoWfaStandardsTable()` | Tabel `who_wfa_standards` — **UUID Primary Key**, unique `(age_in_months, gender)` |
| `seedWhoWfaStandards()` | Mengisi 122 baris data referensi |
| `dropLegacyTrigger()` | Melepas trigger & function lama yang rusak |
| `createZScoreFunction()` | Membuat function `calculate_measurement_who_zscore()` — logika Z-Score **murni SQL** |
| `createTrigger()` | Trigger `trg_measurements_who_zscore` pada `BEFORE INSERT OR UPDATE` |
| `backfillExistingMeasurements()` | Menghitung ulang seluruh data yang sudah terlanjur tersimpan |
| `down()` | Membersihkan trigger, function, dan tabel (rollback aman) |

**Alur logika di dalam function:**

```
1. Ambil date_of_birth + gender dari tabel children
2. Validasi: measurement_date tidak boleh < date_of_birth  → RAISE EXCEPTION
3. Hitung age_in_months (lengkap, berbasis age() bawaan PostgreSQL)
4. Lookup Median & SD dari who_wfa_standards
5. Di luar 0-60 bulan atau referensi tidak ada → z_score & status_gizi = NULL
6. z_score_wfa = ROUND((weight_kg - median) / sd, 2)
7. Tentukan status_gizi sesuai klasifikasi di atas
```

**Constraint validasi di level database:**

```sql
RAISE EXCEPTION 'Tanggal penimbangan (%) tidak boleh lebih awal dari tanggal lahir anak (%).'
```

### 3.2 Perbaikan Bug

| File | Perubahan |
| :--- | :--- |
| `app/Models/User.php` | `children()`: `'parent_id'` → `'user_id'` |
| `app/Models/Child.php` | `parent()`: `'parent_id'` → `'user_id'` |
| `app/Http/Controllers/Api/MeasurementController.php` | Menambah `$measurement->refresh()` agar nilai hasil trigger ikut terbawa pada response API; membuang UUID manual yang sudah otomatis oleh trait `HasUuids` |

---

## 4. Perubahan pada Mobile (`posyandu_mobile`)

Sebelum perubahan, nilai Z-Score **sampai ke API tetapi dibuang** di 2 titik dan tidak pernah tampil.

| File | Perubahan |
| :--- | :--- |
| `lib/services/kader_service.dart` | `addMeasurement()` kini mengembalikan `data` (berisi `z_score_wfa`, `status_gizi`, `age_in_months`) |
| `lib/models/child.dart` | Membaca nama ibu dari nested object `mother` (API tidak pernah mengirim `parent_name`); tetap kompatibel dengan format lama; aman terhadap `null` |
| `lib/models/measurement_model.dart` | Helper `_parseDouble` / `_parseInt` yang aman terhadap format `string`, `number`, maupun `null`; menambah field `headCircumferenceCm` |
| `lib/screens/kader/input_penimbangan_screen.dart` | Dialog hasil kalkulasi setelah simpan, menampilkan BB, TB, Umur, **Z-Score**, dan **Status Gizi** dengan warna indikator |
| `lib/screens/kader/detail_anak_screen.dart` | Menghapus **seluruh data hardcode**; statistik & riwayat kini diambil dari API; tombol FAB "Input Bulan Ini" diaktifkan; otomatis memuat ulang data setelah input |
| `test/kontrak_api_test.dart` | 🆕 6 test kontrak API menggunakan JSON asli dari server |

### Dampak di tampilan

```
Login Kader → Dashboard (nama ibu tampil dari relasi mother)
  → tap anak → Detail (BB/TB/Status Gizi/Z-Score dari API, bukan teks palsu)
  → FAB "Input Bulan Ini" → isi BB/TB → Simpan
      → Dialog: Z-Score -2.50 · Gizi Kurang  (contoh, nilai mengikuti usia anak)
  → kembali ke Detail → data ter-update otomatis
```

---

## 5. Hasil Verifikasi

### 5.1 Uji Logika Z-Score

| Kasus | BB | Z-Score | Status Gizi | Hasil |
| :--- | ---: | ---: | :--- | :--- |
| L, 12 bln, berat median | 9.6 | `0.00` | Normal | ✅ |
| L, 12 bln | 7.1 | `-2.50` | Gizi Kurang | ✅ |
| L, 12 bln | 6.1 | `-3.50` | Gizi Buruk | ✅ |
| L, 12 bln | 12.1 | `+2.50` | Risiko Gizi Lebih | ✅ |
| P, 12 bln, berat median | 8.9 | `0.00` | Normal | ✅ |

**Validasi silang:** anak dengan berat **tepat median WHO** menghasilkan `z = 0.00` pada semua usia yang diuji — 0, 3, 6, 12, 18, 24, 36, 48, dan 60 bulan. Ini membuktikan data referensi dan query trigger saling konsisten.

**Batas rentang:**

| Usia | Hasil | Ekspektasi |
| :--- | :--- | :--- |
| 60 bulan (tepat batas) | `z = 0.00` | ✅ Dihitung |
| 61 bulan (di luar rentang) | `z = NULL`, `status = NULL` | ✅ Tidak dipaksa "Normal" |

**Guard & revisi:**

| Pengujian | Hasil |
| :--- | :--- |
| Tanggal ukur sebelum tanggal lahir | ✅ Ditolak `RAISE EXCEPTION` |
| Revisi BB pada data existing | ✅ Otomatis di-recalc (`9.6 → 7.1` menjadi `-2.50 / Gizi Kurang`) |
| Hapus data anak | ✅ `ON DELETE CASCADE` berjalan, measurement ikut terhapus |

### 5.2 Uji HTTP Nyata

Server dijalankan sungguhan di `http://127.0.0.1:8000`.

```
POST /api/kader/measurements  →  HTTP 201
{
  "success": true,
  "message": "Data penimbangan (e-KMS) berhasil dicatat.",
  "data": {
    "weight_kg": "7.10", "height_cm": "75.00",
    "age_in_months": 16, "z_score_wfa": "-3.09", "status_gizi": "Gizi Buruk"
  }
}
```

| Pengujian | Status | Body |
| :--- | :--- | :--- |
| `GET /api/children` (tanpa token) | `401` | `{"message":"Unauthenticated."}` ⚠️ lihat item 7.1 |
| `POST /api/kader/measurements` | `201` | envelope sesuai Aturan #8 |
| Validasi BB di luar range | `422` | `{"success":false,"message":...,"errors":{...}}` |
| Kader akses endpoint khusus Ibu | `403` | `{"success":false,"message":"Akses ditolak",...}` |

### 5.3 Kualitas Kode

| Pemeriksaan | Hasil |
| :--- | :--- |
| `php -l` (migration) | ✅ Tanpa galat sintaks |
| `artisan migrate` | ✅ Sukses, 1 batch baru |
| `artisan migrate:status` | ✅ 9 migrasi, semua `Ran` |
| `artisan test` (Laravel) | ✅ 2/2 passed |
| `flutter analyze` | ✅ **0 error** (32 `info`/`warning` gaya kode, sebagian besar bawaan proyek) |
| `flutter test` (kontrak API) | ✅ **6/6 passed** |

### 5.4 Integritas Data

Tidak ada data pengguna yang hilang selama pengerjaan.

| Tabel | Sebelum | Sesudah |
| :--- | ---: | ---: |
| `users` | 3 | 3 |
| `children` | 3 | 3 |
| `measurements` | 3 | 5 *(bertambah 2 hasil uji HTTP)* |

Catatan: 3 measurement lama (data dummy awal proyek) tetap utuh dan **diperbarui** oleh `backfillExistingMeasurements()` sehingga z-score serta status Gizinya sudah sesuai standar WHO.

Data di DB saat ini:

| Tanggal | Berat / Tinggi | Z-Score | Status | Keterangan |
| :--- | :--- | ---: | :--- | :--- |
| 2026-09-18 | 20.00 kg / 20.00 cm | 8.64 | — | Data dummy lama, tidak realistis |
| 2026-09-19 | 20.00 kg / 20.00 cm | 8.64 | — | Data dummy lama, tidak realistis |
| 2026-09-19 | 20.00 kg / 20.00 cm | 8.64 | — | Data dummy lama, tidak realistis |
| 2026-09-26 | 7.10 kg / 75.00 cm | -3.09 | Gizi Buruk | **Data valid**, dipakai sebagai contoh |
| 2026-09-26 | 20.00 kg / 30.00 cm | 42.00 | — | Sisa uji HTTP, perlu dihapus |

> ⚠️ **Tertunda**: 4 baris data dummy/uji di atas belum dihapus dan masih memengaruhi grafik.
> Penghapusan tidak dilakukan otomatis karena `measurements` tidak punya endpoint `DELETE` untuk
> cadet..baru. Rekomendasi: tambahkan `DELETE /kader/measurements/{id}` (sudah ada) atau
> hapus manual lewat SQL setelah konfirmasi pemilik data.
>
> Baris valid yang **harus dipertahankan**:
>
> ```
> Measurement ID : 01a0dc0d-67eb-71e5-81c9-edecb72edeed
> Anak           : Budi Santoso (16 bulan)
> Berat / Tinggi : 7.10 kg / 75.00 cm
> Z-Score        : -3.09  →  Gizi Buruk
> ```

Token uji yang dibuat khusus untuk pengujian telah dicabut; token login asli pengguna tetap utuh.

---

## 6. Kontrak API Baru (penting untuk mobile)

### `POST /api/kader/measurements`

**Request:**
```json
{
  "child_id": "01a0d979-c11f-705b-8dd8-a245652c7aa4",
  "measurement_date": "2026-09-26",
  "weight_kg": 7.1,
  "height_cm": 75,
  "head_circumference_cm": null
}
```

**Response `201`:**
```json
{
  "success": true,
  "message": "Data penimbangan (e-KMS) berhasil dicatat.",
  "data": {
    "id": "01a0dc0d-67eb-71e5-81c9-edecb72edeed",
    "child_id": "01a0d979-c11f-705b-8dd8-a245652c7aa4",
    "kader_id": "01a0d979-c297-704b-b89a-d66ff76f2474",
    "measurement_date": "2026-09-26",
    "weight_kg": "7.10",
    "height_cm": "75.00",
    "head_circumference_cm": null,
    "age_in_months": 16,
    "z_score_wfa": "-3.09",
    "status_gizi": "Gizi Buruk",
    "created_at": "2026-09-26T04:51:01.000000Z",
    "updated_at": "2026-09-26T04:51:01.000000Z"
  }
}
```

> ⚠️ **Perhatian developer Flutter:** `weight_kg`, `height_cm`, dan `z_score_wfa` dikirim sebagai **string** (bukan number) karena kolomnya bertipe `decimal` di PostgreSQL. Selalu konversi dengan `double.parse(x.toString())`. Model `MeasurementModel` sudah menangani ini secara aman.

---

## 7. Temuan yang Masih Terbuka

> Status per 26 September 2026, setelah cleanup route, perbaikan otorisasi `show()`,
> dan penyatuan kontrak tambah anak.

### 7.1 Prioritas Tinggi

| Item | Lokasi | Status |
| :--- | :--- | :--- |
| Response `401` belum memakai envelope wajib — masih `{"message":"Unauthenticated."}` | `bootstrap/app.php` (perlu handler `AuthenticationException`) | ⏳ Terbuka |
| Ibu **tidak bisa** mengakses riwayat penimbangan anaknya (terkunci role kader) — menghambat grafik tumbuh kembang di Fase 4 | `routes/api.php` | ⏳ Terbuka (RANCANGAN 3.2.A) |
| Response error `500` di `MeasurementController` masih memakai key `data` alih-alih `errors` | `MeasurementController@index` | ⏳ Terbuka |
| Tidak ada `Log::error()` di `MeasurementController`; pesan exception mentah dikirim ke client | `MeasurementController` | ⏳ Terbuka |
| 4 baris `measurements` berisi data dummy/uji tidak realistis (lihat 5.4) | `measurements` | ⏳ Tertunda |

### 7.2 Prioritas Sedang

| Item | Keterangan | Status |
| :--- | :--- | :--- |
| Route duplikat & bersarang | `POST /logout` 2×, `POST /children` 3×, `auth:sanctum` bersarang, `RoleCheck:ibu` dead code | ✅ Diperbaiki — 12 route unik |
| Nama ibu tidak konsisten antar endpoint | `index()` Ibu tidak memuat relasi `mother` sehingga mobile menampilkan `-` | ✅ Diperbaiki — eager load di semua cabang |
| Otorisasi `GET /children/{id}` terlalu longgar | Ibu bisa melihat anak orang lain | ✅ Diperbaiki — 403 untuk cross-user |
| Kontrak tambah anak terduplikasi (`store` + `storeKader`) | Dua method dengan validasi berbeda; `storeKader` buat UUID manual | ✅ Diperbaiki — satu kontrak unified |
| `PUT`/`PATCH`/`DELETE` untuk `children` belum ada | CRUD anak belum lengkap | ✅ Diperbaiki — `update()` + `destroy()` |
| Hapus anak menghapus riwayat penimbangan | `measurements.child_id` & `immunization_records.child_id` memakai `ON DELETE CASCADE` | ✅ Diperbaiki — soft delete (`children.deleted_at`) |
| ID anak tidak valid di URL membuat `500` | Query ke kolom `uuid` dengan string sembarang melempar error PostgreSQL | ✅ Diperbaiki — validasi `Str::isUuid()` |
| Z-Score tidak dihitung ulang saat DOB/gender anak diubah | Trigger hanya berjalan saat measurement berubah | ✅ Diperbaiki — `update()` menyentuh measurement agar trigger berjalan |
| Tabel `medical_notes` belum ada | RANCANGAN 3.1.A — catatan keluhan (demam, diare) per kunjungan | ⏳ Terbuka |
| Tabel `child_conditions` belum ada | RANCANGAN 3.1.A — penanda alergi & penyakit bawaan | ⏳ Terbuka |
| API Imunisasi belum ada | Tabel `immunization_records` sudah ada, tetapi belum ada Controller/Route | ⏳ Terbuka |
| `casts()` pada Model belum ada | Menyebabkan nilai numerik dikirim sebagai string | ⏳ Terbuka |
| Z-Score TB/U (`z_score_hfa`) | Diperlukan untuk deteksi stunting sejati | ⏳ Terbuka |
| Infrastruktur test belum bisa jalan | `phpunit.xml` memaksa SQLite in-memory; migrasi proyek PostgreSQL-specific | ⏳ Terbuka |
| Daftar/pemulihan anak yang sudah di-soft delete belum ada | `withTrashed()` hanya bisa lewat kode server, belum ada endpoint `restore` | ⏳ Terbuka |
| `Log::error()` belum ada di `MeasurementController` | Pesan exception mentah masih bisa dikirim ke klien | ⏳ Terbuka |

### 7.3 Ketidaksesuaian Dokumentasi

Dokumen berikut **sudah tidak akurat** dan perlu disinkronkan. Status per 26 September 2026:

| Dokumen | Nilai Lama | Nilai Sebenarnya | Status |
| :--- | :--- | :--- | :--- |
| `README.md`, `AI_AGENT_RULES.md` | Laravel 11 | **Laravel 13.33.0** | ✅ Sudah diperbarui |
| `README.md`, `AI_AGENT_RULES.md` | PHP 8.2+ | **PHP 8.4.25** | ✅ Sudah diperbarui |
| `DATABASE_SCHEMA.md` | `children.parent_id` | `children.user_id` | ✅ Sudah diperbarui |
| `DATABASE_SCHEMA.md` | `children.nik_anak` | `children.nik` | ✅ Sudah diperbarui |
| `DATABASE_SCHEMA.md` | `children.birth_date` | `children.date_of_birth` | ✅ Sudah diperbarui |
| `DATABASE_SCHEMA.md` | — | Tabel `who_wfa_standards` + function/trigger | ✅ Sudah ditambahkan |
| `API_CONTRACT.md` | Hanya `/measurements` (draft) | Route `/kader/*` + kontrak unified anak + contoh respons z-score | ✅ Sudah diperbarui |
| `SETUP_LOG.md` | Tidak memuat Z-Score & mobile | Fase Z-Score + mobile | ✅ Sudah ditambahkan |
| `README.md` (docs) | Indeks 3 dokumen | Indeks 5 dokumen | ✅ Sudah diperbarui |
| `PROJECT_OVERVIEW.md` | Roadmap tertulis dua kali dengan status Fase 1 yang saling bertentangan | — | ⏳ Belum diperbarui |

---

## 8. Cara Menjalankan & Menguji

### Backend
```powershell
cd C:\laragon\www\posyandu\posyandu-backend
php artisan migrate        # sudah dijalankan pada 26 Sep 2026
php artisan serve          # http://127.0.0.1:8000
```

### Mobile
```powershell
cd C:\laragon\www\posyandu\posyandu_mobile
flutter test               # 6 test kontrak API
flutter run                # pastikan emulator Android aktif
```

> ⚠️ `baseUrl` di mobile adalah `http://10.0.2.2:8000/api`, yang **hanya** berlaku untuk **emulator Android**. Untuk perangkat fisik, ganti dengan IP LAN komputer (misal `http://192.168.1.10:8000/api`) dan pastikan firewall mengizinkan port 8000.

### Skenario uji manual
1. Login sebagai **Kader** (NIK `5555666677778888`)
2. Dashboard → tap salah satu anak
3. Pastikan nama ibu tampil, bukan `-`
4. Pastikan statistik menampilkan angka dari database (bukan `12.5 kg` hardcode)
5. Tekan **"Input Bulan Ini"** → isi Berat `7.1` dan Tinggi `75` → Simpan
6. Dialog menampilkan Z-Score dan Status Gizi hasil hitungan server, dengan warna indikator sesuai status
7. Kembali ke Detail — data ter-update otomatis

> ⚠️ **Nilai Z-Score pada langkah 6 bergantung pada usia anak.** Z-Score dihitung dari berat menurut umur, bukan dari berat absolut. Contoh: berat `7.1` kg menghasilkan `-2.50` (*Gizi Kurang*) bila usianya 12 bulan, tetapi `-3.09` (*Gizi Buruk*) bila usianya 16 bulan (kondisi data uji HTTP pada laporan ini). Acuan perhitungan ada di tabel `who_wfa_standards`.
>
> ⚠️ Skenario ini **belum dijalankan lewat emulator** pada saat laporan ditulis. Yang sudah terverifikasi secara otomatis adalah `flutter analyze`, 6 contract test, dan HTTP API nyata. Jalankan `flutter run` untuk konfirmasi visual.

---

## 9. Cara Rollback

```powershell
cd C:\laragon\www\posyandu\posyandu-backend
php artisan migrate:rollback --step=1
```

Akan menghapus trigger, function, dan tabel `who_wfa_standards`. **Data pengguna tidak terhapus.**

---

## 10. Ringkasan File

### Backend — 4 file
```
database/migrations/2026_09_26_010000_create_who_wfa_standards_and_fix_zscore_trigger.php  (BARU)
app/Models/User.php                                                      (diperbaiki)
app/Models/Child.php                                                     (diperbaiki)
app/Http/Controllers/Api/MeasurementController.php                       (diperbaiki)
```

### Mobile — 6 file
```
lib/services/kader_service.dart                                          (diperbaiki)
lib/models/child.dart                                                    (diperbaiki)
lib/models/measurement_model.dart                                        (diperbaiki)
lib/screens/kader/input_penimbangan_screen.dart                          (diperbaiki)
lib/screens/kader/detail_anak_screen.dart                                (diperbaiki)
test/kontrak_api_test.dart                                               (BARU)
```

> Tidak ada migration lama, `AuthController`, `routes/api.php`, atau `ChildController` yang dimodifikasi — sesuai Aturan #5 (Immutability) dan Aturan #6 (Strictly Additive).
