# Rencana Terpadu Satu Pintu — Smart Posyandu

> **Dokumen induk tunggal ("satu pintu")** untuk rencana, status, dan arah pengembangan.
> Dokumen ini menggabungkan seluruh dokumen perencanaan, status, dan laporan lama yang kini
> **diarsipkan di `docs/arsip/`**. Dokumen teknis (kontrak API, skema DB, cara menjalankan,
> log setup) tetap terpisah — lihat §9.
>
> **Terakhir diperbarui:** 15 November 2026<br>
> **Prinsip kerja:** kalkulasi Z-score WHO **hanya** di trigger/function PostgreSQL, bukan di PHP.<br>
> **Fokus saat ini:** Menutup Fase 1.5 (data IHS, terminologi KFA/CVX, red flags, rehearsal staging, pilot admin), lalu masuk Fase 2A SATUSEHAT.

**Cara baca:** `[x]` = selesai · `[ ]` = belum · `[~]` = sebagian.

---

## 1. Latar Belakang & Perubahan Arah

Berdasarkan evaluasi saat ini, ada beberapa penyesuaian arah pengembangan:

| Perubahan | Keterangan |
|---|---|
| **Hapus Smart Triage (IoT)** | Lingkup terlalu besar (butuh hardware + integrasi). Modul ini akan dipindahkan ke `docs/arsip/` dan dihapus dari roadmap aktif. |
| **Registrasi berbasis persetujuan kader** | User yang mendaftar dengan role `ibu` **tidak bisa langsung login**. Harus menunggu persetujuan dari Kader Posyandu terlebih dahulu. |
| **Pengetatan data profil pengguna** | Data diri Ibu perlu dilengkapi & diverifikasi: Nama lengkap, NIK, Tempat/Tanggal Lahir, Jenis Kelamin, Alamat, No. HP. |
| **Wajib lampirkan bukti pendaftaran** | Calon Ibu wajib mengunggah foto bukti (foto diri + KK atau bukti lain). File disimpan di `storage/app/public/verifications/`, bukan sebagai blob di database. |
| **Pengetatan data anak** | Data anak diperketat (Nama lengkap, Tempat Lahir, Tanggal Lahir, Jenis Kelamin). Anak hanya bisa didaftarkan oleh Ibu dengan status **aktif** (sudah disetujui kader). |

---

## 2. Ringkasan Proyek

Sistem Informasi Manajemen Terpadu untuk mendigitalisasi pencatatan kesehatan ibu dan anak (KIA) di Posyandu.

| Layer | Teknologi |
|---|---|
| Backend | Laravel 13 (REST API), PHP 8.4 |
| Database | PostgreSQL (`posyandu_db`) — logika Z-score WHO lewat trigger/function |
| Auth | Laravel Sanctum (token-based), role `ibu` / `kader` |
| Mobile | Flutter (Dart) |

**Author:** Moch Riezky Dwi Kuswanto — Institut Teknologi Nasional (Itenas), Informatika.

**Prinsip kunci:**
- Logika `z_score_*` dan `status_*` **wajib** di trigger/function PostgreSQL.
- Primary key **UUID** (`HasUuids`), FK `foreignUuid()`.
- Migration **additive** — jangan ubah migration yang sudah dijalankan.
- Jangan ubah `AuthController`, struktur route, atau schema inti tanpa instruksi eksplisit.

---

## 3. Status Saat Ini

### 3.1 Fondasi & Autentikasi
- [x] REST API Laravel 13 + PostgreSQL, envelope respons seragam (`success`/`message`/`data`).
- [x] Autentikasi Sanctum, role `ibu` / `kader` (role ditentukan server).
- [x] CRUD Data Anak (Kader & Ibu).
- [x] Edit data anak oleh Kader.
- [x] Primary key UUID + soft delete di tabel inti.

### 3.2 e-KMS & Penilaian Gizi WHO
- [x] Penimbangan (`measurements`) + `z_score_wfa` & `status_gizi` (BB/U) via trigger PostgreSQL.
- [x] Tabel referensi WHO (WFA, HFA, BFA, WFH) lengkap.
- [x] Validasi WHO multidimensi + fungsi LMS.
- [x] Kolom indikator WHO pada `measurements`.
- [x] Koreksi & pembatalan penimbangan (e-KMS).
- [x] Grafik Tumbuh Kembang **multidimensi** (BB/U, TB/U, IMT/U).

