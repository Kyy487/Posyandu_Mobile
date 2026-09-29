---
paths:
  - tests/**
  - database/factories/**
---

# Cara menguji di proyek ini

## Jebakan tanggal lahir acak
`ChildFactory` mengisi `date_of_birth` acak antara 5 tahun lalu dan 1 bulan
lalu. Test yang memakai tanggal hardcode tapi membuat anak lewat
`Child::factory()` polos bisa gagal secara acak sekitar 12 persen per jalannya,
karena trigger menolak penimbangan sebelum tanggal lahir. Gejalanya test hijau di
satu kali dan merah di kali berikutnya.

Untuk test dengan tanggal hardcode, anak **wajib** dibuat lewat helper yang
menetapkan `date_of_birth` pasti, misalnya
`Child::factory()->create(['date_of_birth' => '2024-01-01'])`. Helpers seperti
ini sudah ada di beberapa test; buat yang baru kalau memang perlu, tapi jangan
pernah jatuh ke `Child::factory()->create()` tanpa `date_of_birth`.

## Test hanya jalan di PostgreSQL
`tests/TestCase.php` menolak jalan kalau koneksi bukan `pgsql` atau nama
database bukan `posyandu_test`. Jangan dikompromikan dengan memakai SQLite,
karena partial unique index, trigger plpgsql, dan CHECK constraint tidak ada
di sana.

## `RefreshDatabase` bukan `DatabaseTransactions`
Data test boleh dihapus tanpa syarat. Yang tidak boleh adalah test yang
menyentuh database pengembangan - itu dicegah di `TestCase`, dan jangan
dinonaktifkan.

## Jalankan test paling sempit lebih dulu
Setelah menambah atau mengubah test, jalankan file atau filter itu saja.
`php artisan test --compact tests/Feature/ChildTimelineTest.php`, atau
`--filter=nama_test`. Baru jalankan seluruh suite sebelum menyatakan selesai,
supaya regresi di tempat lain ketahuan.

## Nama test menjelaskan perilaku, bukan nama method
Nama test ditulis dalam Bahasa Indonesia dan berbentuk kalimat yang gagal kalau
behavioranya salah, misalnya
`keluhan_tetap_muncul_walau_penimbangan_tertaut_dibatalkan`. Jangan menamai
test dengan `test1`, `testEndpoint`, atau `works`.

## Satu test satu perilaku
Kalau nama test-nya memuat "dan", itu dua test. Test yang gagal harus
menunjuk langsung ke aturan yang dilanggar.

## Fixture pakai factory state, bukan array isi manual
Factory sudah punya state seperti `untukAnak()`, `olehKader()`,
`padaTanggal()`, dan `dibatalkan()`. Pakai state itu. Kalau sebuah skenario
butuh kombinasi yang belum ada, tambahkan state-nya ke factory - jangan
menuliskan seluruh isi baris manual di dalam test, karena test selesai dan
logic-nya tercecer di banyak tempat.

## Asersi pada kontrak yang terlihat dari luar
Asersi isi respons HTTP (kunci, tipe, nilai), bukan query SQL atau jumlah
query. Exception-nya hanya kalau memang menguji internal - misalnya untuk
memastikan soft delete tidak menghapus baris secara fisik.

## Pint dijalankan lewat path penuh
`php` dan `composer` tidak ada di `PATH` di mesin ini, jadi
`vendor/bin/pint.bat` gagal dengan pesan `php is not recognized`. Jalankan
`vendor/bin/pint --dirty` dengan PHP secara langsung, misalnya
`& "C:\laragon\bin\php\php-8.4.25-Win32-vs17-x64\php.exe" vendor/bin/pint --dirty`.
Flutter ada di `C:\src\flutter\bin\flutter.bat`.
