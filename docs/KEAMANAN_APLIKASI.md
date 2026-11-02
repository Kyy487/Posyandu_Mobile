# DOKUMEN KEAMANAN APLIKASI POSYANDU

**Versi Dokumen** : 1.0  
**Tanggal Audit**   : 27 Oktober 2026  
**Lingkup**         : `posyandu-backend` (Laravel 13 + Laravel Sanctum)  
**Tujuan**          : Mendokumentasikan penerapan keamanan, temuan audit, serta rekomendasi perbaikan untuk persiapan rilis/produksi.

## 1. Ringkasan Eksekutif

Berdasarkan hasil audit terhadap kode sumber saat ini, aplikasi Posyandu **sudah menerapkan beberapa kontrol keamanan yang cukup baik** untuk skala aplikasi Posyandu. Beberapa hal krusial seperti pemisahan peran, proteksi data sensitif, dan pembatasan akses sudah ada.

Namun, masih terdapat beberapa poin yang **wajib diperkuat** sebelum dideploy ke lingkungan produksi, terutama terkait konfigurasi lingkungan, model otorisasi, dan penerapan *security header*.

## 2. Mekanisme Keamanan yang Telah Diterapkan

| Aspek | Status | Keterangan |
|---|---|---|
| **Autentikasi** | Sudah Ada | Menggunakan Laravel Sanctum dengan *Bearer Token*. Token lama dihapus saat login ulang dan dapat dicabut saat logout. |
| **Otorisasi Berbasis Peran** | Sudah Ada | Menggunakan middleware `RoleCheck` (`ibu`, `kader`) untuk membatasi akses endpoint. |
| **Status Akun Ibu** | Sudah Ada | Middleware `EnsureIbuActive` membatasi Ibu dengan status `pending` atau `rejected`. Hanya route terkait kelengkapan pendaftaran, profil, dan logout yang diizinkan. |
| **Pemisahan Endpoint** | Sudah Ada | Endpoint Ibu (`/ibu/*`) dan Kader (`/kader/*`) dipisah untuk mencegah akses lintas peran. |
| **Perlindungan NIK** | Sudah Ada | Kolom `nik` dienkripsi menggunakan *Laravel Encryption* (`encrypted` cast). Pencarian untuk login menggunakan `nik_hash` (SHA256). `nik` dan `nik_hash` disembunyikan pada beberapa response. |
| **Proteksi Password** | Sudah Ada | Password di-*hash* menggunakan `Hash::make()` dan diverifikasi dengan `Hash::check()`. |
| **Registrasi Kader Terkontrol** | Sudah Ada | Pendaftaran kader wajib menyertakan `kader_code`. Dicek menggunakan `hash_equals()` untuk mencegah *timing attack*. Jika `KADER_REGISTRATION_CODE` kosong di `.env`, pendaftaran kader otomatis dimatikan (403). |
| **Persetujuan Data (Consent)** | Sudah Ada | Saat penambahan data anak, wajib mengirim `consent_type` dan `consent_document_version`. Tercatat pada tabel `consents` sebagai bukti persetujuan (mendukung prinsip kepatuhan terkait perlindungan data). |
| **Rate Limiting** | Sudah Ada | Diterapkan pada `POST /api/register` dan `POST /api/login` melalui `throttle` dengan nilai yang dikonfigurasi di `config/posyandu.php`. |
| **Standarisasi Error API** | Sudah Ada | Penanganan *exception* dikustomisasi di `bootstrap/app.php`. Response error untuk API bersifat konsisten berbentuk *JSON Envelope* (`success`, `message`, `errors`). Pesan *exception* asli hanya dicatat di *log*. |
| **UUID untuk Data Anak** | Sudah Ada | ID anak menggunakan UUID. Terdapat validasi format UUID pada endpoint sensitif untuk mencegah *error* SQL dan mengurangi potensi *enumeration*. |
| **Soft Delete** | Sudah Ada | Penghapusan data balita bersifat *soft delete*. Riwayat penimbangan, imunisasi, kunjungan, dan rujukan tetap tersimpan untuk menjaga integritas data medis. |
| **Upload Verifikasi** | Sudah Ada | Hanya mengizinkan tipe file `jpg`, `jpeg`, `png`, `pdf` dengan batas ukuran `max:5120` KB. |
| **Audit Trail** | Sudah Ada | Tersedia `AuditLogController` khusus untuk Kader guna meninjau riwayat perubahan data penting. |

