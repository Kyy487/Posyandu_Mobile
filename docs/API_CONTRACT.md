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
| `DELETE` | `/kader/measurements/{id}` | Hapus penimbangan |

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


### Immunization *(Draft)*
| Method | Endpoint | Description | Role Akses |
| :--- | :--- | :--- | :--- |
| `POST` | `/immunizations`| Input data vaksinasi baru | Kader |

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
> - Belum ada paginasi pada daftar anak maupun riwayat penimbangan.
>
> **Sudah diperbaiki**:
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

