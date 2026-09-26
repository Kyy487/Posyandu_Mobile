# 📖 Project Overview: Smart Posyandu Mobile

## 🎯 Target Pengguna
Sistem ini dirancang untuk dua aktor utama dengan otorisasi (role) yang berbeda:
1. **Orang Tua / Ibu:** Konsumen data yang memantau tumbuh kembang anak melalui antarmuka mobile (Flutter).
2. **Kader Posyandu / Bidan:** Administrator lapangan yang menginput data antropometri bulanan secara cepat saat posyandu berlangsung.
## 🚀 Fitur Utama (Core Features)
* **e-KMS (Kartu Menuju Sehat) Digital:** Pencatatan berat badan, tinggi badan, dan lingkar kepala bulanan.
* **Auto-Kalkulasi Z-Score WHO:** Sistem database secara otomatis menghitung status gizi (Stunting, Gizi Kurang, Normal) berdasarkan input e-KMS.
* **Manajemen Imunisasi:** Pelacakan jadwal dan riwayat vaksinasi balita.
* **AI Food Scanner (Microservice):** Pemindai makanan MPASI menggunakan kamera smartphone untuk mengestimasi kalori (terintegrasi dengan API Python terpisah).
* **Pemetaan Spasial (PostGIS):** Visualisasi titik rawan stunting berdasarkan domisili balita (Fitur Khusus Kader).

## 🗺️ Roadmap Pengembangan (12-14 Minggu)
* **Fase 1:** Setup Database (PostgreSQL), Migrasi Inti (Users, Children, Measurements), dan Autentikasi API (Sanctum). *(Sedang Berlangsung)*
* **Fase 2:** Pengembangan CRUD API Data Anak & KMS.
* **Fase 3:** Setup Microservice AI (Python) untuk deteksi nutrisi.
* **Fase 4:** Pengembangan Antarmuka Mobile (Flutter) - Integrasi API, UI/UX Slicing, Chart (fl_chart).
* **Fase 5:** Pengujian Menyeluruh (E2E) dan Finalisasi.

## 🗺️ Roadmap Pengembangan (12-14 Minggu)
* **Fase 1:** Setup Database (PostgreSQL), Migrasi Inti (Users, Children, Measurements), dan Autentikasi API (Sanctum). *(Selesai)*
* **Fase 2:** Pengembangan CRUD API Data Anak & KMS, serta Database Trigger WHO.
* **Fase 3:** Setup Microservice AI (Python) untuk deteksi nutrisi.
* **Fase 4:** Pengembangan Antarmuka Mobile (Flutter) - Integrasi API, UI/UX Slicing, Chart (fl_chart).
* **Fase 5:** Pengujian Menyeluruh (E2E) dan Finalisasi.
* **Fase Ekstra (Pasca-Finalisasi):** Integrasi perangkat keras IoT Smartgate Triage sebagai input data otomatis.

