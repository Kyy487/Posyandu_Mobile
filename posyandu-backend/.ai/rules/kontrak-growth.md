---
paths:
  - app/Services/GrowthChartService.php
  - app/Http/Controllers/Api/ChildController.php
  - routes/api.php
  - tests/Feature/GrowthChartTest.php
---

# Kontrak endpoint grafik tumbuh kembang (Opsi D)

## Sumber kebenaran ada di dokumen, bukan di kode
Spesifikasi lengkap ada di `docs/RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md`. Baca
bagian 5 (keputusan yang sudah ditutup), 7.1 sampai 7.6 (rute, bentuk
respons, aturan, kompatibilitas, dependency), dan 9 (rencana pengujian)
sebelum menulis kode apapun di jalur yang tercantum di `paths` file ini.

Kalau implementasi merasa perlu menyimpang dari dokumen itu, dokumennya yang
diubah lebih dulu. Penyimpangan yang tidak tertulis di dokumen dianggap bug,
bukan variasi yang bisa diterima.

## Sembilan belas aturan di 7.3 tidak boleh dilanggar
Urut naik, tanpa penghitungan ulang, sembunyikan baris soft-deleted, tanpa
data tetap 200, z-score null tetap null, penimbangan tanpa kader tetap tampil,
pita hanya untuk BB/U, pita ikut gender anak, pita dikirim walau points
kosong, pita menutup 0 sampai 60 bulan, tanpa filter tanggal, jumlah query
tetap dua, Ibu tidak boleh membuka anak orang, Ibu boleh membuka anaknya
sendiri, kader boleh semua anak, id bukan UUID membalas 404, `data` berisi
tepat tiga kunci, satu titik per tanggal, dan `medical_flags` terbaca apa
adanya.

Setiap aturan punya satu nama test di bagian 7.3. Test dengan nama itu wajib
ada. Test boleh ditambah, tapi tidak boleh di-rename atau dihapus tanpa
memperbarui tabel di 7.3 - kalau tidak, pemetaan itu berbohong.

## Bentuk respons tidak boleh berubah sendiri
`data` berisi tepat tiga kunci: `child`, `series`, `who_reference`. Di dalam
`series` ada `unit`, `order` (selalu `"asc"`), dan `points`. Di dalam
`points` ada `date`, `age_in_months`, `weight_kg`, `height_cm`,
`head_circumference_cm`, `z_score_wfa`, `status_gizi`. Di dalam
`who_reference` ada `metric` (selalu `"weight_for_age"`), `source`, `gender`,
`age_range`, dan `points`.

Menambah field baru itu boleh dan tidak merusak klien; mengganti nama,
menghapus, atau mengubah tipe field yang ada tidak boleh. `z_score_wfa` dan
`status_gizi` harus tetap bisa `null` - itu berbeda dari "gizi baik".

## Tidak ada penghitungan ulang, di server maupun klien
`age_in_months`, `z_score_wfa`, dan `status_gizi` dibaca apa adanya dari
database. Jangan mengimplementasikan rumus z-score di PHP dan jangan
menghitung ulang umur dari `date_of_birth` di Dart - angka server dihitung
trigger pada saat penimbangan dicatat, dan hitungan kedua di klien bisa
meleset satu bulan.

## Pita WHO dibaca dari database, bukan dihitung dari data anak
`who_reference` dibaca dari `who_wfa_standards` yang sudah ada. `lower_kg` dan
`upper_kg` boleh dihitung dari `median_kg` dan `sd_kg` **di SQL**, karena itu
konstanta referensi WHO, bukan data anak. `z_score_wfa` anak sendiri tidak
pernah diturunkan dari pita: nilainya tetap dibaca dari kolom yang diisi
trigger.

Jangan menulis rumus z-score atau median WHO di PHP maupun Dart. Buka
`database/migrations/2026_09_26_010000_create_who_wfa_standards_and_fix_zscore_trigger.php`
dan baca konstantanya kalau angka referensinya perlu diubah.

## Pita hanya untuk BB/U. Jangan menambah TB/U
`who_reference.metric` adalah `weight_for_age`. Database tidak punya tabel
TB/U, jadi `who_reference` **tidak boleh** memuat pita tinggi badan, dan
`measurements` tidak boleh mendapat kolom `z_score_hfa` atau status stunting.
TB tetap dikirim di `points[].height_cm` sebagai nilai mentah, dan itu
memang tidak punya pita - itu keputusan, bukan kekurangan.

