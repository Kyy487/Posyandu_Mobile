# Status Pengembangan Smart Posyandu

> **Terakhir diperbarui:** 13 Oktober 2026
> **Dokumen acuan utama:** `PERANCANGAN_PERKUATAN.md`
> **Aturan agent:** `AI_AGENT_RULES.md` dan `posyandu-backend/AGENTS.md`

---

## 1. Ringkasan Proyek

| Layer | Teknologi |
|---|---|
| Backend | Laravel 13 (REST API), PHP 8.4 |
| Database | PostgreSQL (`posyandu_db`) |
| Auth | Laravel Sanctum |
| Mobile | Flutter (Dart) |

**Prinsip kunci:** kalkulasi Z-score WHO **wajib di trigger/function PostgreSQL**, bukan di PHP.

---

## 2. Sudah Dikerjakan

### 2.1 Fitur yang sudah selesai (sebelum sesi ini)

| Fitur | Status |
|---|---|
| CRUD Data Anak (Kader & Ibu) | Selesai |
| Autentikasi (Sanctum), role ibu/kader | Selesai |
| e-KMS + Z-Score BB/U via trigger | Selesai |
| Imunisasi & Jadwal Posyandu | Selesai |
| Buku Medis Digital (timeline) | Selesai |
| Catatan Keluhan Kader | Selesai |
| Grafik Tumbuh Kembang | Selesai |
| Edit data anak oleh Kader | Selesai |
| Reminder / notifikasi | Selesai |

### 2.2 P0-2 — Validasi WHO Multidimensi (HFA + BFA + WFH) — 10 Okt 2026

Yang **selesai**:

- **Tabel referensi baru**: `who_hfa_standards` (TB/U), `who_bfa_standards` (IMT/U), dan `who_wfh_standards` (BB/TB, 0–24 bln, panjang 45–110 cm; kolom `length_cm`, `gender`, `l`, `m`, `s`). Ketiganya memakai **PK UUID** (`default gen_random_uuid()`), seragam dengan `who_wfa_standards` sesuai `.ai/rules`.
- **Seed**: `who_hfa_standards` = **122 baris**, `who_bfa_standards` = **122 baris** (gender L/P, bulan 0–60), `who_wfh_standards` = **1302 baris** (gender L/P, 45.0–110.0 cm, interpolasi 0.1 cm). Sumber file di `docs/data_who/`, output `database/seeders/who_hfa_bfa_seed.sql` dan `who_wfh_seed.sql`.
- **Kolom baru di `measurements`**: `z_score_hfa`, `z_score_wfh`, `z_score_bfa`, `status_stunting`, `status_gizi_imt`.
- **Function** `calculate_who_zscore_lms()` (formula Box-Cox LMS) + perluasan `calculate_measurement_who_zscore()` untuk menghitung WFA, HFA, WFH, BFA dan status gizi komposit.
- **Perbaikan bug**:
  - Kolom `m` diubah dari `DECIMAL(8,6)` → `DECIMAL(8,4)` (penyebab error `numeric field overflow` karena nilai TB > 100 cm).
  - Bug fatal trigger `calculate_measurement_who_zscore` (`SELECT median_kg, sd_kg INTO v_wfa_z` ke skalar, padahal dipakai `v_wfa_z.sd_kg`) → semua INSERT/UPDATE `measurements` gagal. Diperbaiki dengan variabel `v_wfa_median` & `v_wfa_sd`.
  - Hapus migration scaffold duplikat `2026_10_10_103955_create_who_hfa_standards_table.php` (pending, akan menggagalkan `php artisan migrate`).
- **Backfill** 7 `measurements` lama; kolom z-score baru kini terisi.

**Migrasi terkait:**

| Migration | Fungsi |
|---|---|
| `2026_10_10_104330_create_who_hfa_standards_table` | Tabel TB/U |
| `2026_10_10_104404_create_who_bfa_standards_table` | Tabel IMT/U |
| `2026_10_10_104713_add_who_multidim_columns_to_measurements` | Kolom z-score baru |
| `2026_10_10_104811_update_zscore_trigger_for_lms` | Function LMS + trigger (WFA/HFA/WFH/BFA) |
| `2026_10_10_104853_seed_who_hfa_bfa_standards` | Seed HFA & BFA |
| `2026_10_10_110126_fix_who_standards_m_column_precision` | Fix presisi kolom `m` |
| `2026_10_10_112842_create_who_wfh_standards_table` | Tabel BB/TB + kolom `z_score_wfh` |
| `2026_10_10_112843_seed_who_wfh_standards` | Seed WFH + backfill |

