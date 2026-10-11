# Perencanaan Penguatan Sistem — Smart Posyandu

> **Status:** Draft untuk review dosen  
> **Tanggal:** 9 Oktober 2026  
> **Prinsip:** Stop tambah fitur baru sampai area-area ini diperkuat.

---

## 1. Alur Kerja Layanan Kesehatan Inti

### 1.1 Flow yang Diusulkan

```
┌─────────────────────────────────────────────────────────────────────┐
│                    ALUR LAYANAN POSYANDU                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ① PENGUMPULAN DATA                                                │
│     ├── Registrasi anak (NIK, nama, tanggal lahir, jenis kelamin)  │
│     ├── Pengukuran fisik (BB, TB, LLA)                             │
│     ├── Keluhan/gejala (demam, rewel, diare, catatan)              │
│     └── Status imunisasi                                           │
│                          │                                          │
│                          ▼                                          │
│  ② VALIDASI                                                        │
│     ├── Validasi input (format, range, konsistensi)                │
│     ├── Validasi klinis (Z-score WHO, status gizi)                │
│     ├── Validasi imunisasi (dosis, interval, jadwal)              │
│     └── Validasi kelengkapan data wajib                            │
│                          │                                          │
│                          ▼                                          │
│  ③ INTERPRETASI                                                    │
│     ├── Klasifikasi status gizi (BB/U, TB/U, BBL, IMT/U)          │
│     ├── Status imunisasi (sudah/belum/terlambat)                  │
│     ├── Deteksi dini risiko (stunting, gizi buruk, dll)           │
│     └── Telaah keluhan → skala triase                             │
│                          │                                          │
│                          ▼                                          │
│  ④ TINDAKAN / RUJUKAN                                              │
│     ├── Tindakan ringan (edukasi, suplemen, jadwal ulang)          │
│     ├── Tindakan sedang (monitoring ketat, kunjungan rumah)        │
│     └── Rujukan (Puskesmas/RS) — kriteria jelas                    │
│                          │                                          │
│                          ▼                                          │
│  ⑤ PELAPORAN KE PUSKESMAS                                         │
│     ├── Rekap imunisasi bulanan (CSV)                             │
│     ├── Laporan pertumbuhan & status gizi                         │
│     ├── Daftar rujukan                                            │
│     └── Data SIKDA terintegrasi (rencana)                         │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 1.2 Entitas "Kunjungan" (Visit) — Perubahan Arsitektur Kunci

**Masalah saat ini:** Pengukuran, imunisasi, keluhan, dan rujukan tercatat terpisah tanpa tautan ke satu kunjungan yang sama. Ini menyulitkan rekam medis longitudinal dan pelaporan.

**Solusi:** Tambah entitas `visits` sebagai penghubung.

```
visits
├── id (UUID PK)
├── child_id (FK → children)
├── schedule_id (FK → posyandu_schedules, nullable — untuk kunjungan terjadwal)
├── visit_date (DATE)
├── visit_type (ENUM: 'posyandu', 'kunjungan_rumah', 'rujukan')
├── kader_id (FK → users, nullable)
├── anamnesis (TEXT) — keluhan utama
├── catatan_kader (TEXT)
├── created_at, updated_at, deleted_at
```

**Relasi baru:**
```
visits 1───< measurements        (measurement.visit_id)
visits 1───< immunization_records (immunization_record.visit_id)
visits 1───< medical_notes       (medical_note.visit_id)
visits 1───< referrals           (referral.visit_id)  ← entitas baru
```

**Tabel `referrals` (baru):**
```
referrals
├── id (UUID PK)
├── visit_id (FK → visits)
├── child_id (FK → children)
├── referral_date (DATE)
├── referral_type (ENUM: 'puskesmas', 'rs', 'faskes_lain')
├── reason (TEXT)
├── facility_name (TEXT)
├── status (ENUM: 'dibuat', 'dilaporkan', 'selesai')
├── kader_id (FK → users)
├── created_at, updated_at, deleted_at
```

### 1.3 Alur Implementasi Visit

1. Saat kader membuka detail anak di Posyandu → buat `visit` baru
2. Semua pengukuran/imunisasi/keluhan selama sesi itu dikaitkan ke `visit_id`
3. Jika ada rujukan → catat di tabel `referrals` dengan `visit_id` yang sama
4. Timeline anak menampilkan data per-kunjungan (bukan per-tanggal)

---

## 2. Validasi Penilaian Pertumbuhan (WHO Multidimensi)

### 2.1 Masalah Saat Ini

Hanya ada **Weight-for-Age (BB/U)**. Ini tidak cukup untuk status gizi lengkap.

### 2.2 Indikator WHO yang Harus Diimplementasikan

| Indikator | Nama | Tabel Referensi | Klasifikasi |
|-----------|------|-----------------|-------------|
| **BB/U** | Weight-for-Age | `who_wfa_standards` (ada) | Gizi Buruk / Kurang / Normal / Risiko Lebih |
| **TB/U** | Height-for-Age | `who_hfa_standards` (baru) | Stunting / Normal |
| **BB/TB** | Weight-for-Length/Height | `who_wfh_standards` (baru) | Gizi Buruk / Kurang / Normal / Risiko Lebih |
| **IMT/U** | BMI-for-Age | `who_bfa_standards` (baru) | Gizi Buruk / Kurang / Normal / Risiko Lebih |

### 2.3 Referensi WHO yang Digunakan

**Standar WHO Child Growth Standards 2006** (untuk anak 0-5 tahun):

- **BB/U:** `who_wfa_standards` — sudah ada (122 baris, 0-60 bulan × 2 gender)
- **TB/U:** Perlu migrasi baru — `who_hfa_standards` (median, -1SD, -2SD, -3SD, +1SD, +2SD, +3SD per usia & gender)
- **BB/TB:** Perlu migrasi baru — `who_wfh_standards` (untuk anak 0-24 bulan, length 45-110cm)
- **IMT/U:** Perlu migrasi baru — `who_bfa_standards` (BMI per usia & gender)

### 2.4 Ambang Batas Klasifikasi Z-Score WHO

| Klasifikasi | Z-Score | BB/U | TB/U | BB/TB | IMT/U |
|-------------|---------|------|------|-------|-------|
| **Gizi Buruk / Severely Stunted** | < -3 SD | ✓ | ✓ | ✓ | ✓ |
| **Gizi Kurang / Stunted** | -3 s.d. -2 SD | ✓ | ✓ | ✓ | ✓ |
| **Normal** | -2 s.d. +2 SD | ✓ | ✓ | ✓ | ✓ |
| **Risiko Gizi Lebih / Overweight** | > +2 SD | ✓ | — | ✓ | ✓ |
| **Obesitas** | — | — | — | — | > +3 SD |

### 2.5 Perubahan Database

**Migrasi baru:**
1. `create_who_hfa_standards_table` — referensi TB/U
2. `create_who_wfh_standards_table` — referensi BB/TB (0-24 bulan)
3. `create_who_bfa_standards_table` — referensi IMT/U
4. `add_zscore_columns_to_measurements` — tambah kolom:
   - `z_score_hfa` (HEIGHT-for-age)
   - `z_score_wfh` (WEIGHT-for-height, hanya jika TB tersedia)
   - `z_score_bfa` (BMI-for-age)
   - `status_stunting` (NULL / 'Stunting' / 'Normal')
   - `status_gizi_imt` (klasifikasi IMT/U)

**Trigger baru:** `trg_measurements_who_zscore` diperluas untuk menghitung semua indikator.

### 2.6 Validasi Klinis

Setiap pengukuran baru otomatis:
1. Hitung Z-score untuk semua indikator yang memungkinkan
2. Tentukan status gizi komposit (paling buruk dari semua indikator)
3. Flag otomatis jika ada indikator ekstrem (< -3 atau > +3)

---

## 3. Klarifikasi Modul Imunisasi

### 3.1 Rekonsiliasi "16 Imunisasi"

**Saat ini:** 16 dosis dalam `immunization_types`:

| Vaksin | Dosis | Usia Target | Kategori |
|--------|-------|-------------|----------|
| Hepatitis B (HB) | 4 | 0, 2, 4, 6 bulan | Dasar |
| BCG | 1 | 2 bulan | Dasar |
| Polio Oral | 5 | 0, 2, 3, 4, 6 bulan | Dasar |
| DPT-HB-Hib | 4 | 2, 3, 4, 6 bulan | Dasar |
| Campak-Rubella (MR) | 2 | 9, 18 bulan | Dasar |
| **Total** | **16** | | |

### 3.2 Jadwal Imunisasi Indonesia yang Berwenang

**Sumber resmi:** **Kementerian Kesehatan RI** — Jadwal Imunisasi Nasional (2023/2024)

**Vaksin wajib program nasional (0-18 bulan):**

| Vaksin | Dosis | Usia | Sumber |
|--------|-------|------|--------|
| Hepatitis B (HB-0) | 1 | 0-7 hari | Kemenkes |
| BCG | 1 | 1 bulan | Kemenkes |
| Polio (OPV) | 4 | 1, 2, 3, 4 bulan | Kemenkes |
| DPT-HB-Hib | 3 | 2, 3, 4 bulan | Kemenkes |
| IPV (Suntik) | 1 | 4 bulan | Kemenkes |
| PCV | 3 | 2, 3, 4 bulan | Kemenkes (daerah tertentu) |
| Rotavirus | 2-3 | 2, 3, 4 bulan | Kemenkes (daerah tertentu) |
| MR/MMR | 2 | 9, 18 bulan | Kemenkes |

**Perbedaan dengan sistem saat ini:**
- Sistem saat ini: 16 dosis (HB 4x, BCG 1x, Polio 5x, DPT-HB-Hib 4x, MR 2x)
- Jadwal Kemenkes: lebih banyak vaksin (IPV, PCV, Rotavirus) tapi dosis HB hanya 1x (HB-0)

**Rekomendasi:**
1. **Klarifikasi dengan dosen:** Apakah "16 imunisasi" mengacu pada 16 dosis atau 16 jenis vaksin?
2. **Jadwal yang digunakan:** Jadwal Imunisasi Nasional Kemenkes RI (bukan WHO)
3. **Penyesuaian master data:** Sesuaikan `immunization_types` dengan jadwal resmi Indonesia
4. **Dokumentasi sumber:** Catat referensi jadwal di kode dan dokumentasi

### 3.3 Validasi Dosis yang Lebih Ketat

Saat ini `assertDoseOrder()` hanya membandingkan dengan dosis tetangga. Perlu ditambah:
- Validasi usia minimum per dosis (sesuai jadwal)
- Validasi interval antar dosis
- Flag otomatis jika dosis diberikan terlalu cepat

---

## 4. Kontrol Ruang Lingkup AI

### 4.1 Prinsip: AI Hanya untuk Tujuan Klinis yang Jelas

**Aturan:** Fitur AI TIDAK BOLEH ditambahkan sampai 5 kriteria terpenuhi:

| Kriteria | Pertanyaan | Status |
|----------|-----------|--------|
| **Tujuan klinis** | Apa masalah klinis yang dipecahkan? | ❌ Belum terdefinisi |
| **Kumpulan data** | Data apa yang dibutuhkan? Dari mana? | ❌ Belum ada |
| **Output yang diharapkan** | Format output? Siapa yang membaca? | ❌ Belum terdefinisi |
| **Metode evaluasi** | Bagaimana mengukur akurasi? | ❌ Belum terdefinisi |
| **Verifikasi manusia** | Siapa yang memverifikasi? Kapan? | ❌ Belum terdefinisi |

### 4.2 Fitur AI yang Ditunda

| Fitur | Alasan Penundaan | Kriteria yang Harus Dipenuhi |
|-------|-----------------|------------------------------|
| **Sepiring Bergizi (CV)** | Butuh dataset makanan Indonesia, model CV, validasi gizi | 1. Tujuan: edukasi nutrisi ibu<br>2. Data: minimal 1000 foto makanan berlabel<br>3. Output: kategori + saran praktis<br>4. Evaluasi: akurasi >85% vs ahli gizi<br>5. Verifikasi: kader review saran |
| **Smart Triage (IoT)** | Butuh hardware, integrasi real-time, validasi klinis | 1. Tujuan: deteksi dini anak sakit<br>2. Data: suhu, denyut jantung, SpO2<br>3. Output: level triase (hijau/kuning/merah)<br>4. Evaluasi: sensitivitas >90%<br>5. Verifikasi: kader konfirmasi semua alert |
| **Rekomendasi Nutrisi** | Butuh basis pengetahuan, validasi ahli gizi | 1. Tujuan: saran menu harian<br>2. Data: komposisi makanan Indonesia<br>3. Output: resep + porsi<br>4. Evaluasi: review ahli gizi<br>5. Verifikasi: kader sebelum ditampilkan |

### 4.3 Prosedur Penambahan Fitur AI

```
1. Dokumen Proposal (tujuan, data, output, evaluasi, verifikasi)
2. Review dosen pembimbing
3. Persetujuan komite etika (jika melibatkan data anak)
4. Pengumpulan & pelabelan data
5. Pelatihan model
6. Evaluasi internal
7. Uji coba terbatas (beta)
8. Review hasil oleh kader & ahli
9. Deployment bertahap
10. Monitoring berkala
```

---

## 5. Tata Kelola Data

### 5.1 Persetujuan (Consent)

**Tabel baru:** `consents`

| Kolom | Tipe | Keterangan |
|-------|------|------------|
| id | UUID PK | |
| child_id | FK → children | |
| consent_type | ENUM | 'data_processing', 'data_sharing', 'research' |
| granted_by | FK → users | Ibu/wali |
| granted_at | TIMESTAMP | |
| revoked_at | TIMESTAMP NULL | |
| document_version | VARCHAR | Versi formulir consent |
| notes | TEXT | |

**Alur:**
1. Saat registrasi anak → tampilkan formulir consent
2. Ibu harus mencentang persetujuan sebelum data disimpan
3. Consent bisa dicabut kapan saja (tapi data historis tetap ada untuk kepentingan medis)
4. Audit trail untuk setiap perubahan consent

### 5.2 Perlindungan Data Kesehatan Anak & NIK

**Prinsip:** Data kesehatan anak adalah data sensitif (UU PDP No. 27/2022).

**Langkah teknis:**

| Aspek | Implementasi |
|-------|-------------|
| **Enkripsi** | Enkripsi kolom `nik` di database (pgcrypto) |
| **Akses** | NIK hanya ditampilkan untuk kader yang menangani anak tersebut |
| **Anonimisasi** | Data untuk pelaporan ke Puskesmas tanpa NIK (gunakan ID internal) |
| **Minimalisasi** | Hanya kumpulkan data yang perlu |
| **Pseudonimisasi** | Untuk penelitian/statistik, gunakan ID pseudonim |

### 5.3 Jejak Audit (Audit Trail)

**Tabel baru:** `audit_logs`

| Kolom | Tipe | Keterangan |
|-------|------|------------|
| id | UUID PK | |
| user_id | FK → users NULL | Siapa yang melakukan |
| action | VARCHAR | 'create', 'update', 'delete', 'view', 'export' |
| entity_type | VARCHAR | 'child', 'measurement', 'immunization', dll |
| entity_id | UUID | |
| old_values | JSONB NULL | Nilai sebelum perubahan |
| new_values | JSONB NULL | Nilai setelah perubahan |
| ip_address | INET | |
| user_agent | TEXT | |
| created_at | TIMESTAMP | |

**Trigger audit:** Otomatis catat semua INSERT/UPDATE/DELETE pada tabel sensitif.

### 5.4 Kontrol Akses

**Saat ini:** Role-based (ibu/kader) — sudah baik.

**Penambahan:**
- **Field-level access:** `medical_flags` hanya kader (sudah ada)
- **Time-based access:** Kader hanya bisa edit data dalam 7 hari terakhir
- **Location-based:** (Opsional) Batasi akses berdasarkan lokasi Posyandu

### 5.5 Pencadangan (Backup)

| Aspek | Rencana |
|-------|---------|
| **Frekuensi** | Backup harian (otomatis) |
| **Retensi** | 30 hari rolling + backup bulanan arsip 1 tahun |
| **Lokasi** | Off-site (cloud storage terenkripsi) |
| **Restore test** | Uji restore setiap bulan |
| **Dokumentasi** | Runbook prosedur restore |

### 5.6 Retensi Data

| Jenis Data | Retensi | Alasan |
|------------|---------|--------|
| Data anak aktif | Selama anak < 5 tahun + 2 tahun | Kebutuhan medis |
| Data anak tidak aktif | 5 tahun setelah terakhir kunjungan | Regulasi kesehatan |
| Audit log | 7 tahun | Kepatuhan hukum |
| Data consent | Selama data anak ada | Bukti persetujuan |

### 5.7 Akuntabilitas untuk Koreksi

**Alur koreksi data:**
1. Ibu/kader mengajukan permohonan koreksi
2. Kader verifikasi kebenaran
3. Koreksi dicatat di audit log (old_values + new_values)
4. Riwayat versi lama tetap tersimpan
5. Notifikasi ke pihak terkait jika koreksi signifikan

---

## 6. Perbaikan Model Basis Data

### 6.1 Ringkasan Perubahan

```
┌─────────────────────────────────────────────────────────┐
│              PERUBAHAN SCHEMA                           │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  TABEL BARU:                                            │
│  ├── visits              (kunjungan/pertemuan)          │
│  ├── referrals           (rujukan)                      │
│  ├── consents            (persetujuan)                  │
│  ├── audit_logs          (jejak audit)                  │
│  ├── who_hfa_standards   (TB/U)                         │
│  ├── who_wfh_standards   (BB/TB)                        │
│  └── who_bfa_standards   (IMT/U)                        │
│                                                         │
│  TABEL YANG DIUBAH:                                     │
│  ├── measurements        (+ visit_id, + z_score_hfa,    │
│  │                         + z_score_wfh, + z_score_bfa,│
│  │                         + status_stunting,           │
│  │                         + status_gizi_imt)           │
│  ├── immunization_records (+ visit_id)                  │
│  ├── medical_notes        (+ visit_id)                   │
│  └── children            (+ consent_status)             │
│                                                         │
│  TRIGGER BARU:                                          │
│  ├── trg_audit_log        (audit trail otomatis)        │
│  └── trg_measurements_who_zscore (diperluas)            │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 6.2 Urutan Migrasi

