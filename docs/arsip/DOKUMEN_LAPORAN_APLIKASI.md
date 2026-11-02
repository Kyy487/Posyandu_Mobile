# Smart Posyandu — Sistem Informasi Posyandu Digital

> **Status:** Dalam Pengembangan (Beta)  
> **Versi:** 0.9.0  
> **Tanggal:** 30 September 2026

---

## 1. Latar Belakang

Posyandu (Pos Pelayanan Terpadu) merupakan wadah pelayanan kesehatan dasar bagi balita di tingkat masyarakat. Selama ini, pencatatan pertumbuhan balita dilakukan secara manual menggunakan buku KMS (Kartu Menuju Sehat) yang memiliki beberapa keterbatasan:

- Rentan terhadap kesalahan perhitungan status gizi
- Data sulit dianalisis untuk pelaporan
- Tidak ada pengingat jadwal imunisasi
- Riwayat kesehatan balita tersebar dan sulit dilacak

**Smart Posyandu** hadir sebagai solusi digitalisasi yang menjawab permasalahan tersebut.

---

## 2. Tujuan Aplikasi

1. Mencatat pertumbuhan balita secara digital dan akurat
2. Menghitung status gizi balita otomatis berdasarkan standar WHO
3. Memantau kelengkapan imunisasi dasar balita
4. Memudahkan kader dalam mencatat keluhan dan tindak lanjut
5. Menyediakan rekap data untuk pelaporan ke puskesmas
6. Memberikan akses informasi kepada ibu balita kapan saja

---

## 3. Pengguna Aplikasi

| Role | Deskripsi | Hak Akses |
|------|-----------|-----------|
| **Ibu** | Ibu dari balita terdaftar | Melihat data anak, riwayat pengukuran, imunisasi, dan catatan |
| **Kader** | Kader Posyandu | Akses penuh: input data, pengukuran, imunisasi, catatan, jadwal |

---

## 4. Fitur-Fitur Aplikasi

### 4.1 Manajemen Akun

| Fitur | Keterangan |
|-------|-----------|
| Registrasi Ibu | Ibu mendaftar dengan NIK, nama, password. Role ditentukan server. |
| Registrasi Kader | Memerlukan kode registrasi khusus yang ditentukan admin. |
| Login | NIK + password, menghasilkan token autentikasi. |
| Logout | Token dicabut, sesi berakhir. |

---

### 4.2 Data Balita

| Fitur | Keterangan |
|-------|-----------|
| Pendaftaran Balita | Kader mendaftarkan balita baru: NIK, nama, tanggal lahir, jenis kelamin, berat/tinggi lahir, catatan khusus. |
| Daftar Balita | Ibu hanya melihat anaknya; Kader melihat semua balita. |
| Detail Balita | Profil lengkap balita + ringkasan pengukuran terakhir. |
| Timeline Balita | Linimasa gabungan: pengukuran + imunisasi + catatan, dikelompokkan per tanggal kunjungan. |
| Edit & Hapus | Soft delete untuk menjaga integritas data historis. |

---

### 4.3 Pengukuran Pertumbuhan (e-KMS)

Setiap balita diukur secara berkala (berat badan, tinggi badan, lingkar kepala). Sistem menghitung otomatis:

| Komponen | Keterangan |
|----------|-----------|
| **Usia (bulan)** | Dihitung otomatis dari tanggal lahir |
| **Z-Score (WFA)** | Berat badan menurut umur, dihitung dari standar WHO |
| **Status Gizi** | Klasifikasi otomatis: Normal / Gizi Kurang / Gizi Buruk / Risiko Gizi Lebih |

**Standar WHO Weight-for-Age** digunakan sebagai acuan perhitungan, dengan data 122 titik (61 umur × 2 gender).

| Fitur | Keterangan |
|-------|-----------|
| Input Pengukuran | Kader memasukkan berat, tinggi, lingkar kepala. |
| Riwayat Pengukuran | Grafik pertumbuhan dari waktu ke waktu. |
| Pembatalan | Soft delete jika kesalahan input. |

