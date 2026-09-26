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
| `GET` | `/children` | List anak milik user | Ibu / Kader |
| `POST` | `/children` | Mendaftarkan anak baru | Ibu |
| `GET` | `/children/{id}`| Detail anak, pengukuran, imunisasi | Ibu / Kader |

### Kader (POSYANDU)
| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET` | `/kader/children` | List anak yang tercatat di Posyandu |
| `POST` | `/kader/children` | Mendaftarkan anak oleh kader |
| `GET` | `/kader/measurements` | Riwayat penimbangan |
| `POST` | `/kader/measurements` | Input penimbangan (e-KMS) — endpoint yang dipakai mobile |
| `DELETE` | `/kader/measurements/{id}` | Hapus penimbangan |

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

> ⚠️ **Known issues**: response `401` belum memakai envelope `{success, message}`
> dan `/children` mengirim nama ibu sebagai nested object `mother` (bukan `parent_name`).