**Contoh hasil backfill:**

| Anak | Bln | WFA | HFA | WFH | BFA |
|---|---|---|---|---|---|
| Budi (L) | 16 | 13.18 Risiko Gizi Lebih | 7.66 Normal | 5.59 | 4.84 Risiko Gizi Lebih |
| Naya (P) | 35 | -0.86 Normal | -1.69 Normal | — (usia ≥24) | 0.53 Normal |

---

### 2.3 P0-1 — Entitas Kunjungan (`visits`) — 12 Okt 2026

Rancangan lengkap: `docs/RANCANGAN_VISIT.md`.

Yang **selesai**:

- **Tabel `visits`** (UUID, soft delete) sebagai payung satu sesi layanan;
  `visit_type` = `posyandu`/`kunjungan_rumah`/`rujukan` (string + CHECK, bukan
  enum PostgreSQL).
- **Kolom `visit_id`** (nullable, `nullOnDelete`) di `measurements`,
  `immunization_records`, dan `medical_notes`.
- **Backfill**: penimbangan lama tanpa `visit_id` dibuatkan satu kunjungan
  "legacy" per `(anak, tanggal)`.
- **Model & relasi**: `Child::visits()`, `Visit::child/schedule/kader/measurements/immunizationRecords/medicalNotes()`.
- **API**: `POST /visits`, `GET /children/{id}/visits` (di `ChildController`,
  seperti `timeline`/`growth`), `GET /visits/{id}`, `PATCH /visits/{id}`.
  Endpoint pencatatan menerima `visit_id` opsional (harus milik anak yang sama).
- **Test**: `tests/Feature/VisitTest.php` (26 test, semua lulus).

**Migrasi terkait:**

| Migration | Fungsi |
|---|---|
| `2026_10_11_233500_create_visits_table` | Tabel `visits` |
| `2026_10_11_233501_add_visit_id_to_measurements_table` | FK `visit_id` di penimbangan |
| `2026_10_11_233502_add_visit_id_to_immunization_records_table` | FK `visit_id` di imunisasi |
| `2026_10_11_233503_add_visit_id_to_medical_notes_table` | FK `visit_id` di keluhan |
| `2026_10_11_233504_backfill_legacy_visits_for_measurements` | Backfill kunjungan legacy |

> **Keputusan yang ditutup:** tidak ada unique `(child_id, visit_date)`
> (kunjungan ganda per hari diizinkan); kunjungan dibuat eksplisit lewat
> `POST`; `visit_date` boleh berbeda dari tanggal data anak.

---

### 2.4 P0-3 — Pembaruan Jadwal Imunisasi Kemenkes — 12 Okt 2026

Rancangan lengkap: `docs/RANCANGAN_IMUNISASI_JADWAL.md`.

Yang **selesai**:

- **Master `immunization_types` diperbarui** ke Program Imunisasi Rutin:
  **21 dosis aktif** — HB 1 (0 bln), BCG 1 (1), Polio Oral 4 (1–4),
  DPT-HB-Hib 4 (2/3/4/18), IPV 2 (4/9), Rotavirus 3 (2/3/4), PCV 3 (2/3/12),
  MR 2 (9/18), JE 1 (10, wilayah endemis).
- Dosis lama **HB 2–4 dan Polio 5 dinonaktifkan**, bukan dihapus.
- **Kolom baru `is_active`** (migrasi aditif, default `true`). Checklist, rekap
  bulanan, dan `GET /immunization-types` hanya membaca dosis aktif (scope
  `ImmunizationType::active()`); catatan anak lama tetap utuh.
- Test: `ImmunizationTypeOrderTest` diperbarui (fixture 21 dosis) + 1 test
  non-aktif; full suite lulus.

**Migrasi terkait:**

| Migration | Fungsi |
|---|---|
| `2026_10_12_011440_add_is_active_to_immunization_types_table` | Kolom `is_active` pada master imunisasi |

---

### 2.5 P1 — Tata Kelola Data (Audit, Consent, Enkripsi NIK) — 13 Okt 2026

Yang **selesai**:

- **Audit trail** — tabel `audit_logs` + trait `Concerns\Auditable` (dipasang di
  `Child`, `Visit`, `Measurement`, `ImmunizationRecord`, `MedicalNote`).
  Endpoint baca: `GET /kader/audit-logs` (Kader).
- **Consent management (UU PDP)** — tabel `consents` + `ConsentController`.
  `POST /children` kini **wajib** mengirim `consent_type` dan
  `consent_document_version`; satu baris `consents` dibuat otomatis. Endpoint
  `GET|POST|DELETE /children/{id}/consents`. Lihat `docs/PERANCANGAN_PERKUATAN.md`
  §5.1.
  - **Mobile**: `models/consent.dart` (`Consent`, `ConsentTipe`,
    `kConsentDocumentVersion`), `services/consent_service.dart` (`getByChild`,
    `grant`, `revoke`), `screens/consent_screen.dart` (satu layar:
    `bisaMengelola` `true` untuk Ibu beri/cabut, `false` untuk Kader baca saja).
    Checkbox persetujuan ditambahkan di pendaftaran anak
    (`screens/ibu/tambah_anak_dialog.dart` dan
    `screens/kader/add_child_screen.dart`); `child_service.addChild` dan
    `kader_service.addChild` kini mengirim `consent_type` +
    `consent_document_version` (sebelumnya 422). Jalan masuk: seksi
    "🔒 Persetujuan" di `screens/kader/detail_anak_screen.dart` dan menu
    "Persetujuan Data" di `screens/ibu/dashboard_ibu_screen.dart`.
- **Enkripsi NIK** — kolom `users.nik` dan `children.nik` dienkripsi
  (cast `encrypted`) dengan `nik_hash` (SHA-256) terindeks untuk pencarian.
  Lihat `docs/RANCANGAN_ENKRIPSI_NIK.md`.

**Migrasi terkait:** `2026_10_12_013352_create_audit_logs_table`,
`2026_10_13_000003_create_consents_table`, `2026_10_13_000001_encrypt_nik_on_users_table`,
`2026_10_13_000002_encrypt_nik_on_children_table`.

---

### 2.6 Rujukan (Referral) — 13 Okt 2026

Rancangan lengkap: `docs/RANCANGAN_RUJUKAN.md`.

Yang **selesai**:

- **Tabel `referrals`** (UUID, soft delete), selalu tertaut ke satu `visit`
  (`visit_id`, wajib) dan satu `child` (`child_id`). `referral_type` =
  `puskesmas`/`rs`/`faskes_lain`, `status` = `dibuat`/`dilaporkan`/`selesai`,
  keduanya string + CHECK constraint.
- **Model & relasi**: `Visit::referrals()`, `Child::referrals()`,
  `Referral::visit/child/kader()`. Model memakai `Auditable`.
- **API**: `POST /referrals`, `GET /children/{id}/referrals` (di `ChildController`,
  seperti `visits`), `GET /referrals/{id}`, `PATCH /referrals/{id}`,
  `DELETE /referrals/{id}` (soft delete). `GET /visits/{id}` menambah kunci
  `rujukan` (aditif).
- **Timeline (aditif)**: `GET /children/{id}/timeline` menambah kunci
  `referrals` pada tiap `entries[]` (dikelompokkan pada `referral_date`). Perubahan
  kontrak ditulis di `docs/RANCANGAN_BUKU_MEDIS.md` dan
  `.ai/rules/kontrak-timeline.md` lebih dulu. `ChildTimelineService` kini lima query.
- **Test**: `tests/Feature/ReferralTest.php` (21 test) + satu aturan baru di
  `tests/Feature/ChildTimelineTest.php` (`rujukan_muncul_pada_tanggal_nya`).
- **Mobile**: `models/referral.dart` (`Referral`, `ReferralTipe`,
  `ReferralStatus`, `ReferralList`), `models/visit.dart` (`Visit`, `VisitTipe`,
  `VisitList`), `services/referral_service.dart` (`getByChild`, `create`,
  `update`, `cancel`), `services/visit_service.dart` (`getByChild`, `create`,
  `update`), `screens/kader/rujukan_screen.dart` (daftar + detail + form
  **buat/koreksi rujukan** dengan pemilihan kunjungan, plus **batalkan** dengan
  konfirmasi), `screens/kader/kunjungan_screen.dart` (daftar + detail + form
  **buat/koreksi kunjungan**), endpoint
  `childReferralsEndpoint`/`kaderReferralsEndpoint`/`childVisitsEndpoint`/
  `kaderVisitsEndpoint` di `utils/constants.dart`. Saat koreksi, kunjungan/rujukan
  yang salah anak dibatalkan lalu dibuat ulang (server mengunci `child_id`/
  `visit_id` pada PATCH). Timeline mobile (`models/child_timeline.dart`
  `TimelineReferral`) menampilkan rujukan di `detail_anak_screen.dart`, dengan
  jalan masuk ke `KunjunganScreen` dan `RujukanScreen`.
