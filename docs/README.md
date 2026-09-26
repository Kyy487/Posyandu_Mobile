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
* `docs/AI_AGENT_RULES.md` - Aturan ketat untuk AI Code Assistant (Cursor/Copilot).
* `docs/DATABASE_SCHEMA.md` - Penjelasan ERD dan relasi tabel.
* `docs/API_CONTRACT.md` - Dokumentasi Endpoint API.
* `docs/SETUP_LOG.md` - Riwayat konfigurasi dan fitur yang sudah selesai.
* `docs/LAPORAN_ZSCORE_TRIGGER.md` - Laporan implementasi Z-Score WHO Weight-for-Age (backend + mobile).
