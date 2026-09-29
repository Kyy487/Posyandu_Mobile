# Laporan Pengerjaan Blokir 4 — Export CSV Rekap Imunisasi

**Tanggal:** 29 September 2026
**Status:** Selesai — backend + dokumentasi; test suite 69/69, regresi API
338/338
**Branch:** `main` (belum commit)

Ini butir terakhir Opsi E. Endpoint rekap dan layarnya sudah jadi sejak
28 September; yang belum ada adalah bentuk file untuk dipegang BIDAN.

---

## Ringkasan Apa Yang Dibangun

`GET /api/kader/immunizations/recap?month=YYYY-MM&format=csv`

Satu route tambahan dijawab dari route yang sudah ada. Tanpa `format`, responsnya
JSON seperti sebelumnya — byte per byte, karena `uji-api.ps1` dan test bandingkan
keduanya.

Berkasnya satu, bukan dua, dan berisi tiga bagian berurutan sesuai urutan di
layar: aktivitas suntikan (stok vaksin), kelengkapan (angka laporan), daftar anak
terlambat (yang dikunjungi).

---

## Keputusan yang Diambil (Dikonfirmasi User)

| Keputusan | Pilihan | Alasan |
|-----------|---------|--------|
| **Bentuk endpoint** | `?format=csv` di endpoint yang sama | Satu sumber data. CSV dibangun dari array yang sama persis dengan JSON, jadi angkanya tidak mungkin berbeda. Route kedua berarti `ImmunizationRecapService` dipanggil dari dua tempat dan harus dijaga sinkron dua kali |
| **Isi file** | Satu file, tiga bagian | Kader mengpegang satu berkas untuk laporan ke BIDAN sekaligus rencana kunjungan. Dua file berarti dia harus ingat mana yang mana |
| **Sisi mobile** | Tidak dikerjakan di blokir ini | Butuh `path_provider` + `share_plus`, itu penambahan dependency yang belum disetujui |

---

## File Yang Ditambah / Diubah

### Baru
| File | Fungsi |
|------|--------|
| `app/Services/ImmunizationRecapCsv.php` | Membangun isi CSV dan nama filenya dari array rekap |
| `tests/Feature/ImmunizationRecapCsvTest.php` | 19 test: kontrak header, kesamaan angka dengan JSON, dan ketahanan file |
| `docs/LAPORAN_REKAP_CSV.md` | File ini |

### Diubah
| File | Perubahan |
|------|-----------|
| `app/Http/Controllers/Api/ImmunizationController.php` | Validasi `format` (`in:json,csv`) + cabang CSV setelah `recapForMonth()` |
| `uji-api.ps1` | Grup 9g baru, 24 pemeriksaan; fungsi `Req` sekarang mengembalikan `Headers` |
| `docs/API_CONTRACT.md` | Parameter `format`, tabel `422` baru, bagian `format=csv` lengkap dengan tiga aturan |
| `docs/RENCANA_SELANJUTNYA.md` | Opsi E ditandai selesai sepenuhnya |

---

## YangIDSesuaidarengan Rekap yang Sudah Ada

**1. CSV tidak pernah jadi sumber data kedua.** `ImmunizationRecapCsv::render()`
menerima array hasil `ImmunizationRecapService::recapForMonth()` apa adanya.
Tidak ada query, tidak ada hitung ulang, tidak ada bentuk ulang angka. Kalau
`evaluate()` berubah, JSON dan CSV berubah bersama di request yang sama.

Ini yang jadi test utama: `angka_csv_identik_dengan_json` mengambil kedua
respons untuk bulan yang sama dan mencocokkan setiap angka.

**2. Baris `count: 0` tidak disembunyikan.** Layar mobile menyembunyikannya di
balik toggle — itu pilihan tampilan yang sah. Berkasnya tidak punya toggle, dan
BIDAN yang mengarsipkan laporan tidak akan pernah menekan apa pun. "Tidak ada
suntikan" dan "tidak sempat dicatat" harus bisa dibedakan dari berkasnya sendiri.

**3. Satu anak = satu baris.** Dosis telat milik satu anak digabung ke satu sel
dengan pemisah `; `. Kalau satu baris per dosis, nama anak muncul berulang di
daftar kunjungan dan daftar itu jadi tidak bisa dipakai.

**4. `sisa_bulan` paling negatif = kolom "Terlambat (bulan)".** Angka yang sama
dengan dasar urutan di server, jadi file dan layar tidak bisa berbeda urutan.
Dosis tanpa `target_age_months` punya `sisa_bulan` null dan tidak ikut dihitung.
Kalau semua null, kolom dikosongkan — bukan diisi `0`, yang akan terbaca oleh
kader sebagai "tepat waktu".

---

## Format File: Untuk Excel di Windows, Bukan Untuk Mesin

Ini keputusan yang terlihat sepele tapi menentukan apakah berkasnya berguna.