1. `create_who_hfa_standards_table`
2. `create_who_wfh_standards_table`
3. `create_who_bfa_standards_table`
4. `create_visits_table`
5. `create_referrals_table`
6. `create_consents_table`
7. `create_audit_logs_table`
8. `add_visit_id_to_measurements`
9. `add_visit_id_to_immunization_records`
10. `add_visit_id_to_medical_notes`
11. `add_zscore_columns_to_measurements`
12. `create_audit_trigger`
13. `update_zscore_trigger`

---

## 7. Langkah Evaluasi

### 7.1 Pengujian Fungsional

| Jenis | Cakupan | Tool |
|-------|---------|------|
| **Unit Test** | Service classes, model methods | PHPUnit |
| **Feature Test** | API endpoints, validasi, otorisasi | PHPUnit |
| **Integration Test** | Alur end-to-end (visit → measurement → referral) | PHPUnit |
| **Mobile Test** | Widget test, integration test | flutter_test |
| **UI/UX Test** | Review dengan kader | Manual + Screenshot |

**Target:** > 90% code coverage untuk business logic kritis.

### 7.2 Validasi Perhitungan Klinis

| Perhitungan | Validasi | Siapa |
|-------------|----------|-------|
| Z-score BB/U | Bandingkan dengan WHO Anthro software | Dosen/kader |
| Z-score TB/U | Bandingkan dengan WHO Anthro | Dosen/kader |
| Z-score BB/TB | Bandingkan dengan WHO Anthro | Dosen/kader |
| Z-score IMT/U | Bandingkan dengan WHO Anthro | Dosen/kader |
| Status gizi | Review kasus oleh ahli gizi | Ahli gizi |
| Status imunisasi | Review jadwal oleh bidan | Bidan |

