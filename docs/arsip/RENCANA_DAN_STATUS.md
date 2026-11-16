# Rencana & Status Pengembangan — Smart Posyandu

> **Dokumen induk tunggal ("satu pintu")** untuk rencana, status, dan laporan pengembangan.
> Ringkasan ini menggabungkan seluruh dokumen perencanaan, status, dan laporan lama yang kini
> **diarsipkan di `docs/arsip/`**. Dokumen teknis (kontrak API, skema DB, cara menjalankan,
> log setup) tetap terpisah — lihat §10.
>
> **Terakhir diperbarui:** 16 Oktober 2026
> **Prinsip kerja:** kalkulasi Z-score WHO **hanya** di trigger/function PostgreSQL, bukan di PHP.

**Cara baca:** `[x]` = selesai · `[ ]` = belum · `[~]` = sebagian.

---

## 1. Ringkasan Proyek

Sistem Informasi Manajemen Terpadu untuk mendigitalisasi pencatatan kesehatan ibu dan anak (KIA)
di Posyandu.

| Layer | Teknologi |
|---|---|
| Backend | Laravel 13 (REST API), PHP 8.4 |
| Database | PostgreSQL (`posyandu_db`) — logika Z-score WHO lewat trigger/function |
| Auth | Laravel Sanctum (token-based), role `ibu` / `kader` |
| Mobile | Flutter (Dart) |
| AI (direncanakan) | Python microservice — deteksi nutrisi (belum dimulai) |

**Author:** Moch Riezky Dwi Kuswanto — Institut Teknologi Nasional (Itenas), Informatika.

**Prinsip kunci:**

