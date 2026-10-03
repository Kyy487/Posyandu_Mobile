# Laporan Opsi D - Grafik Tumbuh Kembang (Backend + Mobile)

**Tanggal:** 1 Oktober 2026
**Spesifikasi acuan:** `docs/RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md`
**Status:** Backend dan mobile selesai 1 Oktober 2026. Layar Kader selesai
2 Oktober 2026.

---

## 1. Apa yang Dibuat

| File | Isi |
| :--- | :--- |
| `posyandu-backend/app/Services/GrowthChartService.php` | Dua query: seluruh riwayat penimbangan + pita WHO BB/U |
| `posyandu-backend/app/Http/Controllers/Api/ChildController.php` | Method `growth()`, memakai `findChildForUser()` yang sudah ada |
| `posyandu-backend/routes/api.php` | `GET /children/{id}/growth` |
| `posyandu-backend/tests/Feature/GrowthChartTest.php` | 20 test, memetakan 19 aturan normatif di bagian 7.3 + 1 tambahan |
| `posyandu-backend/.ai/rules/kontrak-growth.md` | Aturan agent untuk endpoint ini |
| `posyandu_mobile/lib/models/growth_chart.dart` | `GrowthChart`, `GrowthChild`, `GrowthSeries`, `GrowthPoint`, `WhoReference`, `WhoReferencePoint` |
| `posyandu_mobile/lib/services/growth_chart_service.dart` | Service `GET /children/{id}/growth` |
| `posyandu_mobile/lib/widgets/growth_line_chart.dart` | `GrowthLineChart`: pita WHO, garis BB, garis TB, dua sumbu y |
| `posyandu_mobile/lib/screens/ibu/grafik_tumbuh_screen.dart` | Layar grafik untuk Ibu |
| `posyandu_mobile/test/grafik_tumbuh_widget_test.dart` | 9 test widget |
| `posyandu_mobile/test/kontrak_api_test.dart` | 17 test parsing dan path, ditambahkan ke grup yang ada |
| `uji-api.ps1` | Grup 8b - 27 pemeriksaan HTTP |

Perubahan pada file yang sudah ada: `posyandu_mobile/lib/utils/constants.dart`
tambah `childGrowthEndpoint = '/growth'`, dan
`posyandu_mobile/lib/screens/ibu/dashboard_ibu_screen.dart` mengganti
`_info('Grafik pertumbuhan ...')` dengan navigasi ke layar baru. Tidak ada
route lama yang berubah nama, pindah, atau hilang - `php artisan route:list`
tetap mengembalikan 31 route `api/` (30 + 1).

**Tidak ada migration dan tidak ada dependency baru.** `fl_chart: ^1.2.0`
sudah jadi dependency langsung di `pubspec.yaml` sejak awal, hanya belum pernah
di-import.

---

## 2. Satu Endpoint

### `GET /children/{id}/growth`

Seluruh riwayat penimbangan satu anak urut naik, ditambah pita acuan WHO BB/U
untuk gender anak tersebut. Tidak ada parameter dan tidak ada paginasi.

`data` berisi tepat tiga kunci: `child`, `series`, `who_reference`. Tidak ada
`meta` - tanpa pagination, tidak ada yang perlu dipaginasi. Partial unique index
di database membatasi satu baris per tanggal, jadi anak 0-60 bulan paling banyak
61 titik.

Otorisasi memakai `findChildForUser()` yang sudah ada, jadi Ibu hanya melihat
anaknya sendiri, Kader melihat semua anak, dan UUID yang bukan milik pemanggil
menghasilkan 403 (Ibu) atau 404 (Kader, karena memang tidak ada anak dengan
UUID itu).

**Ibu yang tidak pernah menimbang anaknya tetap mendapat 200** dengan
`points: []`. Itu jawaban yang benar, bukan kegagalan: pitanya tidak bergantung
pada riwayat penimbangan, jadi layar bisa menggambar arah tumbuh anak sebelum
kunjungan pertama.

---

## 3. Tiga Hal yang Paling Mudah Salah, dan Bagaimana Dicegah

### Angka tidak boleh dihitung ulang di tempat lain