**Metode:** Buat 20 kasus uji dengan data known-answer, verifikasi output sistem.

### 7.3 Pengujian Kegunaan dengan Kader

| Aspek | Metode | Kriteria Sukses |
|-------|--------|-----------------|
| **Kemudahan** | SUS (System Usability Scale) | Skor > 70 |
| **Efisiensi** | Task completion time | < 5 menit per kunjungan |
| **Akurasi** | Error rate | < 5% kesalahan input |
| **Kepuasan** | Wawancara & kuesioner | > 80% puas |
| **Dapat dipelajari** | Time to first success | < 30 menit training |

**Peserta:** Minimal 5 kader dari Posyandu berbeda.

### 7.4 Kinerja Sistem

| Metrik | Target | Tool |
|--------|--------|------|
| **Response time API** | < 500ms (p95) | Laravel Telescope |
| **Waktu load halaman** | < 2 detik | Lighthouse |
| **Concurrent users** | 50 kader bersamaan | k6 / JMeter |
| **Database query** | < 100ms per query | Query log |
| **Uptime** | > 99% | Monitoring |

### 7.5 Evaluasi Output Mendukung Keputusan

| Output | Mendukung Keputusan | Cara Ukur |
|--------|-------------------|-----------|
| Status gizi | Tindakan ringan/rujukan | Akurasi vs diagnosis bidan |
| Status imunisasi | Home visit / jadwal ulang | Cakupan imunisasi meningkat |
| Rujukan | Waktu ke Puskesmas | Waktu rujukan < 24 jam |
| Laporan bulanan | Perencanaan program | Kader gunakan untuk rapat |

