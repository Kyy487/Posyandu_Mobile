# Checklist Fase 1.5 — Kesiapan Produksi

Dokumen ini adalah checklist kerja untuk menutup Fase 1 sebelum masuk Fase 2.
Isi kolom bukti dengan tautan, nama file, atau hasil perintah. Jangan centang
tanpa bukti.

**Status:** berjalan - Observability & security selesai di repo; verifikasi environment saat deploy
**Pemilik:** _(isi)_
**Target selesai:** _(isi)_
**Commit awal:** `7917057`
**Hasil observability & security:** `2c143dc`, `f11cff5`

## A. Data IHS

- [ ] Format IHS final diterima dari IG SATUSEHAT.
- [ ] `App\Support\IhsNumber` diperbarui sesuai format final.
- [ ] Test validasi IHS diperbarui dan lulus.
- [ ] Data IHS lama divalidasi ulang.
- [ ] Data IHS invalid dikoreksi lewat admin/CSV.
- [ ] Tidak ada IHS duplikat.
- [ ] Bukti: _(tempel hasil query/tautan)_

Perintah cek duplikat:

```sql
SELECT ihs_number, count(*)
FROM children
WHERE ihs_number IS NOT NULL
GROUP BY ihs_number
HAVING count(*) > 1;
```

## B. Terminologi Imunisasi (KFA/CVX)

- [ ] Mapping KFA/CVX resmi diterima.
- [ ] `immunization_types.kfa_code` terisi untuk tipe yang membutuhkan.
- [ ] `immunization_types.cvx_code` terisi untuk tipe yang membutuhkan.
- [ ] `cvx_display`, `cvx_group_code`, `target_disease_code` diisi bila ada.
- [ ] Tipe yang sengaja belum punya mapping didokumentasikan alasannya.
- [ ] Validasi FHIR Immunization untuk semua tipe aktif lulus.
- [ ] Bukti: _(tempel hasil validasi/daftar tipe)_

Perintah cek:

```sql
SELECT code, name, kfa_code, cvx_code
FROM immunization_types
WHERE is_active = true
ORDER BY code, dose_number;
```

## C. Red Flags

- [ ] Daftar red flags direview tenaga kesehatan.
- [ ] `App\Support\RedFlagCodes` diperbarui.
- [ ] Dokumentasi red flags diperbarui.
- [ ] Test red flags diperbarui dan lulus.
- [ ] Kader memahami bahwa red flag bukan diagnosis.
- [ ] Bukti: _(tempel catatan persetujuan)_

## D. Rehearsal Migrasi di Staging

Prasyarat:

- [ ] Salinan database produksi tersedia.
- [ ] Backup sebelum migrate dibuat.
- [ ] `.env` staging menunjuk database staging, bukan produksi.

Langkah:

- [ ] Catat jumlah baris tabel utama sebelum migrate.
- [ ] Catat distribusi `z_score_wfa`/`status_gizi` sebelum migrate.
- [ ] Jalankan `php artisan migrate --force`.
- [ ] Catat durasi migration.
- [ ] Bandingkan jumlah baris setelah migrate.
- [ ] Pastikan `visit_started_at` dan `measured_at` terisi dari tanggal lama.
- [ ] Pastikan Z-Score dan status gizi tidak berubah.
- [ ] Uji rollback di staging.
- [ ] Bukti: _(tempel hasil perbandingan)_

Query pembanding:

```sql
SELECT count(*) FROM children;
SELECT count(*) FROM visits WHERE visit_started_at IS NULL;
SELECT count(*) FROM measurements WHERE measured_at IS NULL;
SELECT status_gizi, count(*) FROM measurements GROUP BY status_gizi ORDER BY 1;
```

## E. Pilot Admin IHS

- [ ] Template CSV diunduh dari endpoint admin.
- [ ] Import `dry_run` dijalankan dengan data nyata.
- [ ] Hasil `dry_run` direview: total, updated, skipped, failed.
- [ ] Import nyata dijalankan di staging.
- [ ] Audit log diperiksa untuk setiap perubahan.
- [ ] Laporan error dapat dilacak per baris.
- [ ] Kader diuji tidak bisa mengubah IHS.
- [ ] Bukti: _(tempel ringkasan hasil import)_

## F. Observability dan Keamanan

- [x] Log import tidak memuat NIK lengkap. Bukti: `SensitiveDataRedactorTest`.
- [x] Log FHIR tidak memuat kredensial. Bukti: `satusehat.log` hanya ringkasan payload.
- [ ] `APP_DEBUG=false` di staging/produksi. Diverifikasi saat deploy.
- [x] Rate limit login/register aktif. Bukti: `AuthThrottleTest`.
- [x] CORS ketat dan security headers aktif. Bukti: `config/cors.php`, `App\Http\Middleware\SecurityHeaders`, `tests/Feature/SecurityHeadersTest.php`.
- [x] Masa berlaku token Sanctum dibatasi 30 hari. Bukti: `config/sanctum.php`, `tests/Feature/TokenExpirationTest.php`.
- [x] Endpoint admin hanya bisa diakses role `admin`. Bukti: `AdminChildIhsTest`.
- [x] Retensi audit log ditentukan: 5 tahun (1825 hari), tidak dihapus otomatis. Bukti: `config/posyandu.php`, `docs/DOKUMENTASI_UTAMA.md` bagian 6.8, `tests/Feature/AuditLogPruneTest.php`.
- [x] Kredensial SATUSEHAT tidak masuk repo; prosedur secret manager terdokumentasi. Bukti: `.env.example`, `docs/DOKUMENTASI_UTAMA.md` bagian 6.8.
- [x] Bukti: `tests/Unit/SensitiveDataRedactorTest.php`, `tests/Feature/LogRedactionConfigTest.php`, `tests/Feature/AuthThrottleTest.php`, `tests/Feature/AuditLogPruneTest.php`.

## G. Handover

- [ ] Runbook deploy tersedia.
- [ ] Runbook rollback tersedia.
- [ ] Kontak penanggung jawab tercatat.
- [ ] Developer lain berhasil menjalankan test dari dokumentasi.
- [ ] `docs/DOKUMENTASI_UTAMA.md` diperbarui.
- [ ] Bukti: _(tempel nama/tautan runbook)_

## H. Sign-off Fase 1.5

| Peran | Nama | Tanggal | Keputusan |
|---|---|---|---|
| Teknis |  |  |  |
| Tenaga kesehatan |  |  |  |
| Koordinator Posyandu |  |  |  |

Fase 2 hanya dimulai setelah semua bagian A-G dicentang dengan bukti dan
sign-off H diisi.