`z_score_wfa`, `age_in_months`, dan `status_gizi` sudah dihitung trigger
PostgreSQL. Server membacanya, mobile membacanya. Kalau salah satu lapisan
menghitung ulang dengan rumus versinya sendiri, Ibu dan Kader bisa melihat
angka berbeda untuk penimbangan yang sama - dan tidak ada yang mengetahuinya
karena keduanya terlihat "benar".

Dijaga oleh `angka_trigger_dibaca_dari_database_tanpa_dihitung_ulang` di sisi
server, dan test parsing mobile yang membandingkan nilai JSON apa adanya.

### `null` tidak boleh jadi `0`

Ada tiga jenis "tidak ada" yang berbeda, dan ketiganya akan salah kalau
dibuat nol:

- `weight_kg: null` - kunjungan itu memang tidak menimbang berat badan
- `age_in_months: null` - anak belum pernah ditimbang, jadi umurnya belum punya
  acuan
- `z_score_wfa: null` - anak di atas 60 bulan, di luar rentang WHO

Kalau ketiganya jadi `0`, Ibu melihat anak beratnya nol pada kunjungan yang
tidak menimbang, dan melihat z-score 0 (yang artinya "tepat median") untuk anak
yang tidak punya acuan sama sekali. `MeasurementModel` yang lama memakai `?? 0`
untuk field yang tidak boleh nullable; model growth sengaja tidak mengikutinya.

Dijaga di sisi mobile oleh test `nil tidak pernah jadi nol: semua field angka
nullable`, yang memeriksa `bisaDigambar` dan `umurTahun` bernilai `null`, dan
oleh test widget `titik dengan angka null tidak diplot sebagai nol`, yang
menghitung jumlah titik yang benar-benar digambar.

**Peringatan dari pengerjaannya:** membandingkan tipe angka dari respons JSON
dengan `assertSame` atau `assertIsFloat` membuat test **gagal acak**, karena
`json_encode` menulis `56.0` sebagai `56` dan `88.0` sebagai `88`. Nilai yang
sama-sama benar akan berganti tipe tergantung angka yang kebetulan keluar dari
factory. Ini sudah terjadi dua kali: satu di
`ChildTimelineTest::nilai_z_score_dibaca_dari_database_tanpa_dihitung_ulang`
(yang sudah ada sebelumnya) dan satu di
`GrowthChartTest::pita_who_hanya_untuk_berat_badan`. Keduanya sudah diganti ke
`assertEqualsWithDelta` plus pemeriksaan `> 0`, jadi sekarang nilai yang diuji
adalah angkanya, bukan tipe JSON-nya. Suite penuh dijalankan enam kali
berturut-turut untuk memastikan tidak ada sisa kekacauan.

### Penimbangan tanpa kader tidak boleh hilang

`kader_id` nullable dengan `ON DELETE SET NULL`, jadi `join` biasa ke `users`
akan diam-diam menghilangkan riwayat anak yang kadernya sudah dihapus - persis
data yang paling tidak boleh hilang. Karena itu query penimbangan memakai
`leftJoin`, sama seperti yang dilakukan `ChildTimelineService`.

Dijaga oleh `penimbangan_tanpa_kader_tetap_tampil`.

---

## 4. Pita WHO

Pita dikirim dari database, tidak dihitung di PHP. `who_wfa_standards` sudah
berisi median dan dua standar deviasi per bulan per gender; query service
menghitung `lower_kg` dan `upper_kg` di SQL (`median - 2*sd` dan
`median + 2*sd`) supaya angka yang sampai ke klien tetap presisi.

Tiga keputusan yang dikunci di bagian 5.1 rancangannya dan tidak dibalik:

1. **Pita hanya untuk BB/U.** Database hanya punya `who_wfa_standards`. Garis TB
   tetap digambar tanpa pita, dan widget test memastikan `betweenBarsData` tetap
   kosong saat pita tidak dikirim - tidak ada interpolasi dari dua titik mana pun.
2. **Tidak ada pita TB dan tidak ada status stunting.** Tabel
   `who_hfa_standards`, kolom `z_score_hfa`, dan klasifikasi stunting tidak
   dibuat.
