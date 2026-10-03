# Rancangan Grafik Tumbuh Kembang untuk Ibu

**Tanggal:** 1 Oktober 2026 (Fase 1), 2 Oktober 2026 (Fase 2 - Kader)
**Status implementasi:** Fase 0 (spesifikasi) dan Fase 1 (endpoint + layar
Ibu) selesai 1 Oktober 2026. Fase 2 (layar Kader + test tambahan bagian 9)
dispesifikasikan 2 Oktober 2026 di bagian 5.4 dan 8.7, dan **selesai di hari
yang sama**. Verifikasi akhir: 121 test / 1167 assertion backend, 135 test
mobile, 31 route `api/` (tidak bertambah), `periksa-teks.ps1` bersih.
**Acuan:** `RANCANGAN.md` bagian 3.2 A, `RENCANA_SELANJUTNYA.md` Opsi D
**Estado repo saat ditulis:** Fase 1 sudah di-commit. Fase 2 masih **belum
di-commit** - berkasnya ada di working tree (`growth_chart_view.dart`,
kedua pembungkus layar, `grafik_tumbuh_kader_test.dart`, dan lima test
`GrowthChartTest.php` yang ditambahkan).

> **Dokumen ini normatif, bukan catatan meeting.** Sejak 1 Oktober 2026,
> dokumen ini yang menentukan bentuk `GET /children/{id}/growth`, nama field,
> dan batasannya. Kalau implementasi nanti menyimpang dari dokumen ini, itu
> yang salah, bukan dokumennya.
>
> Kalau bentuk respons memang harus berubah, **ubah dokumen ini lebih dulu**,
> baru kodenya. Aturan yang mengikat agent ada di
> `posyandu-backend/.ai/rules/`: `yang-jangan-diubah.md` dan `pengujian.md`.

---

## 1. Tujuan

Ibu sekarang bisa membaca status gizi anaknya sebagai satu angka pada
penimbangan terakhir. Itu belum menjawab pertanyaan yang paling sering muncul
di rumah: "anaknya tumbuhnya baik atau tidak dibanding bulan lalu, bulan lalu
lagi?"

Setelah fitur ini jadi, Ibu membuka satu layar dan melihat kurva berat badan
dan tinggi badan anak dari kunjungan pertama sampai yang terakhir, dengan pita
acuan WHO di belakang kurva berat badan. Grafik itu dibaca, bukan dihitung:
semua angka status gizi tetap datang dari trigger PostgreSQL seperti
sekarang.

---

## 2. Ruang Lingkup

### 2.1 Yang dikerjakan (Fase 1)

| Item | Sumber |
|------|--------|
| Grafik berat badan dan tinggi badan dari waktu ke waktu | `RANCANGAN.md:45` |
| Pita acuan WHO BB/U (median dan -/+2 SD) di belakang grafik BB | `RANCANGAN.md:45` |
| Sumbu x memakai umur dalam bulan, bukan tanggal | `RANCANGAN.md:45` |
| Layar khusus untuk Ibu, diisi lewat tombol yang sudah ada | `dashboard_ibu_screen.dart:344` |

### 2.2 Yang TIDAK dikerjakan dan alasannya

| Yang ditunda | Alasan |
| :--- | :--- |
| **Pita WHO untuk TB/U** | Tidak ada tabel `who_hfa_standards`. Satu-satunya acuan di database adalah BB/U 0-60 bulan. Menggambar pita TB tanpa acuan berarti mengarang angka. Lihat bagian 5.1. |
| **`z_score_hfa` dan status stunting** | Sama alasannya. Stunting adalah ukuran TB/U, jadi selama tidak ada TB/U, tidak ada stunting. `LAPORAN_ZSCORE_TRIGGER.md:47` sudah mencatat ini sebagai terbuka. |
| **Tabel WHO TB/U baru** | Butuh 122 baris data WHO 2006 yang akurat dan menyentuh trigger yang sekarang hijau. Itu pekerjaan tersendiri, bukan bagian dari grafik. |
| **Grafik lingkar kepala** | `head_circumference_cm` sudah ikut di payload, tapi tidak ada acuan WHO maupun ambang batas. Grafik tanpa acuan untuk lingkar kepala bisa saja membujuk Ibu salah baca. Buka toggle-nya di fase 2. |
| ~~**Grafik untuk Kader**~~ | **Selesai di Fase 2 (2 Oktober 2026).** `RANCANGAN.md:45` menaruh grafik pertumbuhan di modul Ibu (3.2 A, e-KMS Mandiri), jadi layar Ibu memang yang pertama. Endpoint sudah terdaftar di group `ibu,kader` supaya Kader tidak diblokir. Fase 2 memakai endpoint yang sama tanpa perubahan kontrak apa pun - lihat bagian 5.4. |
| **Simpan grafik sebagai gambar / ekspor PDF** | Butuh package tambahan. Tidak ada di MVP. |

---

## 3. Apa yang Sudah Ada (70%)

Fitur ini **bukan proyek dari nol**:

| Kebutuhan | Sudah ada di |
|------------|--------------|
| Data berat dan tinggi per kunjungan | Tabel `measurements`, sudah ada sejak awal |
| Z-score BB/U dan status gizi per kunjungan | Trigger `trg_measurements_who_zscore`, sudah otomatis |
| Median dan SD WHO per umur dan gender | Tabel `who_wfa_standards`, 122 baris, 0-60 bulan |
| Deret waktu untuk satu anak | `GET /children/{id}/timeline`, sudah ada dari Opsi B |
| Package chart di Flutter | `fl_chart: ^1.2.0` sudah jadi dependency, **belum pernah di-import** |
| Tombol "Grafik Tumbuh" di dashboard Ibu | `dashboard_ibu_screen.dart:344-348`, sekarang hanya menampilkan snackbar |
| Peta status gizi ke warna | `_warnaStatus()` sudah ada di dua layar |

Yang hilang bukan datanya. Yang hilang adalah cara menampilkannya sebagai
kurva, dan satu endpoint yang bisa dibaca Ibu.

---

## 4. Yang Benar-Benar Hilang

### 4.1 Ibu belum punya endpoint deret waktu

`GET /kader/measurements?child_id=` adalah satu-satunya deret waktu, dan
route-nya khusus Kader. Ini sudah dicatat sebagai celah di
`API_CONTRACT.md:1167-1168`. Ibu hari ini tidak punya cara apa pun untuk
mengambil seluruh riwayat penimbangan anaknya.

### 4.2 Timeline tidak bisa dipakai untuk grafik

Endpoint `/timeline` menggoda untuk dipakai ulang, tapi tiga hal membuatnya tidak
cocok, dan ketiganya struktural, bukan prefersensi:

1. **Urutannya terbaru lebih dulu.** Sumbu x grafik harus lama ke baru.
2. **Dibatasi 50 tanggal per halaman dengan cursor `before`.** Grafik yang
   terpotong di tengah adalah grafik yang salah.
3. **`age_in_months` per kunjungan tidak ada.** `TimelineMeasurement`
   sengaja tidak membawanya; usurnya hanya ada di blok anak untuk
   penimbangan terakhir. Tanpa umur per titik, titik data tidak bisa
   disejajarkan dengan pita WHO, karena pita itu diindeks umur.

### 4.3 Pita WHO tidak pernah dikirim ke klien

Tabel `who_wfa_standards` ada di database, tapi tidak ada endpoint yang
membacanya. Tanpa itu, grafik hanya garis nilai anak saja, dan Ibu tidak punya
banding. Membaca tabel referensi **bukan menghitung z-score**, jadi ini
tidak melanggar aturan pemisahan database di bagian 8.

---

## 5. Keputusan yang Sudah Diputuskan

Tiga keputusan ini ditutup pada **1 Oktober 2026**. Jangan dibuka lagi tanpa
alasan tertulis di bagian 13 - kalau nanti berubah, dokumen ini yang harus
diperbarui lebih dulu.

### 5.1 Pita WHO hanya untuk BB/U. TB digambar tanpa pita

| | |
| :--- | :--- |
| Metrik yang digambar | Berat badan (kg) dan tinggi badan (cm) |
| Metrik yang punya pita WHO | Berat badan saja, dari `who_wfa_standards` |
| Field kontrak | `who_reference.metric` bernilai `"weight_for_age"` |
| Migration baru | **Tidak ada.** Fitur ini tidak menambah satu pun tabel atau kolom |
| TB/U | Digambar sebagai garis nilai mentah, dan layar menyatakan terus terang bahwa tidak ada acuan WHO untuk TB |

Alasan: `RANCANGAN.md:45` minta grafik BB dan TB, dan keduanya memang
digambar. Yang tidak bisa dipenuhi adalah **pita** untuk TB, karena tidak ada
acuan yang bisa dibaca. Gambar TB tanpa pita jauh lebih jujur daripada menggambar
pita dari angka yang tidak berasal dari WHO.

Konsekuensi yang harus diterima:

1. Layar wajib menampilkan catatan bahwa pita hanya berlaku untuk BB.
2. Garis TB tidak boleh diberi warna "sehat" atau "berisiko" hanya karena
   posisinya. Klasifikasi hanya boleh datang dari `status_gizi`, yang hanya
   ada untuk BB.
3. `who_reference` tidak boleh diperluas ke TB tanpa migration `who_hfa_standards`
   lebih dulu.

### 5.2 Endpoint baru, bukan memakai timeline

```
GET /api/children/{id}/growth
```

Didaftarkan di group yang sama dengan `GET /children/{id}`, persis seperti
`/timeline`, supaya aturan aksesnya tidak berbeda: Ibu hanya anaknya sendiri,
Kader semua anak.

Alasan: alasannya sudah tiga di bagian 4.2. Menempelkan grafik ke timeline
akan melanggar tiga aturan yang sudah ditulis di `child_timeline.dart` dan
`child_timeline_service.dart` (tanpa pengurutan ulang, tanpa penyaringan,
cursor tidak dikarang), dan itu lebih mahal daripada satu endpoint.

### 5.3 Layar untuk Ibu dulu

Tombol "Grafik Tumbuh" yang sudah ada di `dashboard_ibu_screen.dart:344`
diisi dengan layar baru. Endpoint ada di group `ibu,kader`, jadi menambah
layar Kader nanti tidak perlu mengubah kontrak API sama sekali.

Konsekuensi: `detail_anak_screen.dart` **tidak** disentuh di Fase 1.

### 5.4 Fase 2: satu layar, dipakai Ibu dan Kader

Ditutup pada **2 Oktober 2026**.