| Keputusan | Kenapa |
|-----------|--------|
| **BOM UTF-8 di depan file** | Tanpa BOM, Excel di Windows memaksa file ke ANSI. Isi file tetap UTF-8 yang benar, jadi tidak ada test lain yang menangkapnya — yang rusak baru terjadi di aplikasi yang membukanya, tepat saat BIDAN membacanya |
| **Pemisah baris `CRLF`** | Tabel tidak berantakan di Excel Windows |
| **Tanda kutip tunggal untuk `=`, `+`, `-`, `@`** | `children.name` hanya divalidasi `string\|max:255`, jadi nama anak bisa diawali `=`. Tanpa awakean ini Excel mengeksekusinya sebagai formula begitu file dibuka. Sel angka tidak diberi awakean: `-2` yang berarti "terlambat 2 bulan" bukan formula |
| **Tanggal ISO** | Nama bulan bahasa Indonesia sengaja tidak diduplikasi ke backend. Satu daftar sudah ada di `utils/month_label.dart`; menyalinnya berarti layar dan berkas bisa menampilkan "September" dan "Sep" untuk bulan yang sama |
| **Baris baru di dalam sel diratakan** | Sel yang ber-newline membuat file gagal dibaca pembaca yang memecah per baris, termasuk saat kader menyalin isi laporan ke chat |
| **Kutipan RFC 4180** | Koma di dalam nama anak harus diapit tanda kutip, kalau tidak semua kolom setelahnya bergeser. Nama anak ada di kolom kedua, jadi satu koma saja sudah cukup membuat kolom "Tanggal Lahir" berisi isi yang salah |

### Bentuk berkasnya

```
Rekap Imunisasi - Posyandu Desa Sukamaju
Bulan: 2026-09
Dihitung sampai: 2026-09-30
Dicetak: 2026-09-29 14:05 WIB

AKTIVITAS SUNTIKAN
Kode,Dosis,Nama vaksin,Jumlah Disuntik
BCG,1,BCG,3
HB,1,Hepatitis B,4
MR,1,Campak Rubella,5
TOTAL,,,12

Anak yang disuntik bulan ini,9

KELENGKAPAAN IMUNISASI (pada akhir bulan)
Keterangan,Jumlah Anak
Total anak,25
Imunisasi lengkap,12
Imunisasi belum lengkap,13
Ada dosis terlambat,4
Tidak dihitung (arsip / pindah),2

DAFTAR ANAK TERLAMBAT
No,Nama,Tanggal Lahir,Usia (bulan),Jumlah Dosis Terlambat,Dosis Terlambat,Terlambat (bulan)
1,Budi Santoso,2025-10-15,11,1,Campak Rubella,-9
```

Baris `Dicetak` adalah satu-satunya isi file yang berubah kalau berkas yang sama
diunduh dua kali. Angkanya tetap sama, itu yang dijamin `filter.reference_date`.
Cap waktu tetap berguna untuk arsip: BIDAN perlu tahu berkas mana yang terbaru
kalau dua berkas ada di satu folder.

---

## Verifikasi

| Cek | Hasil |
|-----|-------|
| `php artisan make:class` / `make:test` | beide file dibuat lewat artisan |
| Pint | `vendor/bin/pint --dirty --format agent` → `fixed` 1 file (`single_quote`) |
| Feature test baru | `tests/Feature/ImmunizationRecapCsvTest.php` 19 test / 107 assertions |
| Test suite penuh | 69 test / 284 assertions (dari 50 test sebelumnya) |
| Regresi API (`uji-api.ps1`) | **338/338** lulus (314 + 24 pemeriksaan grup 9g) |
| Periksa teks otomatis | `periksa-teks.ps1` → BERSIH, 352 file |
| Sisa data uji | user 7, anak 3, suntikan 2 — sama seperti sebelum skrip dijalankan |

### Apa Yang Ditambahkan ke `uji-api.ps1` (Grup 9g)

24 pemeriksaan lewat HTTP nyata ke server yang sedang jalan:

- Ibu unduh CSV → `403` (bocornya lewat unduhan sama saja membocorkan lewat JSON)
- `format=excel` → `422` dengan error di field `format`
- `format=csv` + `month=2026-13` → `422`, dan badan tetap JSON tanpa isi laporan
- `Content-Type: text/csv; charset=UTF-8`
- `Content-Disposition: attachment; filename="rekap-imunisasi-2026-09.csv"`
- Tiga bagian ada: `AKTIVITAS SUNTIKAN`, `KELENGKAPAAN IMUNISASI`, `DAFTAR ANAK TERLAMBAT`
- `TOTAL`, `Total anak`, `Ada dosis terlambat`, `Tidak dihitung (arsip / pindah)` sama dengan JSON
- Semua 16 baris master ada di file, termasuk yang `count`-nya `0`
- Jumlah baris anak di tabel = `overdue_children` di JSON
- Tanpa `format` = `format=json`, byte per byte
- Bulan kosong (`2019-01`) → `200` dengan file utuh dan baris penanda