### 3.3 Imunisasi & Jadwal
- [x] Master `immunization_types` (21 dosis aktif sesuai Program Imunisasi Rutin Kemenkes).
- [x] Status dihitung ulang tiap request.
- [x] Jadwal Posyandu + penugasan petugas.
- [x] Rekap bulanan & export CSV.

### 3.4 Rekam Medis & Kunjungan
- [x] Buku Medis Digital / Timeline.
- [x] `medical_flags` pada anak.
- [x] Catatan Keluhan Kader.
- [x] Entitas **Kunjungan** (`visits`) sebagai payung layanan.
- [x] **Rujukan** (`referrals`) tertaut ke kunjungan & anak.

### 3.5 Tata Kelola Data (P1)
- [x] **Audit trail** (`audit_logs`).
- [x] **Consent UU PDP** (`consents`).
- [x] **Enkripsi NIK** + `nik_hash`.

### 3.6 Dalam Perbaikan / Prioritas Baru
- [x] **Alur persetujuan registrasi Ibu (Kader approval)** — **P0 (BARU)**
- [x] **Perbaikan data profil user (kelengkapan + verifikasi)** — **P0 (BARU)**
- [x] **Pengetatan data anak & guard status ibu aktif** — **P0 (BARU)**
- [x] **Standarisasi data Fase 1** — IHS anak, role admin, waktu kunjungan,
  terminologi imunisasi, red flags, sosial media, mapper/validator FHIR.
- [x] **Observability & security dasar** — redaksi log, rate limit login,
  guard admin, retensi audit 5 tahun, log aplikasi 30 hari.
- [~] **Fase 1.5 kesiapan produksi** — menunggu format IHS final, mapping
  KFA/CVX, persetujuan red flags, rehearsal staging, dan pilot admin.
- [ ] **Notifikasi lokal terjadwal** (backend ada, mobile belum)
- [ ] **Evaluasi klinis** (validasi Z-score vs WHO Anthro)
- [ ] **Uji coba kader**
- [ ] **Performance test**

### 3.7 Dihapus/Ditunda
- [ ] **Smart Triage (IoT)** — Dipindahkan ke arsip, tidak dalam scope aktif
- [ ] **Fitur AI kompleks** (Food Scanner, dll) — Ditunda hingga kriteria terpenuhi
- [ ] **Pemetaan Spasial (PostGIS)** — Ditunda
- [~] **Offline-First Sync** — Ditunda
- [~] **Pengiriman SATUSEHAT otomatis** — Draft dan validasi FHIR sudah selesai;
  pengiriman nyata masuk Fase 2A.

---

## 4. Rancangan Registrasi & Validasi Akun

### 4.1 Alur Registrasi Ibu (Berbasis Persetujuan)

```text
1. Calon Ibu mengisi form register (profil lengkap + upload foto bukti verifikasi)
2. Akun tercipta dengan status = pending (TIDAK BISA LOGIN)
3. Kader membuka menu "Permohonan Registrasi" di aplikasi kader
4. Kader melihat detail permohonan: data diri, NIK, alamat, no HP, foto bukti
5. Kader dapat "Setujui" atau "Tolak" (wajib isi alasan jika ditolak)
6. Jika disetujui -> status jadi active, user bisa login & menambah data anak
7. Jika ditolak -> status rejected, tidak bisa login (alasan penolakan ditampilkan)
```

### 4.2 Perubahan Skema Database

#### Tabel `users` (Penambahan Kolom)
| Kolom | Tipe | Keterangan |
|---|---|---|
| `status` | `enum('pending','active','rejected')` | Default `pending` untuk role `ibu`. Role `kader` dapat langsung `active`. |
| `place_of_birth` | `string(100)` | Tempat lahir |
| `date_of_birth` | `date` | Tanggal lahir |
| `gender` | `enum('L','P')` | Jenis kelamin |
| `address` | `text` | Alamat lengkap |
| `approved_by` | `uuid` FK -> `users.id` | Kader yang menyetujui/menolak |
| `approved_at` | `timestamp` nullable | Waktu validasi |
| `rejection_reason` | `text` nullable | Alasan penolakan |
| `verified_at` | `timestamp` nullable | Waktu verifikasi |