| | |
| :--- | :--- |
| Layar Kader | `lib/screens/kader/grafik_tumbuh_screen.dart`, dibuka dari `detail_anak_screen.dart` |
| Perubahan kontrak API | **Tidak ada.** `GET /children/{id}/growth` sudah di group `ibu,kader` |
| Perubahan skema | **Tidak ada** |
| Dependency baru | **Tidak ada** |

#### Isi layar Kader sama dengan layar Ibu, persis

Kader melihat data yang sama dengan Ibu - grafik, pita WHO, z-score, dan status
gizi semua dibaca dari sumber yang sama. Yang berbeda hanya **warna** (biru,
sesuai semua layar Kader lain) dan **tempat pembukaannya**.

Jadi layarnya **bukan salinan**. Isi grafik diekstrak ke
`lib/widgets/growth_chart_view.dart` yang menerima palet warna, dan kedua layar
cuma pembungkus tipis. Alasannya mengikuti aturan yang sudah dipakai di sisi
server (`kontrak-growth.md`: "Satu controller, bukan dua"): dua salinan 500 baris
yang berbeda warna dijamin akan berbeda dalam satu detail dalam beberapa bulan,
dan layar yang gagal menampilkan pita adalah layar yang menyesatkan tanpa
terdeteksi.

Pengecualiannya sudah jelas dan tetap begitu: `detail_anak_screen.dart` punya
`_warnaStatus()` sendiri dengan pemetaan berbeda dari Ibu, dan itu dibiarkan -
karena bukan layar grafik.

#### Kader hanya melihat, tidak mengedit

Layar ini **read-only untuk kedua role**. Kader mencatat penimbangan lewat
`input_penimbangan_screen.dart`, bukan dari dalam grafik. Membuat grafik bisa
menyimpan nilai baru akan berarti ada dua jalan menulis ke `measurements`, dan
`jumlah_query_tetap_dua` beserta seluruh pemetaan aturan di 7.3 diuji terhadap
satu pembacaan saja.

#### Tiga hal yang tidak boleh bocor ke layar Kader

1. **Tidak ada daftar anak.** Grafik selalu milik satu anak; daftar anak sudah
   ada di dashboard Kader dan `detail_anak_screen.dart`. Menambah pemilih anak di
   sini berarti layar kedua untuk hal yang sudah punya tempat.
2. **Tidak ada data milik Ibu.** `child.gender` dan `who_reference.gender` ikut
   terbaca karena pita WHO terindeks gender, dan itu kolom anak - bukan data Ibu.
3. **Tidak ada export, tidak ada share.** Sama seperti Fase 1: butuh package
   tambahan, dan tidak ada di MVP.

#### Jebakan kedua: cache dan muat ulang

Layar Kader dibuka dari `detail_anak_screen.dart`, yang **sudah** memuat
penimbangan dan timeline. Kalau grafik ikut memakai cache `KaderService`, layar
ini akan menampilkan angka yang berbeda dari kartu "Penimbangan Terakhir" tepat
di sebelahnya setelah kader mencatat penimbangan baru. Jadi layar grafik selalu
ambil dari `GrowthChartService` dan punya tombol muat ulang sendiri, persis
seperti layar Ibu - bukan memakai hasil yang sudah ada di memori.

#### Yang tidak berubah di Fase 2

- `dashboard_ibu_screen.dart` **tidak disentuh**. Layar Ibu menjaga API
  publiknya (`GrafikTumbuhScreen(childId:, childName:)`), jadi pemanggilnya
  tidak tahu bahwa isinya sudah diekstrak.
- `growth_chart.dart`, `growth_line_chart.dart`, dan
  `growth_chart_service.dart` **tidak disentuh**. Aturan parsing dan gambar di
  7.3 berlaku untuk kedua role tanpa perbedaan.
- Tidak ada route, migration, atau endpoint baru. `route:list` tetap 31 route
  `api/`.

---

## 6. Rancangan Data

### 6.1 Tidak ada tabel baru

Grafik adalah bentuk baca lain dari `measurements`, ditambah pembacaan
`who_wfa_standards`. Tidak ada tabel baru, tidak ada duplikasi data, tidak
ada migration.

### 6.2 Tabel yang TIDAK dipakai

Bagian ini disimpan supaya tidak ada yang mengulang diskusi. Keputusan 1
Oktober 2026 memilih tidak menambah tabel:

```
who_hfa_standards            # TB/U - TIDAK dibuat di Fase 1
  id, age_in_months, gender, median_cm, sd_cm, timestamps
  UNIQUE (age_in_months, gender)

measurements.z_score_hfa     # kolom baru - TIDAK ditambahkan
measurements.status_stunting # kolom baru - TIDAK ditambahkan
```

Kalau suatu saat tabel `who_hfa_standards` benar-benar dipakai, itu harus
lewat perubahan dokumen di bagian 5.1 lebih dulu, bukan langsung menulis
migration.

### 6.3 Sumber angka pita

Pita dihitung dari konstanta referensi di database, **bukan dari data anak**:

```
median_kg  = who_wfa_standards.median_kg
lower_kg   = median_kg - 2 * sd_kg
upper_kg   = median_kg + 2 * sd_kg
```

Hitungan ini dilakukan di SQL pada `who_wfa_standards`, bukan di PHP dan
bukan di Dart. Alasannya: `z_score_wfa` anak sendiri **tidak pernah**
diturunkan dari pita. Nilai itu tetap dibaca apa adanya dari kolom yang
diisi trigger.

