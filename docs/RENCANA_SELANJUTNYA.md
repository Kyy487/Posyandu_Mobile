# Rencana Pengembangan Smart Posyandu

Dokumen ini dipakai untuk memilih pekerjaan berikutnya. Setiap opsi ditulis
dengan estimasi dan tingkat kesulitan supaya bisa dipilih tanpa perlu tebak.

**Dokumen terkait:** `LAPORAN_IMUNISASI_JADWAL.md` (fase yang baru selesai),
`LAPORAN_MEDICAL_NOTES.md` (Opsi C), `LAPORAN_REKAP_IMUNISASI_BULANAN.md`
(Opsi E, backend + mobile), `LAPORAN_REKAP_CSV.md` (Opsi E, export CSV)

---

## Peta Fitur vs Rancangan Awal

Status fitur berdasarkan `RANCANGAN.md`:

| Modul (dari RANCANGAN.md) | Status |
| :--- | :--- |
| A. CRUD Data Anak | Selesai |
| B. e-KMS dan Z-Score WHO | Selesai |
| C. Imunisasi | Selesai (Fase 3) + rekap bulanan (Opsi E, backend, mobile, dan export CSV) |
| D. Jadwal Posyandu | Selesai (Fase 3) |
| E. Buku Medis Digital (EHR) | Selesai (Opsi B, backend + mobile) |
| F. Catatan Keluhan | Selesai (Opsi C) |
| G. Grafik Tumbuh Kembang | Selesai (Opsi D, backend + mobile) |
| H. Edukasi Kesehatan | Belum ada |
| I. "Sepiring Bergizi" (AI vision) | Belum ada |
| J. Smart Triage (IoT) | Belum ada |

**Mayoritas RANCANGAN.md belum dikerjakan.** Yang sudah selesai adalah fondasi
data, imunisasi, jadwal, buku medis, catatan keluhan, grafik tumbuh kembang, dan
rekap bulanan. Belum ada layar edukasi, AI, atau IoT.

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

## Opsi B - Buku Medis Digital (EHR) (SELESAI)

| | |
| :--- | :--- |
| Estimasi | 2,5 sampai 3 hari |
| Kesulitan | Sedang |
| Status | **Selesai 29 September 2026** - backend + mobile + dokumentasi |

Gabung penimbangan, imunisasi, dan jadwal jadi satu halaman rekam medis
anak yang bisa dibuka kader kapan saja.

**Rancangan lengkapnya ada di `RANCANGAN_BUKU_MEDIS.md`.** Itu yang jadi acuan
saat pengerjaan, dokumen ini cuma ringkasannya.

- [x] Tabel riwayat pemeriksaan (kunjungan) - `GET /children/{id}/timeline`
- [x] Kolom kondisi khusus: alergi, penyakit bawaan (tagging) - `children.medical_flags`
- [x] Layar timeline di `detail_anak_screen.dart`, contoh: "24 Sep 2026 - Penimbangan, BB 6.1 kg, Normal"
- [x] Export PDF sederhana - **ditunda**, tidak masuk MVP

**Dependensi:** Opsi A sudah selesai, jadi penghalang di sini sudah terpecahkan.

**Dua keputusan yang dulu menunggu jawaban sudah ditutup pada 29 September
2026:** kondisi khusus memakai kolom `children.medical_flags` (bukan tabel
terpisah), dan timeline dikelompokkan per kunjungan (bukan per kejadian).
Keduanya beserta alasannya ada di bagian 5 dokumen rancangannya.

---

## Opsi C - Catatan Keluhan Kader (SELESAI — 27 Sep 2026)

| | |
| :--- | :--- |
| Estimasi | 3 sampai 4 hari |
| Kesulitan | Mudah |
| Status | **Selesai** — backend + mobile + dokumentasi |

Kolom keluhan saat kunjungan: demam, rewel, diare, dan catatan saran. Ini
paling murah dari RANCANGAN.md tapi paling sering dipakai di lapangan.

- Tabel `medical_notes` (sudah ada rancangannya di `LAPORAN_ZSCORE_TRIGGER.md`)
- Form keluhan di layar penimbangan
- Ibu bisa read-only
- Filter keluhan per bulan

**Yang berubah dari rancangan awal:**