## 3. Temuan Audit & Rekomendasi

### 3.1 Prioritas P0 (Kritis - Wajib sebelum Produksi)

| No | Temuan | Risiko | Rekomendasi Perbaikan |
|---|---|---|---|
| 1 | `APP_DEBUG` masih `true` pada `.env.example` | Tinggi | Set `APP_DEBUG=false` dan `APP_ENV=production` pada `.env` produksi. Jangan pernah mengaktifkan debug di lingkungan publik. |
| 2 | `APP_KEY` bisa kosong | Tinggi | Pastikan `APP_KEY` ter-generate (`php artisan key:generate`) dan tidak pernah dibagikan atau di-*commit*. |
| 3 | Belum ada konfigurasi CORS ketat | Tinggi | Buat `config/cors.php` dengan `allowed_origins` terbatas hanya ke domain/aplikasi resmi (web admin/mobile). Hindari penggunaan `*`. Jika menggunakan *credentials*, wajib batasi origin secara spesifik. |
| 4 | Belum terkonfigurasi HTTPS/HSTS | Tinggi | Gunakan HTTPS pada seluruh endpoint API. Aktifkan *HTTP Strict Transport Security* (HSTS) melalui web server (Nginx/Apache) atau middleware. |
| 5 | `KADER_REGISTRATION_CODE` dapat dibiarkan kosong/tidak kuat | Tinggi | Jika tidak ada kebutuhan pendaftaran kader mandiri, **biarkan kosong** agar fitur dinonaktifkan. Jika tetap digunakan, wajib isi dengan nilai acak yang panjang dan unik. Jangan simpan di repositori. |

### 3.2 Prioritas P1 (Penting - Sangat Disarankan)

| No | Temuan | Risiko | Rekomendasi Perbaikan |
|---|---|---|---|
| 1 | Otorisasi masih bersifat manual per-controller | Sedang-Tinggi | Implementasikan *Laravel Policy* (`ChildPolicy`, `VisitPolicy`, `ReferralPolicy`, dll) dan manfaatkan `Gate::authorize()` / `$this->authorize()`. Hal ini mengurangi risiko lupa pengecekan kepemilikan data. |
| 2 | Belum ada *Security Headers* | Sedang-Tinggi | Tambahkan middleware global untuk menerapkan: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy`, dan `Strict-Transport-Security`. |
| 3 | *File upload* masih dapat ditingkatkan | Sedang | Simpan file verifikasi di *storage* yang **tidak dapat dieksekusi langsung** oleh web server. Pertimbangkan mengganti nama file secara acak, validasi *MIME type* berbasis konten, serta penggunaan *signed URL* jika perlu diakses terbatas. |
| 4 | `SANCTUM_TOKEN_EXPIRATION` belum diatur | Sedang | Pertimbangkan menetapkan masa berlaku token (mis. 7-30 hari) sesuai kebutuhan aplikasi mobile. Jangan biarkan token berlaku tanpa batas jika risiko pencurian token cukup tinggi. |
| 5 | `SESSION_ENCRYPT=false` | Sedang | Jika aplikasi masih menggunakan session berbasis cookie di masa depan, aktifkan `SESSION_ENCRYPT=true`. Untuk saat ini API *stateless* berbasis Sanctum sudah cukup baik. |
| 6 | Throttling hanya pada login & register | Sedang | Tambahkan *rate limiting* pada endpoint sensitif seperti `POST/PATCH/DELETE` terkait data anak, kunjungan, rujukan, dan imunisasi untuk membatasi penyalahgunaan token yang valid. |

### 3.3 Prioritas P2 (Perbaikan Berkelanjutan)

| No | Temuan | Risiko | Rekomendasi Perbaikan |
|---|---|---|---|
| 1 | Belum ada penerapan 2FA | Rendah-Sedang | Pertimbangkan *Two-Factor Authentication* (2FA) khusus untuk akun **Kader** mengingat peran ini memiliki akses luas ke data kesehatan anak. |
| 2 | Audit log bisa diperluas cakupannya | Rendah-Sedang | Pastikan seluruh aksi krusial tercatat: hapus data anak, persetujuan/penolakan pendaftaran ibu, pencatatan/perubahan imunisasi, pembuatan/pembatalan rujukan, serta perubahan status akun. |
| 3 | Ketergantungan pihak ketiga | Rendah | Lakukan `composer audit` dan `npm audit` secara berkala untuk mendeteksi kerentanan pada dependensi. Terapkan pembaruan *patch* dengan hati-hati. |
| 4 | Backup & Recovery | Rendah | Pastikan mekanisme *backup* database dan *storage* (termasuk file verifikasi) terjadwal, terenkripsi, serta pernah diuji proses *restore*-nya. |

## 4. Checklist Verifikasi Keamanan (Pre-Deployment)

Gunakan checklist ini sebagai panduan final sebelum aplikasi dipublikasikan.

### Konfigurasi Lingkungan
- [ ] `APP_ENV=production`
- [ ] `APP_DEBUG=false`
- [ ] `APP_KEY` sudah ter-set dan unik
- [ ] `.env` tidak masuk ke *version control* (`.gitignore` terkonfirmasi)
- [ ] `KADER_REGISTRATION_CODE` diatur sesuai kebijakan (kosong atau nilai kuat)
- [ ] `APP_URL` menggunakan protokol `https://`