Garis `lower_kg` dan `upper_kg` tepat sama dengan tempat trigger menaruh
`z = -2` dan `z = 2`, jadi pita dan status gizi tidak pernah bertentangan.

---

## 7. Rancangan Endpoint

### 7.1 Rute

```
GET /api/children/{id}/growth
```

**Tidak ada query string.** Endpoint ini sengaja tanpa filter tanggal, tanpa
pagination, dan tanpa cursor.

**Tidak ada pagination, dan itu keputusan, bukan kelalaian.** Satu anak
punya paling banyak satu baris penimbangan per tanggal, karena partial
unique index `measurements_child_date_unique`. Untuk anak 0-60 bulan dengan
kunjungan bulanan, itu 61 titik; skenario terburuk yang realistis, penimbangan
mingguan selama 5 tahun, adalah sekitar 260 titik. Grafik dengan 260 titik
adalah hal biasa, dan JSON 260 titik tidak terasa berat di jaringan seluler.

Kalau nanti ada anak dengan ribuan titik, itu masalah memasukkan data, bukan
masalah grafik. Pagination ditambahkan saat itu terjadi, bukan sekarang.

### 7.2 Bentuk respons

```json
{
  "success": true,
  "message": "Data pertumbuhan anak berhasil diambil.",
  "data": {
    "child": {
      "id": "uuid",
      "name": "Siti",
      "nik": "3273010123456789",
      "gender": "P",
      "date_of_birth": "2024-03-12",
      "age_in_months": 30,
      "medical_flags": null
    },
    "series": {
      "unit": { "weight": "kg", "height": "cm" },
      "order": "asc",
      "points": [
        {
          "date": "2026-09-24",
          "age_in_months": 30,
          "weight_kg": 12.4,
          "height_cm": 88.0,
          "head_circumference_cm": 47.5,
          "z_score_wfa": 0.21,
          "status_gizi": "Normal"
        }
      ]
    },
    "who_reference": {
      "metric": "weight_for_age",
      "source": "WHO Child Growth Standards 2006",
      "gender": "P",
      "age_range": { "from": 0, "to": 60 },
      "points": [
        { "age_in_months": 30, "median_kg": 13.3, "lower_kg": 11.2, "upper_kg": 15.7 }
      ]
    }
  }
}
```

Catatan bentuk:

- `child.age_in_months` adalah umur **pada penimbangan terakhir**, bukan umur
  hari ini. Null kalau anak belum pernah ditimbang. Ini mengikuti
  `TimelineChild.ageInMonths` supaya dua layar tidak berbeda definisi.
- `series.order` selalu `"asc"`. Field ini ada supaya klien tidak perlu
  menebak urutan, dan supaya test bisa membuktikannya.
- `who_reference` **selalu dikirim**, termasuk ketika `points` kosong. Pita
  tidak bergantung pada riwayat penimbangan, jadi layar bisa menggambar
  pita sebelum kunjungan pertama.
- Tidak ada `meta`. Tanpa pagination, tidak ada yang perlu dipaginasi.

### 7.3 Aturan yang tidak boleh dilanggar

Sembilan belas aturan ini **normatif**. Setiap aturan dipetakan ke satu nama
test di `tests/Feature/GrowthChartTest.php`, jadi "aturan ini sudah dipatuhi"
bisa dibuktikan, bukan diklaim. Test dengan nama itu tidak boleh dihapus atau
di-rename tanpa memperbarui tabel ini.

| # | Aturan (WAJIB) | Test yang membuktikannya |
| :--- | :--- | :--- |
| 1 | **Urut naik.** `points` selalu dari tanggal terlama ke terbaru. | `points_selalu_urut_dari_tanggal_terlama` |
| 2 | **Tanpa penghitungan ulang.** `age_in_months`, `z_score_wfa`, dan `status_gizi` dibaca apa adanya dari database. | `angka_trigger_dibaca_dari_database_tanpa_dihitung_ulang` |
| 3 | **Baris yang dibatalkan tidak muncul.** Hanya `deleted_at IS NULL`. | `baris_yang_dibatalkan_tidak_muncul_di_grafik` |
| 4 | **Tanpa data tetap 200.** Anak yang belum pernah ditimbang punya `points: []`, bukan 404. | `anak_tanpa_penimbangan_punya_points_kosong` |
| 5 | **Z-score null tetap null.** Anak di luar 0-60 bulan punya `z_score_wfa` null dan `status_gizi` null. Keduanya tidak boleh jadi 0 atau teks. | `di_luar_rentang_who_z_score_tetap_null` |
| 6 | **Penimbangan tanpa kader tetap tampil.** `kader_id` nullable dengan `ON DELETE SET NULL`, jadi query wajib `leftJoin`. | `penimbangan_tanpa_kader_tetap_tampil` |
| 7 | **Pita hanya untuk BB/U.** `who_reference.metric` adalah `weight_for_age`, dan tidak ada pita untuk TB. | `pita_who_hanya_untuk_berat_badan` |
| 8 | **Pita ikut gender anak.** `who_reference.gender` sama dengan `child.gender`, dan titik pita mengikuti gender itu. | `pita_who_mengikuti_gender_anak` |
| 9 | **Pita dikirim walau `points` kosong.** | `pita_who_tetap_dikirim_saat_tanpa_penimbangan` |
| 10 | **Pita menutup 0 sampai 60 bulan**, 61 titik, satu per umur. | `pita_who_menutup_rentang_0_sampai_60_bulan` |
| 11 | **Tanpa filter tanggal.** Endpoint mengabaikan `from`, `to`, `limit`, dan `before`; tidak ada pagination. | `seluruh_riwayat_dikembalikan_tanpa_paginasi` |
| 12 | **Jumlah query tetap dua**, tidak bergantung pada jumlah titik. | `jumlah_query_tetap_dua` |