- Logika `z_score_*` dan `status_*` **wajib** di trigger/function PostgreSQL (`AI_AGENT_RULES.md` #9).
- Primary key **UUID** (`HasUuids`), FK `foreignUuid()`.
- Migration **additive** — jangan ubah migration yang sudah dijalankan.
- Jangan ubah `AuthController`, struktur route, atau schema inti tanpa instruksi eksplisit.

---

## 2. Visi & Ruang Lingkup (MVP)

Acuan: `docs/arsip/RANCANGAN.md`.

- **Aktor:** hanya dua role — **Kader** (admin/petugas) dan **Ibu** (orang tua). Tanpa super-admin.
- **Pasien:** fokus **Balita**; **Ibu Hamil** direncanakan (Lansia opsional, fase berikutnya).
- **AI:** analisis gizi bersifat **kualitatif/edukatif** — tanpa skor/ kalori numerik kompleks.

**Modul Kader:**

- **EHR / Rekam Medis:** pemisahan kategori pasien, Buku Medis Digital (profil + riwayat),
  data antropometri (BB, TB, lingkar kepala), penanda kondisi khusus (alergi, penyakit bawaan),
  catatan keluhan per kunjungan.
- **Smart Triage (IoT):** *(Dihapus dari scope aktif — dipindahkan ke arsip)*

**Modul Ibu:**

- **e-KMS Mandiri:** grafik pertumbuhan interaktif, riwayat pemeriksaan bulanan + status gizi.
- **Edukasi Kesehatan:** pusat multimedia (video/animasi menyusui, MPASI, sanitasi). *(belum)*
- **"Sepiring Bergizi" (AI Computer Vision):** foto piring → umpan balik kualitatif. *(belum — ditunda)*

---

## 3. Status Fitur

### 3.1 Fondasi & Autentikasi

- [x] REST API Laravel 13 + PostgreSQL, envelope respons seragam (`success`/`message`/`data`).
- [x] Autentikasi Sanctum, role `ibu` / `kader` (role ditentukan server).
- [x] CRUD Data Anak (Kader & Ibu).
- [x] Edit data anak oleh Kader.
- [x] Primary key UUID + soft delete di tabel inti.

### 3.2 e-KMS & Penilaian Gizi WHO

- [x] Penimbangan (`measurements`) + `z_score_wfa` & `status_gizi` (BB/U) via trigger PostgreSQL.
- [x] Tabel referensi `who_wfa_standards` (122 baris, 0–60 bln × 2 gender).
- [x] Validasi WHO multidimensi: **TB/U** (`who_hfa_standards`, 122), **IMT/U** (`who_bfa_standards`, 122),
  **BB/TB** (`who_wfh_standards`, 1302; 45–110 cm, 0–24 bln).
- [x] Function LMS (`calculate_who_zscore_lms`) + perluasan `calculate_measurement_who_zscore`
  (WFA/HFA/WFH/BFA + status komposit).
- [x] Kolom `z_score_hfa`, `z_score_wfh`, `z_score_bfa`, `status_stunting`, `status_gizi_imt`,
  `status_wfh` pada `measurements`.
- [x] Koreksi & pembatalan penimbangan (e-KMS): `PATCH /kader/measurements/{id}` (parsial) +
  `DELETE` (soft delete), mode edit di mobile.
- [x] Grafik Tumbuh Kembang **multidimensi**: `GET /children/{id}/growth` dengan tiga pita WHO
  (BB/U, TB/U, IMT/U) + `who_references` + nilai BMI.

### 3.3 Imunisasi & Jadwal

- [x] Master `immunization_types` (21 dosis aktif sesuai Program Imunisasi Rutin Kemenkes:
  HB-0, BCG, Polio Oral, DPT-HB-Hib, IPV, Rotavirus, PCV, MR, JE).
- [x] Status `sudah` / `belum` / `terlambat` dihitung ulang tiap request (tidak disimpan).
- [x] Jadwal Posyandu (`posyandu_schedules`) + penugasan banyak petugas.
- [x] Rekap suntikan per bulan `GET /kader/immunizations/recap?month=YYYY-MM`
  (`activity` + `coverage`, tanpa N+1).
- [x] Export CSV rekap imunisasi (`?format=csv`) — tiga bagian dalam satu file.
- [x] Kolom `is_active` pada master imunisasi (dosis lama dinonaktifkan, bukan dihapus).

### 3.4 Rekam Medis & Kunjungan

- [x] Buku Medis Digital: `GET /children/{id}/timeline` (per tanggal, paginasi cursor).
- [x] Kolom `children.medical_flags` (kondisi khusus; hanya Kader yang menulis).
- [x] Catatan Keluhan Kader (`medical_notes`) + tindak lanjut ringan/sedang/rujuk.
- [x] Entitas **Kunjungan** (`visits`) — payung satu sesi layanan; `visit_id` di measurements,
  immunization_records, medical_notes.
- [x] Flow mobile "buat kunjungan → input data → selesai".
- [x] **Rujukan** (`referrals`) tertaut ke satu `visit` + satu `child`; terlihat di timeline.

### 3.5 Tata Kelola Data (P1)

- [x] **Audit trail** (`audit_logs` + trait `Concerns\Auditable`); baca via `GET /kader/audit-logs`.
- [x] **Consent UU PDP** (`consents`) + integrasi mobile (checkbox saat daftar anak, layar kelola).
- [x] **Enkripsi NIK** (`users.nik`, `children.nik` cast `encrypted`) + `nik_hash` (SHA-256) untuk login.

### 3.6 Belum Selesai / Backlog

- [ ] **Notifikasi lokal terjadwal** (`flutter_local_notifications`) — endpoint `GET /ibu/reminders`
  & `GET /kader/reminders` sudah ada di backend, tetapi penjadwalan notifikasi di perangkat belum.
- [ ] **Backup & retensi** (runbook `pg_dump` harian, retensi 30 hari + arsip bulanan, uji restore).
- [ ] **Evaluasi klinis** — validasi Z-score trigger vs WHO Anthro (butuh bantuan dosen).
- [ ] **Uji coba kader** (SUS, task completion, error rate) — minimal 5 kader.
- [ ] **Performance test** endpoint berat (timeline/growth/recap) dengan data besar.
- [ ] **KMS Digital interaktif** (pita warna hijau/kuning/merah di grafik).
- [ ] **Dashboard statistik** mobile, **laporan PDF**, **integrasi SIKDA Puskesmas**, **multi-posyandu**.
- [ ] **FHIR-Ready API** (SATUSEHAT), **Offline-First Sync**, **WhatsApp Reminders**, **OCR Buku KIA**.
- [ ] **Fitur AI**: AI Food Scanner / "Sepiring Bergizi", **Pemetaan Spasial (PostGIS)**. *(IoT Smart Triage dihapus dari scope aktif)*

---

## 4. Roadmap Berfase

Acuan: `docs/arsip/PERANCANGAN_PERKUATAN.md` §8, `docs/arsip/RENCANA_KERJA_BERIKUTNYA.md`.

### Fase 1 — Fondasi (Minggu 1–2) — **selesai**

- [x] Migrasi tabel WHO (HFA, WFH, BFA)
- [x] Migrasi tabel `visits`, `referrals`, `consents`, `audit_logs`
- [x] Update trigger Z-score (LMS)
- [x] Update model & migration tabel existing

### Fase 2 — Logika Bisnis (Minggu 3–4) — **selesai**

- [x] Service Visit / Referral / Consent / Audit
- [x] Update `ImmunizationChecklistService` (jadwal Kemenkes)
- [x] Update `MeasurementController` (kaitkan `visit_id`)

### Fase 3 — API & Integrasi (Minggu 5–6) — **selesai**

- [x] Endpoint baru `/visits`, `/referrals`, `/consents`
- [x] Update endpoint existing (kaitkan `visit_id`)
- [x] Audit trail
- [x] Enkripsi NIK

### Fase 4 — Mobile (Minggu 7–8) — **selesai**

- [x] Screen kunjungan + flow "buat kunjungan → input data → selesai"
- [x] Screen rujukan
- [x] Screen consent

### Fase 5 — Evaluasi (Minggu 9–10) — **belum**

- [ ] Unit & feature test kelengkapan (tambal celah, bukan sekadar jumlah)
- [ ] Validasi klinis dengan dosen (Z-score vs WHO Anthro)
- [ ] Uji coba kader
- [ ] Performance test
- [ ] Perbaikan berdasarkan feedback

### Prioritas (P0–P3)

| Prioritas | Item | Status |
|---|---|---|
| **P0** | Entitas Visit | **Selesai** |
| **P0** | Validasi WHO multidimensi | **Selesai** |
| **P0** | Klarifikasi jadwal imunisasi (Kemenkes, 21 dosis) | **Selesai** |
| **P1** | Audit trail | **Selesai** |
| **P1** | Consent management (UU PDP) | **Selesai** |
| **P1** | Enkripsi NIK | **Selesai** |
| **P2** | Backup & retensi | Belum |
| **P2** | Evaluasi klinis | Belum |
| **P3** | Fitur AI | Ditunda sampai kriteria terpenuhi |

---

## 5. Rincian Per Modul

Spesifikasi lengkap tiap modul ada di dokumen arsip.

| Modul | Status | Dokumen arsip |
|---|---|---|
| Master Plan MVP | Rancangan acuan | `arsip/RANCANGAN.md` |
| Penguatan Sistem (roadmap P0–P3 + inovasi) | Acuan utama | `arsip/PERANCANGAN_PERKUATAN.md` |
| Buku Medis / Timeline | Selesai | `arsip/RANCANGAN_BUKU_MEDIS.md` |
| Grafik Tumbuh Kembang | Selesai (diamendemen) | `arsip/RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md` |
| WHO Multidimensi | Selesai | `arsip/RANCANGAN_WHO_MULTIDIM.md` |
| Imunisasi & Jadwal Kemenkes | Selesai | `arsip/RANCANGAN_IMUNISASI_JADWAL.md` |
| Kunjungan (Visit) | Selesai | `arsip/RANCANGAN_VISIT.md` |
| Rujukan | Selesai | `arsip/RANCANGAN_RUJUKAN.md` |
| Enkripsi NIK | Selesai | `arsip/RANCANGAN_ENKRIPSI_NIK.md` |
| Notifikasi | Belum | `arsip/RANCANGAN_NOTIFIKASI.md` |
| Rencana kerja lanjutan | Acuan | `arsip/RENCANA_KERJA_BERIKUTNYA.md` |
| Status (versi sebelumnya) | Arsip | `arsip/STATUS_PENGEMBANGAN.md` |

---

## 6. Riwayat Laporan

Ringkasan hasil tiap modul; detail di `docs/arsip/LAPORAN_*.md`.

- **`LAPORAN_ZSCORE_TRIGGER.md`** — perbaikan trigger Z-Score WHO (BB/U) yang semula mati total
  dan selalu menghasilkan "Normal" palsu. Laravel 2/2, kontrak Flutter 6/6.
  *Temuan terbuka:* envelope 401 belum rapi, Ibu belum bisa akses riwayat penimbangan.
- **`LAPORAN_IMUNISASI_JADWAL.md`** — fitur Imunisasi (16 dosis awal) + Jadwal Posyandu;
  5 migration, 9 endpoint baru. *Temuan:* pengingat agenda & rekap per bulan belum ada
  (dilanjut Fase 4).
- **`LAPORAN_MEDICAL_NOTES.md`** — Catatan Keluhan Kader (3 kolom boolean, satu anak satu catatan
  per tanggal). 288/288 API, 67/67 Flutter.
- **`LAPORAN_BUKU_MEDIS.md`** — timeline anak `GET /children/{id}/timeline` (5 query);
  96 test/364 assertion backend, 105 Flutter.
- **`LAPORAN_GRAFIK_TUMBUH_KEMBANG.md`** — grafik tumbuh (`/growth`) + pita WHO; 121 backend,
  137 Flutter. Diamendemen 15 Okt menjadi multidimensi (3 pita).
- **`LAPORAN_REKAP_IMUNISASI_BULANAN.md`** — rekap bulanan (`activity` + `coverage`), 3 bug 500
  ditemukan lewat feature test. 314/314 API, 88/88 Flutter.
- **`LAPORAN_REKAP_CSV.md`** — export CSV rekap; 338/338 API. Tombol export mobile ditunda.
- **`DOKUMEN_LAPORAN_APLIKASI.md`** — laporan evaluasi aplikasi menyeluruh (Beta v0.9.0):
  latar belakang, arsitektur, ERD, keamanan, status fitur.

---

## 7. Inovasi (P3 / Future-Proofing)

Spesifikasi: `docs/arsip/PERANCANGAN_PERKUATAN.md` §11–12. **Semua belum dikerjakan.**

| Inovasi | Prioritas | Estimasi | Ketergantungan |
|---|---|---|---|
| FHIR-Ready API (SATUSEHAT) | P1 | 2 minggu | Entitas Visit ✅ |
| Offline-First Sync (Isar + SyncEngine) | P1 | 3 minggu | Entitas Visit ✅ |
| KMS Digital Interaktif (pita warna) | P2 | 2 minggu | WHO Standards lengkap ✅ |
| WhatsApp Reminders | P2 | 1 minggu | Jadwal imunisasi final ✅ |
| OCR Buku KIA (Python + Ollama) | P3 | 2 minggu | Python service |

**Dibatasi kebijakan:** fitur AI ("Sepiring Bergizi", rekomendasi nutrisi) hanya boleh
masuk setelah 5 kriteria terpenuhi (tujuan klinis, kumpulan data, output, metode evaluasi,
verifikasi manusia) — lihat `arsip/PERANCANGAN_PERKUATAN.md` §4. *(Smart Triage/IoT dikeluarkan dari scope)*

---

## 8. Aturan Wajib Saat Bekerja

1. Logika Z-score **hanya** di trigger/function PostgreSQL (`AI_AGENT_RULES.md` #9).
2. Primary key **UUID** (`HasUuids`), FK `foreignUuid()`.
3. Migration **additive** — jangan ubah migration lama.
4. Jangan ubah `AuthController`, struktur route, atau schema inti tanpa instruksi eksplisit.
5. Jangan jalankan/mengubah/commit apa pun tanpa persetujuan pengguna.
6. Data WHO diambil dari `docs/data_who/` (format xlsx; kolom A=usia, B=L, C=M, D=S).
7. Kontrak yang dikunci (`kontrak-timeline.md`, `kontrak-growth.md`) harus diubah di dokumen
   lebih dulu, baru di kode.

---

## 9. Pertanyaan Terbuka untuk Dosen

1. **Jadwal imunisasi:** memakai Jadwal Imunisasi Nasional Kemenkes RI 2023/2024? *(sudah direspons: 21 dosis aktif)*
2. **"16 imunisasi":** 16 dosis atau 16 jenis vaksin? *(sudah direspons lewat `arsip/PERANCANGAN_PERKUATAN.md` §10)*
3. **Rujukan:** perlu integrasi dengan sistem SIKDA Puskesmas?
4. **Consent:** perlu consent eksplisit atau cukup implisit saat registrasi?
5. **Evaluasi klinis:** siapa yang membantu validasi perhitungan Z-score?
6. **Uji coba kader:** Posyandu mana yang bisa dijadikan lokasi uji?

---

## 10. Dokumen Teknis (Tetap Terpisah)

| Kebutuhan | Dokumen |
|---|---|
| Aturan teknis agen | `AI_AGENT_RULES.md` |
| Kontrak API | `API_CONTRACT.md` |
| Skema database | `DATABASE_SCHEMA.md` |
| Cara menjalankan | `Cara_menjalankan.md` |
| Setup & riwayat teknis | `SETUP_LOG.md` |
| Data referensi WHO | `data_who/` |
| Aturan turunan backend | `posyandu-backend/.ai/rules/` |
| Dokumen lama (rencana/status/laporan per-fitur) | `arsip/` |