#### Tabel `user_verifications` (Baru)
| Kolom | Tipe | Keterangan |
|---|---|---|
| `id` | `uuid` PK | Primary key |
| `user_id` | `uuid` FK -> `users.id` (cascade delete) | Pemilik permohonan |
| `type` | `enum('self_photo','kk','other')` | Jenis bukti |
| `file_path` | `string` | Path file di `storage/app/public/verifications/...` |
| `file_name` | `string` nullable | Nama asli file |
| `mime_type` | `string(50)` nullable | Tipe file untuk preview |
| `uploaded_at` | `timestamp` | Waktu upload |

> **Catatan:** File disimpan di storage, bukan sebagai `bytea` di PostgreSQL untuk efisiensi dan kemudahan preview.

### 4.3 Perubahan API Contract

#### Auth
| Method | Endpoint | Akses | Keterangan |
|---|---|---|---|
| `POST` | `/register` | Public | **Diubah:** Membuat akun `role: ibu` dengan `status: pending`, wajib upload bukti verifikasi, **tidak mengembalikan token**. |
| `POST` | `/login` | Public | **Diubah:** Akun `pending`/`rejected` tetap mendapat token agar bisa melengkapi/memperbaiki pendaftaran. Respons `200` berisi `message`, `data.status`, dan `data.next_action`; akses dashboard dibatasi middleware, bukan dengan menolak login. |

#### Kader - Manajemen Permohonan Registrasi
| Method | Endpoint | Akses | Keterangan |
|---|---|---|---|
| `GET` | `/kader/registrations` | Kader | List permohonan dengan filter `?status=pending|rejected|approved` |
| `GET` | `/kader/registrations/{user}` | Kader | Detail permohonan + data profil + daftar berkas verifikasi |
| `POST` | `/kader/registrations/{user}/approve` | Kader | Setujui permohonan. Set `status=active`, `approved_by`, `approved_at` |
| `POST` | `/kader/registrations/{user}/reject` | Kader | Tolak permohonan. **Wajib** kirim `rejection_reason`. Set `status=rejected` |

#### Profil Pengguna
| Method | Endpoint | Akses | Keterangan |
|---|---|---|---|
| `GET` | `/profile` | Ibu/Kader (terautentikasi) | Ambil profil lengkap termasuk status & approval info |
| `PUT`/`PATCH` | `/profile` | Ibu/Kader (terautentikasi) | Lengkapi/perbarui data profil |

---

## 5. Perbaikan Data User & Data Anak

### 5.1 Pengetatan Data Profil Ibu
Saat registrasi, wajib melengkapi minimal:
- Nama lengkap
- NIK (16 digit, unik, terenkripsi)
- Tempat lahir
- Tanggal lahir
- Jenis kelamin (`L`/`P`)
- Alamat lengkap
- Nomor HP
- Minimal 1 berkas bukti verifikasi

### 5.2 Pengetatan Data Anak
| Aturan | Keterangan |
|---|---|
| **Wajibkan field lengkap** | `name`, `place_of_birth`/`birth_place`, `date_of_birth`, `gender` wajib diisi. |
| **Hanya bisa didaftarkan oleh Ibu aktif** | Guard baru: jika `mother.status !== 'active'` → `403 "Akun Ibu belum disetujui oleh Kader Posyandu."` |
| **Kader juga tunduk aturan** | Saat Kader mendaftarkan anak untuk Ibu, Ibu yang dituju harus berstatus `active`. |
| **Data lebih mirip form Posyandu** | Penyesuaian field agar konsisten dengan pencatatan di Posyandu. |

---

## 6. Roadmap Revisi (Fokus Saat Ini)

### Urutan Pelaksanaan