Tujuh aturan tambahan yang berasal dari bagian 5 dan bagian 7.1, dengan test
yang sama:

| Aturan (WAJIB) | Test yang membuktikannya |
| :--- | :--- |
| Ibu hanya boleh membuka grafik anaknya sendiri; selain itu `403`. | `ibu_membuka_anak_orang_ditolak` |
| Ibu boleh membuka grafik anaknya sendiri dan mendapat `200`. | `ibu_membuka_anak_anaknya_sendiri_membalas_200` |
| Kader boleh membuka grafik anak siapa saja. | `kader_bisa_membuka_grafik_anak_apa_saja` |
| `id` bukan UUID membalas `404`, bukan `500` dari error PostgreSQL. | `id_bukan_uuid_membalas_404` |
| `data` berisi tepat tiga kunci: `child`, `series`, `who_reference`. | `data_tepat_berisi_tiga_kunci` |
| `points` tidak pernah punya dua titik pada tanggal sama. | `tidak_ada_dua_titik_pada_tanggal_sama` |
| `medical_flags` ikut terbaca di blok `child`, apa adanya. | `medical_flags_terbaca_apa_adanya` |

### 7.4 Endpoint lain yang berubah

**Tidak ada.** Tidak ada route lama yang berubah nama, pindah, atau hilang.
`GET /children/{id}`, `/timeline`, `/kader/measurements`, dan sisanya tetap
persis.

`who_reference` dibaca dari `who_wfa_standards` dengan satu query. Tidak ada
perubahan pada tabel itu dan tidak ada perubahan pada trigger.

### 7.5 Kompatibilitas: yang tidak boleh berubah

Bagian ini ada supaya fitur ini tidak merusak yang sudah jalan. Versi yang
dipakai agent ada di `posyandu-backend/.ai/rules/yang-jangan-diubah.md`.

| Yang tidak boleh berubah | Kenapa | Sumber kebenaran |
| :--- | :--- | :--- |
| 30 registrasi route `api/` yang ada sebelum Opsi D. Opsi D menambah tepat 1, jadi **31** | Mobile sudah memakainya semua | `routes/api.php` |
| Hitungan route memakai **registrasi unik**, bukan baris `route:list` | `Route::match(['put','patch'])` dihitung dua baris oleh `route:list`, jadi angkanya selalu terlihat satu lebih banyak | `routes/api.php:69` |
| Bentuk `success` / `message` / `data` dan `errors` | Parser Flutter bergantung pada itu | `docs/AI_AGENT_RULES.md` bagian 8 |
| Field lama di respons `GET /children/{id}` dan `/timeline` | Ibu dan mobile sudah membacanya | `docs/API_CONTRACT.md` |
| Trigger `trg_measurements_who_zscore` dan tabel `who_wfa_standards` | Z-score hanya boleh dihitung PostgreSQL; menyentuh trigger berarti menggeser angka status gizi semua data lama | `yang-jangan-diubah.md` bagian z-score |
| Tabel `measurements` tidak menambah kolom | Menambah `z_score_hfa` berarti mengklaim stunting tanpa acuan | Bagian 5.1 dokumen ini |
| Partial unique `measurements_child_date_unique` | Yang menjamin aturan "satu titik per tanggal" | `2026_09_27_020000` |
| `kader_id` nullable dengan `ON DELETE SET NULL` | Menghapus akun kader tidak boleh menghapus riwayat | `2026_09_27_020000` |
| NIK tidak pernah ikut di `GET /petugas` | Privasi petugas | `PetugasController` |
| Urutan baris `by_type` dan baris CSV = urutan master suntikan | Kontrak diubah pada commit `6a8d2ed` | `ImmunizationType::scopeOrderedForDosing()` |
| Test hanya jalan di PostgreSQL `posyandu_test` | Test di SQLite hijau tanpa partial index dan trigger | `tests/TestCase.php` |
| Database dev `posyandu_db` tidak boleh tersentuh test | `RefreshDatabase` menghapus seluruh tabel | `tests/TestCase.php` |

### 7.6 Tidak ada dependency baru

`.ai/rules/yang-jangan-diubah.md` melarang menambah dependency tanpa
persetujuan. Fitur ini **tidak perlu persetujuan apa pun**, karena
`fl_chart: ^1.2.0` sudah jadi dependency langsung di `pubspec.yaml:39` sejak
awal, hanya belum pernah di-import. Tidak ada `pub add` yang perlu dijalankan.

`google_fonts: ^8.2.1` juga sudah ada tapi tidak dipakai. Grafik tidak
memerlukannya; biarkan apa adanya, tidak ada tugas untuk membersihkan itu
di sini.

---

## 8. Rancangan Layar Mobile

Layar baru: `lib/screens/ibu/grafik_tumbuh_screen.dart`. Bukan tab, bukan
dialog, dan bukan layar yang menimpa dashboard.

### 8.1 Struktur

