# Rancangan Buku Medis Digital (EHR) — Balita

**Tanggal:** 28 September 2026
**Spesifikasi final:** 29 September 2026
**Status implementasi:** Fase 0 + Fase 1 (backend) + Fase 2 (mobile)
selesai 29 September 2026
**Acuan:** `RANCANGAN.md` bagian 3.1 A, `RENCANA_SELANJUTNYA.md` Opsi B
**Estado repo saat ditulis:** 6 commit di depan `origin/main` (push tertunda -
environment tidak punya kredensial GitHub)

> **Dokumen ini normatif, bukan catatanMeeting.** Sejak 29 September 2026,
> dokumen ini yang menentukan bentuk `GET /children/{id}/timeline`, nama
> field, dan batasannya. Kalau implementasi nanti menyimpang dari dokumen ini,
> itu yang salah, bukan dokumennya.
>
> Kalau bentuk respons memang harus berubah, **ubah dokumen ini lebih dulu**,
> baru kodenya. Aturan yang mengikat agent ada di
> `posyandu-backend/.ai/rules/`: `kontrak-timeline.md`,
> `yang-jangan-diubah.md`, dan `pengujian.md`.

---

## 1. Tujuan

Buku medis adalah tempat kader membuka satu anak dan melihat seluruh
riwayatnya dalam satu layar. Sekarang data itu tersebar di empat layar
terpisah, jadi kader harus mengingat layar mana yang sudah dicek untuk
membentuk gambaran lengkap seorang anak.

Setelah fitur ini jadi, satu permintaan cukup untuk melihat kunjungan-kunjungan
sebuah anak, termasuk penimbangan, suntikan, dan keluhan pada tanggal yang
sama.

---

## 2. Ruang Lingkup

### 2.1 Yang dikerjakan (2A)

| Item | Sumber |
|------|--------|
| Halaman profil anak terpadu | `RANCANGAN.md:24` |
| Data demografi | `RANCANGAN.md:26` |
| Data antropometri (BB, TB, lingkar kepala) | `RANCANGAN.md:28` |
| Kondisi khusus / tagging (alergi, penyakit bawaan) | `RANCANGAN.md:30` |
| Catatan medis historis sebagai rekam jejak | `RANCANGAN.md:32` |

### 2.2 Yang TIDAK dikerjakan (2B) dan alasannya

`RANCANGAN.md:22` mewajibkan navigasi memisahkan data Balita dan Ibu Hamil.
Itu **tidak** termasuk pekerjaan ini, dengan alasan:

- Tabel `children` adalah satu-satunya tempat data pasien sekarang. Ibu hamil
  tidak punya entitas sama sekali.
- Menambahkan Ibu Hamil berarti membuat entity baru (kehamilan, kunjungan ANC,
  usia mengandung, funding), bukan menambah fitur ke buku medis.
- Belum ada kerangka rekam medis yang bisa menampungnya. Membangunnya sebelum
  timeline ada hanya menghasilkan dua layar yang tidak saling menyambung.

Rekomendasi: 2B jadi proyek tersendiri setelah 2A stabil.

### 2.3 Non-goals lain

- **Export PDF.** Ada di `RENCANA_SELANJUTNYA.md:75` tapi tidak sekarang.
- **Foto anak.** Butuh upload dan storage; tidak ada di MVP.
- **Grafik tumbuh kembang untuk Ibu (e-KMS).** Itu modul 3.2 A, bukan 3.1 A.
- **Riwayat carpal/riwayat timestamp-an per perubahan field.** Tidak ada.

---

## 3. Apa yang Sudah Ada (60%)

Buku medis ini **bukan** proyek dari nol. Yang sudah jadi:

| Kebutuhan | Sudah ada di |
|------------|--------------|
| Demografi anak | `Child` + `GET /children/{id}` |
| Riwayat penimbangan | `GET /measurements?child_id=` |
| Rekam suntikan + checklist | `GET /children/{id}/immunizations` |
| Keluhan + tindak lanjut | `GET /children/{id}/medical-notes` |
| Status gizi & z-score | Trigger PostgreSQL, sudah otomatis |
| Layar profil anak | `posyandu_mobile/lib/screens/kader/detail_anak_screen.dart` (522 baris) |
| Format label bulan | `posyandu_mobile/lib/utils/month_label.dart` |