- Keluhan disimpan sebagai tiga kolom boolean terpisah (`demam`, `rewel`,
  `diare`), bukan satu daftar — supaya rekap bulanan (Opsi E) bisa dijawab
  dengan satu aggregate. Tidak ada `jenis_keluhan` terpisah.
- Ditambah `tindak_lanjut` (`ringan`/`sedang`/`rujuk`) yang tidak ada di daftar
  awal, karena Posyandu perlu tahu apakah anak cukup diobati di tempat atau
  perlu dirujuk.
- Satu anak satu catatan per tanggal, dengan soft delete supaya tanggal yang
  sama bisa dipakai lagi setelah catatan lama dibatalkan.
- Layar catatan keluhan berdiri sendiri, tidak ditempelkan ke form penimbangan.
  Alasannya: keluhan sering muncul di hari yang sama dengan penimbangan, tapi
  tidak selalu. Catatan juga harus bisa diperbarui atau dibatalkan tanpa
  mencatat berat badan baru.

Rincian endpoint, constraint, dan cara rollback ada di
`docs/LAPORAN_MEDICAL_NOTES.md`.

---

## Opsi D - Grafik Tumbuh Kembang (SELESAI)

| | |
| :--- | :--- |
| Estimasi | 3 sampai 4 hari |
| Kesulitan | Sedang |
| Status | **Selesai 1 Oktober 2026** (Fase 1) - backend + mobile Ibu.
**Fase 2 selesai 2 Oktober 2026** - layar Kader + test tambahan |

Grafik BB dan TB dari waktu ke waktu. Ibu sudah bisa akses datanya sendiri di
aplikasi, tinggal divisualisasikan.

**Rancangan lengkapnya ada di `RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md`**, dan
rincian hasil pengerjaan ada di `LAPORAN_GRAFIK_TUMBUH_KEMBANG.md`.

- [x] Endpoint deret waktu satu anak - `GET /children/{id}/growth`
- [x] Pita acuan WHO BB/U (median dan -/+2 SD) di belakang grafik BB
- [x] Layar grafik di `grafik_tumbuh_screen.dart`, dipanggil dari tombol
      "Grafik Tumbuh" yang sebelumnya hanya menampilkan snackbar
- [x] Grafik untuk Kader - **Fase 2, 2 Oktober 2026**. Satu
      `GrowthChartView` dipakai Ibu dan Kader, dibedakan palet warna saja.
      Tombol ada di `AppBar` `detail_anak_screen.dart`.
- [x] Lima test tambahan bagian 9 rancangan - semuanya ditulis, bukan lagi
      daftar `[ ]`
- [ ] Grafik lingkar kepala - **ditunda**, tidak ada acuan WHO LK
- [ ] Pita TB/U dan status stunting - **ditunda**, butuh migration
      `who_hfa_standards` terpisah

**Tiga keputusan sudah dikunci 1 Oktober 2026** (detailnya di bagian 5
dokumen rancangannya):

1. **Pita WHO hanya untuk BB/U.** Database hanya punya `who_wfa_standards`.
   TB tetap digambar sebagai garis nilai, tanpa pita, dan layar menyatakan
   terus terang tidak ada acuan WHO untuk TB. Tabel `who_hfa_standards`,
   `z_score_hfa`, dan status stunting **tidak** dibuat sekarang.
2. **Endpoint baru, bukan memakai `/timeline`.** Timeline urutnya terbaru
   lebih dulu, dibatasi 50 tanggal per halaman, dan tidak punya
   `age_in_months` per kunjungan. Ketiganya membuat pita WHO tidak bisa
   disejajarkan dengan titik data.
3. **Layar untuk Ibu dulu**, sesuai `RANCANGAN.md` 3.2 A. Endpoint-nya di
   group `ibu,kader`, jadi menambah layar Kader nanti tidak mengubah kontrak.

**Tanpa migration baru dan tanpa dependency baru.** `fl_chart: ^1.2.0` sudah
jadi dependency langsung di `pubspec.yaml` sejak awal, hanya belum pernah
di-import. Feature ini tidak perlu izin menambah package. Fase 2 juga tidak
menambah apa pun.