- `AppBar` `Colors.pink[400]` dengan judul "Grafik Tumbuh", mengikuti semua
  layar Ibu lain. Nama anak ditampilkan di kartu header di bawah `AppBar`,
  bukan di judul - judul yang memuat nama anak akan terpotong di layar sempit
  dan tidak ada tempat untuk tombol muat ulang.
- Dua tombol toggle di atas grafik: **Berat Badan** dan **Tinggi Badan**.
  Bukan `SegmentedButton` atau `TabBar`, karena grafik menampilkan keduanya
  di satu kanvas dengan sumbu y terpisah; toggle memilih mana yang
  ditebalkan.
- Grafik `fl_chart` `LineChart` dengan dua sumbu y, karena kg dan cm tidak
  boleh dibandingkan langsung.
- Di bawah grafik, kartu status gizi terakhir. Kolomnya **persis sama** dengan
  kartu yang sudah ada di dashboard Ibu: `Tercatat`, `Z-Score`, dan `Status`,
  dengan pemetaan warna yang sama, supaya tidak ada dua definisi "status
  terakhir" di aplikasi yang sama. Umur saat penimbangan sudah tampil di kartu
  header di atas grafik, jadi tidak diulang di sini.

### 8.2 Sumbu

| Sumbu | Isi | Kenapa |
| :--- | :--- | :--- |
| x | `age_in_months` | Pita WHO diindeks umur. Kalau sumbu x tanggal, pita tidak bisa disejajarkan |
| y kiri | `weight_kg`, dengan pita WHO | Acuan WHO ada hanya untuk metrik ini |
| y kanan | `height_cm`, tanpa pita | Bagian 5.1 |

Umur pada titik adalah `age_in_months` dari server. **Tidak boleh dihitung
dari `date_of_birth` di Dart**, karena angka server dihitung trigger pada
saat penimbangan dicatat, dan hitungan ulang di klien bisa meleset satu bulan
di tanggal berulang.

Tanggal hanya dipakai untuk label di titik yang dipilih, bukan untuk
posisinya. `date` tetap ada di payload karena Ibu perlu tahu kapan kunjungan
it terjadi, bukan hanya umurnya.

**Umur yang sama boleh terjadi lebih dari sekali** - penimbangan 20 hari
sekitaran bisa dua-duanya di bulan ke-30. Itu bukan bug, dan garis tetap
digambar.

### 8.3 Pita WHO

- Area abu-abu sangat muda antara `lower_kg` dan `upper_kg`, diisi di bawah
  garis anak.
- Garis median tipis di tengah.
- Legenda satu baris: "Area abu = rentang normal WHO (median -/+2 SD)". Ibu
  tidak boleh menebak artinya dari warna saja.
- Pita digambar **hanya** untuk rentang umur 0-60 bulan. Anak yang sudah di
  atas 60 bulan tetap melihat garisnya, ditambah catatan bahwa standar WHO
  hanya berlaku sampai 60 bulan.
- Jika `who_reference.points` kosong, pita tidak digambar sama sekali dan
  catatan "Standar WHO belum tersedia untuk data ini" muncul. Layar tidak
  boleh mengarang pita dari interpolasi di sisi klien.

### 8.4 Angka nol

`MeasurementModel` yang sekarang punya `weightKg` dan `heightCm` non-nullable
dengan fallback `?? 0`. Model grafik **tidak boleh** meniru itu: satu titik
dengan `weight_kg` null berarti "tidak ditimbang hari itu", dan kalau
diparsing jadi `0.0` lalu digambar, Ibu melihat anak beratnya nol. Titik
dengan nilai null **tidak digambar sama sekali**.

### 8.5 State kosong dan gagal

- `points: []`: kartu `Icons.child_care_outlined` 72 `Colors.pink[200]` dan
  teks "Belum ada penimbangan yang tercatat". Pita tetap digambar kalau ada,
  supaya Ibu melihat ke mana anaknya akan tumbuh.
- Gagal: kartu `Icons.cloud_off` 64 `Colors.pink[200]` +
  `FilledButton.icon` "Coba Lagi", sama persis dengan layar Ibu lain.
- Memuat: `CircularProgressIndicator` pink.
- `who_reference.points` kosong: pita tidak digambar dan muncul catatan
  "Standar WHO belum tersedia untuk data ini". Interpolasi dari dua titik mana
  pun dilarang.

### 8.6 Apa yang tidak berubah

- `dashboard_ibu_screen.dart` tidak berubah strukturnya, hanya callback
  tombol di baris 344 yang diisi, plus satu import. Callback-nya memakai
  penjaga `if (anak == null) return;` yang **sudah ada** di
  `_bukaStatusImunisasi` dan `_bukaCatatanKeluhan` pada file yang sama, jadi
  grafik tidak boleh jadi satu-satunya tombol yang melempar crash saat
  `_anak` kosong.
- `AppTheme` tidak dipakai. Layar Ibu punya sistem warna pink sendiri yang
  hardcoded per layar, dan `app_theme.dart` hanya berlaku untuk layar
  autentikasi.
- Tidak ada `DateTime.parse` di jalur gambar. `intl` juga tidak dipakai,
  seperti seluruh aplikasi ini.

### 8.7 Layar Kader (Fase 2)

Seluruh isi layar ada di `lib/widgets/growth_chart_view.dart`:

| Widget | Isi |
| :--- | :--- |
| `GrowthChartView` | `StatefulWidget` yang memegang status muat, metrik aktif, dan seluruh subtree yang sebelumnya ada di `_GrafikTumbuhScreenState` |
| `GrowthChartPalette` | Lima warna: `appBar`, `latar`, `aksen`, `warnaTeksAksen`, `warnaIkonKosong` |

Dua pembungkus tipis, masing-masing satu file:

| Layar | Palet | Dipanggil dari |
| :--- | :--- | :--- |
| `screens/ibu/grafik_tumbuh_screen.dart` | pink (`Colors.pink[400]` dst) | `dashboard_ibu_screen.dart` |
| `screens/kader/grafik_tumbuh_screen.dart` | biru (`Colors.blue[800]` dst) | `detail_anak_screen.dart` |

Keduanya punya konstruktor yang sama persis, `({required String childId,
required String childName})`, dan keduanya meneruskan ke `GrowthChartView`.
Perbedaannya hanya nilai palet - **tidak ada** percabangan `if (isKader)` di
dalam view.

Tempat pembukaannya: `detail_anak_screen.dart`, sebagai `IconButton` di
`AppBar` bersama "Catatan Keluhan" dan "Imunisasi" yang sudah ada. Dipasang di
sana, bukan di dashboard Kader, karena grafik milik satu anak dan profil anak
adalah tempat semua layar per-anak sudah dibuka. Menu `AppBar` sudah punya tiga
tombol, jadi grafik adalah keempat - `Tooltip` wajib, seperti ketiga tombol
sebelumnya.

`_warnaStatus()` **tidak** dipindah ke view bersama: `detail_anak_screen.dart`
pun punya versinya sendiri yang berbeda, dan menyatukan keduanya berarti satu
dari dua layar berubah perilakunya tanpa disadari. Status gizi di dalam kartu
grafik memakai pemetaan yang sudah ada di layar Ibu, dan itu dibiarkan apa
adanya.