`detail_anak_screen.dart` bahkan sudah diberi judul "Profil Medis Anak". Yang
kurang bukan tampilannya, melainkan **penyatuan**: layar itu mengambil riwayat
dari satu sumber saja.

---

## 4. Yang Benar-Benar Hilang

Cuma dua hal. Ini yang membuat fitur ini murah sekaligus jadi.

### 4.1 Satu endpoint timeline gabungan

Sekarang kader harus memanggil tiga endpoint lalu menggabungkan sendiri di
kepala. Yang baru: satu endpoint yang mengembalikan seluruh riwayat anak dalam
bentuk kronologis.

### 4.2 Penyimpanan kondisi khusus

`RANCANGAN.md:30` minta penanda visual untuk alergi dan penyakit bawaan. Tabel
`children` tidak punya kolom apa pun untuk ini, jadi ini satu-satunya model
data baru di proyek ini.

---

## 5. Keputusan yang Sudah Diputuskan

Kedua keputusan ini ditutup pada **29 September 2026**. Jangan dibuka lagi
tanpa alasan tertulis di bagian 13 - kalau nanti berubah, dokumen ini yang
harus diperbarui lebih dulu.

### 5.1 Kondisi khusus = KOLOM di `children` (bukan tabel terpisah)

| | |
| :--- | :--- |
| Keputusan | `children.medical_flags` |
| Tipe kolom | `text`, **nullable**, tanpa batasan CHECK |
| Batas panjang | 500 karakter (divalidasi di `ChildController@update`, bukan di database) |
| Format isi | Teks bebas, satu penanda per baris, mis. `alergi: penisilin` + `asma`. **Tidak diparsing**, ditampilkan apa adanya |
| Tabel `child_medical_flags` | **Tidak dibuat.** Bagian 6.2 di bawah jadi tidak berlaku |
| Endpoint CRUD baru | **Tidak ada.** Penanda ditulis lewat `PATCH /children/{id}` yang sudah ada |

Alasan: untuk MVP, most Posyandu menulis penanda sekali dan jarang
mengubahnya. Tabel terpisah baru layak kalau nanti ada pertanyaan "alergi ini
sejak kapan" atau lebih dari satu jenis penanda per anak yang perlu dilacak
sejarahnya.

Konsekuensi yang harus diterima, supaya tidak dianggap bug nanti:

1. Tidak ada riwayat perubahan penanda. Kalau nanti mau tahu siapa yang
   menulis, jawabannya memang tidak tersimpan.
2. Kader dan Ibu membaca nilai yang sama, apa adanya, tanpa normalisasi.
3. `GET /children/{id}` **ikut membawa** `medical_flags` karena controller
   itu men-serialize model secara langsung. Field lama tidak berubah apa pun;
   ini penambahan murni (lihat bagian 7.4).

### 5.2 Timeline = PER KUNJUNGAN (dikelompokkan per tanggal)

Satu tanggal = satu entri `entries[]`, di dalamnya ada `measurement`
(nullable), `immunizations` (array), dan `medical_note` (nullable). Bukan satu
baris per kejadian.

Alasan: satu kunjungan ke Posyandu hampir selalu menghasilkan penimbangan,
keluhan, dan suntikan pada tanggal yang sama. Kalau dipisah per kejadian, satu
kunjungan jadi tiga baris terpisah dan kader harus membacanya sebagai satu
kesatuan. Bentuknya ada di bagian 7.2; urutan isi di dalam satu tanggal ada di
bagian 8.2.

---

## 6. Rancangan Data

### 6.1 Timeline: tidak butuh tabel baru

Timeline bukan tabel. Dia hasil penggabungan tiga tabel yang sudah ada
(`measurements`, `immunization_records`, `medical_notes`) berdasarkan
`child_id`, lalu dikelompokkan per tanggal. Tidak ada tabel baru dan tidak ada
duplikasi data.

### 6.2 Pilihan tabel yang TIDAK dipakai

Bagian ini sengaja disimpan, bukan dihapus, supaya tidak ada yang mengulang
diskusi tabel-versus-kolom. Keputusan 29 September 2026 memilih kolom, jadi
rancangan di bawah ini **tidak akan diimplementasikan**:

```
child_medical_flags
  id          uuid PK
  child_id    uuid FK -> children.id  (cascade delete)
  kind        string   'alergi' | 'penyakit_bawaan' | 'lainnya'
  label       string   contoh: 'penisilin', 'asma'
  note        text     nullable
  created_at, updated_at
  UNIQUE (child_id, kind, label)
```

Kalau suatu saat tabel ini benar-benar dipakai, itu harus lewat perubahan
dokumen di bagian 5.1 lebih dulu, bukan langsung menulis migration.

---

## 7. Rancangan Endpoint

### 7.1 Rute

```
GET /api/children/{id}/timeline
```

Harus masuk group yang sama dengan `GET /children/{id}` supaya aturan aksesnya
tidak berbeda: Ibu hanya boleh melihat anaknya sendiri, Kader boleh melihat
semua anak.

Query string:

| Parameter | Default | Validasi | Keterangan |
|-----------|---------|----------|------------|
| `limit` | 50 | `integer`, `min:1`, `max:200` | Jumlah **tanggal** kunjungan, bukan jumlah baris data |
| `before` | - | `date_format:Y-m-d` | Cursor tanggal untuk load halaman berikutnya |

`before` **tidak** memakai `before_or_equal:today`. Riwayat harus tetap bisa
dibaca setelah tanggal lewat; yang tidak boleh adalah tanggal yang tidak
pernah ada seperti `2026-13-45`, dan itu sudah tertangkap `date_format`.

Cara memperoleh halaman berikutnya: kirim `before` dengan nilai
`meta.next_before` dari halaman sebelumnya. `next_before` bernilai `null`
kalau tidak ada halaman berikutnya.

### 7.2 Bentuk respons

```json
{
  "success": true,
  "message": "Riwayat medis anak berhasil diambil.",
  "data": {
    "child": {
      "id": "uuid",
      "name": "Siti",
      "nik": "3273...",
      "date_of_birth": "2024-03-12",
      "age_in_months": 30,
      "gender": "P",
      "mother": { "name": "Ibu A", "nik": "3273..." },
      "medical_flags": "alergi: penisilin\nasma",
      "latest_measurement": { "weight_kg": 12.4, "status_gizi": "Normal" }
    },
    "entries": [
      {
        "date": "2026-09-24",
        "measurement": {
          "weight_kg": 12.4,
          "height_cm": 88.0,
          "head_circumference_cm": 47.5,
          "z_score_wfa": 0.21,
          "status_gizi": "Normal",
          "kader": { "id": "uuid", "name": "Kader 1" }
        },
        "immunizations": [
          { "type": "HB-0", "date_given": "2026-09-24" }
        ],
        "medical_note": {
          "demam": true,
          "rewel": false,
          "diare": false,
          "catatan": "Demam sejak 2 hari",
          "tindak_lanjut": "rujuk"
        }
      }
    ],
    "meta": { "has_more": true, "next_before": "2026-08-15" }
  }
}
```

Tiga kunci di dalam `entries` boleh `null`. Tanggal tanpa penimbangan tapi ada
keluhan tetap muncul sebagai entri — itu kunjungan yang sah.

### 7.3 Aturan yang tidak boleh dilanggar

Tujuh aturan ini **normatif**, sama sifatnya dengan aturan rekap. Setiap aturan
dipetakan ke satu nama test di `tests/Feature/ChildTimelineTest.php`, jadi
"aturan ini sudah dipatuhi" bisa dibuktikan, bukan diklaim. Test dengan nama
itu tidak boleh dihapus atau di-rename tanpa memperbarui tabel ini.