---

### 4.4 Imunisasi Dasar Lengkap

Aplikasi mencatat 16 jenis imunisasi sesuai program pemerintah:

| Jenis Vaksin | Dosis |
|-------------|-------|
| Hepatitis B (HB) | 1 dosis |
| BCG | 1 dosis |
| Polio | 4 dosis |
| DPT-HB-Hib | 3 dosis |
| MR (Campak-Rubela) | 2 dosis |

| Fitur | Keterangan |
|-------|-----------|
| Checklist Otomatis | Status `sudah` / `belum` / `terlambat` dihitung dari tanggal lahir + target usia vaksin. |
| Pencatatan | Tanggal pemberian, nomor batch, catatan. |
| Validasi Dosis | Mencegah pencatatan dosis yang tidak berurutan. |
| Rekap Bulanan | Ringkasan cakupan imunisasi seluruh Posyandu per bulan. |
| Export CSV | Rekap dapat diunduh untuk pelaporan ke puskesmas. |

---

### 4.5 Catatan Keluhan & Tindak Lanjut

Setiap kunjungan, kader dapat mencatat keluhan balita:

| Komponen | Keterangan |
|----------|-----------|
| Keluhan | Demam, Rewel, Diare (checkbox) |
| Catatan Bebas | Deskripsi tambahan |
| Tindak Lanjut | Ringan / Sedang / Rujuk ke Puskesmas |

| Fitur | Keterangan |
|-------|-----------|
| Pencatatan | Kader mencatat keluhan saat kunjungan. |
| Riwayat | Daftar catatan per balita, default bulan berjalan. |
| Koreksi & Pembatalan | Soft delete untuk koreksi data. |

---

### 4.6 Jadwal Posyandu

| Fitur | Keterangan |
|-------|-----------|
| Buat Jadwal | Judul, tanggal, waktu mulai/selesai, lokasi, status, penugasan kader. |
| Daftar Jadwal | Filter berdasarkan tanggal atau rentang tanggal. |
| Status Jadwal | Terjadwal / Berlangsung / Selesai / Dibatalkan. |
| Penugasan Petugas | Banyak kader dapat ditugaskan dalam satu jadwal. |

---

### 4.7 Aplikasi Mobile (Flutter)

Aplikasi mobile memungkinkan Ibu dan Kader mengakses sistem dari smartphone:

| Fitur Mobile | Keterangan |
|-------------|-----------|
| Login/Register | Autentikasi berbasis token |
| Dashboard | Ringkasan data balita |
| Riwayat | Pengukuran, imunisasi, catatan |
| Profil | Data pengguna |

---

## 5. Arsitektur Sistem