Kalimat state kosong juga **sama untuk kedua role** ("Kader akan
mencatatnya"). Mengubahnya jadi "Anda" hanya untuk Kader terlihat sopan, tapi
itu persis percabangan role yang dilarang di atas: begitu ada teks yang berbeda,
kedua layar tidak lagi identik dan harus diuji terpisah selamanya.

Testing parsing (`kontrak_api_test.dart`) dan gambar (`grafik_tumbuh_widget_test.dart`)
tidak berubah: keduanya identik untuk Ibu dan Kader. Test **baru** ada, tapi
bukan mengulang isi grafik - `grafik_tumbuh_kader_test.dart`, 6 test yang
menjaga satu-satunya hal yang memang berbeda: palet dan kemampuan kedua layar
untuk dipasang.

---

## 9. Rencana Pengujian

| Lapisan | Isi | Status |
|---------|-----|--------|
| Feature test PHP | Hit HTTP endpoint sungguhan, cek seluruh aturan di 7.3 satu per satu | Selesai - `tests/Feature/GrowthChartTest.php`, 25 test |
| `uji-api.ps1` grup baru | Cek urutan, pita, kosong, dan 403 lewat HTTP | Selesai - grup 8b, 27 pemeriksaan, dijalankan 2 Oktober 2026 dan lulus semua |
| Flutter test parsing | `GrowthChart.fromJson` terhadap JSON asli, termasuk `null` dan desimal sebagai string | Selesai - 17 test di `kontrak_api_test.dart` |
| Flutter test path | `ApiConstants.childGrowthEndpoint` dicek nilainya, seperti grup timeline | Selesai - satu test di grup yang sama |
| Flutter test widget | `LineChart` ter-render tanpa error untuk 1 titik, 3 titik, dan `points: []` | Selesai - `grafik_tumbuh_widget_test.dart`, 7 test |
| Flutter test palet dan screen | Kedua palet berbeda per field dan persis warna layar Kader/Ibu lain; kedua layar bisa dipasang | Selesai - `grafik_tumbuh_kader_test.dart`, 6 test |
| Manual | Buka di emulator, cek pita turun di atas garis saat anak berat kurang | Belum dilakukan - butuh perangkat/emulator |

Feature test minimal ada di **bagian 7.3**, yang memetakan setiap aturan ke
nama test-nya. Daftar di sini sengaja tidak diulang: dua daftar yang bisa
berbeda jauh lebih berbahaya daripada satu daftar yang lengkap. Test yang
tidak punya pasangan di 7.3 berarti ada aturan yang belum dipatuhi.

> **Peringatan dari pelajaran terakhir.** `MeasurementRecapTest` pernah hijau
> karena kebetulan: `ChildFactory` mengisi `date_of_birth` acak sementara test
> memakai tanggal hardcode, dan trigger menolak penimbangan sebelum tanggal
> lahir. Peluang gagalnya sekitar 12% per jalannya.
>
> Untuk fitur ini aturan yang sama berlaku lebih ketat, karena grafik selalu
> menampilkan seluruh riwayat. Kalau test memakai tanggal hardcode, anak di
> dalamnya **wajib** dibuat dengan `date_of_birth` pasti lewat
> `Child::factory()->create(['date_of_birth' => '...'])`, dan lebih baik lagi
> pakai `MeasurementFactory::tanggalSesudahLahir()`. Jangan mengulang
> kesalahan yang sama.

Test tambahan di luar daftar 7.3, ditambahkan 2 Oktober 2026:

- [x] `anak_di_atas_60_bulan_tetap_mendapat_poin_dengan_z_score_null`
- [x] `gender_anak_hanya_l_dan_p_menghasilkan_pita_yang_sesuai`
- [x] `garis_pita_konsisten_dengan_z_score_yang_dibaca_trigger`
- [x] `titik_punya_umur_kalendar_yang_sama_dengan_trigger`
- [x] `nilai_desimal_dibaca_sebagai_angka_bukan_teks`

---

## 10. Urutan Kerja

Urutan ini disengaja supaya tidak pernah ada layar yang memakai endpoint yang
belum ada.

1. **Kunci spesifikasi dan aturan** - dokumen ini, plus
   `posyandu-backend/.ai/rules/kontrak-growth.md` yang memetakan bagian 7.3
   ke nama test.
2. **Backend service** `GrowthChartService`: dua query, `leftJoin` ke
   `users`, nilai desimal dipaksa float karena PostgreSQL mengirim `DECIMAL`
   sebagai string.
3. **Endpoint + feature test.** `ChildController@growth` di group yang sama
   dengan `GET /children/{id}`, memakai `findChildForUser()` yang sudah ada.
4. **Dokumentasi** `API_CONTRACT.md` dan `DATABASE_SCHEMA.md` (tidak ada
   perubahan skema, tapi endpoint baru harus tercatat).
5. **Mobile model dan service** `growth_chart.dart` dan
   `growth_chart_service.dart`, plus `ApiConstants.childGrowthEndpoint`.
6. **Widget grafik** `widgets/growth_line_chart.dart` yang membungkus
   `fl_chart`.
7. **Layar Ibu** `screens/ibu/grafik_tumbuh_screen.dart` dan penghubung
   tombol di `dashboard_ibu_screen.dart`.
8. **Verifikasi akhir**: Pint, `php artisan test`, `flutter analyze`,
   `flutter test`, `periksa-teks.ps1`.

Tidak ada migration di urutan ini, dan itu bukan kelalaian - bagian 5.1
sudah ditetapkan.

---

## 11. Estimasi

| Bagian | Estimasi |
|--------|----------|
| Service + endpoint + feature test | 1 hari |
| Model, service, dan test parsing mobile | 0,5 hari |
| Widget `fl_chart` + test widget | 0,5 hari |
| Layar Ibu + penghubung tombol | 0,5 hari |
| Dokumentasi + `uji-api.ps1` + verifikasi | 0,5 hari |
| **Total** | **3 hari** |

Sesuai perkiraan di `RENCANA_SELANJUTNYA.md:136`. Tidak naik dari sana,
meskipun cakupan TB ikut digambar, karena pita TB justru dikorbankan - dan
itulah yang membuat biaya migration WHO TB/U tidak masuk ke estimasi ini.

Kalau nanti TB/U diputuskan untuk dikerjakan, tambah 1 sampai 1,5 hari dan
satu migration terpisah.

---

## 12. Pertanyaan yang Sudah Ditutup

| Pertanyaan | Jawaban | Alasan |
| :--- | :--- | :--- |
| Apakah Ibu boleh melihat grafik anaknya sendiri? | **Ya** | Sama dengan timeline; itu hak orang tua atas data anaknya |
| Apakah Kader boleh? | **Ya**, endpoint-nya | Layar menyusul di fase berikutnya; menambahkannya nanti tidak mengubah kontrak |
| Pita dihitung di PHP atau dikirim dari database? | **Dikirim**, dihitung di SQL pada tabel referensi | Aturan z-score hanya boleh dihitung PostgreSQL; pita adalah konstanta referensi, bukan data anak |
| Apakah grafik perlu pagination? | **Tidak** | Partial unique index membatasi satu baris per tanggal; 61 titik untuk anak 0-60 bulan |
| Sumbu x tanggal atau umur? | **Umur dalam bulan** | Pita WHO diindeks umur |
| Apakah lingkar kepala digambar? | **Belum** | Tidak ada acuan WHO LK dan tidak ada ambang batas |
| Apakah pakai `MeasurementModel` yang sudah ada? | **Tidak** | `weightKg` dan `heightCm` non-nullable dengan fallback nol, dan model itu hanya untuk Kader |

Kalau ada pertanyaan baru muncul selama implementasi, jawabannya ditulis di
bagian ini, bukan disimpan di commit atau komentar kode.

---

## 13. Riwayat Perubahan

| Tanggal | Perubahan |
|---------|-----------|
| 1 Okt 2026 | Rancangan awal ditulis. Tiga keputusan ditutup: pita WHO hanya untuk BB/U, endpoint baru `GET /children/{id}/growth`, layar untuk Ibu dulu. Sembilan belas aturan di 7.3 dipetakan ke nama test. Belum ada kode fitur yang ditulis. |
| 1 Okt 2026 | Implementasi selesai: `GrowthChartService`, `ChildController@growth`, route, 20 feature test, 24 test Flutter, layar Ibu, dan `uji-api.ps1` grup 8b. Tidak ada migration, tidak ada dependency baru, tidak ada endpoint lama yang berubah. |
| 1 Okt 2026 | Dua penyimpangan dari rancangan ditemukan saat test dan diperbaiki: (1) sumbu y harus ikut menghitung pita WHO, kalau tidak pita meluber keluar area gambar dan terlihat terpotong; (2) rentang cm butuh nilai cadangan, karena `reduce` atas daftar kosong melempar `StateError` pada anak yang hanya ditimbang tinggi badannya. |