| # | Aturan (WAJIB) | Test yang membuktikannya |
| :--- | :--- | :--- |
| 1 | **Tanggal turun.** `entries` selalu urut dari yang terbaru. | `entries_selalu_urut_dari_tanggal_terbaru` |
| 2 | **Baris yang dibatalkan tidak muncul.** Semua tiga tabel memakai `deleted_at`; timeline hanya membaca yang `deleted_at IS NULL`. | `baris_yang_dibatalkan_tidak_muncul_di_timeline` |
| 3 | **Keluhan tetap tampil walau penimbangannya dibatalkan.** Ini konsekuensi dari perilaku `medical_notes.measurement_id` yang sudah didokumentasikan di `DATABASE_SCHEMA.md`. Timeline **tidak boleh** menyembunyikan keluhan hanya karena `measurement` di entri itu `null`. | `keluhan_tetap_muncul_walau_penimbangan_tertaut_dibatalkan` |
| 4 | **Tidak ada penghitungan ulang.** Z-score, status gizi, dan status imunisasi semuanya dibaca apa adanya dari server. Klien dan server ini sama-sama tidak menghitung. | `nilai_z_score_dibaca_dari_database_tanpa_dihitung_ulang` |
| 5 | **Satu tanggal satu entri.** Dua penimbangan pada tanggal yang sama tidak mungkin terjadi (partial unique index), tapi dua suntikan pada tanggal yang sama boleh, dan keduanya masuk ke array `immunizations`. | `dua_suntikan_tanggal_sama_masih_satu_entri` |
| 6 | **Tanpa data tetap 200.** Anak yang belum pernah ditimbang punya `entries: []`, bukan 404. | `anak_tanpa_data_punya_entries_kosong` |
| 7 | **`limit` menghitung tanggal, bukan baris.** Kalau satu tanggal punya 3 suntikan, itu tetap satu entri. | `limit_menghitung_tanggal_bukan_baris` |

Dua aturan tambahan yang berasal dari bagian 5 dan bagian 7.1, dengan test
yang sama:

| Aturan (WAJIB) | Test yang membuktikannya |
| :--- | :--- |
| Ibu hanya boleh membuka timeline anaknya sendiri; selain itu `403`. | `ibu_membuka_anak_orang_ditolak` |
| `id` bukan UUID membalas `404`, bukan `500` dari error PostgreSQL. | `id_bukan_uuid_membalas_404` |
| `limit` di luar 1-200 dan `before` bukan `Y-m-d` membalas `422`. | `parameter_tidak_valid_membalas_422` |
| Penanda kondisi khusus **hanya boleh ditulis Kader**; Ibu tidak. | `ibu_tidak_bisa_menulis_medical_flags`, `kader_bisa_menulis_medical_flags` |
| `medical_flags` anak terbaca apa adanya di respons timeline. | `medical_flags_terbaca_apa_adanya` |

### 7.4 Endpoint lain yang berubah

`GET /children/{id}` **ikut membawa** `medical_flags` tanpa kode tambahan,
karena `ChildController@show` men-serialize model secara langsung. Field lama
tidak berubah apa pun, jadi ini penambahan murni dan aman untuk backward
compatibility. Konsekuensi yang sama berlaku pada `GET /children` dan
`GET /kader/children`.

### 7.5 Kompatibilitas: yang tidak boleh berubah

Bagian ini ada supaya fitur ini tidak merusak yang sudah jalan. Versi yang
dipakai agent ada di `posyandu-backend/.ai/rules/yang-jangan-diubah.md`.

| Yang tidak boleh berubah | Kenapa | Sumber kebenaran |
| :--- | :--- | :--- |
| 29 route API yang ada sebelum Opsi B | Mobile sudah memakainya semua. Opsi B menambah tepat 1 route, jadi 30 — `php artisan route:list` harus mengembalikan 30 route `api/` | `routes/api.php` |
| Bentuk `success` / `message` / `data` dan `errors` | Parser Flutter bergantung pada itu | `docs/AI_AGENT_RULES.md` bagian 8 |
| Field lama di respons `GET /children/{id}` | Ibu dan mobile sudah membacanya | `docs/API_CONTRACT.md` |
| NIK tidak pernah ikut di `GET /petugas` | Privasi petugas | `PetugasController` |
| Z-score, `age_in_months`, `status_gizi` hanya dari trigger PostgreSQL | Aturan pemisahan DB vs logika aplikasi | `docs/AI_AGENT_RULES.md` bagian 9 |
| Urutan baris `by_type` dan baris CSV = urutan master suntikan | Kontrak yang diubah pada commit `6a8d2ed` | `ImmunizationType::scopeOrderedForDosing()` |
| Partial unique index + soft delete di tiga tabel | Suntikan, penimbangan, atau keluhan yang dibatalkan harus bisa dicat ulang | migration `2026_09_26_035000`, `2026_09_27_010000` |
| `kader_id` nullable + `ON DELETE SET NULL` | Menghapus akun kader tidak boleh menghapus riwayat kesehatan anak | `2026_09_26_032000` |
| Test hanya jalan di PostgreSQL `posyandu_test` | Test di SQLite hijau tanpa menguji partial index dan trigger | `tests/TestCase.php` |
| Database dev `posyandu_db` tidak boleh tersentuh test | `RefreshDatabase` menghapus seluruh tabel | `tests/TestCase.php` |