---

## 8. Roadmap Implementasi

### Fase 1: Fondasi (Minggu 1-2)
- [ ] Migrasi tabel WHO (HFA, WFH, BFA)
- [ ] Migrasi tabel visits, referrals, consents, audit_logs
- [ ] Update trigger Z-score
- [ ] Update model & migration existing tables

### Fase 2: Logika Bisnis (Minggu 3-4)
- [ ] Service VisitService (CRUD kunjungan)
- [ ] Service ReferralService
- [ ] Service ConsentService
- [ ] Service AuditService
- [ ] Update ImmunizationChecklistService (validasi jadwal Kemenkes)
- [ ] Update MeasurementController (kaitkan visit_id)

### Fase 3: API & Integrasi (Minggu 5-6)
- [ ] Endpoint baru: /visits, /referrals, /consents
- [ ] Update endpoint existing (kaitkan visit_id)
- [ ] Audit trail middleware
- [ ] Enkripsi NIK

### Fase 4: Mobile (Minggu 7-8)
- [ ] Screen kunjungan baru
- [ ] Flow: buat kunjungan → input data → selesai
- [ ] Screen rujukan
- [ ] Screen consent

### Fase 5: Evaluasi (Minggu 9-10)
- [ ] Unit & feature test
- [ ] Validasi klinis dengan dosen
- [ ] Uji coba kader
- [ ] Performance test
- [ ] Perbaikan berdasarkan feedback