```
┌─────────────────────────────────────────────────────┐
│                   Mobile App (Flutter)               │
│         Ibu & Kader akses via smartphone             │
└──────────────────────┬──────────────────────────────┘
                       │ HTTP/JSON (Bearer Token)
┌──────────────────────▼──────────────────────────────┐
│              API Server (Laravel 13)                 │
│  ┌─────────┐ ┌──────────┐ ┌───────────┐            │
│  │  Auth   │ │  Balita  │ │ Imunisasi │            │
│  │Controller│ │Controller│ │Controller │            │
│  └─────────┘ └──────────┘ └───────────┘            │
│  ┌─────────┐ ┌──────────┐ ┌───────────┐            │
│  │Pengukuran│ │ Catatan  │ │  Jadwal   │            │
│  │Controller│ │Controller│ │Controller │            │
│  └─────────┘ └──────────┘ └───────────┘            │
└──────────────────────┬──────────────────────────────┘
                       │ Eloquent ORM
┌──────────────────────▼──────────────────────────────┐
│              PostgreSQL Database                     │
│  ┌─────────────────────────────────────────────┐   │
│  │  Trigger: Kalkulasi Z-Score Otomatis         │   │
│  │  Tabel: users, children, measurements,       │   │
│  │  immunization_records, medical_notes,        │   │
│  │  schedules, who_wfa_standards                │   │
│  └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

---

## 6. Database

### 6.1 Jenis Database

**PostgreSQL** — dipilih karena:
- Native UUID support
- PL/pgSQL trigger function untuk perhitungan Z-score
- Partial unique index untuk soft delete
- Performa tinggi untuk relasi kompleks

### 6.2 Entity Relationship Diagram (ERD)

```
┌──────────────────┐         ┌──────────────────┐
│      users       │         │    children      │
├──────────────────┤         ├──────────────────┤
│ id (PK, UUID)    │◄───────┤│ user_id (FK)     │
│ nik (unique)     │   1:N   │ id (PK, UUID)    │
│ name             │         │ nik (unique)     │
│ password         │         │ name             │
│ role (ibu/kader) │         │ date_of_birth    │
│ phone_number     │         │ gender (L/P)     │
│ jabatan          │         │ birth_weight     │
└───────┬──────────┘         │ birth_height     │
        │                    │ medical_flags    │
        │                    │ deleted_at       │
        │                    └────────┬─────────┘
        │                             │
        │              ┌──────────────┼──────────────┐
        │              │              │              │
        │     ┌────────▼───────┐ ┌───▼────────────┐ │
        │     │  measurements  │ │immunization_    │ │
        │     ├────────────────┤ │records         │ │
        │     │ id (PK)        │ ├────────────────┤ │
        │     │ child_id (FK)  │ │ id (PK)        │ │
        └─────┤ kader_id (FK)  │ │ child_id (FK)  │ │
         1:N  │ measurement_dt │ │ kader_id (FK)  │ │
              │ weight_kg      │ │immunization_   │ │
              │ height_cm      │ │type_id (FK)    │ │
              │ head_circum    │ │ date_given     │ │
              │ age_in_months  │ │ batch_number   │ │
              │ z_score_wfa    │ │ notes          │ │
              │ status_gizi    │ │ deleted_at     │ │
              │ deleted_at     │ └────────────────┘ │
              └────────┬───────┘                    │
                       │                            │
              ┌────────▼───────┐                    │
              │ medical_notes  │                    │
              ├────────────────┤                    │
              │ id (PK)        │                    │
              │ child_id (FK)  │                    │
              │ measurement_id │                    │
              │ kader_id (FK)  │                    │
              │ note_date      │                    │
              │ demam/rewel/   │                    │
              │ diare (bool)   │                    │
              │ catatan        │                    │
              │ tindak_lanjut  │                    │
              │ deleted_at     │                    │
              └────────────────┘                    │
                                                    │
┌──────────────────────┐    ┌──────────────────────┐│
│  immunization_types  │    │ posyandu_schedules   ││
├──────────────────────┤    ├──────────────────────┤│
│ id (PK, UUID)        │◄───┤ id (PK, UUID)        ││
│ code                 │1:N │ title                ││
│ name                 │    │ scheduled_date       ││
│ dose_number          │    │ start/end_time       ││
│ target_age_months    │    │ location             ││
│ interval_months      │    │ status               ││
└──────────────────────┘    │ created_by (FK)      ││
                            └──────────┬───────────┘│
                                       │            │
                            ┌──────────▼───────────┐│
                            │schedule_petugas      ││
                            │(pivot M:N)           ││
                            ├──────────────────────┤│
                            │ schedule_id (FK)     ││
                            │ petugas_id (FK)      ││
                            └──────────────────────┘│
                                                   │