---

## 8. Rancangan Layar Mobile

Bukan layar baru. `detail_anak_screen.dart` yang sekarang sudah jadi tempat
yang tepat; tugasnya ditambah, bukan dipecah.

### 8.1 Penanda kondisi khusus

> **Status: selesai 29 September 2026.** Badge ada di
> `detail_anak_screen.dart` (`_buildBadgeKondisiKhusus`), data dari
> `TimelineChild.medicalFlags` atau `Child.medicalFlags`.

Karena keputusan 5.1 = kolom, tampilan paling sederhana: badge berwarna di
bawah nama anak, merah untuk alergi, kuning untuk penyakit bawaan. Teks mentah
ditampilkan apa adanya, tanpa ikon per jenis - karena daftar jenis tidak
dikunci database.

### 8.2 Timeline

> **Status: selesai 29 September 2026.** Implementasi ada di
> `posyandu_mobile/lib/models/child_timeline.dart`,
> `posyandu_mobile/lib/services/child_timeline_service.dart`, dan
> `posyandu_mobile/lib/screens/kader/detail_anak_screen.dart`.

- Dikelompokkan per bulan, judul memakai `labelBulan()` dari
  `month_label.dart` supaya konsisten dengan layar lain.
- Di dalam satu tanggal, urutan tampilan: penimbangan, lalu suntikan, lalu
  keluhan. Alasan: kader paling sering datang untuk "berapa beratnya" dulu.
- Tanggal yang punya keluhan tapi tanpa penimbangan tetap tampil, dengan
  catatan visual bahwa penimbangan tidak ada.
- Tombol "Muat lebih banyak" untuk `meta.has_more`.
- Muat ulang memakai tombol refresh yang **sudah ada** di baris
  "Penimbangan Terakhir" (`IconButton(Icons.refresh)` yang sekarang memanggil
  `_muatUlangSemua()`), bukan pull-to-refresh. Layar ini memang tidak punya
  `RefreshIndicator` - itu sudah dicek langsung di
  `detail_anak_screen.dart` pada 29 September 2026.

### 8.3 Apa yang tidak berubah

Judul layar, warna header, dan navigasi ke layar imunisasi serta keluhan yang
sudah ada. Tetap satu layar yang sama: ini tambahan isi, bukan layar baru.

---

## 9. Rencana Pengujian

Mengikuti pola yang sudah dipakai proyek ini, karena polanya sudah terbukti
menangkap bug nyata.

| Lapisan | Isi | Status |
|---------|-----|--------|
| Feature test PHP | Hit HTTP endpoint sungguhan, cek aturan 1–7 satu per satu | Selesai (21 test) |
| `uji-api.ps1` grup baru | Cek aturan 1–7 lewat HTTP, termasuk 403 untuk Ibu | Belum ditulis |
| Flutter test | Parsing model timeline terhadap JSON asli, bukan JSON buatan | Selesai (13 test) |
| Manual | Buka di emulator, scroll ke bawah | Belum dilakukan |

> **Peringatan dari pelajaran terakhir.** `MeasurementRecapTest` pernah hijau
> karena kebetulan: `ChildFactory` mengisi `date_of_birth` acak sementara test
> memakai tanggal hardcode, dan trigger menolak penimbangan sebelum tanggal
> lahir. Peluang gagalnya sekitar 12% per jalannya.
>
> Untuk fitur ini: kalau test memakai tanggal hardcode, anak di dalamnya **wajib**
> dibuat dengan `date_of_birth` pasti lewat helper, bukan `Child::factory()`
> polos. Jangan mengulang kesalahan yang sama.

Feature test minimal ada di **bagian 7.3**, yang memetakan setiap aturan ke
nama test-nya. Daftar di sini sengaja tidak diulang: dua daftar yang bisa
berbeda jauh lebih berbahaya daripada satu daftar yang lengkap. Test yang
tidak punya pasangan di 7.3 berarti ada aturan yang belum dipatuhi.