- **Mobile — flow "buat kunjungan → input data → selesai"**: setelah kunjungan
  baru tersimpan, `KunjunganScreen` menawarkan lembar pilihan (Penimbangan /
  Imunisasi / Catatan Keluhan / Rujukan / Selesai). Tiap pilihan membuka layar
  input dengan membawa `visitId` kunjungan itu, lalu kembali ke lembar yang sama
  sampai kader memilih Selesai. `services/kader_service.dart`,
  `immunization_service.dart`, dan `medical_note_service.dart` mengirim
  `visit_id` opsional; `InputPenimbanganScreen`, `ImunisasiScreen`, dan
  `CatatanKeluhanScreen` menampilkan banner "menempel pada kunjungan", dan
  `RujukanScreen` menerima `initialVisitId` untuk pra-pilih kunjungan.

**Migrasi terkait:**

| Migration | Fungsi |
|---|---|
| `2026_10_13_152047_create_referrals_table` | Tabel `referrals` |

---

## 3. Yang Harus Dikerjakan (Roadmap)

### 3.1 Prioritas P0

| ID | Pekerjaan | Status |
|---|---|---|
| P0-2 | **Validasi WHO Multidimensi** (WFA/U, TB/U, BB/TB, IMT/U) | **Selesai** |
| P0-1 | **Entitas `Visit`**: tambah tabel `visits` + relasi `measurements.visit_id` | **Selesai** |
| P0-3 | **Klarifikasi "16 Imunisasi"** (dosis vs jenis) + jadwal Kemenkes RI | **Selesai** — jadwal 21 dosis aktif; keputusan dosen direspons belakangan lewat `PERANCANGAN_PERKUATAN.md` §10 |

### 3.2 Prioritas selanjutnya (ringkas, lihat `PERANCANGAN_PERKUATAN.md`)

**Selesai (P1):** Audit trail, Consent management + integrasi mobile (checkbox
persetujuan saat daftar anak, layar kelola Ibu/Kader), Enkripsi NIK, Rujukan
(`referrals`) + integrasi mobile (baca, buat, koreksi, batalkan), Kunjungan
(`visits`) + screen mobile, serta flow **"buat kunjungan → input data →
selesai"** (penimbangan/imunisasi/keluhan/rujukan menempel pada kunjungan) —
lihat §2.5 dan §2.6.

**Berikutnya:**

- P2: **Backup & retensi** (`PERANCANGAN_PERKUATAN.md` §5.5–5.6), Evaluasi klinis
  (validasi Z-score vs WHO Anthro).
- P2: KMS Digital interaktif, AI Food Scanner, Pemetaan Spasial (PostGIS), IoT Smart Triage.

---

## 4. Aturan Wajib Saat Bekerja

1. Logika Z-score **hanya** di trigger/procedure PostgreSQL (`AI_AGENT_RULES.md` #9).
2. Primary key **UUID** (`HasUuids`), foreign key pakai `foreignUuid()`.
3. Migration bersifat **additive** — jangan ubah migration lama yang sudah dijalankan.
4. Jangan ubah `AuthController`, struktur route, atau schema inti tanpa instruksi eksplisit.
5. Jangan jalankan/mengubah apa pun tanpa persetujuan pengguna.
6. Data WHO diambil dari `docs/data_who/` (format xlsx; kolom: A=usia, B=L, C=M, D=S).

---

## 5. Referensi Dokumen

| Kebutuhan | Dokumen |
|---|---|
| Prioritas & perancangan | `PERANCANGAN_PERKUATAN.md` |
| Aturan teknis | `AI_AGENT_RULES.md` |
| Kontrak API | `API_CONTRACT.md` |
| Skema database | `DATABASE_SCHEMA.md` |
| Setup & riwayat | `SETUP_LOG.md` |
| Data referensi WHO | `docs/data_who/` |
