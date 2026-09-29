# 🌐 API Contract & Endpoints

Base URL: `http://localhost:8000/api`

## Authentication (Public)
| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `POST` | `/register` | Mendaftarkan akun baru — **[role ditentukan server](#role-ditentukan-server-bukan-pilih-dari-input)** |
| `POST` | `/login` | Masuk dan mendapatkan Bearer Token |

## Role Ditentukan Server (bukan pilih dari input)

`role` **tidak pernah** dipercaya dari body request. Server yang memutuskan:

| Body request | `KADER_REGISTRATION_CODE` di `.env` | Hasil |
| :--- | :--- | :--- |
| tanpa `role` / `role: "ibu"` | — | Akun **`ibu`** (`201`) |
| `role: "kader"` tanpa `kader_code` | terisi | `403` — kode wajib diisi |
| `role: "kader"` + `kader_code` salah | terisi | `403` — kode tidak cocok |
| `role: "kader"` + `kader_code` benar | terisi | Akun **`kader`** (`201`) |
| `role: "kader"` + kode apa pun | **kosong** | `403` — pendaftaran kader dimatikan |
| `role` selain `kader` (mis. `"admin"`) | — | `422` |

> **Kenapa begitu?** Sebelumnya `role` diterima apa adanya dari body request, dan
>layar pendaftaran punya dropdown "Kader Posyandu". Siapa pun tanpa login bisa
> membuat akun kader lalu menghapus data anak siapa pun. Role kini hanya bisa
> didapat dengan kode yang dibagikan koordinator posyandu.

> **Menonaktifkan pendaftaran kader**: kosongkan `KADER_REGISTRATION_CODE` di
> `.env`, lalu `php artisan config:clear`. Kader dibuat lewat
> `php artisan tinker` atau SQL di HeidiSQL.

### Request body `POST /register`

| Field | Tipe | Wajib | Keterangan |
| :--- | :--- | :--- | :--- |
| `nik` | string(16) | Ya | NIK, unik |
| `name` | string | Ya | Nama lengkap |
| `password` | string | Ya | Minimal 8 karakter |
| `password_confirmation` | string | Ya | Harus sama dengan `password` (`422` bila tidak) |
| `phone_number` | string(15) | Tidak | Nomor HP |
| `role` | `"kader"` | Tidak | Hanya boleh bernilai `kader`. Kosong = `ibu` |
| `kader_code` | string | Kader¹ | Kode dari `KADER_REGISTRATION_CODE` |

¹ Wajib hanya bila `role` = `kader`.

### Respons sukses (`201`)

```json
{
  "success": true,
  "message": "Registrasi berhasil",
  "data": {
    "user": { "id": "...", "nik": "...", "name": "...", "role": "ibu" },
    "token": "1|xxxxxxxx"
  }
}
```

> Field `password` tidak pernah ikut respons (`$hidden` pada model `User`).

### Kode error

| HTTP | Kondisi | `message` |
| :--- | :--- | :--- |
| `422` | validasi gagal | `Validasi gagal.` + `errors` per-field |
| `403` | kode kader salah/kosong | `Pendaftaran akun kader ditolak.` |
| `401` | login gagal | `Kredensial yang diberikan tidak cocok dengan data kami.` |
| `429` | melewati batas percobaan | `Terlalu banyak percobaan. Silakan coba lagi beberapa saat lagi.` |


## Protected Routes (Requires Bearer Token)
Header Wajib: `Authorization: Bearer {token}` & `Accept: application/json`

### Children (Data Anak)
| Method | Endpoint | Description | Role Akses |
| :--- | :--- | :--- | :--- |
| `GET` | `/children` | List anak milik user (Ibu) atau seluruh anak (Kader) | Ibu / Kader |
| `POST` | `/children` | Mendaftarkan anak baru — **[kontrak unified](#menambah-data-anak-kontrak-unified)** | Ibu / Kader |
| `GET` | `/children/{id}`| Detail anak, pengukuran, imunisasi | Ibu / Kader |
| `PUT`/`PATCH` | `/children/{id}` | **[Ubah data anak](#mengubah-data-anak)** | Ibu / Kader |
| `DELETE` | `/children/{id}` | **[Hapus data anak (soft delete)](#menghapus-data-anak-soft-delete)** | **Kader saja** |

### Kader (POSYANDU)
| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET` | `/kader/children` | List anak yang tercatat di Posyandu |
| `POST` | `/kader/children` | Mendaftarkan anak oleh kader — **[kontrak unified](#menambah-data-anak-kontrak-unified)** |
| `GET` | `/kader/measurements` | Riwayat penimbangan |
| `POST` | `/kader/measurements` | Input penimbangan (e-KMS) — endpoint yang dipakai mobile |
| `DELETE` | `/kader/measurements/{id}` | Batalkan penimbangan (soft delete) |
| `GET` | `/kader/immunizations/recap` | **[Rekap bulanan](#get-kaderimmunizationsrecap)** - aktivitas + kelengkapan, Kader saja. `?format=csv` untuk laporan ke BIDAN |
| `POST` | `/kader/children/{child}/immunizations` | Catat suntikan — **[lihat bagian imunisasi](#imunisasi)** |
| `PATCH` | `/kader/immunizations/{record}` | Koreksi suntikan yang sudah tercatat |
| `DELETE` | `/kader/immunizations/{record}` | Batalkan suntikan (soft delete) |
| `POST` | `/kader/schedules` | **[Agenda posyandu](#jadwal-posyandu-agenda-kegiatan)** — buat agenda |
| `PATCH`/`DELETE` | `/kader/schedules/{id}` | Ubah / hapus agenda |

> **Tidak ada `GET /kader/schedules`.** Membaca daftar agenda tidak perlu prefix
> `kader`: Ibu dan Kader memakai endpoint yang sama, `GET /api/schedules`.
> Prefix `kader` hanya untuk operasi tulis.

### Imunisasi & Agenda (Ibu dan Kader)
| Method | Endpoint | Description | Role Akses |
| :--- | :--- | :--- | :--- |
| `GET` | `/immunization-types` | Master 16 dosis imunisasi | Ibu / Kader |
| `GET` | `/children/{id}/immunizations` | Checklist imunisasi + status per dosis | Ibu (anaknya) / Kader |
| `GET` | `/petugas` | Daftar petugas untuk dipilih di agenda | Ibu / Kader |
| `GET` | `/schedules` | Daftar agenda kegiatan | Ibu / Kader |

## Menambah Data Anak (Kontrak Unified)

`POST /children` dan `POST /kader/children` memakai **method yang sama** (`ChildController@store`)
dengan kontrak identik. Keduanya mengembalikan respons yang sama.

### Cara menentukan ibu

| Role | `ibu_nik` | `user_id` | Perilaku |
| :--- | :--- | :--- | :--- |
| **Ibu** | tidak diisi | tidak diisi | Anak otomatis milik Ibu yang login |
| **Ibu** | diisi | diisi | **Diabaikan** — Ibu tidak pernah bisa menunjuk ibu lain |
| **Kader** | diisi | — | Ibu dicari dari NIK (`ibu_nik`) |
| **Kader** | — | diisi | Ibu diambil langsung dari UUID |
| **Kader** | diisi | diisi | Wajib menunjuk user yang **sama**, selain itu `422` |

> **Identifier eksternal adalah NIK, relasi database adalah UUID.**
> klien sebaiknya mengirim `ibu_nik` (sesuai KK) karena lebih stabil dan mudah dibaca petugas.
> `user_id` (UUID) tetap diterima untuk backward compatibility.

### Request body

| Field | Tipe | Wajib | Keterangan |
| :--- | :--- | :--- | :--- |
| `name` | string | Ya | Nama anak |
| `date_of_birth` | date | Ya | Format `YYYY-MM-DD` |
| `gender` | enum | Ya | `L` atau `P` |
| `nik` | string(16) | Tidak | NIK anak, unik bila diisi |
| `birth_weight` | numeric | Tidak | BB lahir (kg) |
| `birth_height` | numeric | Tidak | TB lahir (cm) |
| `ibu_nik` | string(16) | Kader¹ | NIK ibu |
| `user_id` | uuid | Kader¹ | UUID ibu |

¹ Wajib **salah satu** untuk Kader; tidak wajib untuk Ibu.

### Contoh request (Kader)

```json
{
  "nik": "1234567890123456",
  "name": "Budi Santoso",
  "date_of_birth": "2024-06-06",
  "gender": "L",
  "birth_weight": 3.4,
  "birth_height": 51,
  "ibu_nik": "1111222233334445"
}
```

### Respons sukses (`201`)

Relasi `mother` selalu ikut dikembalikan agar mobile bisa menampilkan nama dan NIK ibu
(tanpa query tambahan).

```json
{
  "success": true,
  "message": "Data balita berhasil ditambahkan.",
  "data": {
    "id": "01a0dc0d-67eb-71e5-81c9-edecb72edeed",
    "user_id": "01a0dc36-cd5a-71ba-b279-66bab377c0a7",
    "nik": "1234567890123456",
    "name": "Budi Santoso",
    "date_of_birth": "2024-06-06",
    "gender": "L",
    "birth_weight": "3.40",
    "birth_height": "51.00",
    "mother": {
      "id": "01a0dc36-cd5a-71ba-b279-66bab377c0a7",
      "name": "Ibu Ceri",
      "nik": "1111222233334445"
    }
  }
}
```

### Kode error

| HTTP | Kondisi | `message` |
| :--- | :--- | :--- |
| `404` | `ibu_nik` tidak terdaftar | `NIK Ibu tidak ditemukan di sistem. Pastikan akun Ibu sudah terdaftar.` |
| `404` | ibu tidak bisa ditentukan | `Ibu pemilik anak tidak ditemukan.` |
| `422` | `user_id` dan `ibu_nik` tidak sinkron | `user_id dan ibu_nik harus menunjuk Ibu yang sama.` |
| `422` | target bukan role `ibu` | `Data anak hanya dapat ditambahkan pada akun dengan role ibu.` |
| `422` | Kader tidak mengirim ibu | pesan validasi `user_id` / `ibu_nik` |
| `422` | field lain tidak valid | `Validasi gagal.` + `errors` per-field |
| `403` | Ibu memanggil `/kader/children` | Pesan middleware role |

> Pesan error internal (SQLSTATE, nama tabel, path file) **tidak pernah** dikirim ke klien;
> hanya ditulis ke log aplikasi.

## Mengubah Data Anak

`PUT` dan `PATCH` keduanya diterima dan **berperilaku sama sebagai partial update**:
hanya field yang dikirim yang berubah. Ini membuat klien mobile tidak perlu
mengirim ulang seluruh data.

| Role | Akses |
| :--- | :--- |
| **Ibu** | Hanya anak miliknya sendiri |
| **Kader** | Semua anak |

Field yang dapat diubah: `nik`, `name`, `date_of_birth`, `gender`, `birth_weight`,
`birth_height`. Ibu maupun Kader boleh mengirim `ibu_nik`/`user_id` untuk
**memindahkan** anak ke ibu lain, tetapi:
- Ibu tidak pernah bisa memindahkan anaknya ke ibu lain (identifier diabaikan).
- Non-Ibu yang dituju harus benar-benar ber-role `ibu`.

### Hitung ulang Z-Score otomatis

Bila `date_of_birth` atau `gender` berubah, umur dan acuan WHO ikut berubah sehingga
`age_in_months`, `z_score_wfa`, dan `status_gizi` pada measurement anak tersebut
dihitung ulang oleh trigger. Jumlah baris yang dihitung ulang disebut di `message`:

```
"Data balita berhasil diperbarui. Z-score 3 data penimbangan dihitung ulang."
```

Mengubah field lain (misalnya hanya `name`) **tidak** menyentuh measurement.

### Contoh

```json
// hanya ubah nama
{ "name": "Budi Santoso" }
```

```json
// Kader memindahkan anak ke ibu lain
{ "ibu_nik": "1111222233334445" }
```

### Kode error

| HTTP | Kondisi | `message` |
| :--- | :--- | :--- |
| `404` | id bukan UUID / anak tidak ada / anak sudah di-soft delete | `Data balita tidak ditemukan.` |
| `403` | Ibu mencoba anak orang | `Akses ditolak. Anda tidak berhak mengubah data anak ini.` |
| `422` | tidak ada field yang dikirim | `Tidak ada data yang diperbarui.` |
| `422` | nilai field tidak valid | `Validasi gagal.` + `errors` per-field |
| `422` | NIK anak bentrok | pesan `nik` (dispensai bila bentrok dengan anak yang sudah di-soft delete) |
| `404` / `422` | `ibu_nik` / `user_id` bermasalah | sama seperti kontrak tambah data |

## Menghapus Data Anak (Soft Delete)

`DELETE /children/{id}` — **hanya Kader**.

Respons `200`:

```json
{
  "success": true,
  "message": "Data balita berhasil dihapus. Riwayat penimbangan dan imunisasi tetap disimpan.",
  "data": {
    "id": "01a0dc0d-67eb-71e5-81c9-edecb72edeed",
    "archived_measurements": 3,
    "archived_immunizations": 0
  }
}
```

Yang terjadi di database:

- `children.deleted_at` diisi; baris **tidak** dihapus fisik.
- Semua `measurements` dan `immunization_records` anak tersebut **tetap utuh**
  (FK-nya `ON DELETE CASCADE`, jadi hard delete akan memusnahkan riwayat).
- Anak yang di-soft delete otomatis hilang dari `GET /children`,
  `GET /kader/children`, `GET /children/{id}`, dan `PUT/PATCH`/`DELETE` berikutnya.

Pemulihan dilakukan dari sisi server:

```php
Child::withTrashed()->find($id)->restore();
```

> NIK anak tetap unik termasuk baris yang sudah di-soft delete. Bila NIK tersebut
> dipakai lagi, API membalas `422` dengan pesan yang menyebut nama anak yang sudah dihapus.


## Imunisasi

Status imunisasi **tidak disimpan** di database. Setiap kali checklist diambil,
server menghitung ulang umur anak lalu menetapkan status tiap dosis:

| Status | Arti |
| :--- | :--- |
| `sudah` | Sudah ada suntikan untuk dosis tersebut |
| `belum` | Belum disuntik, masih dalam batas waktu |
| `terlambat` | Belum disuntik dan sudah melewati batas toleransi |

> **Klien tidak boleh menghitung ulang.** Ambang toleransi "terlambat" diatur di
> `config/posyandu.php` (`terlambat_setelah_bulan`, default 2) dan bisa diubah
> koordinator posyandu. Bila Flutter menyalin logikanya, layar bisa menampilkan
> status yang berbeda dari server.

### `GET /immunization-types`

Master 16 dosis (program HB Indonesia). Field `label` sudah diformat server,
mis. `"Hepatitis B (Dosis 2)"`.

| Dosis | `code` | Target |
| :--- | :--- | :--- |
| Hepatitis B 1-4 | `HB` | 0, 2, 4, 6 bulan |
| BCG 1 | `BCG` | 2 bulan |
| Polio Oral 1-5 | `POLIO` | 0, 2, 3, 4, 6 bulan |
| DPT-HB-Hib 1-4 | `DPT-HB-HIB` | 2, 3, 4, 6 bulan |
| Campak-Rubella 1-2 | `MR` | 9, 18 bulan |

### `GET /children/{id}/immunizations`

Ibu hanya boleh melihat anaknya sendiri; Kader boleh melihat semua anak.

```json
{
  "success": true,
  "message": "Checklist imunisasi berhasil diambil.",
  "data": {
    "child": {
      "id": "01a0d979-c11f-705b-8dd8-a245652c7aa4",
      "name": "Budi Santoso",
      "date_of_birth": "2025-05-10",
      "gender": "L"
    },
    "summary": { "sudah": 1, "belum": 1, "terlambat": 14, "total": 16 },
    "checklist": [
      {
        "immunization_type_id": "01a0ddcb-8197-7184-9c37-fe42f3cc1fd9",
        "code": "HB",
        "name": "Hepatitis B",
        "label": "Hepatitis B",
        "dose_number": 1,
        "target_age_months": 0,
        "interval_months": null,
        "status": "terlambat",
        "sisa_bulan": -14,
        "record": null
      },
      {
        "immunization_type_id": "01a0ddcb-81d2-72d7-af73-83b7815725e6",
        "code": "MR",
        "name": "Campak-Rubella",
        "label": "Campak-Rubella (Dosis 2)",
        "dose_number": 2,
        "target_age_months": 18,
        "interval_months": 9,
        "status": "belum",
        "sisa_bulan": 4,
        "record": null
      }
    ]
  }
}
```

> **`sisa_bulan` memakai nama snake_case.** Nilainya negatif bila sudah
> terlambat (`-14` = sudah 14 bulan lewat) dan positif bila masih ada sisa
> waktu. Parser yang salah mengira `null` di sini akan membuat teks
> "terlambat X bulan" hilang tanpa error terlihat.
>
> `sisa_bulan` bernilai `null` untuk dosis berstatus **`sudah`**, dan hanya
> untuk itu. Countdown-nya memang tidak relevan di sana: anak 11 bulan yang
> suntik MR tepat waktu punya sisa `0` (atau negatif) yang akan tampil
> "terlambat 0 bulan" kalau dikirim, padahal dosisnya justru sudah diberikan
> tepat waktu. Klien boleh menampilkan "Sudah disuntik <tanggal>" tanpa
> menyentuh `sisa_bulan` sama sekali.

Bila dosis sudah disuntik, `record` berisi `id`, `date_given`, `batch_number`,
`notes`, dan `kader_id`.

### `POST /kader/children/{child}/immunizations`

| Field | Tipe | Wajib | Keterangan |
| :--- | :--- | :--- | :--- |
| `immunization_type_id` | uuid | Ya | Dosis yang disuntik |
| `date_given` | date | Ya | Format `YYYY-MM-DD` |
| `batch_number` | string(60) | Tidak | Nomor batch vaksin |
| `notes` | string(255) | Tidak | Catatan |

Respons `201` berisi objek suntikan yang baru dibuat.

### Validasi urutan dosis (POST dan PATCH)

Server membandingkan `date_given` dengan suntikan yang **sudah tercatat** pada
dosis tetangga N-1 dan N+1 untuk vaksin dengan `code` yang sama.

Aturan: dosis N tidak boleh lebih awal dari dosis N-1, dan tidak boleh lebih
baru dari dosis N+1.

```json
{
  "success": false,
  "message": "Validasi gagal.",
  "errors": {
    "date_given": [
      "Tanggal suntikan tidak boleh lebih awal dari Hepatitis B (Dosis 1) yang tercatat pada 2026-03-01."
    ]
  }
}
```

**Kenapa tidak mengukum dari master `interval_months`:** anak boleh datang
dengan dosis 2 tanpa dose 1 di sistem ini, misalnya karena dosis 1 diberikan
di fasilitas lain atau catatan hilang. Menolak kasus itu akan menghambat
pekerjaan di lapangan, jadi yang dibandingkan hanya dosis yang ada record-nya.

Record yang sudah dibatalkan (soft delete) tidak ikut dibandingkan.

### `PATCH /kader/immunizations/{record}`

Partial update: `date_given`, `batch_number`, `notes`. **Dosis tidak bisa
dipindah lewat endpoint ini** - memindahkan catatan ke dosis lain berarti
membatalkan satu dosis lalu mencatat yang lain, dua operasi terpisah di
lapangan. Bila tidak ada field yang dikirim, `422`.

Validasi urutan dosis di atas ikut dijalankan pada `PATCH`, dan record yang
sedang diedit dikecualikan dari perbandingan agar tidak dibandingkan dengan
dirinya sendiri.

| HTTP | Kondisi | `message` |
| :--- | :--- | :--- |
| `403` | Ibu memanggil endpoint `/kader/*` | `Akses ditolak.` |
| `404` | anak / record tidak ada | `Data yang diminta tidak ditemukan.` |
| `422` | dosis sudah tercatat untuk anak ini | pesan `immunization_type_id` (dibatasi unique `immunization_child_type_unique`) |
| `422` | tanggal bukan `YYYY-MM-DD` | pesan `date_given` |
| `422` | tanggal mendahului / mendului dosis tetangga | `Validasi gagal.` + `errors.date_given` |
| `422` | `PATCH` tanpa field | `Tidak ada data yang diperbarui.` |

### `DELETE /kader/immunizations/{record}`

Membatalkan suntikan yang tercatat. Record **tidak dihapus fisik** - hanya
ditandai tidak aktif (soft delete), jadi ada jejak auditnya.

Setelah dibatalkan, dosis tersebut kembali bisa dicatat ulang tanpa bentrok
dengan unique constraint, karena `immunization_child_type_unique` sekarang
huni oleh record aktif saja (`WHERE deleted_at IS NULL`).

Kader-only. Di aplikasi, ini dipakai tombol "Batalkan suntikan" pada form
koreksi - kasus ketika yang salah adalah dosisnya, bukan tanggal/batch.

Request body: tidak ada.

Respons `200`:

```json
{
  "success": true,
  "message": "Catatan imunisasi berhasil dibatalkan.",
  "data": { "id": "01a0dc0d-67eb-71e5-81c9-edecb72edeed" }
}
```

| HTTP | Kondisi | `message` |
| :--- | :--- | :--- |
| `403` | Ibu memanggil endpoint `/kader/*` | `Akses ditolak.` |
| `404` | record tidak ada, **sudah pernah dibatalkan**, atau id bukan UUID | `Data imunisasi tidak ditemukan.` |
| `500` | kesalahan server | `Terjadi kesalahan server. Silakan coba lagi.` |

Tidak ada `422` di endpoint ini - tidak ada field yang divalidasi saat
pembatalan.

### `GET /kader/immunizations/recap`

Rekap imunisasi **seluruh Posyandu** untuk satu bulan. Kader-only: Ibu boleh
melihat checklist anaknya sendiri lewat `GET /children/{id}/immunizations`,
tetapi tidak boleh melihat status anak lain, jadi route ini tidak pernah memakai
prefix `/children/{id}`.

| Parameter | Tipe | Wajib | Keterangan |
| :--- | :--- | :--- | :--- |
| `month` | `YYYY-MM` | Tidak | Bulan yang direkap. Default: bulan berjalan |
| `format` | `json` \| `csv` | Tidak | Bentuk respons. Default: `json` |

Responsnya **dua bagian yang tidak boleh dijumlahkan**:

| Bagian | Pertanyaan | Kegunaan |
| :--- | :--- | :--- |
| `activity` | Berapa dosis yang disuntik bulan itu | Stok vaksin |
| `coverage` | Kelengkapan tiap anak di akhir bulan itu | Laporan ke BIDAN, siapkan kunjungan rumah |

```json
{
  "success": true,
  "message": "Rekap imunisasi berhasil diambil.",
  "data": {
    "filter": { "month": "2026-09", "reference_date": "2026-09-30" },
    "activity": {
      "total_doses": 12,
      "total_children": 9,
      "by_type": [
        {
          "immunization_type_id": "01a0ddcb-8197-7184-9c37-fe42f3cc1fd9",
          "code": "HB",
          "name": "Hepatitis B",
          "label": "Hepatitis B",
          "dose_number": 1,
          "count": 4
        }
      ]
    },
    "coverage": {
      "total_children": 25,
      "complete": 12,
      "incomplete": 9,
      "overdue": 4,
      "excluded_archived": 2,
      "overdue_children": [
        {
          "child_id": "01a0d979-c11f-705b-8dd8-a245652c7aa4",
          "name": "Budi Santoso",
          "date_of_birth": "2025-10-15",
          "age_in_months": 11,
          "overdue_doses": [
            {
              "immunization_type_id": "01a0ddcb-8201-7184-9c37-fe42f3cc1fd9",
              "code": "MR",
              "name": "Campak-Rubella",
              "label": "Campak-Rubella (Dosis 1)",
              "dose_number": 1,
              "target_age_months": 9,
              "sisa_bulan": 0
            }
          ]
        }
      ]
    }
  }
}
```

#### Empat aturan yang tidak boleh dilanggar klien

**1. `activity` dan `coverage` tidak boleh dijumlahkan.** Aktivitas menjawab "apa
yang terjadi", coverage menjawab "keadaan apa yang tersisa". Posyandu bisa punya
aktivitas tinggi dan coverage-nya tetap jelek.

**2. `filter.reference_date` adalah akhir bulan yang diminta, bukan hari ini.**
Suntikan dengan `date_given` setelah tanggal itu diabaikan, termasuk saat
menghitung `coverage`. Konsekuensinya laporan lama bisa dipakai sebagai arsip:
rekap September yang dibuat di November angkanya sama dengan yang dibuat di
Oktober. field ini dikirim supaya klien tidak perlu menghitung ulang sendiri,
dan tidak bisa salah mengira rekap ini memakai hari ini.

**3. `by_type` selalu memuat seluruh master 16 dosis, termasuk yang `count`-nya
`0`.** Kader perlu melihat "tidak ada yang disuntik bulan ini" untuk satu jenis
vaksin. Kalau baris nol disembunyikan, "memang tidak ada suntikan" dan "tidak
sempat dicatat" tampil sama saja.

**4. `excluded_archived` adalah anak yang dihitung KECUALI.** Anak yang sudah
di-soft delete tidak masuk `total_children` maupun `overdue`, karena rekap ini
dipakai untuk memutuskan siapa yang dikunjungi. Jumlahnya tetap dilaporkan
supaya angka yang muncul tidak menutupi ada anak yang tidak ikut dihitung.

#### Status anak

| Field | Arti |
| :--- | :--- |
| `complete` | Semua dosis yang usianya sudah tercapai sudah disuntik |
| `incomplete` | Ada dosis jatuh tempo yang belum disuntik |
| `overdue` | Ada dosis yang sudah melewati target + toleransi |

`complete` + `incomplete` selalu sama dengan `total_children`. Dosis yang **belum
jatuh tempo** diabaikan di semua kategori: anak usia 2 bulan tidak boleh
ditandai kurang hanya karena belum waktunya BCG. `complete` bernilai `true` bila
tidak ada satu pun dosis jatuh tempo yang belum disuntik.

#### Urutan `overdue_children`

1. Paling banyak dosis terlambat dulu
2. Jika sama, paling lama terlambat (`sisa_bulan` paling negatif)

Kader bisa langsung tahu siapa dikunjungi duluan tanpa sort manual. Dosis
tanpa `target_age_months` tidak punya `sisa_bulan` dan tidak ikut memengaruhi
urutan.

#### Kesalahan

| HTTP | Kondisi | `message` |
| :--- | :--- | :--- |
| `401` | tanpa / token tidak valid | `Akses ditolak.` |
| `403` | Ibu memanggil endpoint ini | `Akses ditolak.` |
| `422` | `month` bukan `YYYY-MM` atau bulan tidak ada (mis. `2026-13`) | `Validasi gagal.` + `errors.month` |
| `422` | `format` selain `json` / `csv` | `Validasi gagal.` + `errors.format` |

Tidak ada `404`: bulan yang tidak ada aktivitasnya tetap `200` dengan angka nol.

#### `format=csv`

`GET /kader/immunizations/recap?month=2026-09&format=csv` mengembalikan
**berkas** untuk laporan ke BIDAN, bukan JSON.

| Header | Nilai |
| :--- | :--- |
| `Content-Type` | `text/csv; charset=UTF-8` |
| `Content-Disposition` | `attachment; filename="rekap-imunisasi-2026-09.csv"` |

Isinya satu file dengan tiga bagian berurutan, sama dengan urutan di layar:

```
Rekap Imunisasi - Posyandu Desa Sukamaju
Bulan: 2026-09
Dihitung sampai: 2026-09-30
Dicetak: 2026-09-29 14:05 WIB

AKTIVITAS SUNTIKAN
Kode,Dosis,Nama Vaksin,Jumlah Disuntik
BCG,1,BCG,3
HB,1,Hepatitis B,4
MR,1,Campak Rubella,5
TOTAL,,,12

Anak yang disuntik bulan ini,9

KELENGKAPAAN IMUNISASI (pada akhir bulan)
Keterangan,Jumlah Anak
Total anak,25
Imunisasi lengkap,12
Imunisasi belum lengkap,13
Ada dosis terlambat,4
Tidak dihitung (arsip / pindah),2

DAFTAR ANAK TERLAMBAT
No,Nama,Tanggal Lahir,Usia (bulan),Jumlah Dosis Terlambat,Dosis Terlambat,Terlambat (bulan)
1,Budi Santoso,2025-10-15,11,1,Campak Rubella,-9
```

**Tiga aturan yang tidak boleh dilanggar klien file ini:**

**1. Angkanya harus sama persis dengan JSON.** CSV dibangun dari array yang
sama persis dengan yang dikirim ke JSON - bukan query terpisah. Kalau ada
perhitungan yang berubah, keduanya berubah bersama. Export yang angkanya
berbeda dari layar adalah kegagalan paling mahal di fitur ini, karena laporan
yang salah akan dipakai untuk memutuskan kunjungan.

**2. Baris `count: 0` tetap ditulis, dan satu anak tetap satu baris.** Di layar,
baris nol disembunyikan di balik toggle; di berkas tidak ada toggle, jadi "tidak
ada suntikan" harus tetap bisa dibedakan dari "tidak sempat dicatat". Dosis
telat milik satu anak digabung ke satu sel dengan pemisah `; ` supaya daftar
nama anak bisa langsung disalin ke daftar kunjungan.

**3. Formatnya untuk Excel di Windows, bukan untuk mesin.** BOM UTF-8 di depan
file, pemisah baris `CRLF`, dan nilai teks yang diawali `=`, `+`, `-`, `@`
diberi awalan tanda kutip tunggal supaya Excel tidak memperlakukannya sebagai
formula. Tanggal ditulis ISO (`2026-09-30`), bukan nama bulan bahasa
Indonesia, supaya tidak pernah tampil berbeda dari yang dibaca kader.

> **Belum dipakai dari aplikasi mobile.** Unduh lewat browser atau `curl` dulu.
> Tombol export di aplikasi perlu `path_provider` + `share_plus`, dan itu
> penambahan dependency yang belum disetujui.

> **Sudah dipakai di aplikasi:** layar Kader "Rekap Imunisasi" di
> `posyandu_mobile/lib/screens/kader/rekap_imunisasi_screen.dart`. Klien tidak
> menjumlahkan `activity` dengan `coverage`, tidak menghitung status ulang, dan
> tidak mengurutkan ulang `overdue_children` — semuanya apa adanya dari server.
> Parser-nya diuji terhadap JSON asli di
> `posyandu_mobile/test/kontrak_api_test.dart`.

> **Status dihitung dari `ImmunizationChecklistService` yang sama dengan checklist
> anak.** Satu anak bisa muncul dengan `overdue_doses` berbeda di dua endpoint
> hanya kalau ada dua salinan aturan status, dan itu tidak terjadi. Sumbernya
> satu: `evaluate()`.
>
> `sisa_bulan` di `overdue_doses` selalu terisi (dosis yang telat pasti punya
> batas). Di `checklist` anak, `sisa_bulan` bernilai `null` untuk dosis
> berstatus `sudah` - countdown-nya tidak relevan di sana, dan angka yang
> tersisa akan menampilkan "terlambat X bulan" untuk dosis yang justru sudah
> diberikan tepat waktu.

## Jadwal Posyandu (Agenda Kegiatan)

Satu agenda = **satu kegiatan pada tanggal tertentu**, bukan jadwal kunjungan
per anak. Satu agenda bisa ditangani beberapa petugas lewat pivot
`posyandu_schedule_petugas`.

Status agenda: `terjadwal`, `berlangsung`, `selesai`, `dibatalkan`
(dibatasi CHECK constraint di database).

### `GET /schedules`

| Parameter | Tipe | Keterangan |
| :--- | :--- | :--- |
| `date` | `YYYY-MM-DD` | Filter agenda pada tanggal tertentu |

```json
{
  "success": true,
  "message": "Daftar jadwal posyandu berhasil diambil.",
  "data": [
    {
      "id": "01a0ddcb-81e1-7060-8710-81d18ae89d7d",
      "title": "Penimbangan Rutin Bulanan",
      "description": "Penimbangan dan pengukuran tinggi badan balita.",
      "scheduled_date": "2026-11-02",
      "start_time": "08:00",
      "end_time": "11:00",
      "location": "Posyandu Desa Sukamaju",
      "location_name": "Posyandu Desa Sukamaju",
      "status": "terjadwal",
      "notes": null,
      "created_by": "01a0d979-c297-704b-b89a-d66ff76f2474",
      "creator_name": "Kader Siti",
      "petugas_ids": ["01a0d979-c297-704b-b89a-d66ff76f2474"],
      "petugas": [
        { "id": "01a0d979-c297-704b-b89a-d66ff76f2474", "name": "Kader Siti", "jabatan": "Kader Posyandu" }
      ],
      "created_at": "2026-09-26T12:58:16+00:00",
      "updated_at": "2026-09-26T12:58:16+00:00"
    }
  ]
}
```

> `location_name` selalu terisi: kalau kolom `location` kosong, server memakai
> `config('posyandu.posyandu_name')`. Satu lokasi dipakai untuk seluruh aplikasi,
> jadi tidak ada tabel lokasi terpisah.

### `POST /kader/schedules`

| Field | Tipe | Wajib | Keterangan |
| :--- | :--- | :--- | :--- |
| `title` | string(120) | Ya | Nama kegiatan |
| `scheduled_date` | date | Ya | Format `YYYY-MM-DD` |
| `description` | string(500) | Tidak | |
| `start_time` | time | Tidak | Format `HH:MM` (24 jam) |
| `end_time` | time | Tidak | Harus `>=` `start_time` |
| `status` | enum | Tidak | Default `terjadwal` |
| `location` | string(120) | Tidak | Kosongkan untuk memakai nama posyandu dari config |
| `notes` | string(500) | Tidak | |
| `petugas_ids` | uuid[] | Tidak | **Harus user dengan role `kader`** |

Respons `201` berisi agenda yang baru, termasuk `petugas` hasil sinkronisasi.

### `PATCH /kader/schedules/{id}`

Partial update dengan field yang sama. Dua hal yang mudah terlewat:

- **`petugas_ids: []` berarti MENGOSONGKAN seluruh penugasan.** Server memakai
  `sync`, bukan `syncWithoutDetaching`. Bila field-nya tidak dikirim sama sekali,
  penugasan lama tidak berubah.
- **`created_by` tidak pernah berubah** walau Kader lain yang mengedit.

### `DELETE /kader/schedules/{id}`

Respons `200` berisi `id` agenda yang dihapus. Penugasan di pivot ikut terhapus.
Menghapus ulang id yang sama membalas `404`.

| HTTP | Kondisi | `message` |
| :--- | :--- | :--- |
| `403` | Ibu memanggil endpoint `/kader/*` | `Akses ditolak.` |
| `403` | `petugas_ids` menunjuk user role `ibu` | pesan `petugas_ids` |
| `422` | `end_time` < `start_time` | pesan `end_time` |
| `422` | `status` di luar enum | pesan `status` |
| `422` | tidak ada field yang dikirim | `Tidak ada data yang diperbarui.` |
| `404` | id agenda tidak ada | `Data yang diminta tidak ditemukan.` |

## Daftar Petugas

`GET /petugas` — terbuka untuk Ibu dan Kader, karena Ibu perlu tahu siapa
petugas yang menangani agendasnya.

```json
{
  "success": true,
  "message": "Daftar petugas posyandu berhasil diambil.",
  "data": [
    {
      "id": "01a0d979-c297-704b-b89a-d66ff76f2474",
      "name": "Kader Siti",
      "jabatan": "Kader Posyandu",
      "phone_number": null
    }
  ]
}
```

> **NIK tidak pernah dikirim.** Kolom yang dibaca query sudah dikunci lewat
> `select('id', 'name', 'jabatan', 'phone_number')`, jadi kolom sensitif baru di
> tabel `users` tidak akan bocor tanpa sengaja mengubah query ini. `id` tetap
> dikirim karena mobile memakainya untuk menyinkronkan penugasan di pivot agenda.
>
> `jabatan` (`"Bidan"` / `"Kader Posyandu"`) murni deskriptif untuk ditampilkan.
> Otorisasi tetap memakai `role`, yang hanya punya dua nilai: `ibu` / `kader`.

## Catatan Keluhan Kader (Opsi C)

Keluhan yang dilihat kader saat penimbangan. Satu anak punya **satu catatan per
tanggal**, dan catatan bisa berdiri sendiri tanpa penimbangan.

Empat endpoint, bukan lima: endpoint baca sengaja dipakai bersama Ibu dan Kader
(pola yang sama seperti `/children/{id}/immunizations`), jadi tidak perlu route
`/kader/children/{id}/medical-notes` yang isinya akan identik.

| Method | Path | Akses |
| :--- | :--- | :--- |
| `GET` | `/children/{id}/medical-notes` | Ibu (anaknya sendiri) + Kader |
| `POST` | `/kader/children/{child}/medical-notes` | Kader |
| `PATCH` | `/kader/medical-notes/{note}` | Kader |
| `DELETE` | `/kader/medical-notes/{note}` | Kader |

### Kenapa keluhan disimpan sebagai tiga kolom boolean

Kolomnya `demam`, `rewel`, `diare` — bukan satu daftar STRING dan bukan satu baris
per keluhan. Alasannya rekap bulanan (Opsi E) nanti harus bisa menjawab "berapa
anak bulan ini punya demam" dengan satu aggregate:

```sql
SELECT count(DISTINCT child_id) FROM medical_notes
WHERE demam = true AND note_date BETWEEN '2026-09-01' AND '2026-09-30';
```

Kalau keluhan disimpan sebagai array atau baris per keluhan, hitungan itu jadi
jauh lebih mahal dan tidak bisa dijawab lewat index. Konsekuensinya, menambah
jenis keluhan baru berarti menambah kolom boolean lewat migration baru.

### `GET /children/{id}/medical-notes`

| Query | Tipe | Default | Keterangan |
| :--- | :--- | :--- | :--- |
| `month` | `string \| null` | bulan berjalan | Format `YYYY-MM` |
| `all` | `boolean` | `false` | `all=1` mengabaikan `month` |

```json
{
  "success": true,
  "message": "Data catatan keluhan berhasil diambil.",
  "data": {
    "child": { "id": "01a0d979-c11f-705b-8dd8-a245652c7aa4", "name": "Budi Santoso" },
    "filter": { "month": "2026-09", "all": false },
    "summary": {
      "total": 2,
      "demam": 1,
      "rewel": 1,
      "diare": 1,
      "perlu_rujuk": 1
    },
    "notes": [
      {
        "id": "01a0d979-c33f-705b-8dd8-a245652c7bb5",
        "child_id": "01a0d979-c11f-705b-8dd8-a245652c7aa4",
        "measurement_id": "01a0d979-c22f-705b-8dd8-a245652c7cc6",
        "kader_id": "01a0d979-c0f7-727e-903e-fc1892439685",
        "note_date": "2026-09-27",
        "demam": true,
        "rewel": false,
        "diare": false,
        "keluhan": ["Demam"],
        "catatan": "Demam sejak semalam, masih mau makan.",
        "tindak_lanjut": "rujuk",
        "ringkasan": "Demam; Perlu rujukan",
        "kader": { "id": "01a0d979-c0f7-727e-903e-fc1892439685", "name": "Kader Rina" }
      }
    ]
  }
}
```

> **`keluhan` dan `ringkasan` dihitung server, jangan dihitung ulang di mobile.**
> Keduanya berasal dari tiga kolom boolean yang sama, jadi menghitungnya lagi
> di Flutter hanya membuka pintu untuk tampilan yang berbeda antara Kader dan Ibu.
>
> **`summary` juga dibaca apa adanya.** Kalau mobile menjumlahkan sendiri dari
> `notes`, angkanya bisa berbeda dari database tanpa error yang terasa.
>
> `catatan` boleh `null` atau string kosong. `tindak_lanjut` `null` berarti kader
> belum memutuskan — itu kondisi normal, **bukan** data rusak, jadi jangan
> ditampilkan sebagai "Tidak diketahui".

### `POST /kader/children/{child}/medical-notes`

```json
{
  "note_date": "2026-09-27",
  "demam": true,
  "rewel": false,
  "diare": false,
  "catatan": "Demam sejak semalam, masih mau makan.",
  "tindak_lanjut": "rujuk",
  "measurement_id": "01a0d979-c22f-705b-8dd8-a245652c7cc6"
}
```

Membalas `201`. Field yang perlu diperhatikan:

- **`kader_id` tidak pernah dikirim.** Server selalu mengisinya dari user yang
  login, jadi tidak ada cara bagi Kader A untuk menuliskan nama Kader B.
- **`measurement_id` opsional.** Keluhan tetap sah tanpa penimbangan; kalau
  filled, server memverifikasi measurement itu memang milik anak tersebut.
- **`catatan` dan `tindak_lanjut` boleh dihilangkan** (null-safe di sisi
  mobile). Field yang bernilai kosong tidak ikut dikirim ke server.
- `note_date` maksimal hari ini, format `YYYY-MM-DD`.

### `PATCH /kader/medical-notes/{note}`

Partial update, hanya field yang dikirim yang berubah. Membalas `200`.

> **`note_date` BOLEH diubah** — berbeda dari koreksi suntikan yang mengunci
> tanggal. Salah pilih hari di kalender adalah kesalahan yang wajar terjadi,
> jadi cara memperbaikinya adalah mengoreksi tanggal, bukan membatalkan catatan
> lalu mencatat ulang.
>
> Bila tanggal hasil koreksi sudah dipakai catatan lain, `422` dengan
> `errors.note_date`.

### `DELETE /kader/medical-notes/{note}`

Soft delete, membalas `200` berisi `id` yang dibatalkan. Baris tidak hilang dari
database sehingga riwayat kesehatan anak tetap bisa diaudit, dan tanggal yang
sama boleh dicatat ulang setelahnya.

### Kode error

| HTTP | Kondisi | `message` / `errors` |
| :--- | :--- | :--- |
| `403` | Ibu memanggil endpoint `/kader/*` | `Akses ditolak.` |
| `403` | Ibu membaca catatan anak orang lain | `Akses ditolak.` |
| `422` | tidak ada keluhan dicentang **dan** `catatan` kosong | pesan `catatan` |
| `422` | `tindak_lanjut` di luar enum | pesan `tindak_lanjut` |
| `422` | satu anak sudah punya catatan pada `note_date` itu | pesan `note_date` |
| `422` | `measurement_id` bukan milik anak tersebut | pesan `measurement_id` |
| `422` | `note_date` di masa depan | pesan `note_date` |
| `404` | `child` / `note` tidak ada, atau UUID tidak valid | `Data yang diminta tidak ditemukan.` |

> Pesan duplikat tanggal sengaja menjelaskan bahwa anak "sudah punya catatan pada
> tanggal tersebut", karena jawaban yang benar dari kader adalah **mengoreksi**
> catatan lama, bukan membuat catatan kedua.

## Respons Penimbangan (Penting untuk mobile)

`POST /api/kader/measurements` mengembalikan `age_in_months`, `z_score_wfa`, dan `status_gizi`
yang dihitung oleh trigger database:

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

> ⚠️ `weight_kg`, `height_cm`, dan `z_score_wfa` dikirim sebagai **string** karena kolomnya
> bertipe `decimal` di PostgreSQL. Selalu konversi dengan `double.parse(x.toString())`.

Rincian perhitungan, klasifikasi `status_gizi`, dan cara rollback ada di
`docs/LAPORAN_ZSCORE_TRIGGER.md`.

> **Known issues**:
> - Belum ada endpoint untuk melihat daftar anak yang sudah di-soft delete
>   (butuh `withTrashed()`), dan belum ada `restore` via API.
> - `login` menghapus SEMUA token lama milik user tersebut, jadi login di satu
>   device akan memutus sesi device lain.
> - Belum ada paginasi pada daftar anak, riwayat penimbangan, agenda, maupun
>   checklist imunisasi.
> - Belum ada endpoint untuk memindahkan catatan suntikan dari satu dosis ke
>   dosis lain (lihat catatan di bagian Imunisasi).
> - Agenda tidak bisa di recurring (mis. "setiap bulan Rabu"), jadi jadwal rutin
>   harus dibuat manual satu per satu.
>
> **Sudah diperbaiki**:
> - Request ke endpoint API tanpa token dan **tanpa** header
>   `Accept: application/json` sekarang membalas `401` dengan envelope yang
>   benar. Sebelumnya `Authenticate` middleware memanggil `route('login')` yang
>   tidak ada di aplikasi ini (API-only, login dilakukan di Flutter), sehingga
>   hasilnya `500` dan mobile tidak bisa membedakan "sesi habis" dari
>   "server rusak". Diperbaiki lewat `redirectGuestsTo` di `bootstrap/app.php`.
> - Nama ibu dikirim sebagai nested object `mother` (bukan `parent_name`) pada
>   **keduanya** `/children` (Ibu maupun Kader) dan `/kader/children`, sehingga
>   dashboard Ibu tidak lagi menampilkan `-`.
> - Semua error (termasuk `401`, `403`, `404`, `405`, `422`, `429`) sekarang
>   memakai envelope `{success, message, errors}` yang konsisten - lihat
>   `bootstrap/app.php`. Sebelumnya `401` membalas `{"message":"Unauthenticated."}`.
> - `POST /login` dan `POST /register` dibatasi `throttle` (default 10/menit dan
>   30/menit, diatur lewat `LOGIN_THROTTLE` / `REGISTER_THROTTLE`).
> - Daftar anak (`GET /children`, `GET /kader/children`, `GET /children/{id}`)
>   sekarang ikut mengirim **ringkasan penimbangan terakhir**, supaya Dashboard
>   Ibu tidak perlu request tambahan:
>
>   | Field | Tipe | Keterangan |
>   |-------|------|------------|
>   | `last_measurement_date` | `string \| null` | Tanggal penimbangan terakhir (`YYYY-MM-DD`), `null` bila anak belum pernah ditimbang |
>   | `latest_z_score` | `number \| null` | Z-Score W/A terakhir, sudah dihitung trigger PostgreSQL |
>   | `nutritional_status` | `string \| null` | Klasifikasi status gizi, mis. `"Gizi Buruk"` |
>
>   Objek `latest_measurement` **sengaja tidak dikirim** (disembunyikan lewat
>   `$hidden` pada model `Child`) karena isinya sudah diringkas di 3 field di atas.
>   Catatan: nama relasi pada `$hidden` ditulis **camelCase**
>   (`latestMeasurement`) karena `relationsToArray()` memfilter `$hidden`
>   sebelum men-snake_case key-nya.
>
>   Untuk riwayat penimbangan lengkap, Ibu belum punya endpoint sendiri -
>   `GET /kader/measurements?child_id=` masih restricted Kader.

### Layar Flutter yang memakai endpoint baru

| Layar | File | Endpoint |
| :--- | :--- | :--- |
| Status imunisasi (Ibu) | `lib/screens/ibu/status_imunisasi_screen.dart` | `GET /children/{id}/immunizations` |
| Imunisasi + input (Kader) | `lib/screens/kader/imunisasi_screen.dart` | `GET /children/{id}/immunizations`, `POST` + `PATCH` + `DELETE` |
| Jadwal posyandu (Ibu) | `lib/screens/ibu/jadwal_posyandu_screen.dart` | `GET /schedules` |
| Jadwal posyandu (Kader) | `lib/screens/kader/jadwal_posyandu_screen.dart` | `GET /schedules`, `GET /petugas`, `POST`/`PATCH`/`DELETE` |
| Catatan keluhan (Ibu) | `lib/screens/ibu/catatan_keluhan_screen.dart` | `GET /children/{id}/medical-notes` |
| Catatan keluhan (Kader) | `lib/screens/kader/catatan_keluhan_screen.dart` | `GET /children/{id}/medical-notes`, `POST` + `PATCH` + `DELETE` |

Entry point di dashboard:

- **Ibu** — tombol "Jadwal Posyandu" di Menu Cepat, kartu "Status Imunisasi" dan
  "Catatan Keluhan" di bawahnya, untuk anak yang sedang dipilih.
- **Kader** — tombol "Jadwal Posyandu" di Menu Utama, dan ikon vaksin di
  AppBar `detail_anak_screen.dart` untuk mencatat/mengoreksi suntikan.
- **Catatan keluhan** — ikon denyut jantung di AppBar `detail_anak_screen.dart`
  dan baris "Buka Catatan Keluhan" di halaman profil anak (Kader).

## Kode Error Seragam (Aturan #8)

Semua respons error dari API — baik dari controller maupun dari exception handler
Laravel — memakai satu bentuk:

```json
{
  "success": false,
  "message": "Deskripsi utama error",
  "errors": null
}
```

| HTTP | Kapan | `message` default |
| :--- | :--- | :--- |
| `401` | token tidak ada / kedaluwarsa / sudah dilogout | `Sesi tidak valid atau telah berakhir. Silakan login kembali.` |
| `403` | role tidak berwenang | `Akses ditolak.` |
| `404` | endpoint atau data tidak ada | `Endpoint tidak ditemukan.` / `Data yang diminta tidak ditemukan.` |
| `405` | metode HTTP salah | `Metode HTTP tidak diizinkan untuk endpoint ini.` |
| `422` | validasi gagal | `Validasi gagal.` + `errors` per-field |
| `429` | melewati batas percobaan | `Terlalu banyak percobaan. Silakan coba lagi beberapa saat lagi.` |
| `500` | kesalahan server | `Terjadi kesalahan server. Silakan coba lagi.` |

> Detail internal (SQLSTATE, nama tabel, nama route, path file) **tidak pernah**
> dikirim ke klien — hanya ditulis ke `storage/logs/laravel.log`.

