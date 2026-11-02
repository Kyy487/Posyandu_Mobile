# API Contract & Endpoints

Base URL: `http://localhost:8000/api`

## Authentication (Public)
| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `POST` | `/register` | Mendaftarkan akun baru — [role ditentukan server](#role-ditentukan-server-bukan-pilih-dari-input) |
| `POST` | `/login` | Masuk dan mendapatkan Bearer Token |

## Role Ditentukan Server (bukan pilih dari input)

`role` **tidak pernah** dipercaya dari body request. Server yang memutuskan:

| Body request | `KADER_REGISTRATION_CODE` di `.env` | Hasil |
| :--- | :--- | :--- |
| tanpa `role` / `role: "ibu"` | — | Akun **`ibu`** dengan `status: pending` (perlu persetujuan kader) (`201`) |
| `role: "kader"` tanpa `kader_code` | terisi | `403` — kode wajib diisi |
| `role: "kader"` + `kader_code` salah | terisi | `403` — kode tidak cocok |
| `role: "kader"` + `kader_code` benar | terisi | Akun **`kader`** dengan `status: active` (`201`) |
| `role: "kader"` + kode apa pun | **kosong** | `403` — pendaftaran kader dimatikan |
| `role` selain `kader` (mis. `"admin"`) | — | `422` |

> Akun `ibu` yang mendaftar sendiri **tidak langsung bisa login**. Akun dibuat dengan `status = pending` dan harus disetujui oleh Kader Posyandu terlebih dahulu. Akun `kader` yang terdaftar dengan kode valid langsung berstatus `active`.

### Request body `POST /register`

| Field | Tipe | Wajib | Keterangan |
| :--- | :--- | :--- | :--- |
| `nik` | string(16) | Ya | NIK, unik |
| `name` | string | Ya | Nama lengkap |
| `password` | string | Ya | Minimal 8 karakter |
| `password_confirmation` | string | Ya | Harus sama dengan `password` (`422` bila tidak) |
| `phone_number` | string(15) | Tidak | Nomor HP |
| `place_of_birth` | string(100) | Tidak | Tempat lahir |
| `date_of_birth` | date | Tidak | Tanggal lahir |
| `gender` | enum(`L`,`P`) | Tidak | Jenis kelamin |
| `address` | text | Tidak | Alamat lengkap |
| `role` | `"kader"` | Tidak | Hanya boleh bernilai `kader`. Kosong = `ibu` |
| `kader_code` | string | Kader¹ | Kode dari `KADER_REGISTRATION_CODE` |
| `verification_file` | file(jpg,jpeg,png,pdf) | Tidak | Bukti verifikasi (maks 5MB) |
| `verification_type` | enum(`self_photo`,`kk`,`other`) | Tidak | Jenis bukti verifikasi |

¹ Wajib hanya bila `role` = `kader`.

### Respons sukses
**Untuk akun `ibu` (pending, tanpa token):**
```json
{
  "success": true,
  "message": "Pendaftaran berhasil. Akun Anda menunggu persetujuan dari Kader Posyandu.",
  "data": {
    "user": { "id": "...", "name": "...", "role": "ibu", "status": "pending" },
    "status": "pending"
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

### Kode error
| HTTP | Kondisi | `message` |
| :--- | :--- | :--- |
| `422` | validasi gagal | `Validasi gagal.` + `errors` per-field |
| `403` | kode kader salah/kosong | `Pendaftaran akun kader ditolak.` |
| `401` | login gagal | `Kredensial yang diberikan tidak cocok dengan data kami.` |
| `403` | akun ibu masih pending | `Akun Anda masih menunggu persetujuan dari Kader Posyandu.` |
| `403` | akun ibu ditolak | `Pendaftaran Anda ditolak. Alasan: ...` |
| `429` | melewati batas percobaan | `Terlalu banyak percobaan. Silakan coba lagi beberapa saat lagi.` |

## Login
`POST /login` — Hanya akun dengan `status: active` yang mendapat token. Akun `pending`/`rejected` ditolak dengan `403`.

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