**`uji-api.ps1` grup 8b sudah dijalankan** 2 Oktober 2026 terhadap server
hidup: 27 pemeriksaan HTTP lulus semua. Seluruh skrip sekarang **369 pemeriksaan
lulus, 0 gagal**, dua kali berturut-turut.

Menjalankannya sempat membongkar tiga cacat di skrip itu sendiri - semua sudah
diperbaiki:

1. Ekspektasi pesan 403 di grup 8b terlalu longgar dan salah; dikunci ke kalimat
   penuh yang sama dengan `API_CONTRACT.md`.
2. **Grup Buku Medis hanya lulus di tanggal 5 s.d. akhir bulan.** Skrip memakai
   tanggal "hari ini - 4 hari", sedangkan ringkasan keluhan default-nya bulan
   berjalan, jadi tanggal 3 Oktober membuat catatan uji jatuh di bulan lalu.
3. **Rekap imunisasi bulanan gagal kalau ada data lain.** Rekap mengagregasi
   seluruh Posyandu, jadi skrip tidak boleh menganggap angka HB0 mulai dari nol;
   sekarang skrip mengukur kenaikannya (+1 setelah disuntik, kembali ke semula
   setelah dibatalkan).

**Hasil verifikasi Fase 1:** backend 116 test / 621 assertion hijau, 20 test di
`GrowthChartTest.php`. Mobile 129 test hijau, 24 test baru. `route:list`
membuktikan 31 route `api/` (30 sebelum Opsi D, 31 sesudahnya) - jadi
perkiraan manual di rancangannya benar.

**Hasil verifikasi Fase 2:** backend 121 test / 1167 assertion hijau, 25 test
(`GrowthChartTest.php` +5). Mobile 135 test hijau, 6 test baru di
`grafik_tumbuh_kader_test.dart`. `route:list` tetap 31 route `api/` - Fase 2
tidak menambah endpoint.

**Dua kegagalan itu ada di luar ruang lingkup Opsi D** - keduanya bug skrip uji,
bukan bug aplikasi, dan sudah diperbaiki di atas tanpa menyentuh endpoint mana
pun. Endpoint dan kontrak tidak berubah sama sekali oleh perbaikan ini.

---

## Opsi E - Rekap dan Laporan (SELESAI)

| | |
| :--- | :--- |
| Estimasi | 3 sampai 5 hari |
| Kesulitan | Sedang |
| Status | **Selesai 29 September 2026** - backend + mobile + export CSV |

Vista cepat untuk kader: berapa anak yang imunisasinya belum lengkap bulan
ini. Ini paling bernilai secara operasional.

- [x] Rekap suntikan per bulan — `GET /kader/immunizations/recap`
- [x] Rekap bulanan untuk laporan ke BIDAN — bagian `coverage`
- [x] Filter "anak yang punya dosis terlambat" — `overdue_children`, sudah terurut
- [x] Layar rekap di aplikasi mobile — "Rekap Imunisasi" di dashboard Kader
- [x] Export CSV — `?format=csv` di endpoint yang sama, 29 September 2026
- [ ] Konfirmasi ke tim mobile apakah perlu `batch_number` di `activity`

**Nilai praktis:** kapan perlu menambah stok vaksin, kapan harus menyiapkan
kunjungan rumah. Saat ini informasi itu harus dibuka manual satu per satu.
Contoh: kalau ada rekap "3 anak punya suntikan terlambat bulan ini", kader
tahu harus menyiapkan vaksin lebih awal.

**Bentuk CSV sudah diputuskan:** query param `?format=csv` di endpoint yang
sama, bukan route baru. Alasannya satu sumber data - CSV dibangun dari array
yang sama persis dengan yang dikirim ke JSON, jadi angkanya tidak mungkin
berbeda. Route kedua akan berarti `ImmunizationRecapService` dipanggil dari
dua tempat dan harus dijaga sinkron dua kali.

Rinciannya ada di `docs/LAPORAN_REKAP_CSV.md`; kontrak lengkapnya di
`docs/API_CONTRACT.md` bagian `GET /kader/immunizations/recap`.

---

## Perbaikan Kader - Edit Data, Dashboard, dan Warna Status (SELESAI)

| | |
| :--- | :--- |
| Estimasi | 1 hari |
| Kesulitan | Mudah |
| Risiko | Rendah |
| Status | **Selesai - 3 Oktober 2026** |