---

## 9. Ringkasan Prioritas

| Prioritas | Item | Dampak |
|-----------|------|--------|
| **P0** | Entitas Visit | Menghubungkan semua data klinis |
| **P0** | Validasi WHO multidimensi | Status gizi akurat |
| **P0** | Klarifikasi jadwal imunisasi | Kepatuhan nasional |
| **P1** | Audit trail | Akuntabilitas |
| **P1** | Consent management | Kepatuhan UU PDP |
| **P1** | Enkripsi NIK | Perlindungan data |
| **P2** | Backup & retensi | Business continuity |
| **P2** | Evaluasi klinis | Validasi sistem |
| **P3** | Fitur AI | Ditunda sampai kriteria terpenuhi |

---

## 10. Pertanyaan untuk Dosen

1. **Jadwal imunisasi:** Apakah menggunakan Jadwal Imunisasi Nasional Kemenkes RI 2023/2024?
2. **"16 imunisasi":** Apakah mengacu pada 16 dosis atau 16 jenis vaksin?
3. **Rujukan:** Apakah perlu integrasi dengan sistem SIKDA Puskesmas?
4. **Consent:** Apakah perlu consent eksplisit atau cukup dengan persetujuan implisit saat registrasi?
5. **Evaluasi klinis:** Siapa yang bisa membantu validasi perhitungan Z-score?
6. **Uji coba kader:** Posyandu mana yang bisa dijadikan lokasi uji?

---

## 11. Inovasi Tambahan (Future-Proofing)

### 11.1 SATUSEHAT-Ready: Integrasi HL7 FHIR

**Visi:** Backend Laravel siap terhubung dengan platform SATUSEHAT Kemenkes kapan saja.

**Arsitektur:**

```
┌─────────────────────────────────────────────────────────────┐
│                  ARSITEKTUR FHIR-READY                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │   Mobile     │───▶│   Backend    │───▶│  SATUSEHAT   │  │
│  │   (Flutter)  │    │   (Laravel)  │    │   Kemenkes   │  │
│  └──────────────┘    └──────┬───────┘    └──────────────┘  │
│                             │                               │
│                      ┌──────┴───────┐                       │
│                      │  FHIR        │                       │
│                      │  Resource    │                       │
│                      │  Mapper      │                       │
│                      └──────────────┘                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Mapping FHIR Resources:**

| Entitas Lokal | FHIR Resource | Contoh Mapping |
|---------------|---------------|----------------|
| `Patient` (Anak) | `Patient` | NIK → identifier, nama → name, tgl_lahir → birthDate |
| `Practitioner` (Kader) | `Practitioner` | NIK → identifier, nama → name |
| `Encounter` (Kunjungan) | `Encounter` | visit_date → period, tipe → class |
| `Observation` (Pengukuran) | `Observation` | BB/TB/Z-score → valueQuantity, code |
| `Immunization` | `Immunization` | vaksin → vaccineCode, tanggal → occurrenceDateTime |
| `Condition` (Keluhan) | `Condition` | keluhan → code, catatan → note |
| `Referral` | `ServiceRequest` | rujukan → performer, reasonCode |

**Contoh Payload FHIR (Observation - Pengukuran BB):**

```json
{
  "resourceType": "Observation",
  "id": "obs-bb-001",
  "status": "final",
  "category": [{
    "coding": [{
      "system": "http://terminology.hl7.org/CodeSystem/observation-category",
      "code": "vital-signs",
      "display": "Vital Signs"
    }]
  }],
  "code": {
    "coding": [{
      "system": "http://loinc.org",
      "code": "29463-7",
      "display": "Body weight"
    }]
  },
  "subject": {
    "reference": "Patient/child-uuid"
  },
  "encounter": {
    "reference": "Encounter/visit-uuid"
  },
  "effectiveDateTime": "2026-10-09",
  "valueQuantity": {
    "value": 8.5,
    "unit": "kg",
    "system": "http://unitsofmeasure.org",
    "code": "kg"
  },
  "referenceRange": [{
    "type": {
      "coding": [{
        "system": "http://terminology.hl7.org/CodeSystem/referencerange-meaning",
        "code": "normal"
      }]
    },
    "low": { "value": 7.2, "unit": "kg" },
    "high": { "value": 10.1, "unit": "kg" }
  }]
}
```

**Implementasi:**
1. Buat `FhirResourceMapper` service di Laravel
2. Setiap endpoint API bisa mengembalikan format FHIR dengan header `Accept: application/fhir+json`
3. Endpoint khusus `POST /api/fhir/$sync` untuk push data ke SATUSEHAT
4. Dokumentasi mapping di `docs/FHIR_MAPPING.md`

**Nilai Jual:** Aplikasi tidak lagi "silo" — siap integrasi nasional.

---

### 11.2 Arsitektur Offline-First dengan Sinkronisasi Tertunda

**Masalah:** Koneksi internet tidak stabil di Posyandu tingkat RT/RW.

**Solusi:** Database lokal di Flutter + background sync.

**Arsitektur:**

```
┌─────────────────────────────────────────────────────────────┐
│              ARSITEKTUR OFFLINE-FIRST                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              FLUTTER MOBILE                          │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │   │
│  │  │  UI Layer   │  │  Local DB   │  │  Sync       │  │   │
│  │  │  (Widgets)  │  │  (Isar)     │  │  Engine     │  │   │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  │   │
│  │         │                │                │         │   │
│  │         └────────────────┼────────────────┘         │   │
│  │                          │                          │   │
│  │                   ┌──────┴──────┐                   │   │
│  │                   │  Connectivity│                   │   │
│  │                   │  Monitor     │                   │   │
│  │                   └──────┬──────┘                   │   │
│  └──────────────────────────┼──────────────────────────┘   │
│                             │                               │
│                      ┌──────┴──────┐                        │
│                      │  Backend    │                        │
│                      │  (Laravel)  │                        │
│                      └─────────────┘                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Database Lokal (Isar):**

