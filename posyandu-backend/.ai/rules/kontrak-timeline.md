---
paths:
  - app/Services/ChildTimelineService.php
  - app/Http/Controllers/Api/ChildController.php
  - routes/api.php
  - tests/Feature/ChildTimelineTest.php
---

# Kontrak endpoint timeline (Opsi B - Buku Medis Digital)

## Sumber kebenaran ada di dokumen, bukan di kode
Spesifikasi lengkap ada di `docs/RANCANGAN_BUKU_MEDIS.md`. Baca bagian 5
(keputusan yang sudah ditutup), 7.1 sampai 7.5 (rute, bentuk respons, aturan,
inventaris kompatibilitas), dan 9 (rencana pengujian) sebelum menulis kode
apapun di jalur yang tercantum di `paths` file ini.

Kalau implementasi merasa perlu menyimpang dari dokumen itu, dokumennya yang
diubah lebih dulu. Penyimpangan yang tidak tertulis di dokumen dianggap bug,
bukan variasi yang bisa diterima.

## Tujuh aturan di 7.3 tidak boleh dilanggar
Urutan tanggal, sembunyikan baris soft-deleted, keluhan tetap tampil walau
penimbangannya dibatalkan, tidak ada penghitungan ulang, satu tanggal satu
entri, tanpa data tetap 200, dan `limit` menghitung tanggal bukan baris.

Setiap aturan punya satu nama test di bagian 7.3. Test dengan nama itu wajib
ada. Test boleh ditambah, tapi tidak boleh di-rename atau dihapus tanpa
memperbarui tabel di 7.3 - kalau tidak, pemetaan itu berbohong.

## Bentuk respons tidak boleh berubah sendiri
`data` berisi tepat tiga kunci: `child`, `entries`, `meta`. Di dalam `entries`
ada `date` (`Y-m-d`) plus `measurement`, `immunizations`, `medical_note`, dan
tiga kunci itu boleh `null`. `meta` berisi `has_more` dan `next_before`.
Menambah field baru itu boleh dan tidak merusak klien; mengganti nama,
menghapus, atau mengubah tipe field yang ada tidak boleh.

## Tidak ada penghitungan ulang di server maupun klien
Z-score, `status_gizi`, dan status imunisasi dibaca apa adanya dari database.
Jangan mengimplementasikan rumus z-score di PHP dan jangan menghitung ulang
nilai yang sudah diisi trigger. Kalau nilai di respons terasa salah,
perbaikannya di sisi data atau trigger, bukan di endpoint baca.

## `limit` menghitung tanggal, bukan jumlah baris
Satu tanggal dengan tiga suntikan tetap satu entri. Service harus mengambil
daftar tanggal dulu (satu query `UNION` atas tiga kolom tanggal), memotongnya
sesuai `limit`, lalu mengisi isinya dalam rentang tanggal tersebut. Mengambil
`limit` baris per tabel lalu menggabungkannya menghasilkan timeline yang
terpotong di tengah satu kunjungan.

## Cursor `before` hanya boleh menolak format yang salah
Validasi `before` adalah `date_format:Y-m-d`, **tanpa** `before_or_equal:today`.
Riwayat harus tetap terbaca setelah tanggal lewat. Nilai halaman berikutnya
diambil dari `meta.next_before`; di halaman terakhir `next_before` bernilai
`null`, bukan string kosong.

## Tanpa data tetap 200
Anak yang belum pernah ditimbang, belum disuntik, dan tidak punya catatan
keluhan menghasilkan `entries: []` dengan status 200. `404` hanya untuk anak
yang memang tidak ada.

## Soft delete harus difilter eksplisit di query mentah
`measurements`, `immunization_records`, dan `medical_notes` semuanya punya
`deleted_at`. Query lewat Eloquent memakai global scope, tapi query lewat
`DB::query()` atau `DB::select()` **tidak**, jadi `deleted_at IS NULL` harus
ditulis sendiri di setiap cabang. Lupa menulisnya berarti baris yang sudah
dibatalkan kader muncul lagi di timeline.

## Otorisasi mengikuti `GET /children/{id}`, jangan buat aturan sendiri
Route timeline wajib didaftarkan di group yang sama dengan
`GET /children/{id}` (`RoleCheck` ibu + kader), bukan di prefix `/kader/`.
Ibu hanya boleh membuka anaknya sendiri, kader boleh semua. Pemeriksaan
kepemilikan dan pengecekan `Str::isUuid()` sudah ada di
`ChildController::findChildForUser()` - pakai helper itu, jangan salin
versinya sendiri ke tempat lain.

## Satu controller, bukan dua
Method timeline tinggal di `ChildController`. Query, pengelompokan, dan
pembentukannya masuk ke `ChildTimelineService`. Controller baru yang
menyalin logika otorisasi dari `ChildController` adalah duplikasi yang pasti
kelak berbeda satu sama lain.

## Jumlah query harus tetap
Empat query: satu untuk daftar tanggal, tiga untuk isi jendela. Kalau
perubahan membuat jumlah query tumbuh seiring jumlah tanggal, itu salah.

## Route yang ada sekarang tidak boleh hilang atau berubah
Ada 29 route API sebelum Opsi B, dan setelah timeline ada 30. Jangan
menghapus, mengganti nama, atau memindahkan route lama. `?format=csv` tetap
query param pada route rekap, bukan route baru.

## Penanda kondisi khusus hanya boleh ditulis Kader
`medical_flags` masuk lewat `PATCH /children/{id}` yang sudah ada, bukan
endpoint baru. Ibu yang mengirim field itu harus mendapat penolakan yang
terbaca, bukan diam-diam diabaikan. Ibu tetap boleh **membaca** penanda
anaknya sendiri.
