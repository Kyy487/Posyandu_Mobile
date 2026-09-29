# Smart Posyandu - Backend API

Sistem Informasi Manajemen Terpadu untuk mendigitalisasi proses pencatatan kesehatan ibu dan anak (KIA). API ini melayani aplikasi mobile Flutter dan berinteraksi dengan microservice AI (Python) untuk deteksi nutrisi.

## 👨‍💻 Author
* **Moch Riezky Dwi Kuswanto** 
* Institut Teknologi Nasional (Itenas) - Informatika (NRP: 152024133)

## 🛠 Tech Stack
* **Framework:** Laravel 13 (REST API)
* **Database:** PostgreSQL (Lokal menggunakan Laragon/HeidiSQL)
* **Authentication:** Laravel Sanctum (Token-based)
* **Mobile Client:** Flutter
* **Spatial Data:** PostGIS (direncanakan)

## ⚙️ Persyaratan Sistem
* PHP 8.4+
* Composer
* PostgreSQL (Ekstensi `pdo_pgsql` dan `pgsql` wajib aktif di `php.ini`)

## 🚀 Cara Setup Lokal
1. `git clone [repository_url]`
2. `composer install`
3. Salin `.env.example` ke `.env` dan atur konfigurasi database PostgreSQL.
4. `php artisan key:generate`
5. `php artisan migrate`
6. `php artisan serve`

## 📂 Struktur Dokumentasi

**Panduan**
* `AI_AGENT_RULES.md` - Aturan ketat untuk AI Code Assistant (Cursor/Copilot).
* `SETUP_LOG.md` - Riwayat konfigurasi dan fitur yang sudah selesai.
* `Cara_menjalankan.md` - Cara menjalankan backend, test, dan skrip pemeriksaan.
* `PROJECT_OVERVIEW.md` - Gambaran umum proyek dan pembagian kerja.

**Kontrak**
* `API_CONTRACT.md` - Dokumentasi Endpoint API.
* `DATABASE_SCHEMA.md` - Penjelasan ERD dan relasi tabel.

**Perencanaan**
* `RANCANGAN.md` - Rancangan awal seluruh modul (A sampai J).
* `RENCANA_SELANJUTNYA.md` - Opsi pekerjaan berikutnya beserta statusnya.
* `RANCANGAN_BUKU_MEDIS.md` - Spesifikasi normatif Buku Medis Digital (Opsi B).

**Laporan implementasi**
* `LAPORAN_ZSCORE_TRIGGER.md` - Z-Score WHO Weight-for-Age (backend + mobile).
* `LAPORAN_IMUNISASI_JADWAL.md` - Imunisasi & Jadwal Posyandu (backend + mobile).
* `LAPORAN_MEDICAL_NOTES.md` - Catatan Keluhan Kader, Opsi C.
* `LAPORAN_REKAP_IMUNISASI_BULANAN.md` - Rekap bulanan, Opsi E.
* `LAPORAN_REKAP_CSV.md` - Export CSV rekap, Opsi E.

**Aturan untuk agent di dalam repo**
* `posyandu-backend/.ai/rules/` - `kontrak-timeline.md`, `yang-jangan-diubah.md`,
  `pengujian.md`. Dibaca otomatis lewat `posyandu-backend/AGENTS.md`.
