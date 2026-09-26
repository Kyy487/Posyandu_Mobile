# 🌐 API Contract & Endpoints

Base URL: `http://localhost:8000/api`

## Authentication (Public)
| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `POST` | `/register` | Mendaftarkan akun baru (Kader/Ibu) |
| `POST` | `/login` | Masuk dan mendapatkan Bearer Token |

## Protected Routes (Requires Bearer Token)
Header Wajib: `Authorization: Bearer {token}` & `Accept: application/json`

### Children (Data Anak)
| Method | Endpoint | Description | Role Akses |
| :--- | :--- | :--- | :--- |
| `GET` | `/children` | List anak milik user (Ibu) atau seluruh anak (Kader) | Ibu / Kader |
| `POST` | `/children` | Mendaftarkan anak baru — **[kontrak unified](#menambah-data-anak-kontrak-unified)** | Ibu / Kader |
| `GET` | `/children/{id}`| Detail anak, pengukuran, imunisasi | Ibu / Kader |

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

> ⚠️ **Known issues**:
> - Response `401` (unauthenticated) belum memakai envelope `{success, message}`.
> - Belum ada `PUT`/`PATCH`/`DELETE` untuk data anak.
>
> ✅ **Sudah diperbaiki**: nama ibu dikirim sebagai nested object `mother` (bukan `parent_name`)
> pada **keduanya** `/children` (Ibu maupun Kader) dan `/kader/children`, sehingga dashboard Ibu
> tidak lagi menampilkan `-`.