| Urutan | Tugas | Prioritas | Status | Keterangan |
|---|---|---|---|---|
| **1** | **Dokumen terpusat (SATU PINTU)** | P0 | **SELESAI** | Buat file ini `docs/RENCANA_UNIFIED_SATU_PINTU.md` sebagai acuan tunggal. |
| **2** | **Migrasi DB (User + Verifikasi)** | P0 | **SELESAI** | Tambah kolom status & biodata ke `users`. Buat tabel `user_verifications`. |
| **3** | **Auth (Register/Login)** | P0 | **SELESAI** | Ubah alur register (pending + upload bukti), ubah login dengan cek status. |
| **4** | **Approval Kader** | P0 | **SELESAI** | Endpoint + UI kader untuk list/detail/approve/reject permohonan. |
| **5** | **Perketat Data Anak** | P0 | **SELESAI** | Guard status ibu aktif, perkuat validasi field wajib anak. |
| **6** | **Pindah/arsip IoT Smart Triage** | P1 | **SELESAI** | Dipindahkan/arsipkan atau dikeluarkan dari scope aktif. |
| **7** | **Testing Alur** | P1 | **SELESAI** | Registrasi, approval, guard anak, unggah bukti, serta login akun `pending`/`rejected` sudah diuji lewat `LoginStatusTest`. |
| **8** | **Standarisasi data Fase 1** | P1 | **SELESAI** | IHS, waktu, terminologi, red flags, sosial media, FHIR draft/validasi, import CSV admin. |
| **9** | **Observability & security dasar** | P1 | **SELESAI** | Redaksi log, rate limit, guard admin, retensi audit, CORS ketat, security headers, token 30 hari, dokumentasi secret manager. |
| **10** | **Finalisasi data eksternal Fase 1.5** | P1 | **BELUM** | Format IHS final, mapping KFA/CVX, persetujuan red flags. |
| **11** | **Rehearsal staging + pilot admin** | P1 | **BELUM** | Migrasi data staging, dry-run import, import nyata, rollback, audit review. |
| **12** | **Fase 2A SATUSEHAT** | P2 | **BERIKUTNYA** | OAuth, outbox, queue, retry, idempotency, pengiriman resource, rekonsiliasi. |

### Prioritas Keseluruhan

| Prioritas | Item | Status | Keterangan |
|---|---|---|---|
| **P0** | Alur Persetujuan Registrasi Ibu | **SELESAI** | Fondasi akses aplikasi Ibu |
| **P0** | Pengetatan Profil & Verifikasi | **SELESAI** | Kelengkapan data & keamanan |
| **P0** | Entitas Visit, WHO Multidimensi, Imunisasi Kemenkes | **Selesai** | Sudah dikerjakan |
| **P1** | Audit trail, Consent UU PDP, Enkripsi NIK | **Selesai** | Sudah dikerjakan |
| **P1** | Arsipkan Smart Triage (IoT) | **SELESAI** | Dikeluarkan dari scope aktif |
| **P1** | Standarisasi Fase 1 + FHIR draft | **Selesai** | IHS, waktu, terminologi, red flags, mapper/validator |
| **P1** | Observability & security dasar | **Selesai** | Redaksi log, rate limit, retensi audit, CORS, header, token expiry |
| **P1** | Fase 1.5 kesiapan produksi | **Berjalan** | Menunggu data eksternal dan staging |
| **P2** | Fase 2A pengiriman SATUSEHAT | **Berikutnya** | OAuth, outbox, queue, retry, rekonsiliasi |
| **P2** | Backup & retensi, Evaluasi klinis | **Sebagian** | Retensi audit/log selesai; backup dan evaluasi klinis belum |
| **P2** | Notifikasi lokal (mobile) | **Belum** | Backend ready, mobile pending |
| **P3** | Fitur AI, Offline Sync, PostGIS | **Ditunda** | Sesuai kebijakan |

### Fase Pengembangan Saat Ini
- **Fase 1-4:** Selesai
- **Fase 1.5 (Kesiapan produksi):** Sedang berjalan. Observability & security
  dasar selesai; data IHS final, mapping KFA/CVX, red flags, rehearsal staging,
  dan pilot admin masih menunggu.
- **Fase 2A (SATUSEHAT):** Berikutnya setelah seluruh item A-G di
  `docs/CHECKLIST_FASE_1_5.md` selesai dengan bukti.
- **Fase 5 (Evaluasi):** Dilakukan setelah Fase 2A stabil.

---

## 7. Modul & Dokumen Arsip

### Modul Aktif
| Modul | Status | Keterangan |
|---|---|---|
| e-KMS & WHO Multidimensi | Selesai | Grafik tumbuh kembang lengkap |
| Imunisasi & Jadwal Kemenkes | Selesai | 21 dosis, rekap & CSV |
| Buku Medis / Timeline | Selesai | Riwayat medis gabungan |
| Kunjungan (Visit) & Rujukan | Selesai | Payung layanan terpadu |
| Tata Kelola (Audit, Consent, Enkripsi) | Selesai | Pematuhan kebijakan |
| **Registrasi & Approval Ibu** | **SELESAI** | Fondasi akses aplikasi |
| **Standarisasi Fase 1 + FHIR draft** | **SELESAI** | IHS, waktu, terminologi, red flags |
| **Observability & security dasar** | **SELESAI** | Redaksi log, retensi, rate limit |
| **Fase 1.5 kesiapan produksi** | **Berjalan** | Menunggu data eksternal/staging |

