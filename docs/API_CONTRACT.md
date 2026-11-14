# API Contract & Endpoints

Base URL: `http://localhost:8000/api`

## Authentication (Public)
| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `POST` | `/register` | Mendaftarkan akun baru — [role ditentukan server](#role-ditentukan-server-bukan-pilih-dari-input) |
| `POST` | `/login` | Masuk dan mendapatkan Bearer Token |

## Status Akun & `next_action`

`status` adalah sumber kebenaran di database. API juga mengirim dua field
turunan pada objek `user`:

| Field | Nilai | Arti |
| :--- | :--- | :--- |
| `verification_status` | `pending` | `status = pending` — menunggu persetujuan Kader |
| `verification_status` | `approved` | `status = active` — sudah disetujui Kader |
| `verification_status` | `rejected` | `status = rejected` — ditolak Kader |
| `onboarding_status` | `need_child_data` | Ibu sudah disetujui tetapi belum punya data anak |
| `onboarding_status` | `completed` | Data anak sudah ada / onboarding selesai |
| `next_action` | `complete_registration` | Ibu masih `pending`; lengkapi data pendaftaran |
| `next_action` | `fix_registration` | Ibu `rejected`; perbaiki lalu kirim ulang |
| `next_action` | `add_child` | Ibu `approved`; tambahkan data anak |
| `next_action` | `null` | Tidak ada langkah wajib; boleh masuk dashboard |

`verification_status` adalah **kolom generated stored** di `users` yang
diturunkan dari `users.status` (`pending` -> `pending`, `active` -> `approved`,
`rejected` -> `rejected`). Accessor model selalu menghitung dari `status` agar
respons tetap benar setelah approval tanpa perlu `refresh()`.

## Role Ditentukan Server (bukan pilih dari input)

`role` **tidak pernah** dipercaya dari body request. Server yang memutuskan:

| Body request | `KADER_REGISTRATION_CODE` di `.env` | Hasil |
| :--- | :--- | :--- |
| tanpa `role` / `role: "ibu"` | — | Akun **`ibu`** dengan `status: pending` (`201`) |
| `role: "kader"` tanpa `kader_code` | terisi | `403` — kode wajib diisi |
| `role: "kader"` + `kader_code` salah | terisi | `403` — kode tidak cocok |
| `role: "kader"` + `kader_code` benar | terisi | Akun **`kader`** dengan `status: active` (`201`) |
| `role: "kader"` + kode apa pun | **kosong** | `403` — pendaftaran kader dimatikan |
| `role` selain `kader` (mis. `"admin"`) | — | `422` |

> Akun `ibu` yang mendaftar sendiri langsung mendapat **token**, tetapi aksesnya
> dibatasi middleware sampai datanya lengkap dan disetujui Kader. Token ini
> diperlukan agar klien bisa memanggil endpoint pelengkapan data. Akun `kader`
> yang terdaftar dengan kode valid langsung berstatus `active`.

### Request body `POST /register`

| Field | Tipe | Wajib | Keterangan |
| :--- | :--- | :--- | :--- |
| `nik` | string(16 digit) | Ya | NIK, unik |
| `name` | string | Ya | Nama lengkap |
| `password` | string | Ya | Minimal 8 karakter |
| `password_confirmation` | string | Ya | Harus sama dengan `password` (`422` bila tidak) |
| `no_kk` | string(16 digit) | Tidak | Nomor Kartu Keluarga; **tidak unik** karena satu KK dipakai bersama |
| `phone_number` | string(16) | Tidak | Nomor HP |
| `place_of_birth` | string(100) | Tidak | Tempat lahir |
| `date_of_birth` | date | Tidak | Tanggal lahir, tidak boleh di masa depan |
| `gender` | enum(`L`,`P`) | Tidak | Jenis kelamin |
| `blood_type` | enum(`A`,`B`,`AB`,`O`) | Tidak | Golongan darah |
| `address` | text | Tidak | Alamat lengkap (diwajibkan saat `/registration/complete`) |
| `rt_rw` | string(10) | Tidak | Format seperti `001/002` |
| `education` | enum(`SD`,`SMP`,`SMA`,`SMK`,`D3`,`S1`,`S2`,`S3`,`other`) | Tidak | Pendidikan terakhir |
| `occupation` | string(100) | Tidak | Pekerjaan |
| `role` | `"kader"` | Tidak | Hanya boleh bernilai `kader`. Kosong = `ibu` |
| `kader_code` | string | Kader¹ | Kode dari `KADER_REGISTRATION_CODE` |
| `verification_file` | file(jpg,jpeg,png) | Tidak | Bukti verifikasi, maksimal 2 MB |
| `verification_type` | enum(`self_photo`,`kk`,`other`) | Tidak | Jenis bukti verifikasi |

¹ Wajib hanya bila `role` = `kader`.

### Respons sukses

**Untuk akun `ibu` (pending, dengan token):**
```json
{
  "success": true,
  "message": "Pendaftaran berhasil. Akun Anda menunggu persetujuan dari Kader Posyandu.",
  "data": {
    "user": {
      "id": "...",
      "name": "...",
      "role": "ibu",
      "status": "pending",
      "verification_status": "pending",
      "onboarding_status": "need_child_data",
      "next_action": "complete_registration"
    },
    "status": "pending",
    "token": "1|xxxxxxxx"
  }
}
```

**Untuk akun `kader` (active, dengan token):**
```json
{
  "success": true,
  "message": "Registrasi kader berhasil.",
  "data": {
    "user": { "id": "...", "name": "...", "role": "kader" },
    "token": "1|xxxxxxxx"
  }
}
```

### Kode error `POST /register`
| HTTP | Kondisi | `message` |
| :--- | :--- | :--- |
| `422` | validasi gagal / NIK sudah terdaftar | `Validasi gagal.` + `errors` per-field |
| `403` | kode kader salah/kosong | `Pendaftaran akun kader ditolak.` |
| `429` | melewati batas percobaan | `Terlalu banyak percobaan. Silakan coba lagi beberapa saat lagi.` |

## Login

`POST /login` — memeriksa NIK + password. **Semua akun yang kredensialnya benar
mendapat token**, termasuk Ibu `pending` dan `rejected`. Pembatasan akses
dilakukan middleware, bukan dengan menolak login, supaya Ibu tetap bisa
memperbaiki pendaftarannya.

Respons sukses berisi `data.user`, `data.token`, `data.status`, dan
`data.next_action`. `message` menyesuaikan status akun.

| HTTP | Kondisi | `message` |
| :--- | :--- | :--- |
| `200` | Ibu `pending` | `Akun Anda sedang menunggu verifikasi oleh Kader Posyandu.` |
| `200` | Ibu `rejected` | `Pendaftaran Anda ditolak. Alasan: ...` |
| `200` | Ibu `approved` + `need_child_data` | `Login berhasil. Lengkapi data anak Anda terlebih dahulu.` |
| `200` | Ibu `approved` + `completed` / Kader | `Login berhasil` |
| `401` | NIK/password salah | `Kredensial yang diberikan tidak cocok dengan data kami.` |
| `429` | melewati batas percobaan | `Terlalu banyak percobaan. Silakan coba lagi beberapa saat lagi.` |

## Alur Pendaftaran & Onboarding Ibu

1. `POST /register` → akun `ibu`, `status = pending`,
   `onboarding_status = need_child_data`, token diterbitkan.
2. `POST /registration/complete` (Bearer token **atau** `nik`) → melengkapi
   profil dan/atau mengunggah bukti verifikasi. Status tetap `pending`.
3. Kader menyetujui lewat `POST /kader/registrations/{user}/approve` →
   `status = active`, `verification_status = approved`.
4. Ibu login → token → `next_action = add_child` bila belum punya anak.
5. `POST /registration/child` → menyimpan data anak dan mengubah
   `onboarding_status = completed`.
6. Ibu dapat mengakses dashboard (`GET /children`, `/ibu/reminders`, dll).

Bila Kader menolak, `status = rejected` dan `next_action = fix_registration`.
Ibu dapat memanggil `POST /registration/complete` lagi; status otomatis
kembali ke `pending` dan alasan penolakan dibersihkan.

## Middleware Akses Ibu

| Middleware | Efek |
| :--- | :--- |
| `kader.verification` | Ibu `pending`/`rejected` ditolak `403` dari area dashboard. Kader selalu lolos. |
| `child.onboarding` | Ibu `approved` dengan `onboarding_status = need_child_data` ditolak `403` sampai punya anak. Kader selalu lolos. |

Endpoint yang tetap dapat diakses Ibu `pending`/`rejected`: `POST /logout`,
`GET /profile`, `PUT/PATCH /profile`, `GET /user`, `GET /registration/status`,
`POST/PUT/PATCH /registration/complete`.

`POST /registration/child` hanya memakai `kader.verification` (bukan
`child.onboarding`), karena endpoint inilah jalan keluar dari status
`need_child_data`.

Respons `403` dari middleware selalu memakai envelope standar dan menyertakan
`errors.next_action`:

```json
{
  "success": false,
  "message": "Lengkapi data anak terlebih dahulu sebelum mengakses dashboard.",
  "errors": {
    "onboarding_status": ["Data anak belum dilengkapi."],
    "next_action": ["add_child"],
    "endpoint": ["POST /api/registration/child"]
  }
}
```

## Registration & Onboarding (Public / Protected)

| Method | Endpoint | Akses | Description |
| :--- | :--- | :--- | :--- |
| `GET` | `/registration/status` | Token atau `?nik=` | Status pendaftaran + data verifikasi |
| `POST`/`PUT`/`PATCH` | `/registration/complete` | Token atau `nik` | Lengkapi/perbaiki data pendaftaran Ibu |
| `POST` | `/registration/child` | Bearer token, Ibu `approved` | Simpan data anak dan selesaikan onboarding |

### `GET /registration/status`

Dapat memakai Bearer token atau query `?nik=3273...`. Lewat token, respons
berisi user yang sedang login. Lewat NIK, hanya akun dengan status
`pending`/`rejected` yang dicari. Respons berisi objek `user` beserta
`verifications`.

### `POST /registration/complete`

Menerima `application/json` atau `multipart/form-data` (bila mengunggah berkas).

| Field | Tipe | Wajib | Keterangan |
| :--- | :--- | :--- | :--- |
| `nik` | string(16 digit) | Tidak | Boleh dikirim ulang; unik kecuali milik akun sendiri |
| `no_kk` | string(16 digit) | Tidak | Nomor KK |
| `name` | string(255) | Tidak | Nama lengkap |
| `phone_number` | string(16) | Tidak | Nomor HP |
| `place_of_birth` | string(100) | Tidak | Tempat lahir |
| `date_of_birth` | date | Tidak | Tanggal lahir |
| `gender` | enum(`L`,`P`) | Tidak | Jenis kelamin |
| `blood_type` | enum(`A`,`B`,`AB`,`O`) | Tidak | Golongan darah |
| `address` | text(1000) | **Ya** | Alamat lengkap |
| `rt_rw` | string(10) | Tidak | Format `001/002` |
| `education` | enum(`SD`,`SMP`,`SMA`,`SMK`,`D3`,`S1`,`S2`,`S3`,`other`) | Tidak | Pendidikan terakhir |
| `occupation` | string(100) | Tidak | Pekerjaan |
| `verification_file` | file(jpg,jpeg,png) | Tidak | Bukti verifikasi, maksimal 2 MB |
| `verification_type` | enum(`self_photo`,`kk`,`other`) | Tidak | Jenis bukti verifikasi |

Respons `200` berisi `data` = objek `user` terbaru.

### `POST /registration/child`

Memerlukan Bearer token Ibu yang sudah `approved`. Semua field lahir wajib
karena dipakai untuk skrining awal dan koreksi usia prematur.

| Field | Tipe | Wajib | Keterangan |
| :--- | :--- | :--- | :--- |
| `nik` | string(16 digit) | Ya | NIK anak, unik termasuk data yang sudah di-soft delete |
| `name` | string(255) | Ya | Nama anak |
| `place_of_birth` | string(100) | Ya¹ | Tempat lahir |
| `birth_place` | string(100) | Ya¹ | Alias lama `place_of_birth` |
| `date_of_birth` | date(`Y-m-d`) | Ya | Tidak boleh di masa depan |
| `gender` | enum(`L`,`P`) | Ya | Jenis kelamin |
| `birth_order` | integer | Ya | Urutan kelahiran, 1–20 |
| `birth_weight` | numeric | Ya | Berat lahir, 0,5–10 kg |
| `birth_length` | numeric | Ya | Panjang lahir, 20–70 cm |
| `birth_head_circumference` | numeric | Ya | Lingkar kepala lahir, 20–60 cm |
| `birth_status` | enum(`normal`,`premature`) | Ya | Status kelahiran |
| `buku_kia_id` | string(50) | Tidak | Nomor/identitas Buku KIA |
| `consent_type` | enum(`data_processing`,`data_sharing`,`research`) | Tidak | Persetujuan UU PDP |
| `consent_document_version` | string(20) | Ya² | Versi dokumen persetujuan |

¹ Salah satu dari `place_of_birth`/`birth_place` wajib ada. Keduanya
disinkronkan ke kolom yang sama.
² Wajib bila `consent_type` dikirim.

Respons `201`:

```json
{
  "success": true,
  "message": "Data anak berhasil disimpan. Onboarding selesai.",
  "data": {
    "child": { "id": "...", "name": "...", "birth_length": "48.50" },
    "user": { "id": "...", "onboarding_status": "completed", "next_action": null }
  }
}
```

`birth_length` adalah nama kanonis. `birth_height` adalah **generated column**
dari `birth_length`, jadi server tidak menulisnya lagi; klien lama tetap bisa
membaca nilai yang sama.

## Profile (Protected)
| Method | Endpoint | Description | Role Akses |
| :--- | :--- | :--- | :--- |
| `GET` | `/profile` | Ambil profil + status approval + verifikasi | Ibu / Kader |
| `PUT`/`PATCH` | `/profile` | Update profil (bisa ganti password) | Ibu / Kader |

## Kader - Persetujuan Registrasi Ibu (Protected, Kader only)
| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET` | `/kader/registrations?status=pending|active|rejected` | List permohonan registrasi ibu |
| `GET` | `/kader/registrations/{user}` | Detail permohonan + data profil + berkas verifikasi |
| `POST` | `/kader/registrations/{user}/approve` | Setujui permohonan |
| `POST` | `/kader/registrations/{user}/reject` | Tolak permohonan (wajib `rejection_reason`) |
| `PATCH` | `/kader/registrations/{user}` | Koreksi data pendaftaran oleh Kader |
