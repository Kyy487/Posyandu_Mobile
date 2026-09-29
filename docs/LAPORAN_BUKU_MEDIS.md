# Laporan Opsi B — Buku Medis Digital (Fase 1: Backend)

**Tanggal:** 29 September 2026
**Spesifikasi acuan:** `docs/RANCANGAN_BUKU_MEDIS.md`
**Status:** Backend selesai, mobile belum dikerjakan (fase berikutnya)

---

## 1. Apa yang Dibuat

| File | Isi |
| :--- | :--- |
| `database/migrations/2026_09_29_010000_add_medical_flags_to_children_table.php` | Kolom `children.medical_flags` (`text`, nullable) |
| `app/Services/ChildTimelineService.php` | Penyusun timeline: 4 query, pengelompokan per tanggal |
| `app/Http/Controllers/Api/ChildController.php` | Method `timeline()` + validasi tulis `medical_flags` |
| `routes/api.php` | `GET /children/{id}/timeline` |
| `tests/Feature/ChildTimelineTest.php` | 21 test, memetakan seluruh aturan di bagian 7.3 |

Perubahan pada file yang sudah ada: `Child::$fillable` tambah `medical_flags`,
dan `ChildController@update` menambah validasi plus penolakan bagi Ibu. Tidak ada
route lama yang berubah nama, pindah, atau hilang — `php artisan route:list`
tetap mengembalikan 30 route `api/` (29 + 1).

---

## 2. Dua Endpoint

### `GET /children/{id}/timeline`

Seluruh riwayat satu anak dalam satu layar, dikelompokkan per tanggal kunjungan.

| Parameter | Default | Validasi |
| :--- | :--- | :--- |
| `limit` | `50` | `integer`, `min:1`, `max:200` — menghitung **tanggal**, bukan baris |
| `before` | - | `date_format:Y-m-d` — tanpa `before_or_equal:today` |

`data` berisi tepat tiga kunci: `child`, `entries`, `meta`. Halaman berikutnya
diambil dengan mengirim `before` = `meta.next_before`; di halaman terakhir
`next_before` bernilai `null`.

### `PATCH /children/{id}` dengan `medical_flags`

Tidak ada endpoint CRUD baru. Penanda kondisi khusus ditulis lewat endpoint yang
sudah ada, dan **hanya Kader** yang boleh mengirim field itu. Ibu tetap boleh
membaca penanda anaknya sendiri.

Penolakan bagi Ibu sengaja terlihat (`403`), bukan diam-diam diabaikan: jawaban
200 padahal penandanya tidak tersimpan lebih berbahaya daripada error, karena
kader akan mengira sudah tercatat.

---

## 3. Tiga Hal yang Paling Mudah Salah, dan Bagaimana Dicegah

### `limit` menghitung tanggal, bukan baris

Kalau service mengambil `limit` baris per tabel lalu menggabungkannya, satu
kunjungan dengan tiga suntikan memakan tiga slot dan timeline terpotong di tengah
satu kunjungan. Solusinya: satu query `UNION` mengambil daftar tanggal dulu,
memotongnya sesuai `limit`, lalu mengisi isinya dalam rentang tanggal itu.

`UNION`, bukan `UNION ALL` — tanpa itu satu tanggal yang punya penimbangan dan
suntikan akan muncul dua kali dan menggeser batas halaman.

Dijaga oleh `limit_menghitung_tanggal_bukan_baris`.

### Baris yang dibatalkan tidak boleh muncul lagi

Ketiga tabel punya `deleted_at`. Dua query timeline memakai Eloquent, jadi
soft delete terfilter otomatis. Satu query tanggal memakai query builder mentah
karena tiga kolom dengan nama berbeda harus disatukan — dan di situ
`deleted_at IS NULL` ditulis eksplisit di tiap cabang. Kalau lupa di satu saja,
baris yang sudah dibatalkan kader muncul lagi sebagai tanggal kunjungan.

Dijaga oleh `baris_yang_dibatalkan_tidak_muncul_di_timeline`.

### Penimbangan tanpa kader tidak boleh hilang

`kader_id` nullable dengan `ON DELETE SET NULL`, jadi `join` biasa ke `users`
akan diam-diam menghilangkan riwayat anak yang kadernya sudah dihapus — persis
data yang paling tidak boleh hilang. Karena itu query penimbangan memakai
`leftJoin`.

Dijaga oleh `penimbangan_tanpa_kader_tetap_tampil`.

---

## 4. Yang Tidak Dihitung Ulang

`z_score_wfa`, `age_in_months`, dan `status_gizi` dibaca apa adanya dari
database; semuanya dihitung trigger PostgreSQL. Server dan mobile sama-sama
tidak menghitung. Test `nilai_z_score_dibaca_dari_database_tanpa_dihitung_ulang`
membandingkan nilai respons dengan nilai yang benar-benar ada di tabel, jadi
server yang diam-diam menghitung ulang dengan rumus sendiri akan gagal di sana.

---

## 5. Jumlah Query

Service memakai **empat query**: satu `UNION` untuk daftar tanggal, tiga untuk
isi jendela. Jumlahnya tidak bergantung pada jumlah tanggal kunjungan — anak
dengan 10 kunjungan dan anak dengan 1 membutuhkan query yang sama. Diuji dengan
menghitung query langsung, bukan menghitung query seluruh request (autentikasi
memiliki query sendiri yang tidak berkaitan dengan timeline).

---

## 6. Verifikasi

| Pemeriksaan | Hasil |
| :--- | :--- |
| `php artisan test` | 96 test / 364 assertion hijau (21 test baru) |
| `vendor/bin/pint --dirty` | Lulus, tanpa perubahan |
| `php artisan route:list` | 30 route `api/` |
| `periksa-teks.ps1` | Bersih |

---

## 7. Belum Dikerjakan

Mobile adalah fase berikutnya dan **belum disentuh**: model timeline, service,
kemudian perubahan `detail_anak_screen.dart`. Rawatannya sudah ada di
`docs/RANCANGAN_BUKU_MEDIS.md` bagian 8.2 — termasuk catatan bahwa layar itu
tidak punya pull-to-refresh, jadi pemuatan ulang memakai tombol refresh yang
sudah ada di baris "Penimbangan Terakhir".

Grup `uji-api.ps1` untuk aturan 1–7 juga belum ditulis.
