# Rencana Kerja Berikutnya

> **Dibuat:** 14 Oktober 2026
> **Dokumen acuan:** `STATUS_PENGEMBANGAN.md`, `PERANCANGAN_PERKUATAN.md`
> **Status commit terakhir:** `4ed57c4` — P1: consent UU PDP, enkripsi NIK,
> rujukan, dan kunjungan.

Semua pekerjaan P0 dan P1 (Fase 1–4 `PERANCANGAN_PERKUATAN.md` §8) sudah selesai
dan sudah di-commit. Sisa jalan: **Fase 5 (Evaluasi)** lalu **P2** (backup &
retensi, evaluasi klinis). Dokumen ini memecahnya jadi urutan kerja yang bisa
langsung dikerjakan.

---

## 1. Prioritas hari ini

| # | Pekerjaan | Perkiraan | Bergantung pada |
|---|---|---|---|
| 1 | Verifikasi menyeluruh (test backend + mobile) | 0.5 hari | — |
| 2 | Rapikan checklist & tanggal dokumen | 0.5 jam | #1 |
| 3 | Fase 5 — Evaluasi teknis (performa + cakupan test) | 1 hari | #1 |

Fokus hari ini: **#1 dan #2 dulu** (memastikan batch P1 benar-benar hijau),
baru lanjut #3.

---

## 2. Langkah 1 — Verifikasi menyeluruh

Belum ada test backend yang dijalankan di sesi commit terakhir, jadi ini
pemeriksaan wajib sebelum menambah pekerjaan baru.

### Backend (PostgreSQL `posyandu_test`, `RefreshDatabase`)

```powershell
$php = "C:\laragon\bin\php\php-8.4.26-nts-Win32-vs17-x64\php.exe"
& $php artisan test
& $php "C:\laragon\bin\composer\composer.phar" pint --dirty
```

Yang dipastikan:

- Suite penuh hijau (terakhir 212 test; kini bertambah `ConsentManagementTest`,
  `NikEncryptionTest`, `ReferralTest`).
- `pint --dirty` bersih untuk file PHP yang tersentuh batch P1
  (`ConsentController`, `ReferralController`, `Consent`, `Referral`,
  `AuthController`, `Child`, `User`).
- Perhatikan `ChildFactory` random DOB: test baru yang menyentuh tanggal lahir
  harus hardcode `date_of_birth` (`.ai/rules/pengujian.md`).

### Mobile

```powershell
flutter analyze
flutter test
```

Target: `flutter analyze` tanpa isu, suite **203/203**. Tambahan test kandidat
(jika belum, cek dulu):

- `test/consent_screen_test.dart` — `ConsentScreen(bisaMengelola: false)` tidak
  merender tombol Beri/Cabut, sedangkan `bisaMengelola: true` merendernya.
  Pakai pola stub secure storage di `test/grafik_tumbuh_kader_test.dart`
  (tanpa server, layar berakhir di state error — cek via
  `tester.takeException()`).
- `test/kunjungan_flow_test.dart` sudah menambah kontrak 4 layar input; tidak
  perlu diubah kecuali ada regresi.

### Kriteria selesai

- [ ] `php artisan test` hijau.
- [ ] `pint --dirty` tanpa diff.
- [ ] `flutter analyze` bersih.
- [ ] `flutter test` 203/203 atau lebih.
- [ ] Bila ada perbaikan, commit terpisah (bukan amend `4ed57c4`).

---

## 3. Langkah 2 — Rapikan dokumentasi

- [ ] Centang checklist **Fase 4** di `PERANCANGAN_PERKUATAN.md` §8
      (Screen kunjungan, flow, Screen rujukan, Screen consent) dan tandai
      Fase 1–3 selesai.
- [ ] Naikkan tanggal `STATUS_PENGEMBANGAN.md` menjadi 14 Oktober 2026.
- [ ] Pastikan `docs/API_CONTRACT.md` sudah memuat endpoint consent & referral
      (sudah disertakan di commit `4ed57c4`; verifikasi saja).

---

## 4. Langkah 3 — Fase 5: Evaluasi

### 4.1 Evaluasi teknis

- Tinjau **cakupan test** consent & rujukan (endpoint + mobile). Tambal celah
  yang ketemu, bukan sekadar menambah jumlah test.
- **Uji performa endpoint berat** dengan data banyak:
  - `GET /children/{id}/timeline` (limit + cursor; 5 query di
    `ChildTimelineService`).
  - `GET /children/{id}/growth`.
  - `GET /kader/immunizations/recap`.
  - Ukur waktu respons setelah seed beberapa ribu baris `measurements`.
- Perhatikan potensi N+1 pada relasi baru (`Child::consents()`,
  `Child::referrals()`, `User::consents()`).

### 4.2 Verifikasi kontrak

- Pastikan `data` untuk `GET /children/{id}/consents` tetap **list langsung**
  (bukan `{child, consents}`) — sudah dikunci di test kontrak.
- Pastikan `POST /children` menolak 422 tanpa `consent_type`
  (sudah dicakup `ConsentManagementTest`).
- Cek `POST/DELETE /children/{id}/consents` hanya boleh Ibu (Kader 403).

### 4.3 Yang butuh pihak luar (jadwalkan, jangan dikerjakan sendiri)

- **Validasi klinis**: bandingkan Z-score hasil trigger PostgreSQL vs WHO Anthro
  (butuh bantuan dosen). Siapkan skrip/sampel kasus + tabel pembanding.
- **Uji coba kader**: skenario manual alur "buat kunjungan → input data →
  rujukan", pendaftaran anak + centang consent, dan beri/cabut consent sebagai
  Ibu. Siapkan lembar skenario + kriteria lulus.

### Kriteria selesai

- [ ] Ada catatan hasil uji performa (waktu respons per endpoint).
- [ ] Tidak ada N+1 yang belum disadari pada endpoint timeline/growth/recap.
- [ ] Dokumen skenario uji kader & validasi klinis siap dipakai.

---

## 5. Backlog setelahnya (P2, belum dijadwalkan)

- **Backup & retensi** (`PERANCANGAN_PERKUATAN.md` §5.5–5.6): runbook backup
  harian `pg_dump`, retensi 30 hari rolling + arsip bulanan 1 tahun, uji restore
  bulanan.
- **Retensi data** §5.6: kebijakan hapus/anonimkan sesuai tabel.
- **Akuntabilitas koreksi** §5.7: alur koreksi + old/new values di audit log.

---

## 6. Catatan teknis penting (jangan dilanggar)

- Logika Z-score **hanya** di trigger/function PostgreSQL.
- Migration **additive**; jangan ubah migration lama.
- Jangan ubah `AuthController`/struktur route/skema inti tanpa instruksi.
- Primary key UUID (`HasUuids`), FK `foreignUuid()`.
- Jangan commit/amend tanpa permintaan eksplisit.