```dart
// Schema lokal di Flutter
@Collection()
class LocalVisit {
  Id id = Isar.autoIncrement;
  String? serverId; // UUID dari backend (null jika belum sync)
  String childId;
  DateTime visitDate;
  String visitType;
  String? anamnesis;
  String status; // 'pending', 'synced', 'conflict'
  DateTime createdAt;
  DateTime? syncedAt;
}

@Collection()
class LocalMeasurement {
  Id id = Isar.autoIncrement;
  String? serverId;
  String visitId; // FK lokal
  double weightKg;
  double heightCm;
  double? headCircumferenceCm;
  String status;
  DateTime createdAt;
  DateTime? syncedAt;
}
```

**Sync Engine:**

```dart
class SyncEngine {
  Future<void> syncPending() async {
    if (!await _hasConnection()) return;
    
    final pendingVisits = await _localDb.visits
        .where()
        .statusEqualTo('pending')
        .findAll();
    
    for (final visit in pendingVisits) {
      try {
        final response = await _api.createVisit(visit.toJson());
        await _localDb.writeTxn(() async {
          visit.serverId = response['id'];
          visit.status = 'synced';
          visit.syncedAt = DateTime.now();
          await _localDb.visits.put(visit);
        });
      } on ConflictException {
        // Handle conflict: server has newer data
        await _resolveConflict(visit);
      }
    }
  }
}
```

**Strategi Conflict Resolution:**
1. **Last-Write-Wins:** Data terbaru menang (default)
2. **Manual Review:** Konflik ditandai, kader pilih mana yang benar
3. **Merge:** Field-level merge jika memungkinkan

**Trigger Sync:**
- Saat koneksi pulih (connectivity monitor)
- Saat app dibuka (foreground sync)
- Saat kader klik "Sync Now" (manual)
- Background sync berkala (setiap 15 menit jika online)

**Nilai Jual:** Solusi rekayasa untuk masalah infrastruktur nyata di lapangan.

---

### 11.3 Visualisasi KMS Digital Interaktif

**Masalah:** Kader dan ibu tidak paham arti Z-Score "-2.5 SD".

**Solusi:** Terjemahkan ke grafik pita warna KMS (hijau/kuning/merah).

**Desain Visual:**

```
┌─────────────────────────────────────────────────────────────┐
│              GRAFIK KMS DIGITAL                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  BB (kg)                                                    │
│  12 ┤                                          ╱─── Hijau  │
│     │                                        ╱───  (Normal) │
│  10 ┤                                    ╱───              │
│     │                                ╱───                  │
│   8 ┤                            ╱───    ● Anak Anda      │
│     │                        ╱───                        │
│   6 ┤                    ╱───                            │
│     │                ╱───                                │
│   4 ┤            ╱───                                    │
│     │        ╱───                                        │
│   2 ┤    ╱───                                            │
│     │╱───                                                │
│   0 ┼────┬────┬────┬────┬────┬────┬────┬────┬────┬───  │
│     0    3    6    9   12   15   18   21   24   27      │
│                    Usia (bulan)                           │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  ● Anak Anda: 8.5 kg @ 12 bulan                     │   │
│  │  Status: Normal (Z: -0.5)                          │   │
│  │  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │   │
│  │  ↑ Naik dari kunjungan sebelumnya (7.8 kg)        │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Implementasi Flutter:**

```dart
class KmsChart extends StatelessWidget {
  final List<Measurement> measurements;
  final List<WhoStandard> whoStandards;
  
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(double.infinity, 300),
      painter: KmsChartPainter(
        measurements: measurements,
        whoStandards: whoStandards,
        zones: [
          // Zona merah (< -3 SD)
          ChartZone(color: Colors.red, minZ: -5, maxZ: -3),
          // Zona kuning (-3 s.d. -2 SD)
          ChartZone(color: Colors.yellow, minZ: -3, maxZ: -2),
          // Zona hijau (-2 s.d. +2 SD)
          ChartZone(color: Colors.green, minZ: -2, maxZ: 2),
          // Zona kuning (> +2 SD)
          ChartZone(color: Colors.yellow, minZ: 2, maxZ: 3),
          // Zona merah (> +3 SD)
          ChartZone(color: Colors.red, minZ: 3, maxZ: 5),
        ],
      ),
    );
  }
}
```

**Fitur Interaktif:**
1. **Tap pada titik** → tampilkan detail pengukuran
2. **Pinch to zoom** → perbesar area tertentu
3. **Geser** → lihat histori panjang
4. **Toggle indikator** → BB/U, TB/U, BB/TB, IMT/U
5. **Animasi** → titik baru muncul dengan animasi

**Nilai Jual:** Menjembatani data matematis dengan pemahaman visual masyarakat.

---

### 11.4 Sistem Pengingat Otomatis via WhatsApp

**Masalah:** Ibu lupa jadwal → anak putus imunisasi (drop-out).

**Solusi:** Notifikasi WhatsApp otomatis.

**Arsitektur:**

```
┌─────────────────────────────────────────────────────────────┐
│           SISTEM PENGINGAT WHATSAPP                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │   Backend    │───▶│  WhatsApp    │───▶│   Ibu        │  │
│  │   (Laravel)  │    │  Gateway     │    │   (WA)       │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│         │                                                   │
│         ▼                                                   │
│  ┌──────────────┐                                           │
│  │  Scheduler   │                                           │
│  │  (Cron)      │                                           │
│  └──────────────┘                                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Jenis Notifikasi:**

