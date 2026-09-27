# Rencana Pengembangan Smart Posyandu

Dokumen ini dipakai untuk memilih pekerjaan berikutnya. Setiap opsi ditulis
dengan estimasi dan tingkat kesulitan supaya bisa dipilih tanpa perlu tebak.

**Dokumen terkait:** `LAPORAN_IMUNISASI_JADWAL.md` (fase yang baru selesai)

---

## Peta Fitur vs Rancangan Awal

Status fitur berdasarkan `RANCANGAN.md`:

| Modul (dari RANCANGAN.md) | Status |
| :--- | :--- |
| A. CRUD Data Anak | Selesai |
| B. e-KMS dan Z-Score WHO | Selesai |
| C. Imunisasi | Selesai (Fase 3) |
| D. Jadwal Posyandu | Selesai (Fase 3) |
| E. Buku Medis Digital (EHR) | Belum ada |
| F. Catatan Medis / Keluhan | Belum ada |
| G. Grafik Tumbuh Kembang | Belum ada |
| H. Edukasi Kesehatan | Belum ada |
| I. "Sepiring Bergizi" (AI vision) | Belum ada |
| J. Smart Triage (IoT) | Belum ada |

**Mayoritas RANCANGAN.md belum dikerjakan.** Yang sudah selesai hanya
fondasi data dan 2 fitur operasional.

---

## Opsi A - Rapikan Kualitas (SELESAI)

| | |
| :--- | :--- |
| Estimasi | 1 sampai 2 hari |
| Kesulitan | Mudah |
| Risiko | Sangat rendah |
| Status | **Selesai - 27 September 2026** |

Rincian hasil ada di `LAPORAN_IMUNISASI_JADWAL.md`.

- [x] `vendor/bin/pint` dijalankan untuk seluruh repo (commit terpisah)
- [x] `laravel/boost` dipasang
- [x] Validasi urutan dosis (dosis N tidak boleh sebelum dosis N-1)
- [x] Endpoint `DELETE /kader/immunizations/{id}` + tombol "Batalkan suntikan" di aplikasi
- [x] Data uji yang tertinggal di DB lokal dihapus (kembali ke 7 user, 3 anak)
- [x] Dokumentasi diperbarui
- [x] `git push` — `main` sinkron dengan `origin/main`

**Catatan:** validasi yang dipasang membandingkan tanggal yang dicatat pada
dosis tetangga N-1 dan N+1, bukan mengukum dari master `interval_months`.
Alasannya ada di bagian "Temuan Selesai" pada laporan.

**Saran urutan berikutnya:** Opsi C (catatan keluhan), lalu Opsi E (rekap).

---

## Opsi B - Buku Medis Digital (EHR)

| | |
| :--- | :--- |
| Estimasi | 4 sampai 6 hari |
| Kesulitan | Sedang |

Gabung penimbangan, imunisasi, dan jadwal jadi satu halaman rekam medis
anak yang bisa dibuka kader kapan saja.

- Tabel riwayat pemeriksaan (kunjungan)
- Kolom kondisi khusus: alergi, penyakit bawaan (tagging)
- Layar timeline, contoh: "24 Sep 2026 - Penimbangan, BB 6.1 kg, Normal"
- Export PDF sederhana

**Dependensi:** Opsi A sudah selesai, jadi penghalang di sini sudah terpecahkan.

---

## Opsi C - Catatan Keluhan Kader

| | |
| :--- | :--- |
| Estimasi | 3 sampai 4 hari |
| Kesulitan | Mudah |

Kolom keluhan saat kunjungan: demam, rewel, diare, dan catatan saran. Ini
paling murah dari RANCANGAN.md tapi paling sering dipakai di lapangan.

- Tabel `medical_notes` (sudah ada rancangannya di `LAPORAN_ZSCORE_TRIGGER.md`)
- Form keluhan di layar penimbangan
- Ibu bisa read-only
- Filter keluhan per bulan

---

## Opsi D - Grafik Tumbuh Kembang