Test tambahan di luar daftar 7.3 (semua sudah ada di `ChildTimelineTest`):

- [x] `ibu_membuka_anak_anaknya_sendiri_membalas_200`
- [x] `medical_flags_kosong_dibaca_sebagai_null`
- [x] `cursor_before_melanjutkan_dari_tanggal_terakhir`
- [x] `kader_bisa_menulis_medical_flags`
- [x] `ibu_tidak_bisa_menulis_medical_flags`
- [x] `medical_flags_terbaca_apa_adanya`
- [x] `medical_flags_lebih_dari_500_karakter_menolak_422`
- [x] `data_tepat_berisi_tiga_kunci`
- [x] `jumlah_query_tetap_walaupun_tanggal_banyak`
- [x] `penimbangan_tanpa_kader_tetap_tampil`
- [x] `riwayat_lama_tetap_bisa_dibaca`

---

## 10. Urutan Kerja

Urutan ini disengaja supaya tidak pernah ada layar yang memakai endpoint yang
belum ada.

1. ~~**Commit dulu** apa yang sekarang ada.~~ **Selesai 29 September 2026.**
   Empat commit di `main`: pengujian/factory, backend rekap+CSV, mobile rekap,
   dokumentasi. Working tree bersih. **Push masih tertunda** - environment-nya
   tidak punya kredensial GitHub. Setelah commit urutan dosis (`6a8d2ed`)
   ditambahkan, `main` sekarang **5 commit di depan `origin/main`**. Push ulang
   begitu kredensial tersedia; tidak ada konflik yang mungkin muncul karena
   belum ada yang lain menyentuh repo ini.

2. ~~**Perbaiki urutan dosis kronologi**~~ **Selesai 29 September 2026.**
   `ImmunizationType::scopeOrderedForDosing()` sekarang `ORDER BY
   target_age_months ASC NULLS LAST, code, dose_number`. Diuji di
   `ImmunizationTypeOrderTest` (5 test, master 16 dosis dari seeder) plus satu
   test di `ImmunizationRecapTest` untuk `by_type`. Kontrak yang berubah: urutan
   baris `by_type` dan baris tabel CSV, jadi klien yang mengurutkan ulang
   sendiri harus dihentikan.

3. ~~**Kunci spesifikasi dan aturan**~~ **Selesai 29 September 2026.**
   Dua keputusan di bagian 5 ditutup, inventaris kompatibilitas ditulis di
   bagian 7.5, dan aturan agent dibuat di
   `posyandu-backend/.ai/rules/` (`kontrak-timeline.md`,
   `yang-jangan-diubah.md`, `pengujian.md`). Langkah ini sengaja mendahului
   semua kode: kalau spesifikasi berubah setelah ada kode, ketidaksepakatan
   antar file jauh lebih mahal daripada satu revisi dokumen.

4. ~~**Migration** kolom `medical_flags` (`text`, nullable).~~ **Selesai
   29 September 2026.** `2026_09_29_010000_add_medical_flags_to_children_table.php`.
   Tanpa CHECK constraint: batas 500 karakter divalidasi di controller supaya
   salah ketik jadi 422, bukan error PostgreSQL.
5. ~~**Model + service** timeline di backend.~~ **Selesai 29 September 2026.**
   `ChildTimelineService` memakai empat query: satu `UNION` untuk daftar tanggal,
   tiga untuk isi jendela. Jumlahnya tidak bergantung pada jumlah tanggal.
6. ~~**Endpoint + feature test.**~~ **Selesai 29 September 2026.**
   `GET /children/{id}/timeline` di group yang sama dengan `GET /children/{id}`.
   `ChildTimelineTest` 21 test, semua nama di 7.3 terpakai.
7. ~~**Dokumentasi.**~~ **Selesai 29 September 2026.** `API_CONTRACT.md`
   (dua endpoint + kode error), `DATABASE_SCHEMA.md` (kolom baru + alasannya),
   `docs/LAPORAN_BUKU_MEDIS.md`.