3. **Tidak ada lingkar kepala.** Tidak ada acuan WHO LK di database dan tidak ada
   ambang batas yang bisa dipertanggungjawabkan. Nilainya tetap dikirim di API
   karena sudah ada di tabel, tapi tidak digambar.

---

## 5. Jumlah Query

Service memakai **dua query**: satu untuk seluruh riwayat penimbangan, satu
untuk pita WHO. Jumlahnya tidak bergantung pada jumlah kunjungan - anak dengan
20 kunjungan dan anak dengan 1 membutuhkan query yang sama. Diuji dengan
`jumlah_query_tetap_dua`, yang menghitung query langsung ke service, bukan
menghitung query seluruh request (autentikasi punya query sendiri yang tidak
berkaitan dengan grafik).

Paginasi sengaja tidak ada. Menambah `limit` di sisi klien akan membuat layar
menampilkan garis yang terpotong di tengah - lebih menyesatkan daripada grafik
penuh yang sedikit padat.

---

## 6. Mobile

### Keputusan implementasi

- **Sumbu x adalah umur dalam tahun, bukan tanggal.** Pita WHO diindeks umur, jadi
  sumbu tanggal tidak akan bisa disejajarkan dengan pita. Umurnya dibaca dari
  `age_in_months` milik server.
- **Tinggi badan dipetakan ke koordinat y yang sama dengan pita.** cm dan kg
  tidak bisa berbagi sumbu, jadi rentang cm dipetakan ke rentang y dan sumbu
  kanan menerjemahkan kembali ke cm. Angka yang dibaca Ibu tetap satuan
  aslinya, dan tidak ada konversi yang disimpan atau dikirim ulang ke server.
- **Rentang y ikut menghitung pita WHO.** Kalau hanya garis anak yang menentukan,
  pita yang lebih lebar meluber keluar area gambar dan terlihat terpotong - dan
  pita terpotong terlihat persis seperti pita yang salah. Ini penyimpangan dari
  rancangan awal yang ditemukan saat test widget.
- **Rentang cm punya nilai cadangan.** `_min`/`_max` menerima nilai cadangan
  karena `reduce` atas daftar kosong melempar `StateError` pada anak yang hanya
  ditimbang tinggi badannya. Ini penyimpangan kedua dari rancangan awal.
- **Sumbu x mengikuti umur anak, bukan rentang pita.** Kalau pita yang menentukan,
  anak 2 bulan mendapat kanvas 0-60 bulan dan garisnya jadi titik kecil di tepi.
- **Dua tombol, bukan `TabBar`.** Grafik menampilkan BB dan TB di satu kanvas
  dengan dua sumbu y, jadi tombol hanya menebalkan garis yang dipilih. `TabBar`
  akan menyiratkan isi tab yang berbeda, padahal tidak ada.
- **Kartu status gizi memakai `titikStatusTerakhir`**, yaitu titik terakhir yang
  punya z-score, bukan titik terakhir yang ada. Dua-duanya bisa berbeda pada anak
  di luar rentang WHO: titik terakhirnya `null`, tapi titik sebelumnya masih ada
  z-score yang diketahui.
- **Pita yang tidak lengkap tetap digambar apa adanya.** Sumbu x boleh lebih
  sempit dari 0-60 bulan; yang tidak boleh terjadi adalah melebar atau
  menyempitkan pita untuk mengisinya.
- **Tombol dashboard punya penjaga `_anakAktif == null`** yang sama dengan
  navigasi lain di file itu, supaya tidak menjadi satu-satunya tombol yang
  melempar crash.
- **`who_reference` tidak pernah menggagalkan layar.** Kalau `points` kosong,
  `GrowthLineChart` mengembalikan `SizedBox.shrink()` dan layar menampilkan
  catatan, bukan kanvas kosong tanpa penjelasan.

### Verifikasi mobile

| Pemeriksaan | Hasil |
| :--- | :--- |
| `flutter analyze` | 0 error, 0 warning (1 info pre-existing di `kader_service.dart`) |
| `flutter test` | 137 test hijau (32 test baru: 17 parsing + 9 widget + 6 palet/screen) |

### Ukuran layar ponsel, bukan kanvas longgar