`Req` di `uji-api.ps1` sekarang mengembalikan `Headers` juga. Fungsi lama tidak
berubah perilakunya, cuma satu kunci tambahan.

### Yang Tidak Bisa Dicek Lewat `uji-api.ps1`

**BOM UTF-8 dan pemisah `CRLF` sengaja tidak diperiksa di skrip.** `Invoke-WebRequest`
mendecode body dan membuang BOM sebelum skrip menyentuhnya, jadi yang tersisa
hanyalah teks UTF-8 yang kelihatan benar. Kalau BOM hilang, 338 pemeriksaan ini
tetap lulus. Dua hal itu diuji di feature test yang membaca respons mentah.

---

## Bug Yang Ditemukan Saat Menulis Test

Bukan bug produksi — ekspektasi test yang salah, tapi tiga di antaranya membuka
pertanyaan nyata:

**1. Anak "lengkap" saya sebenarnya tidak lengkap.** Helper test awal hanya
membuat baris anaknya tanpa record suntikan. Usia 7 bulan tanpa HB dan BCG
justru **terlambat**, bukan lengkap. Testnya gagal dan perbaikannya adalah
membuat helper-nya benar-benar menyuntikkan HB dan BCG.

**2. Unique constraint `(child_id, immunization_type_id)` menahan cara test
menulis data.** Dua test gagal dengan `23505` karena satu anak dibuat punya dua
record untuk dosis yang sama. Ini constraint yang benar di produksi - satu anak
satu dosis. Test harus menyesuaikan, bukan production code-nya.

**3. Nama anak ter-arsip tidak muncul di file sama sekali.** Ekspektasi awal
saya: nama anak yang ter-archive muncul di suatu tempat supaya bisa
diaudit. Kenyataannya tidak — `ImmunizationRecapService` hanya melaporkan
`excluded_archived` sebagai **angka**, dan anak yang ter-archive tidak masuk
`overdue_children`.

Setelah ditinjau, itu perilaku yang benar dan sengaja: berkasnya untuk
memastikan siapa yang perlu dikunjungi, bukan untuk mengaudit siapa yang pindah.
Yang berubah cuma testnya - nama anak ter-arsip tidak boleh muncul di file mana
pun. Kalau BIDAN perlu daftar anak yang pindah, itu laporan terpisah, bukan
kolom tambahan di rekap ini.

---

## Yang Masih Butuh Dilakukan

1. **Commit** blokir 1–4 termasuk file ini.
2. **Tombol export di mobile** - ditunda. Butuh `path_provider` (tulis berkas)
   dan `share_plus` (buka share sheet), keduanya dependency baru. Perlu
   persetujuan dulu sebelum dipasang.
3. **Konfirmasi ke tim mobile** - apakah `activity` perlu `batch_number` untuk
   tracking stok? Bukan dari blokir ini, masih terbuka sejak 28 September.
4. **Urutan dosis sesuai kronologi** - `scopeOrderedForDosing()` masih sorting
   berdasarkan `code` (`BCG` < `HB` < `MR`), bukan urutan suntikan. Sekarang
   urutannya terlihat di CSV dan di layar checklist, jadi gangguannya lebih
   mudah dilihat. Di luar cakupan blokir ini, tapi belum ada yang memperbaikinya.

---

## Catatan Untuk Agent Berikutnya

- `ImmunizationRecapCsv` sengaja **tidak** melakukan query. Kalau ada kolom baru
  yang perlu di file, tambahkan di `ImmunizationRecapService` dulu supaya muncul
  di JSON dan CSV sekaligus. Menambahkannya hanya di CSV berarti dua laporan
  dengan angka berbeda.
- `render()` menerima array, bukan bulan. Jangan diubah jadi menerima bulan dan
  memanggil service sendiri — itu yang membuat controller dan service bisa
  menghitung dua kali.
- Awakan anti-formula ada di `teks()`, bukan di `angka()`. Kalau nanti ada kolom
  teks baru, pakainya `teks()` dan angka baru pakai `angka()`. Menaruh
  penjaganya di `row()` akan merusak angka negatif.
- **Jangan simpulkan "338 pemeriksaan lulus berarti CSV-nya benar."** Pemeriksaan
  `uji-api.ps1` berjalan lewat `Invoke-WebRequest` yang sudah membuang BOM.
  Yang menangkap masalah level file hanya feature test.
- Test `ImmunizationRecapCsvTest` sengaja mengunci urutan `BCG, HB, MR` yang
  sekarang. Itu urutan `code`, bukan urutan suntikan - dan itu warisan Opsi A
  yang masih tercatat. Kalau nanti diperbaiki, test ini harus ikut diperbarui
  pada saat yang sama, bukan diam-diam.