8. ~~**Mobile**~~ **Selesai 29 September 2026.** Model `child_timeline.dart`,
   service `child_timeline_service.dart`, `medicalFlags` di `Child`, konstanta
   `childTimelineEndpoint`, dan integrasi `detail_anak_screen.dart` (badge
   kondisi khusus + section Buku Medis + pagination + refresh gabungan).
   105 test hijau, `flutter analyze` bersih.
9. **Verifikasi akhir**: Pint dan test backend sudah hijau (96 test / 364
   assertion). `uji-api.ps1` belum ditulis; `flutter analyze` / `flutter test`
   sudah hijau (105 test).

---

## 11. Estimasi

| Bagian | Estimasi |
|--------|----------|
| Kolom `medical_flags` + endpoint + test | 1 hari |
| Layar timeline | 1 hari |
| Dokumentasi + verifikasi | 0,5 hari |
| **Total** | **2,5–3 hari** |

Lebih cepat dari angka 4–6 hari di `RENCANA_SELANJUTNYA.md:66` karena data
dasarnya sudah lengkap. Angka lama itu perkiraan saat tabel rekap belum ada.

Fase 0 (dokumentasi + aturan) sudah menambah 0,5 hari dari estimasi di atas dan
sudah selesai pada 29 September 2026. Angka 1,5–2,5 hari di atas berlaku untuk
implementasi backend yang belum dimulai.

Kalau nanti keputusan 5.1 dibalik menjadi tabel, tambah 1–1,5 hari.

---

## 12. Pertanyaan yang Sudah Ditutup

Tiga pertanyaan ini ikut diputuskan pada 29 September 2026, bukan "masih
terbuka":

| Pertanyaan | Jawaban | Alasan |
| :--- | :--- | :--- |
| Apakah Ibu boleh melihat `medical_flags` anak sendiri? | **Ya** | Itu hak informasi orang tua, dan isinya bukan data Posyandu |
| Siapa yang boleh mengubah penanda? | **Kader saja** | Kalau Ibu juga boleh menulis, ada dua sumber perubahan untuk data yang sama |
| Apakah timeline perlu batas waktu? | **Tidak** | Cursor `before` sudah menangani itu; batas waktu tambahan hanya menyembunyikan riwayat |

Kalau ada pertanyaan baru muncul selama implementasi, jawabannya ditulis di
bagian ini, bukan disimpan di commit atau komentar kode.

---

## 13. Riwayat Perubahan

| Tanggal | Perubahan |
|---------|-----------|
| 28 Sep 2026 | Rancangan awal ditulis. Belum ada kode yang dibuat untuk fitur ini. |
| 29 Sep 2026 | Spesifikasi dikunci: keputusan 1 = kolom `children.medical_flags`, keputusan 2 = timeline per kunjungan. Tiga pertanyaan di bagian 12 ditutup. Tujuh aturan di 7.3 dipetakan ke nama test. Inventaris kompatibilitas ditulis di 7.5. Aturan agent dibuat di `posyandu-backend/.ai/rules/`. Belum ada kode fitur yang ditulis. |
| 29 Sep 2026 | Fase 1 backend selesai. Migration `medical_flags`, `ChildTimelineService` (4 query), `GET /children/{id}/timeline`, validasi kader-saja untuk `medical_flags`, dan `ChildTimelineTest` 21 test. Semua aturan 1-7 terbukti hijau; 96 test total. Dokumentasi di `API_CONTRACT.md`, `DATABASE_SCHEMA.md`, `LAPORAN_BUKU_MEDIS.md`. Mobile belum disentuh. |
| 29 Sep 2026 | Fase 2 mobile selesai. Model `child_timeline.dart`, service `child_timeline_service.dart`, `medicalFlags` di `Child`, konstanta `childTimelineEndpoint`, integrasi `detail_anak_screen.dart` (badge kondisi khusus + section Buku Medis + pagination + refresh gabungan). 105 test hijau, `flutter analyze` bersih, `dart format` 39 file. |
| 1 Okt 2026 | Judul dan baris status yang masih menyebut "mobile belum dikerjakan" dikoreksi menjadi selesai. `RENCANA_SELANJUTNYA.md` diperbarui: Opsi B ditandai selesai dan Opsi D (grafik tumbuh kembang) masuk sebagai kandidat berikutnya, rancangannya di `RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md`. |