Dua test tambahan menutup bagian yang biasanya hanya bisa dilihat dengan mata.
Test lama memakai kanvas 400x320; ponsel sempit 360 dp dan tinggi, sehingga
ruang untuk label sumbu y dan tinggi badan jauh lebih sedikit - di situlah
`RenderFlex` paling sering meluber.

- `tester.view.physicalSize` 1080x2400 dengan density 3.0, jadi 360x800 dp.
- Data persis seperti hasil server untuk anak aged 3 tahun lebih: pita 61 bulan
  penuh dan enam titik yang semuanya di rentang 35-39 bulan.
- `expect(tester.takeException(), isNull)` menutup semua kemungkinan meluber
  tanpa perlu menghitung piksel.
- Case kedua: satu titik dengan angka ekstrem (21,4 kg / 104 cm), yang mensyaratkan
  label sumbu y panjang.

Salah satu yang ketahuan di sini: `lineBarsData` memuat **dua** garis - pita WHO
(61 titik) dan garis anak. Assertion yang mengira `lineBarsData.first` sebagai
garis anak akan salah, jadi test ini memeriksa keberadaan jumlah titik dan bukan
urutannya.

### Yang tidak bisa diverifikasi

Screenshot di emulator **tidak dapat dinilai**, jadi tidak ada klaim bahwa
pita, label sumbu, dan warnanya sudah dilihat oleh mata manusia. Dua alasannya:

1. Alat ini tidak bisa membaca gambar, jadi screenshot hanya bisa diambil, tidak
   bisa dilihat.
2. Flutter tidak mengekspos semantics-nya ke `uiautomator` tanpa layanan
   aksesibilitas aktif. Yang terbaca hanya dua `EditText` native; tombol
   "Masuk" tidak ditemukan, sehingga layar grafik tidak pernah dibuka.

Sebagian yang bisa dipastikan tanpa mata: APK terpasang, aplikasinya jalan,
`10.0.2.2:8000` terjangkau dari emulator (ping 2/2), dan datanya nyata dari
server. Untuk menutup sisanya, akun uji sudah disiapkan dan tinggal dibuka
melalui UI.

Akun uji visual (dibuat 2 Oktober 2026, NIK acak dari suffix jam):

| Peran | NIK | Password |
| :--- | :--- | :--- |
| Kader | `7766554433221153` | `Rahasia123` |
| Ibu | `5544332211009953` | `Rahasia123` |

Anak uji: "Naya Putri Uji", lahir 2023-06-15, perempuan, enam penimbangan
Mei-Oktober 2026 dengan z-score -0,86 sampai +0,13 (semua Normal) - jadi
garisnya naik dan **harus berada di dalam** pita WHO. Kalau pita meleset ke atas
atau ke bawah, kelihatan langsung di layar.

### Fase 2: layar Kader (2 Oktober 2026)

Layar Kader memakai endpoint yang sama persis. Tidak ada perubahan kontrak,
tidak ada migration, tidak ada dependency baru, dan `route:list` tetap 31.

- **Satu `GrowthChartView`, dua palet.** Isi dan perilakunya identik; yang
  berbeda hanya warna. Ini yang membuat "tambah role di masa depan" tidak
  berarti menggandakan 600 baris kode grafik.
- **Titik masuk di `AppBar` `detail_anak_screen.dart`**, bukan di dashboard.
  Alasannya sederhana: dashboard Kader bekerja pada tingkat desa atau
  kecamatan, sedangkan grafik ini milik satu anak. Grafik milik satu anak harus
  dibuka dari halaman anak itu, berdampingan dengan penimbangan dan imunisasi.
- **Ibu tidak berubah perilakunya.** `grafik_tumbuh_screen.dart` kini hanya
  wrapper. Tiga test palet menjaga agar ekstraksi ini tidak mengubah warna
  layar Ibu diam-diam - warna pink lama masih diuji sebagai angka persis,
  bukan "darker dari pink".

### Test yang ditambahkan di Fase 2

`grafik_tumbuh_kader_test.dart`, 6 test:

- Kedua palet berbeda **per field**, bukan hanya "objeknya beda". Palet yang
  berbeda objek tapi sama warnanya tetap salah.
- Warna AppBar Kader persis `Colors.blue[800]`, sama dengan
  `detail_anak_screen.dart`, `kader_dashboard_screen.dart`, dan
  `catatan_keluhan_screen.dart`.