### Keamanan API & Akses
- [ ] CORS dikonfigurasi ketat (hanya origin resmi)
- [ ] Rate limiting aktif untuk endpoint login & register
- [ ] Semua route sensitif terlindungi oleh `auth:sanctum` + `RoleCheck`
- [ ] Logika status `ibu` (pending/rejected/active) berfungsi sesuai ekspektasi
- [ ] Token Sanctum dapat dicabut dengan benar saat logout

### Data & File
- [ ] NIK tersimpan terenkripsi dan tidak bocor di response publik
- [ ] Password hanya tersimpan dalam bentuk *hash*
- [ ] File upload dibatasi tipe & ukuran, serta disimpan di lokasi aman
- [ ] Soft delete berfungsi dan riwayat tidak terhapus permanen
- [ ] Persetujuan (*consent*) tercatat saat penambahan anak

### Infrastruktur & Monitoring
- [ ] HTTPS & HSTS aktif
- [ ] *Security headers* terpasang
- [ ] *Logging* aktif tanpa menampilkan data sensitif ke client
- [ ] Proses backup database & storage terjadwal
- [ ] `composer audit` dan `npm audit` dalam keadaan bersih atau telah ditindaklanjuti

## 5. Kesimpulan

Secara keseluruhan, penerapan keamanan pada aplikasi Posyandu ini **sudah berjalan di arah yang benar**. Kontrol seperti autentikasi berbasis token, pembatasan peran, perlindungan NIK, *rate limiting*, konsistensi *error handling*, serta penggunaan *soft delete* patut diapresiasi.

Fokus utama untuk kelayakan produksi adalah menyelesaikan poin **P0** terlebih dahulu, khususnya **konfigurasi lingkungan, CORS, dan HTTPS**. Setelah itu, lanjutkan ke **P1** untuk memperkuat model otorisasi dan *security headers*. Dengan perbaikan tersebut, aplikasi ini sudah cukup layak untuk digunakan secara aman pada lingkungan operasional Posyandu.

**Catatan:** Dokumen ini bersifat *living document*. Direkomendasikan untuk ditinjau ulang minimal setiap kali terdapat penambahan fitur sensitif (penambahan role, integrasi pihak ketiga, atau perubahan alur data kesehatan).  
**Lokasi Dokumen:** `docs/KEAMANAN_APLIKASI.md`  
**Pemilik Dokumen:** Tim Pengembang Posyandu  
**Terakhir Diperbarui:** 27 Oktober 2026