Kalau suatu saat TB/U dibutuhkan, itu perubahan dokumen bagian 5.1 lebih
dulu, lalu migration terpisah. Jangan menambah kolomnya sambil mengimplementasikan
grafik.

## `leftJoin` ke `users`, bukan `join`
`kader_id` bisa `null` karena `ON DELETE SET NULL`. Query penimbangan wajib
`leftJoin('users as kader', ...)`; `join` biasa akan diam-diam menghilangkan
riwayat anak yang kadernya sudah dihapus - persis data yang paling tidak
boleh hilang. `ChildTimelineService` sudah memakai `leftJoin` dengan alasan
yang sama; ikuti itu.

## Urutan titik adalah responsibilities server
`points` selalu urut naik dari tanggal terlama. Klien tidak boleh mengurutkan
ulang, dan `series.order` ada supaya ia tidak perlu menebak. Dua titik boleh
punya `age_in_months` sama - penimbangan 20 hari sekitaran bisa dua-duanya di
bulan ke-30 - dan itu bukan bug.

## Tanpa pagination, dan itu keputusan
Endpoint ini sengaja tidak punya query string: tidak ada `limit`, `before`,
`from`, maupun `to`. Partial unique index `measurements_child_date_unique`
membatasi satu baris per tanggal, jadi anak 0-60 bulan paling banyak 61 titik
dan skenario terburuk yang realistis sekitar 260 titik.

Jangan menambahkan pagination "supaya aman". Kalau nanti ada anak dengan
ribuan titik, itu masalah memasukkan data. Yang tetap wajib: seluruh riwayat
harus bisa dibaca, dan grafik yang terpotong di tengah adalah grafik yang
salah.

## Jumlah query harus tetap dua
Satu untuk titik penimbangan, satu untuk pita WHO. Kalau perubahan membuat
jumlah query tumbuh seiring jumlah titik, atau menambah query per titik, itu
salah. Aturan ini diuji dengan menghitung query, bukan menghitung query
seluruh request (autentikasi punya query sendiri).

## Tanpa data tetap 200
Anak yang belum pernah ditimbang menghasilkan `points: []` dengan status 200,
dan `who_reference` tetap terisi penuh karena pita tidak bergantung pada
riwayat penimbangan. `404` hanya untuk anak yang memang tidak ada, dan untuk
id yang bukan UUID - bukan 500 dari error PostgreSQL.

## Otorisasi mengikuti `GET /children/{id}`, jangan buat aturan sendiri
Route growth wajib didaftarkan di group yang sama dengan
`GET /children/{id}` (`RoleCheck` ibu + kader), bukan di prefix `/kader/`.
Ibu hanya boleh membuka anaknya sendiri, kader boleh semua. Pemeriksaan
kepemilikan dan pengecekan `Str::isUuid()` sudah ada di
`ChildController::findChildForUser()` - pakai helper itu, jangan salin
versinya sendiri ke tempat lain.

## Satu controller, bukan dua
Method `growth` tinggal di `ChildController`. Query dan pembentukannya masuk
ke `GrowthChartService`, supaya file yang beraturan jelas. Controller
`GrowthChartController` yang menyalin logika otorisasi dari `ChildController`
adalah duplikasi yang pasti kelak berbeda satu sama lain.

## Route yang ada sekarang tidak boleh hilang atau berubah
Ada 30 registrasi route API sebelum Opsi D, dan setelah growth ada 31.
Jangan menghapus, mengganti nama, atau memindahkan route lama.

Hitung route dengan **registrasi unik**, bukan baris `route:list`:
`Route::match(['put','patch'], ...)` dihitung dua baris oleh `route:list`,
jadi angkanya selalu terlihat satu lebih banyak dari kenyataannya.

## Jangan tambah dependency tanpa persetujuan
`.ai/rules/yang-jangan-diubah.md` melarang menambah dependency tanpa
persetujuan pengguna. Fitur ini kebetulan tidak butuh izin apa pun karena
`fl_chart: ^1.2.0` sudah jadi dependency langsung di `pubspec.yaml` sejak
awal, hanya belum pernah di-import. Kalau nanti butuh package chart kedua,
tanyakan dulu - jangan diam-diam menambahkannya.