| Trigger | Pesan | Waktu |
|---------|-------|-------|
| **H-1 Posyandu** | "Ibu, besok ada Posyandu di [lokasi]. Jangan lupa bawa Buku KIA!" | 1 hari sebelum |
| **Imunisasi Terlambat** | "Ibu, [Nama Anak] belum mendapat vaksin [Vaksin]. Segera ke Posyandu terdekat." | Saat terdeteksi |
| **Imunisasi Akan Datang** | "Ibu, [Nama Anak] akan memasuki usia [X] bulan. Siapkan jadwal imunisasi [Vaksin]." | H-7 sebelum target |
| **Kunjungan Tidak Hadir** | "Ibu, [Nama Anak] tidak hadir di Posyandu [tanggal]. Apakah ada kendala?" | H+1 setelah jadwal |

**Contoh Pesan WhatsApp:**

```
*SATUSEHAT POSYANDU*

Ibu [Nama Ibu],

Besok, [Tanggal], akan dilaksanakan Posyandu di:
📍 [Lokasi]
🕐 [Waktu]

Jangan lupa bawa:
✅ Buku KIA
✅ Kartu Imunisasi

Salam sehat,
[Kader Posyandu]
```

**Implementasi:**

```php
// Laravel Command: SendReminderNotifications
class SendReminderNotifications extends Command
{
    protected $signature = 'posyandu:send-reminders';
    
    public function handle()
    {
        // 1. Reminder H-1 Posyandu
        $tomorrow = now()->addDay();
        $schedules = PosyanduSchedule::whereDate('scheduled_date', $tomorrow)->get();
        
        foreach ($schedules as $schedule) {
            $children = Child::whereHas('user', function($q) {
                $q->where('role', 'ibu');
            })->get();
            
            foreach ($children as $child) {
                $this->sendWhatsApp($child->user->phone_number, $this->buildMessage($schedule, $child));
            }
        }
        
        // 2. Reminder Imunisasi Terlambat
        $overdue = ImmunizationChecklistService::getOverdueImmunizations();
        foreach ($overdue as $item) {
            $this->sendWhatsApp($item->child->user->phone_number, $this->buildOverdueMessage($item));
        }
    }
}
```

**Provider WhatsApp:**
- **Twilio** (paling mudah, tapi mahal)
- **Fonnte** (murah, Indonesia)
- **Wablas** (murah, Indonesia)
- **Meta WhatsApp Business API** (resmi, perlu verifikasi bisnis)

**Nilai Jual:** Tindakan preventif & proaktif — meningkatkan cakupan imunisasi.

---

### 11.5 Fitur "AI Aman": OCR untuk Digitalisasi Buku KIA

**Masalah:** Anak pindah Posyandu → riwayat imunisasi di buku KIA lama tidak tercatat digital.

**Solusi:** OCR berbasis AI untuk scan buku KIA → draft input otomatis → kader konfirmasi.

**Arsitektur:**

```
┌─────────────────────────────────────────────────────────────┐
│              ARSITEKTUR OCR KIA                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │   Mobile     │───▶│   Backend    │───▶│  Python      │  │
│  │   (Camera)   │    │   (Laravel)  │    │  Service     │  │
│  └──────────────┘    └──────────────┘    │  (OCR)       │  │
│                                            └──────────────┘  │
│                                                   │         │
│                                            ┌──────┴──────┐  │
│                                            │  Ollama     │  │
│                                            │  (LLM)      │  │
│                                            └─────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Flow:**

```
1. Kader foto halaman Buku KIA
         │
         ▼
2. Mobile upload ke backend
         │
         ▼
3. Backend forward ke Python OCR Service
         │
         ▼
4. OCR extract teks + tanggal
         │
         ▼
5. LLM (Ollama) parse → structured data
         │
         ▼
6. Backend return draft JSON ke mobile
         │
         ▼
7. Kader review & konfirmasi di mobile
         │
         ▼
8. Data tersimpan di database
```

**Contoh Output OCR:**

```json
{
  "status": "success",
  "confidence": 0.85,
  "extracted_data": [
    {
      "vaccine_name": "BCG",
      "date": "2025-03-15",
      "batch_number": "BCG-2025-001",
      "confidence": 0.92
    },
    {
      "vaccine_name": "Polio 1",
      "date": "2025-03-15",
      "batch_number": "POLIO-2025-015",
      "confidence": 0.88
    },
    {
      "vaccine_name": "DPT-HB-Hib 1",
      "date": "2025-05-20",
      "batch_number": "DPT-2025-042",
      "confidence": 0.79
    }
  ],
  "needs_review": true,
  "raw_text": "BCG 15/03/2025..."
}
```

**Implementasi Python Service:**

```python
# Python OCR Service (FastAPI)
from fastapi import FastAPI, UploadFile
import pytesseract
from PIL import Image
import ollama

app = FastAPI()

@app.post("/ocr-kia")
async def ocr_kia(file: UploadFile):
    # 1. OCR extract teks
    image = Image.open(file.file)
    text = pytesseract.image_to_string(image, lang='ind')
    
    # 2. LLM parse ke structured data
    prompt = f"""
    Extract immunization records from this KIA book text.
    Return JSON array with: vaccine_name, date, batch_number.
    
    Text:
    {text}
    """
    
    response = ollama.chat(model='llama3.2', messages=[
        {'role': 'user', 'content': prompt}
    ])
    
    # 3. Parse & return
    return parse_llm_response(response['message']['content'])
