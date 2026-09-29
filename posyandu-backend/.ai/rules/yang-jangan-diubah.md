---
paths:
  - app/**
  - config/**
  - database/migrations/**
  - database/factories/**
  - routes/api.php
  - docs/API_CONTRACT.md
  - docs/DATABASE_SCHEMA.md
---

# Yang tidak boleh diubah

Aturan ini berlaku untuk semua perubahan di backend. Semuanya berasal dari
keputusan yang sudah diambil dan dari bagian 7.5 `docs/RANCANGAN_BUKU_MEDIS.md`.

## Migration yang sudah pernah jalan tidak boleh diedit
Ubah hanya lewat migration baru. Mengedit migration lama membuat database yang
sudah ter-migrate berbeda dari database yang dibangun dari nol, dan kedua-duanya
tetap terlihat benar.

## Skema, route, dan AuthController tidak dirapikan ulang
Tugas baru menambah, tidak mengubah bentuk yang sudah ada. Kalau ada duplikat
route atau kode yang tidak rapi, itu dilaporkan dulu, bukan dirapikan sambil
bekerja pada fitur lain.

## UUID tetap primary key
Seluruh tabel memakai UUID. Jangan ubah ke auto-increment. Relasi baru di
migration wajib memakai `foreignUuid()`.

## `$fillable` bukan `$guarded = []`
Mass assignment selalu ditulis di `$fillable` per model. Kolom yang boleh
diisi klien ditentukan satu per satu.

## Bentuk envelope respons tidak berubah
Sukses: `success`, `message`, `data`. Error: `success`, `message`, dan
`errors` bila ada. Handler di `bootstrap/app.php` yang mengubah 401/403/404/
405/422/429 jadi JSON tidak boleh dilanggar - sebelum itu, 401 membalas
`{"message": "Unauthenticated."}` dan Flutter tidak bisa membaca `success`.

## Field yang sudah ada hanya boleh ditambah
Menambah field baru pada respons itu aman karena parser Flutter mengabaikan
field yang tidak dikenal. Mengganti nama, menghapus, atau mengubah tipe field
lama merusak klien yang sudah berjalan, termasuk `posyandu_mobile`.

## Z-score hanya boleh dihitung PostgreSQL
Logika `z_score_wfa` dan `status_gizi` hidup di function dan trigger
(`calculate_measurement_who_zscore`). Menulis ulang rumus itu di PHP
melanggar aturan pemisahan database dan aplikasi, dan biasanya menghasilkan
angka yang berbeda dari trigger.

## Tidak ada `dd()` atau `var_dump()` di controller
Blok yang risked gunakan `try-catch`, catat dengan `Log::error()`, lalu balas
500 dengan envelope standar. Isi exception tidak pernah dikirim ke klien.

## Istilah domain tidak diterjemahkan
`posyandu`, `kader`, `ibu`, `kms`, `mpasi`, `stunting`, `gizi kurang` tetap
seperti aslinya di nama variabel, kolom, dan route. Nama kolom berbahasa
Inggris hanya untuk hal teknis yang memang tidak punya padanan.

## NIK petugas tidak pernah ikut respons
`GET /petugas` tidak mengirim NIK. Jangan menambahkan NIK ke respons mana pun
karena "cuma produk sampingan" - kalau dibutuhkan, kirim field terpisah yang
disengaja.

## `kader_id` nullable dengan `ON DELETE SET NULL`
Menghapus akun kader tidak boleh menghapus riwayat kesehatan anak. Jangan
mengubahnya jadi cascade, dan jangan mengubahnya jadi non-nullable.

## Urutan master suntikan mengikuti jadwal, bukan abjad
`ImmunizationType::scopeOrderedForDosing()` memakai
`target_age_months ASC NULLS LAST, code, dose_number`. Baris `by_type` pada
rekap dan baris tabel CSV ikut urut itu. Mengembalikan urutan abjad
membatalkan kontrak yang sudah diuji.

## Test tidak boleh menyentuh database pengembangan
`tests/TestCase.php` menolak jalan kalau nama database bukan
`posyandu_test`, dan `RefreshDatabase` menghapus seluruh tabel di database
yang dipilih. Jangan menonaktifkan pemeriksaan itu.

## Test hanya jalan di PostgreSQL
Partial unique index, trigger plpgsql, dan CHECK constraint tidak ada di
SQLite. Menjalankan test di SQLite menghasilkan hijau tanpa menguji bagian
paling rawan salah.

## Kode yang sudah jalan tidak direfaktor tanpa diminta
Perubahan bersifat aditif. Refactor boleh kalau diminta atau kalau refactor
itu bagian dari pekerjaan yang diminta - bukan karena sedang membuka filenya.

## File dokumentasi hanya dibuat kalau diminta
Dokumen yang sudah ada boleh diperbarui sebagai bagian dari pekerjaan yang
sedang berjalan. Dokumen baru hanya kalau diminta.

## Dependency tidak ditambah tanpa persetujuan
Kalau sebuah fitur bisa dikerjakan dengan paket yang sudah ada, pakai yang
sudah ada.