- Warna AppBar Ibu persis `Colors.pink[400]` seperti sebelum ekstraksi.
- Kedua layar bisa dipasang dan memakai paletnya masing-masing.
- Dengan sesi tapi server mati, kedua layar menampilkan state gagal dan tombol
  "Coba Lagi" tanpa melempar exception.

Test widget ini perlu mock method channel
`plugins.it_nomads.com/flutter_secure_storage`, karena
`GrowthChartService` membaca token di `initState`. Tanpa token layar langsung
mengarahkan ke login, jadi error state-nya tidak pernah terlihat.

---

## 7. Verifikasi

| Pemeriksaan | Hasil |
| :--- | :--- |
| `php artisan test` | 121 test / 1167 assertion hijau (25 test baru), 3 kali berturut-turut |
| `vendor/bin/pint --dirty` | Lulus, tanpa perubahan |
| `php artisan route:list` | 31 route `api/` - tetap sama, Fase 2 tidak menambah endpoint |
| `flutter analyze` | 0 error, 0 warning (1 info pre-existing di `kader_service.dart`) |
| `flutter test` | 137 test hijau (32 test baru: 17 parsing + 9 widget + 6 palet/screen) |
| `periksa-teks.ps1` | BERSIH - 163 file diperiksa |
| `uji-api.ps1` grup 8b | Dijalankan 2 Oktober 2026 terhadap server hidup - **semua 27 pemeriksaan lulus** |
| `uji-api.ps1` utuh | 369 pemeriksaan lulus, 0 gagal (2x berturut-turut) |
| Cek di emulator | Dijalankan 2 Oktober 2026. Emulator Android 17 (1080x2400), APK terpasang, jaringan `10.0.2.2:8000` terjangkau, data uji sudah disiapkan. **Screenshots tidak dapat dinilai** - lihat catatan di bawah |

---

## 8. Belum Dikerjakan

- **Grafik lingkar kepala** dan **pita TB/U** - keduanya butuh data acuan WHO
  yang tidak ada di database, dan keduanya butuh migration terpisah.
- **Penilaian visual di emulator.** APK sudah terpasang dan datanya sudah siap,
  tapi belum ada yang melihat layarnya. Yang belum dari item ini adalah
  penilaian mata: pita benar-benar turun di atas garis saat anak berat kurang,
  dan keterbacaan label sumbu di layar sempit.

### Cara menjalankan grup 8b

```powershell
# terminal 1
cd C:\laragon\www\posyandu\posyandu-backend
& "C:\laragon\bin\php\php-8.4.25-Win32-vs17-x64\php.exe" artisan serve

# terminal 2
cd C:\laragon\www\posyandu
powershell -ExecutionPolicy Bypass -File .\uji-api.ps1
```

Hasil 2 Oktober 2026: **369 pemeriksaan lulus, 0 gagal**, dua kali berturut-turut.
Sisa data uji di `posyandu_db` tidak bertambah antar-jalankan.

Menjalankan skrip ini sekaligus menemukan tiga cacat di skripnya sendiri, yang
semuanya sudah diperbaiki dan ketahuan justru karena grafik adalah bagian yang
paling duluan dijalankan:

1. **Ekspektasi pesan 403 di grup 8b salah.** Skrip mengharapkan `Akses
   ditolak`, sedangkan API dan `API_CONTRACT.md` mengunci kalimat penuh
   `Akses ditolak. Anda tidak berhak melihat data anak ini.`
2. **Grup Buku Medis hanya lulus di tanggal 5 s.d. akhir bulan.** Skrip memakai
   tanggal "hari ini - 4 hari", sementara `MedicalNoteController` meringkas
   bulan berjalan secara default, jadi tanggal 3 Oktober membuat catatan uji
   jatuh di September dan ringkasannya nol.
3. **Grup rekap imunisasi gagal kalau ada data lain.** Rekap bersifat agregat
   seluruh Posyandu, sedangkan skrip menganggap angka HB0 mulai dari nol.

Keduanya adalah cacat skrip uji, bukan bug aplikasi, dan tidak ada yang menyentuh
endpoint mana pun.