```

**Keamanan & Validasi:**
1. **Confidence threshold:** Data dengan confidence < 0.7 ditandai "Perlu Review"
2. **Kader wajib konfirmasi:** Tidak ada data yang langsung tersimpan tanpa review
3. **Audit trail:** Semua hasil OCR dicatat di audit log
4. **Data minimization:** Hanya ekstrak data imunisasi, bukan data lain di buku

**Nilai Jual:** AI tetap ada di proyek, tapi untuk tugas administratif rendah risiko dengan verifikasi manusia penuh.

---

## 12. Roadmap Inovasi

| Inovasi | Prioritas | Estimasi | Ketergantungan |
|---------|-----------|----------|----------------|
| **FHIR-Ready API** | P1 | 2 minggu | Entitas Visit |
| **Offline-First Sync** | P1 | 3 minggu | Entitas Visit |
| **KMS Digital Interaktif** | P2 | 2 minggu | WHO Standards lengkap |
| **WhatsApp Reminders** | P2 | 1 minggu | Jadwal imunisasi final |
| **OCR KIA** | P3 | 2 minggu | Python service |

---

## 13. Estimasi Waktu Implementasi

### 13.1 Asumsi

| Asumsi | Keterangan |
|--------|------------|
| **Developer** | 1 orang (mahasiswa skripsi) |
| **Jam kerja** | 4-6 jam/hari, 5 hari/minggu |
| **Review dosen** | 1x per minggu |
| **Testing** | Termasuk dalam estimasi |
| **Dokumentasi** | Termasuk dalam estimasi |

### 13.2 Estimasi per Modul

| Modul | Estimasi | Keterangan |
|-------|----------|------------|
| **Fondasi Database** | 2 minggu | Migrasi WHO (HFA, WFH, BFA), visits, referrals, consents, audit_logs |
| **Logika Bisnis Inti** | 2 minggu | VisitService, ReferralService, ConsentService, AuditService |
| **Validasi WHO Multidimensi** | 1.5 minggu | Trigger Z-score, klasifikasi, validasi klinis |
| **Klarifikasi Imunisasi** | 0.5 minggu | Penyesuaian master data, validasi jadwal Kemenkes |
| **API & Integrasi** | 1.5 minggu | Endpoint baru, update existing, audit middleware |
| **Mobile - Visit Flow** | 1.5 minggu | Screen kunjungan, input data, rujukan |
| **Mobile - Consent** | 0.5 minggu | Screen consent, flow persetujuan |
| **FHIR-Ready API** | 2 minggu | FhirResourceMapper, endpoint FHIR, dokumentasi mapping |
| **Offline-First Sync** | 3 minggu | Isar local DB, SyncEngine, conflict resolution |
| **KMS Digital Interaktif** | 2 minggu | CustomPainter, interaksi, animasi |
| **WhatsApp Reminders** | 1 minggu | Scheduler, template pesan, provider integration |
| **OCR KIA** | 2 minggu | Python service, Ollama integration, mobile upload |
| **Testing & Bug Fix** | 2 minggu | Unit test, feature test, integration test |
| **Evaluasi & Perbaikan** | 1.5 minggu | Uji coba kader, validasi klinis, perbaikan |
| **Dokumentasi Final** | 1 minggu | Laporan, dokumentasi API, user manual |
| **TOTAL** | **~24 minggu** | **± 6 bulan** |

### 13.3 Timeline Visual

```
Bulan 1:  [████] Fondasi Database + Logika Bisnis
Bulan 2:  [████] Validasi WHO + Klarifikasi Imunisasi + API
Bulan 3:  [████] Mobile Visit Flow + FHIR-Ready
Bulan 4:  [████] Offline-First Sync + KMS Digital
Bulan 5:  [████] WhatsApp Reminders + OCR KIA
Bulan 6:  [████] Testing + Evaluasi + Dokumentasi
```

### 13.4 Fokus per Sprint (2 minggu)

| Sprint | Fokus | Deliverable |
|--------|-------|-------------|
| **Sprint 1** | Database + Visit Entity | Migrasi, model, migration existing |
| **Sprint 2** | Service Layer | VisitService, ReferralService, ConsentService |
| **Sprint 3** | WHO Multidimensi | Trigger Z-score, klasifikasi, validasi |
| **Sprint 4** | API + Mobile Visit | Endpoint, screen kunjungan, flow input |
| **Sprint 5** | FHIR-Ready | FhirResourceMapper, endpoint FHIR |
| **Sprint 6** | Offline-First | Isar DB, SyncEngine, conflict resolution |
| **Sprint 7** | KMS Digital | CustomPainter, interaksi, animasi |
| **Sprint 8** | WhatsApp + OCR | Scheduler, Python service, mobile upload |
| **Sprint 9** | Testing | Unit test, feature test, bug fix |
| **Sprint 10** | Evaluasi | Uji coba kader, validasi klinis, perbaikan |
| **Sprint 11** | Dokumentasi | Laporan, dokumentasi API, user manual |
| **Sprint 12** | Final | Polish, persiapan sidang |

### 13.5 Faktor Risiko

| Risiko | Dampak | Mitigasi |
|--------|--------|----------|
| **Scope creep** | +2-4 minggu | Patuhi prioritas P0/P1/P2 |
| **Review dosen lambat** | +1-2 minggu | Jadwal review rutin |
| **Bug kompleks** | +1-2 minggu | Testing bertahap |
| **Integrasi WhatsApp** | +0.5-1 minggu | Fallback ke SMS |
| **OCR accuracy** | +1 minggu | Manual review fallback |
| **Data WHO lengkap** | +0.5 minggu | Sumber resmi WHO |

### 13.6 Estimasi Realistis

| Skenario | Waktu | Keterangan |
|----------|-------|------------|
| **Optimis** | 18 minggu (4.5 bulan) | Semua berjalan lancar |
| **Realistis** | 24 minggu (6 bulan) | Dengan risiko normal |
| **Pesimis** | 30 minggu (7.5 bulan) | Ada kendala signifikan |

---

*Dokumen ini akan diperbarui setelah review dengan dosen pembimbing.*