| | |
| :--- | :--- |
| Estimasi | 3 sampai 4 hari |
| Kesulitan | Sedang |

Grafik BB dan TB dari waktu ke waktu. Ibu sudah bisa akses datanya sendiri di
aplikasi, tinggal divisualisasikan.

- Butuh 1 dependency chart di Flutter, misalnya `fl_chart`
- Butuh endpoint khusus deret waktu (endpoint sekarang hanya per bulan)

---

## Opsi E - Rekap dan Laporan

| | |
| :--- | :--- |
| Estimasi | 3 sampai 5 hari |
| Kesulitan | Sedang |

Vista cepat untuk kader: berapa anak yang imunisasinya belum lengkap bulan
ini. Ini paling bernilai secara operasional.

- Filter "anak yang punya dosis terlambat"
- Rekap suntikan per bulan
- Rekap bulanan untuk laporan ke BIDAN
- Export CSV

**Nilai praktis:** kapan perlu menambah stok vaksin, kapan harus menyiapkan
kunjungan rumah. Saat ini informasi itu harus dibuka manual satu per satu.
Contoh: kalau ada rekap "3 anak punya suntikan terlambat bulan ini", kader
tahu harus menyiapkan vaksin lebih awal.

---

## Opsi F - Notifikasi dan Pengingat

| | |
| :--- | :--- |
| Estimasi | 4 sampai 6 hari plus backend push service |
| Kesulitan | Sulit |

- Pengingat agenda H-1 ke Ibu
- Pengingat dosis yang jatuh tempo

**Catatan:** butuh layanan push (FCM) atau backend job. Poundasi
infrastrukturnya lebih besar dari aplikasi mobile-nya sendiri. Saran:
kerjakan nanti, setelah Opsi B, C, atau E terbukti aplikasinya benar-benar
dipakai.

---

## Opsi G - "Sepiring Bergizi" (AI Computer Vision)

| | |
| :--- | :--- |
| Estimasi | 2 sampai 3 minggu |
| Kesulitan | Sangat sulit |

Ibu memotret porsi makanan anak, AI mendeteksi komponen gizi, lalu memberi
feedback kualitatif.

**Ini fitur paling besar dan paling berisiko.** Butuh:

1. Microservice Python terpisah
2. Model computer vision
3. Pipeline upload gambar
4. Validasi output

**Saran:** jangan dikerjakan sekarang. Butuh MVP yang benar-benar dipakai
terlebih dulu sebelum menambah kompleksitas sebesar ini.

---

## Saran Urutan

1. ~~**Opsi A** (rapikan)~~ - **selesai 27 September 2026**
2. **Opsi C** (catatan keluhan) - paling murah, paling sering dipakai
3. **Opsi E** (rekap) - paling bernilai operasional
4. **Opsi B** (buku medis) - fondasi rekam medis lengkap
5. **Opsi D** (grafik) - setelah ada cukup data
6. **Opsi F** (notifikasi) - setelah aplikasi benar-benar dipakai
7. **Opsi G** (AI) - terakhir, kalau masih relevan

---

## Cara Memilih

Jawab 3 pertanyaan ini:

1. **Sudah dipakai secara nyata belum?** Kalau belum, utamakan Opsi A
   (kualitas), bukan fitur baru.
2. **Siapa yang jadi target?** Ibu fokus D, G, F. Kader kejar B, C, E.
3. **Kapan harus demo?** Kalau ada batas waktu, kerjakan yang bisa
   didemokan dulu, bukan yang paling rapi.

---

## Catatan Environment

| Config | Nilai |
| :--- | :--- |
| `API_BASE_URL` | `http://10.0.2.2:8000/api` (default emulator) |
| `KADER_REGISTRATION_CODE` | isi di `.env` |
| `POSYANDU_NAME` | `Posyandu Desa Sukamaju` |
| `IMMUNIZATION_LATE_AFTER_MONTHS` | `2` |

**Belum ada environment production.** Kalau mau deploy, ini yang perlu
dibuat lebih dulu: credential, HTTPS, backup, dan monitoring.