Tiga perbaikan mobile yang ditemukan saat audit read-only sebelum mulai
mengerjakan fitur baru (Edukasi Kesehatan).

### 1. Form edit data anak untuk Kader

Ikon pensil di `detail_anak_screen.dart` sebelumnya hanya menampilkan SnackBar
"Fitur edit data anak segera hadir" — belum diimplementasikan. Backend sudah
siap menerima `PATCH /children/{id}` sejak lama, jadi ini murni gap mobile.

- `edit_child_screen.dart` — form lengkap: nama, jenis kelamin, tanggal lahir,
  berat lahir, panjang lahir, dan kondisi khusus (`medical_flags`)
- `KaderService.updateChild()` — tambah parameter `medical_flags`; `null`
  eksplisit sekarang benar-benar dikirim (sebelumnya di-drop oleh spread
  null-aware `?field`, sehingga field nullable tidak pernah bisa dikosongkan)
- `Child` model — tambah `birthWeight`/`birthHeight` (backend sudah mengirim,
  mobile belum membaca) + `copyWith()` dengan sentinel `_tidakDiubah` agar
  `null` bisa berarti "kosongkan"

### 2. Dashboard Kader

| Masalah | Perbaikan |
| :--- | :--- |
| `Posyandu Melati 01` dan `RT 01 / RW 10` hardcoded — tidak ada di DB mana pun | Diganti nama kader asli dari `GET /api/user` + kartu "Perlu Perhatian" (hitungan nyata dari status gizi) |
| Gagal memuat menampilkan "Tidak ada data anak ditemukan." | State error terpisah + tombol "Coba Lagai" |
| Pencarian hilang saat refresh | `TextEditingController` + filter dijalankan ulang setelah fetch |
| `ListView` `shrinkWrap` + `NeverScrollableScrollPhysics` membatalkan virtualisasi | Dua properti dihapus |
| Kartu statistik `Column` tanpa `Expanded` → overflow | `Expanded` + `ellipsis` |
| Row "Daftar Balita" + "Tambah Data" overflow di 360dp | `Expanded` pada teks judul |

### 3. Warna status gizi disatukan

Tiga pemetaan terpisah (`detail_anak_screen.dart`, `dashboard_ibu_screen.dart`,
`growth_chart_view.dart`) diganti satu fungsi `warnaStatusGizi()` di
`utils/status_gizi.dart`. Akibatnya `"Risiko Gizi Lebih"` tampil oranye tua di
semua layar — sebelumnya biru-abu di detail Kader tapi oranye di layar Ibu.

### Bonus: overflow pre-existing

Dua `Row` overflow di layar 360dp yang ditemukan oleh test baru:
- `kader_dashboard_screen.dart` — Row "Daftar Balita" + "Tambah Data"
- `login_screen.dart` — footer "Belum punya akun?" + "Daftar di sini"

### Verifikasi

- `flutter analyze` — bersih
- `flutter test` — 160 lulus (dari 137, +23 test baru)
- `php artisan test --filter=ChildTimelineTest` — 24 lulus (termasuk 3 test
  baru untuk kontrak "null = hapus" di backend)

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

1. ~~**Opsi A** (rapikan)~~ - selesai 27 September 2026
2. ~~**Opsi C** (catatan keluhan)~~ - selesai 27 September 2026
3. ~~**Opsi E** (rekap)~~ - selesai 29 September 2026, export CSV sudah ikut
4. ~~**Opsi B** (buku medis)~~ - selesai 29 September 2026, backend dan
   mobile
5. ~~**Opsi D** (grafik)~~ - selesai 1 Oktober 2026, backend dan mobile.
   Sisa yang sengaja ditunda: layar Kader (endpoint-nya sudah siap), pita
   TB/U, dan grafik lingkar kepala.
6. **Opsi F** (notifikasi) - kandidat berikutnya
7. **Opsi G** (AI) - terakhir, kalau masih relevan

> **Semua commit sudah masuk `main` dan sinkron dengan `origin/main`.**
> Blokir commit yang dulu ada di versi 27-29 September 2026 sudah beres;
> blocker itu dihapus pada 30 September 2026.

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