### Dokumen Arsip
Spesifikasi lengkap modul yang sudah selesai atau ditunda ada di `docs/arsip/`.

| Modul | Status | Dokumen |
|---|---|---|
| Master Plan MVP | Rancangan acuan | `arsip/RANCANGAN.md` |
| Penguatan Sistem (P0–P3) | Acuan utama | `arsip/PERANCANGAN_PERKUATAN.md` |
| Buku Medis / Timeline | Selesai | `arsip/RANCANGAN_BUKU_MEDIS.md` |
| Grafik Tumbuh Kembang | Selesai | `arsip/RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md` |
| WHO Multidimensi | Selesai | `arsip/RANCANGAN_WHO_MULTIDIM.md` |
| Imunisasi & Jadwal Kemenkes | Selesai | `arsip/RANCANGAN_IMUNISASI_JADWAL.md` |
| Kunjungan (Visit) | Selesai | `arsip/RANCANGAN_VISIT.md` |
| Rujukan | Selesai | `arsip/RANCANGAN_RUJUKAN.md` |
| Enkripsi NIK | Selesai | `arsip/RANCANGAN_ENKRIPSI_NIK.md` |
| Notifikasi | Belum | `arsip/RANCANGAN_NOTIFIKASI.md` |
| Smart Triage (IoT) | **Ditunda/Dipindah** | `arsip/RANCANGAN_SMART_TRIAGE.md` (akan dipindahkan) |
| Rencana kerja lanjutan | Acuan | `arsip/RENCANA_KERJA_BERIKUTNYA.md` |

---

## 8. Aturan Wajib Saat Bekerja

1. **Z-score hanya di PostgreSQL** — Logika `z_score_*` dan `status_*` wajib di trigger/function PostgreSQL.
2. **UUID everywhere** — Primary key **UUID** (`HasUuids`), FK `foreignUuid()`.
3. **Migration additive** — Jangan ubah migration yang sudah dijalankan. Hanya tambah migration baru.
4. **Jangan ubah inti tanpa izin** — Jangan ubah `AuthController`, struktur route, atau schema inti tanpa instruksi eksplisit.
5. **Persetujuan sebelum perubahan besar** — Jangan jalankan/mengubah/commit apa pun tanpa persetujuan pengguna.
6. **Data WHO** — Diambil dari `docs/data_who/` (format xlsx).
7. **Kontrak terkunci** — Kontrak yang dikunci harus diubah di dokumen lebih dulu, baru di kode.
8. **Simpan file di storage** — Untuk upload bukti verifikasi, gunakan `storage/app/public/`, bukan blob di database.
9. **Akun pending tidak bisa login** — Pastikan filter status diterapkan di login dengan pesan yang jelas.

---

## 9. Dokumen Teknis (Terpisah)

| Kebutuhan | Dokumen |
|---|---|
| Aturan teknis agen | `AI_AGENT_RULES.md` |
| Kontrak API | `API_CONTRACT.md` |
| Skema database | `DATABASE_SCHEMA.md` |
| Cara menjalankan | `Cara_menjalankan.md` |
| Setup & riwayat teknis | `SETUP_LOG.md` |
| Data referensi WHO | `data_who/` |
| Aturan turunan backend | `posyandu-backend/.ai/rules/` |
| Dokumen lama (arsip) | `arsip/` |
| **Dokumen induk saat ini** | **`RENCANA_UNIFIED_SATU_PINTU.md`** |

---

**Status:** Steps 1-9 selesai; testing alur dan observability/security dasar
sudah selesai. Fokus berikutnya adalah menutup Fase 1.5 (data IHS, KFA/CVX,
red flags, rehearsal staging, pilot admin), lalu masuk Fase 2A SATUSEHAT.
Hasil teknis terbaru: `7917057`, `2c143dc`, `f11cff5`; full test 328 lulus,
2363 assertion.