┌──────────────────────┐                           │
│ who_wfa_standards    │                           │
├──────────────────────┤                           │
│ id (PK, UUID)        │                           │
│ age_in_months (0-60) │                           │
│ gender (L/P)         │                           │
│ median_kg            │                           │
│ sd_kg                │                           │
└──────────────────────┘                           │
```

### 6.3 Relasi Antar Tabel

| Relasi | Tipe | Keterangan |
|--------|------|-----------|
| users → children | 1:N | Satu ibu memiliki banyak anak |
| users → measurements | 1:N | Satu kader melakukan banyak pengukuran |
| users → immunization_records | 1:N | Satu kader mencatat banyak imunisasi |
| users → medical_notes | 1:N | Satu kader menulis banyak catatan |
| users → posyandu_schedules | 1:N | Satu kader membuat banyak jadwal |
| users ↔ posyandu_schedules | M:N | Banyak petugas di banyak jadwal (pivot table) |
| children → measurements | 1:N | Satu balita memiliki riwayat pengukuran |
| children → immunization_records | 1:N | Satu balita memiliki riwayat imunisasi |
| children → medical_notes | 1:N | Satu balita memiliki catatan keluhan |
| measurements → medical_notes | 1:N | Pengukuran dapat memiliki catatan |
| immunization_types → immunization_records | 1:N | Jenis vaksin diberikan ke banyak balita |

### 6.4 Tabel WHO Weight-for-Age

Tabel `who_wfa_standards` menyimpan data standar WHO untuk perhitungan Z-score:

| Kolom | Tipe | Keterangan |
|-------|------|-----------|
| age_in_months | SmallInt | 0-60 bulan |
| gender | Char(1) | L (Laki-laki) / P (Perempuan) |
| median_kg | Decimal(5,2) | Median berat badan WHO |
| sd_kg | Decimal(5,2) | Standar deviasi WHO |

Total: 122 baris data (61 umur × 2 gender).

---

## 7. Keamanan Sistem

| Aspek | Implementasi |
|-------|-------------|
| Autentikasi | Token-based (Laravel Sanctum) |
| Otorisasi | Role-based middleware (Ibu vs Kader) |
| Password | Bcrypt hashing |
| SQL Injection | Parameter binding via Eloquent ORM |
| Primary Key | UUID (tidak mudah ditebak/dienumerasi) |
| Soft Delete | Data historis tidak dihapus permanen |
| Role Determination | Server-side (tidak percaya input client) |

---

## 8. Status Pengembangan

### 8.1 Sudah Berfungsi

- Autentikasi login/register dengan role berbeda
- CRUD data balita dengan validasi
- Input pengukuran dengan Z-score otomatis (PostgreSQL trigger)
- Pencatatan imunisasi dengan checklist status otomatis
- Catatan keluhan dengan tindak lanjut
- Manajemen jadwal posyandu dengan penugasan kader
- Rekap imunisasi bulanan + export CSV
- Mobile app (Flutter) untuk Ibu dan Kader
- Timeline riwayat balita (pengukuran + imunisasi + catatan)

### 8.2 Dalam Pengembangan

- Dashboard statistik dengan grafik pertumbuhan
- Notifikasi pengingat jadwal & imunisasi
- Laporan PDF/print untuk puskesmas
- Integrasi dengan sistem puskesmas
- Multi-posyandu (saat ini single posyandu)

---

## 9. Keunggulan Aplikasi

| No | Keunggulan |
|----|-----------|
| 1 | Z-score dihitung otomatis oleh database, bukan manual |
| 2 | Status imunisasi (terlambat/belum) dihitung real-time |
| 3 | Soft delete menjaga integritas data historis |
| 4 | UUID primary key mencegah enumerasi data |
| 5 | Mobile app memudahkan akses di lapangan |
| 6 | Export CSV untuk pelaporan ke puskesmas |
| 7 | Timeline balita menggabungkan semua riwayat dalam satu tampilan |

---

## 10. Kesimpulan

Smart Posyandu merupakan solusi digitalisasi Posyandu yang menjawab permasalahan pencatatan manual. Dengan arsitektur API yang rapi, database yang ternormalisasi, perhitungan status gizi otomatis berbasis standar WHO, dan aplikasi mobile untuk akses di lapangan, aplikasi ini memiliki fondasi yang kuat untuk dikembangkan lebih lanjut menjadi sistem pelayanan kesehatan masyarakat yang terintegrasi.

---

*Dokumen ini disusun sebagai laporan pengembangan aplikasi untuk keperluan evaluasi.*
