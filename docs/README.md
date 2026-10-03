# Smart Posyandu

Sistem Informasi Manajemen Terpadu untuk mendigitalisasi pencatatan kesehatan ibu dan anak (KIA) di posyandu. Terdiri dari **backend API (Laravel)** dan **aplikasi mobile (Flutter)**, dengan kalkulasi status gizi otomatis berdasarkan standar WHO.

## Author

* **Moch Riezky Dwi Kuswanto**
* Institut Teknologi Nasional (Itenas) - Informatika (NRP: 152024133)

## Tech Stack

| Layer | Teknologi |
|---|---|
| Backend | Laravel 13 (REST API), PHP 8.4 |
| Database | PostgreSQL (trigger z-score WHO) |
| Auth | Laravel Sanctum (token-based) |
| Mobile | Flutter (Dart) |
| AI (direncanakan) | Python microservice - deteksi nutrisi |

## Struktur Proyek

```
posyandu/
├── posyandu-backend/     # API Laravel + migrasi + test (PHPUnit)
├── posyandu_mobile/      # Aplikasi Flutter + test (flutter_test)
├── docs/                 # Dokumentasi, kontrak API, rancangan, laporan
├── uji-api.ps1           # Skrip uji API end-to-end
└── periksa-teks.ps1      # Pemeriksaan konsistensi teks
```

## Fitur

| Fitur | Status |
|---|---|
| CRUD Data Anak | Selesai |
| e-KMS & Z-Score WHO (otomatis via trigger DB) | Selesai |
| Imunisasi & Jadwal Posyandu | Selesai |
| Buku Medis Digital (timeline medis) | Selesai |
| Catatan Keluhan Kader | Selesai |
| Grafik Tumbuh Kembang | Selesai |
| Edit data anak oleh Kader | Selesai |
| AI Food Scanner (microservice) | Belum dimulai |
| Pemetaan Spasial (PostGIS) | Belum dimulai |

## Menjalankan Backend

```bash
cd posyandu-backend
composer install
cp .env.example .env        # atur koneksi PostgreSQL
php artisan key:generate
php artisan migrate
php artisan serve
```

**Test backend** (butuh PostgreSQL `posyandu_test`):

```bash
php artisan test
```

## Menjalankan Mobile

```bash
cd posyandu_mobile
flutter pub get
flutter run
```

**Test mobile:**

```bash
flutter test
```

## Dokumentasi

| Kategori | File |
|---|---|
| Panduan | `AI_AGENT_RULES.md`, `Cara_menjalankan.md`, `SETUP_LOG.md`, `PROJECT_OVERVIEW.md` |
| Kontrak | `API_CONTRACT.md`, `DATABASE_SCHEMA.md` |
| Perencanaan | `RANCANGAN.md`, `RENCANA_SELANJUTNYA.md`, `RANCANGAN_BUKU_MEDIS.md`, `RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md` |
| Laporan | `LAPORAN_ZSCORE_TRIGGER.md`, `LAPORAN_IMUNISASI_JADWAL.md`, `LAPORAN_MEDICAL_NOTES.md`, `LAPORAN_BUKU_MEDIS.md`, `LAPORAN_GRAFIK_TUMBUH_KEMBANG.md`, `LAPORAN_REKAP_IMUNISASI_BULANAN.md`, `LAPORAN_REKAP_CSV.md` |
| Aturan agent | `posyandu-backend/.ai/rules/` (dibaca otomatis lewat `AGENTS.md`) |
