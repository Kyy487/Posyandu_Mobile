# Rancangan Indikator WHO Multidimensi di Grafik Tumbuh

**Tanggal:** 15 Oktober 2026
**Status:** **selesai 15 Oktober 2026** — kode backend, migration, test, amendemen
dokumen, dan sisi mobile (model, widget pemilih tiga metrik, kartu multidimensi)
sudah ditulis. Verifikasi: `GrowthChartTest` 33 test, `WhoZScoreTriggerTest` 4
test, suite backend 224 test / 1995 assertion, `pint` bersih, `flutter analyze`
bersih, `flutter test` 214 test.
**Acuan:** `docs/RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md` (normatif, mendahului
dokumen ini), `docs/PERANCANGAN_PERKUATAN.md` §8, `docs/STATUS_PENGEMBANGAN.md`
**Branch:** `riezky`

> **Dokumen ini mengamendemen `RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md`, bukan
> menggantikannya.** Bagian 5.1 dan 6.2 dokumen lama menyatakan "database tidak
> punya acuan TB/U, jadi tidak akan pernah ada pita tinggi badan". Pernyataan itu
> benar saat ditulis (1 Oktober 2026) tetapi **sudah tidak benar** sejak
> P0-2 (10 Oktober 2026) menambah tabel acuan HFA/BFA/WFH dan kolom multidimensi.
> Rancangan ini menutup jarak antara kenyataan database dan kontrak yang masih
> berbunyi BB/U-saja.
>
> Aturan mengikat agent ada di `posyandu-backend/.ai/rules/`:
> `yang-jangan-diubah.md`, `kontrak-growth.md`, dan `pengujian.md`. Sesuai
> `yang-jangan-diubah.md`, **dokumen lama diubah lebih dulu**, baru kodenya.

---

## 1. Tujuan

Backend sudah menghitung empat indikator WHO untuk setiap penimbangan sejak
P0-2 (10 Oktober 2026): BB/U, TB/U, IMT/U, dan BB/TB. Yang belum ada adalah
**jembatan ke layar**: `GET /children/{id}/growth` hanya mengirim `z_score_wfa`
dan `status_gizi`, dan grafik Flutter hanya menggambar berat badan (dengan pita)
serta tinggi badan (tanpa pita).

Ibu dan Kader tidak pernah bisa melihat stunting atau status IMT anaknya,
padahal angkanya sudah tersimpan rapi di baris `measurements`. Setelah fitur ini
jadi, grafik tumbuh menampilkan **tiga pita WHO** (BB/U, TB/U, IMT/U) dengan
status masing-masing, ditambah nilai BB/TB. Semua angka tetap datang dari
trigger PostgreSQL; layar hanya membaca.

---

## 2. Apa yang sudah ada (titik awal yang sebenarnya)

### 2.1 Kolom multidimensi di `measurements`

Migration `2026_10_10_104713_add_who_multidim_columns_to_measurements.php` dan
`2026_10_10_112842_create_who_wfh_standards_table.php` menambah:

| Kolom | Sumber | Rentang |
| :--- | :--- | :--- |
| `z_score_wfa` | `who_wfa_standards` (median_kg, sd_kg) | 0–60 bulan |
| `status_gizi` | BB/U (lihat koreksi 2.3) | 0–60 bulan |
| `z_score_hfa` | `who_hfa_standards` (l, m, s) | 0–60 bulan |
| `status_stunting` | TB/U | 0–60 bulan |
| `z_score_bfa` | `who_bfa_standards` (l, m, s) | 0–60 bulan |
| `status_gizi_imt` | IMT/U | 0–60 bulan |
| `z_score_wfh` | `who_wfh_standards` (l, m, s) | **< 24 bulan**, indeks `length_cm` |

Semuanya nullable. Trigger `calculate_measurement_who_zscore` mengosongkan
seluruhnya lebih dulu, lalu hanya mengisi yang acuannya ketemu (lihat
`2026_10_12_000000_restore_wfa_only_status_gizi_trigger.php` baris 77–138).

### 2.2 Tabel acuan yang sudah di-seed

| Tabel | Kolom acuan | Kunci unik |
| :--- | :--- | :--- |
| `who_wfa_standards` | `median_kg`, `sd_kg` | (age_in_months, gender) |
| `who_hfa_standards` | `l`, `m`, `s` | (age_in_months, gender) |
| `who_bfa_standards` | `l`, `m`, `s` | (age_in_months, gender) |
| `who_wfh_standards` | `l`, `m`, `s` | (length_cm, gender) |

Ketiganya 61 baris per gender (0–60 bulan) kecuali WFH yang diindeks panjang
badan. Tidak ada tabel baru yang dibutuhkan rancangan ini.

### 2.3 Koreksi penting: `status_gizi` adalah BB/U, bukan komposit

Migration `2026_10_12_000000_restore_wfa_only_status_gizi_trigger.php`
mengembalikan `status_gizi` ke semantik **BB/U saja**. Sebelumnya (migration
P0-2 `2026_10_10_104811`) trigger sempat menulis `status_gizi` sebagai status
terburuk dari empat indikator; itu dibatalkan karena (a) selalu di-`COALESCE`
jadi `"Normal"` untuk anak di luar rentang, dan (b) membuat titik yang ada di
dalam pita BB/U bisa berlabel "Gizi Buruk".

Konsekuensi untuk rancangan ini: **`status_gizi` tetap satu-satunya status
BB/U.** Status TB/U (`status_stunting`), IMT/U (`status_gizi_imt`), dan BB/TB
(dilihat §4.6) adalah kolom/kunci **terpisah**. Layar tidak boleh menyimpulkan
satu status dari status lainnya.

### 2.4 Yang belum dijembatani

- `GrowthChartService::points()` hanya `SELECT` `z_score_wfa` + `status_gizi`.
- `GrowthChartService::whoReference()` hanya membaca `who_wfa_standards`.
- `ChildTimelineService::measurementsIn()` juga hanya memilih `z_score_wfa` +
  `status_gizi` (di luar cakupan rancangan ini; lihat §4.7).
- `Measurement::$fillable` belum memuat kolom multidimensi, tetapi Eloquent
  mengembalikan seluruh kolom saat read, jadi `POST`/`GET /kader/measurements`
  sebenarnya sudah mengirimnya tanpa didokumentasikan.
- Mobile `growth_chart.dart` dan `growth_line_chart.dart` sama sekali tidak
  mengenal field multidimensi.

---

## 3. Ruang Lingkup

### 3.1 Yang dikerjakan

| Item | Bentuk |
| :--- | :--- |
| **BB/U** | Nilai + pita + status (sudah ada, dipertahankan apa adanya) |
| **TB/U** | Nilai (`height_cm`) + **pita baru** + `status_stunting` |
| **IMT/U** | Nilai baru (`bmi`) + **pita baru** + `status_gizi_imt` |
| **BB/TB** | Nilai `z_score_wfh` + status, **tanpa pita** (sumbunya panjang badan, bukan umur) |
| Grafik mobile | Pemilih metrik: BB/U, TB/U, IMT/U (satu pita per grafik) |
| Kartu BB/TB | Nilai + status untuk anak < 24 bulan |

### 3.2 Yang TIDAK dikerjakan dan alasannya

| Yang ditunda | Alasan |
| :--- | :--- |
| **Pita BB/TB** | Sumbu acuan BB/TB adalah panjang badan, sedangkan tiga grafik lain bersumbu umur. Menyatukannya berarti sumbu x berbeda arti antar grafik, dan itu lebih membingungkan daripada satu kartu nilai. |
| **Grafik lingkar kepala** | Tidak ada acuan WHO LK di database dan tidak ada ambang batas. Tetap seperti keputusan lama. |
| **Grafik BB/TB sebagai kurva** | BB/TB 0–24 bulan sudah cukup ditampilkan sebagai nilai + status. Kurva yang sumbunya bukan umur tidak bisa dibaca berdampingan dengan tiga kurva lain. |
| **Ekspor PDF / gambar** | Butuh package tambahan. Tidak ada di MVP. |
| **Indikator di `/timeline`** | Endpoint timeline sengaja ramping dan dipakai untuk hal lain; membuka multidimensi di sana adalah pekerjaan terpisah. Lihat §4.7. |
| **Validasi klinis** | Sudah dijadwalkan terpisah di `RENCANA_KERJA_BERIKUTNYA.md` §4.3 (butuh bantuan dosen). |

---

## 4. Keputusan yang Diputuskan

### 4.1 Aditif di `GET /children/{id}/growth`, bukan endpoint baru

Tidak ada route baru. `GET /children/{id}/growth` yang sudah ada di group
`ibu,kader` ditambah field. Alasannya:

1. Tidak ada nomor route yang bertambah (tetap 31 registrasi `api/`).
2. Otorisasi tetap pakai `findChildForUser()`; tidak ada jalan kedua membaca
   data anak yang harus diaudit terpisah.
3. Field baru aman: parser Flutter mengabaikan field yang tidak dikenal
   (`yang-jangan-diubah.md`).

### 4.2 `data` menjadi empat kunci — amendemen sadar

Sekarang: `child`, `series`, `who_reference`. Setelah fitur ini:
`child`, `series`, `who_reference`, **`who_references`**.

`who_reference` (tunggal, WFA) **tidak diubah dan tidak dihapus** supaya klien
lama tetap jalan. `who_references` (jamak) adalah daftar tiga metrik
BB/U, TB/U, IMT/U dengan bentuk seragam (lihat §6.2). WFA muncul di keduanya —
itu disengaja untuk kompatibilitas, dan test memastikan keduanya konsisten.
Aturan "`data` berisi tepat tiga kunci" di `RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md`
§7.3 dan `kontrak-growth.md` **wajib diubah** menjadi "empat kunci" sebelum
kode ditulis.

### 4.3 Jumlah query tetap dua

Aturan `jumlah_query_tetap_dua` tetap berlaku. Pita tiga metrik dibaca dengan
**satu** `UNION ALL` atas `who_wfa_standards`/`who_hfa_standards`/
`who_bfa_standards` (satu query), bukan tiga query. `who_reference` tunggal
di-`slice` dari hasil query yang sama di PHP — tidak ada query tambahan. Total
tetap: satu query titik penimbangan + satu query pita.

### 4.4 Pita HFA/BFA dihitung di SQL dari konstanta WHO

`who_hfa_standards` dan `who_bfa_standards` menyimpan `l`, `m`, `s`, bukan
median/sd. Batas pita `z = -2`, median `z = 0`, dan batas `z = +2` dihitung
dengan rumus **inverse LMS** WHO di SQL:

```sql
CASE WHEN l = 0 THEN m * exp(s * z)
     ELSE m * power(1 + l * s * z, 1.0 / l) END
```

Ini **bukan** menghitung ulang z-score anak dan bukan menghitung median WHO di
PHP/Dart. Ini membaca konstanta referensi dari tabel yang sama yang dipakai
trigger, lalu mengevaluasinya di tiga nilai z tetap — persis seperti pita BB/U
yang boleh dihitung `median_kg - 2 * sd_kg` di SQL menurut
`kontrak-growth.md`. Angka `z_score_hfa`/`z_score_bfa` anak **tidak pernah**
diturunkan dari pita ini; keduanya dibaca apa adanya dari kolom trigger.

### 4.5 BMI anak dihitung di SQL

IMT/U dipetakan sebagai grafik dengan sumbu y `kg/m²`. Agar titik anak bisa
disejajarkan dengan pita BFA, service mengirim `bmi` per titik, dihitung di SQL:

```sql
CASE WHEN height_cm IS NOT NULL AND height_cm > 0
     THEN round(weight_kg / power(height_cm / 100.0, 2), 2)
     ELSE NULL END AS bmi
```

BMI adalah turunan antropometri sederhana (bukan z-score dan bukan median WHO),
jadi menghitungnya di SQL tidak melanggar aturan apa pun. Menghitungnya di Dart
justru yang dilarang pola repo ini: satu rumus, satu tempat.

### 4.6 BB/TB: nilai + status — **butuh satu keputusan skema**

Ini satu-satunya titik yang membuka migrasi, dan sengaja disorot.

Kenyataan: trigger mengisi `z_score_wfh` **tetapi tidak menyimpan status BB/TB**.
Tidak ada kolom `status_wfh`. Sementara aturan repo mengunci
"z-score dan **status** hanya dihitung PostgreSQL" (`yang-jangan-diubah.md`):
memetakan z-score → teks ("Gizi Kurang" dst.) di PHP berarti menggandakan
klasifikasi yang sudah hidup di trigger.

Dua pilihan:

| | Opsi A — tambah `status_wfh` (direkomendasikan) | Opsi B — tanpa migrasi |
| :--- | :--- | :--- |
| Skema | Migration aditif baru: kolom `status_wfh` di `measurements` + `CREATE OR REPLACE FUNCTION` trigger mengisinya | Tidak ada perubahan skema |
| Yang tampil | `z_score_wfh` + `status_wfh` (kategori sama: Gizi Buruk/Kurang/Risiko Gizi Lebih/Normal) | `z_score_wfh` saja, tanpa teks status |
| Sesuai aturan | Ya — status tetap dihitung PostgreSQL | Ya — tidak ada klasifikasi di PHP |
| Risiko | Trigger tersentuh lagi; seluruh perilaku z-score harus diuji ulang | BB/TB kurang "satu teks" dibanding tiga indikator lain |

**Diputuskan 15 Oktober 2026: Opsi A.** Migration aditif: `ALTER TABLE
measurements ADD COLUMN status_wfh` + `CREATE OR REPLACE FUNCTION` trigger
mengisinya (mengikuti preseden `2026_10_12_000000_...`, yang juga tidak
mengedit migration lama). Kategori teks memakai himpunan yang sama dengan
`status_gizi`: `Gizi Buruk`, `Gizi Kurang`, `Risiko Gizi Lebih`, `Normal`.
Karena trigger tersentuh lagi, seluruh perilaku z-score existing wajib diuji
ulang (lihat §8).

### 4.7 Mobile: satu metrik per grafik, bukan dual-axis

Grafik sekarang menumpuk BB (kg, sumbu kiri + pita) dan TB (cm, sumbu kanan)
dalam satu kanvas. IMT/U menambah satuan ketiga (kg/m²) yang **tidak bisa**
dipetakan ke kanvas yang sama. Menambah pita TB di sumbu kanan juga berarti dua
pita berbeda satuan bertumpuk — dua area abu-abu yang sulit dibedakan.

Karena itu grafik diubah menjadi **pemilih satu metrik**: BB/U, TB/U, IMT/U.
Setiap pilihan menggambar satu kurva dengan pitanya sendiri, satu sumbu y, dan
sumbu x tetap umur. Ini lebih sederhana dibaca daripada tiga pita bertumpuk.
BB/TB tidak masuk grafik (sumbunya panjang badan); ia jadi kartu nilai.

---

## 5. Rancangan Data

### 5.1 Tidak ada tabel acuan baru

Ketiga pita memakai tabel yang sudah ada (§2.2). Satu-satunya perubahan skema
adalah kolom baru `status_wfh` (§4.6).

### 5.2 Bentuk baca pita seragam

Setiap titik pita, apa pun metriknya, berbentuk sama:

```
{ "age_in_months": 30, "median": 13.3, "lower": 11.2, "upper": 15.7 }
```

- BB/U: `median = median_kg`, `lower = median_kg - 2*sd_kg`,
  `upper = median_kg + 2*sd_kg`.
- TB/U: dievaluasi dari `(l, m, s)` HFA di `z = -2, 0, +2`, satuan cm.
- IMT/U: dievaluasi dari `(l, m, s)` BFA di `z = -2, 0, +2`, satuan kg/m².

### 5.3 Contoh angka (laki-laki, 24 bulan) — ilustrasi bentuk, bukan nilai resmi

```
TB/U   z=-2 → 80.9 cm   median → 87.1 cm   z=+2 → 93.9 cm
IMT/U  z=-2 → 13.6 kg/m² median → 16.2 kg/m² z=+2 → 19.4 kg/m²
```

Nilai sebenarnya diambil dari database, bukan dari dokumen ini.

---

## 6. Rancangan Endpoint

### 6.1 Rute

Tidak berubah: `GET /api/children/{id}/growth`, tanpa query string.

### 6.2 Bentuk respons

Kunci `child` dan `series.unit`/`order` tidak berubah. Yang berubah: setiap
`points[]` mendapat field baru, dan `data` mendapat `who_references`.

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
      "unit": { "weight": "kg", "height": "cm", "bmi": "kg/m2" },
      "order": "asc",
      "points": [
        {
          "date": "2026-09-24",
          "age_in_months": 30,
          "weight_kg": 12.4,
          "height_cm": 88.0,
          "head_circumference_cm": 47.5,
          "bmi": 16.01,
          "z_score_wfa": 0.21,
          "status_gizi": "Normal",
          "z_score_hfa": -0.8,
          "status_stunting": "Normal",
          "z_score_bfa": 0.4,
          "status_gizi_imt": "Normal",
          "z_score_wfh": null
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
    },
    "who_references": [
      {
        "metric": "weight_for_age",
        "label": "BB/U",
        "unit": "kg",
        "x_axis": "age_in_months",
        "source": "WHO Child Growth Standards 2006",
        "gender": "P",
        "age_range": { "from": 0, "to": 60 },
        "points": [
          { "age_in_months": 30, "median": 13.3, "lower": 11.2, "upper": 15.7 }
        ]
      },
      {
        "metric": "height_for_age",
        "label": "TB/U",
        "unit": "cm",
        "x_axis": "age_in_months",
        "source": "WHO Child Growth Standards 2006",
        "gender": "P",
        "age_range": { "from": 0, "to": 60 },
        "points": [
          { "age_in_months": 30, "median": 87.1, "lower": 80.9, "upper": 93.9 }
        ]
      },
      {
        "metric": "bmi_for_age",
        "label": "IMT/U",
        "unit": "kg/m2",
        "x_axis": "age_in_months",
        "source": "WHO Child Growth Standards 2006",
        "gender": "P",
        "age_range": { "from": 0, "to": 60 },
        "points": [
          { "age_in_months": 30, "median": 16.2, "lower": 13.6, "upper": 19.4 }
        ]
      }
    ]
  }
}
```

Catatan bentuk:

- `who_references` **urut normatif**: `weight_for_age`, `height_for_age`,
  `bmi_for_age` (diuji).
- `who_references` selalu berisi tiga entri. Kalau gender tidak `L`/`P`,
  `points` di tiap entri kosong (bukan entri dihilangkan), supaya layar bisa
  menjelaskan alasannya.
- `who_reference` (tunggal) tetap ada dan **selalu sama** dengan entri
  `weight_for_age` di `who_references` (diuji konsistensinya).
- Field baru di `points[]` boleh `null` (di luar rentang WHO, atau BB/TB untuk
  umur ≥ 24 bulan). `null` berbeda dari 0 dan dari "Normal".
- `series.unit` hanya bertambah kunci `bmi` (aditif). `weight`/`height` tetap.

### 6.3 Aturan baru dan test yang membuktikannya

Aturan lama di §7.3 `RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md` tetap berlaku kecuali
tiga yang diamendemen (§11). Aturan **baru** yang wajib ditambahkan ke tabel
§7.3 (setiap baris satu test di `GrowthChartTest.php`):

| # | Aturan (WAJIB) | Test yang membuktikannya |
| :--- | :--- | :--- |
| 13 | **`data` berisi tepat empat kunci** `child`, `series`, `who_reference`, `who_references`. | `data_tepat_berisi_empat_kunci` |
| 14 | **Nilai multidimensi dibaca apa adanya.** `z_score_hfa`, `status_stunting`, `z_score_bfa`, `status_gizi_imt`, `z_score_wfh`, dan `bmi` sama dengan baris database, tanpa dihitung ulang. | `angka_multidimensi_dibaca_dari_database` |
| 15 | **`who_references` berisi tiga metrik** dengan urutan BB/U, TB/U, IMT/U. | `who_references_berisi_tiga_metrik_berurut` |
| 16 | **Pita HFA/BFA ikut gender** dan titiknya cocok dengan `who_hfa_standards`/`who_bfa_standards` untuk gender itu. | `pita_tbu_dan_imtu_mengikuti_gender_anak` |
| 17 | **Pita HFA/BFA dikirim walau `points` kosong**, menutup 0–60 bulan (61 titik). | `pita_tbu_dan_imtu_menutup_0_sampai_60_bulan` |
| 18 | **`who_reference` konsisten dengan `who_references[0]`** (WFA): `metric`/`source`/`gender`/`age_range` sama, dan nilai `median_kg`/`lower_kg`/`upper_kg` tiap titik sama dengan `median`/`lower`/`upper`. Nama kunci titik sengaja berbeda (tunggal memakai akhiran `_kg` demi kompatibilitas klien lama). | `who_reference_konsisten_dengan_who_references` |
| 19 | **Pita TB/U konsisten dengan `z_score_hfa`**, dan **pita IMT/U konsisten dengan `z_score_bfa`** yang dibaca trigger. | `pita_tbu_dan_imtu_konsisten_dengan_z_score_trigger` |
| 20 | **`bmi` = berat/(tinggi/100)² dibulatkan 2 desimal**, `null` kalau berat/tinggi kosong. | `bmi_dihitung_dari_berat_dan_tinggi` |
| 21 | **BB/TB tanpa pita.** `z_score_wfh` ada untuk umur < 24 bulan, `null` di luarnya; tidak pernah ada entri `who_references` bermetrik `weight_for_height`. | `bb_tb_tanpa_pita` |
| 22 | **Jumlah query tetap dua** (sudah ada sebagai aturan 12; dipertahankan dengan `UNION ALL`). | `jumlah_query_tetap_dua` |

### 6.4 Kompatibilitas

| Yang tidak boleh berubah | Sumber |
| :--- | :--- |
| 31 registrasi route `api/` | `routes/api.php` |
| `data.child` dan `series.unit.weight`/`height`, `series.order` | `GrowthChartTest::data_tepat_berisi_tiga_kunci` (diubah, bukan dihapus) |
| Bentuk titik `who_reference` tunggal (empat field kg) | `pita_who_hanya_untuk_berat_badan` |
| Trigger dan tabel acuan | `yang-jangan-diubah.md` |

---

## 7. Rancangan Mobile

### 7.1 Model (`lib/models/growth_chart.dart`)

- `GrowthPoint` menambah field: `bmi`, `zScoreHfa`, `statusStunting`,
  `zScoreBfa`, `statusGiziImt`, `zScoreWfh` — semuanya nullable, semua dibaca
  apa adanya (pola `_desimal`/`_teks` yang sudah ada).
- Kelas baru `WhoBandPoint { ageInMonths, median, lower, upper }` untuk bentuk
  pita seragam, dan `WhoBandReference { metric, label, unit, source, gender,
  ageFrom, ageTo, points }` untuk `who_references`.
- `GrowthChart` menambah field `whoBands: List<WhoBandReference>` (nama Dart
  bebas; nama JSON-nya `who_references`).
- Kelas `WhoReference` (tunggal) **tidak diubah**.

### 7.2 Widget grafik (`lib/widgets/growth_line_chart.dart`)

`enum GrowthMetric` berubah dari `{ weight, height }` menjadi
`{ weightForAge, heightForAge, bmiForAge }`. Widget menggambar **satu** kurva
anak + satu pita, memilih sumber berdasarkan enum:

| Metrik | Nilai titik | Pita | Satuan |
| :--- | :--- | :--- | :--- |
| BB/U | `weight_kg` | entri `weight_for_age` | kg |
| TB/U | `height_cm` | entri `height_for_age` | cm |
| IMT/U | `bmi` | entri `bmi_for_age` | kg/m² |

Kehilangan/pemetaan sumbu cm khusus (mekanisme `yDariCm`) dihapus karena tidak
ada lagi dua satuan di satu kanvas. Aturan grafik lain tetap: sumbu x
`age_in_months`, tanpa nilai nol, tanpa interpolasi pita.

### 7.3 Layar (`lib/widgets/growth_chart_view.dart`)

- Tiga tombol metrik (bukan dua) berisi label BB/U, TB/U, IMT/U dan satuannya.
- Legenda pita generik: "Area abu = rentang normal WHO (median -/+2 SD)".
- Kartu status di bawah grafik tetap menampilkan BB/U (tidak berubah), lalu
  ditambah kartu ringkas multidimensi: TB/U (`status_stunting`), IMT/U
  (`status_gizi_imt`), dan BB/TB (`z_score_wfh` + `status_wfh`) untuk anak
  < 24 bulan.
- Warna/ikon kartu memakai `utils/status_gizi.dart` yang sudah ada
  (`'stunting'` sudah dipetakan ke merah).

### 7.4 Yang tidak berubah

- Palet Ibu/Kader, `GrowthChartService` (mobile), state kosong/gagal, tombol
  muat ulang, dan pemasangan layar tidak disentuh.

---

## 8. Rencana Pengujian

| Lapisan | Isi | Dasar |
| :--- | :--- | :--- |
| Feature PHP | Aturan 13–22 di §6.3 + amendemen tiga aturan lama | `tests/Feature/GrowthChartTest.php` |
| Feature PHP (regresi) | Seluruh test z-score existing tetap hijau, terutama setelah `CREATE OR REPLACE` trigger (Opsi A) | suite penuh |
| `uji-api.ps1` | Grup 8b ditambah cek `who_references` (tiga metrik, gender, rentang) | `uji-api.ps1` |
| Flutter parsing | `GrowthChart.fromJson` membaca `who_references`, `bmi`, dan field multidimensi; `null` tetap `null` | `test/kontrak_api_test.dart` |
| Flutter widget | Ketiga metrik ter-render; pita TB/U & IMT/U muncul; BB/TB tidak punya pita | `test/grafik_tumbuh_widget_test.dart` |
| Flutter layar | Pemilih tiga metrik berpindah dengan benar, tetap identik Ibu/Kader | `test/grafik_tumbuh_kader_test.dart` |

**Peringatan yang berlaku** (`pengujian.md`, §9 dokumen lama): `ChildFactory`
mengisi `date_of_birth` acak. Setiap test yang menyentuh tanggal **wajib**
membuat anak dengan `date_of_birth` pasti. Untuk menguji BB/TB yang hanya
berlaku < 24 bulan, lahirkan anak pada tanggal tetap lalu timbang sebelum ulang
tahun kedua.

---

## 9. Urutan Kerja (dokumen dulu, kode kemudian)

1. **Amendemen dokumen** (§11) — termasuk penguncian aturan 13–22 di §7.3 dan
   `kontrak-growth.md`.
2. **Backend `GrowthChartService`**: perluas `points()` (select + `bmi` SQL),
   ganti `whoReference()` menjadi satu query `UNION ALL` + helper slice WFA,
   bentuk `who_references`.
3. **Feature test** `GrowthChartTest.php`: tambah aturan 13–22, ubah tiga aturan
   lama, pastikan `jumlah_query_tetap_dua` tetap lulus.
4. **(Opsi A) Migration `status_wfh`** + `CREATE OR REPLACE FUNCTION`, plus test
   regresi trigger.
5. **Dokumentasi** `API_CONTRACT.md` dan `DATABASE_SCHEMA.md`.
6. **Mobile model** `growth_chart.dart` + test parsing.
7. **Widget & layar** `growth_line_chart.dart`, `growth_chart_view.dart`, +
   test widget/layar.
8. **Verifikasi akhir**: Pint, `php artisan test`, `flutter analyze`,
   `flutter test`, `uji-api.ps1`.

---

## 10. Estimasi

| Bagian | Estimasi |
| :--- | :--- |
| Amendemen dokumen + kontrak | 0,5 hari |
| Backend service + enum/pita + feature test | 1 hari |
| Migration `status_wfh` + regresi trigger (Opsi A) | 0,5 hari |
| Model & parsing mobile + test | 0,5 hari |
| Widget/layar tiga metrik + test | 1 hari |
| Dokumentasi API/skema + `uji-api.ps1` + verifikasi | 0,5 hari |
| **Total** | **4 hari** |

---

## 11. Amendemen Dokumen yang Harus Dilakukan Lebih Dulu

| Dokumen | Bagian | Perubahan |
| :--- | :--- | :--- |
| `docs/RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md` | §5.1 | "Pita hanya BB/U" → "pita BB/U, TB/U, IMT/U; bukan BB/TB". Alasan TB ditunda ditandai **usang sejak 10 Okt 2026**. |
| | §6.2 | Tabel "yang TIDAK dibuat" (`who_hfa_standards`, `z_score_hfa`, dst.) ditandai sudah **dibuat** oleh P0-2. |
| | §6.3 | Sumber pita bertambah HFA/BFA (inverse LMS di SQL). |
| | §7.2 | Contoh respons ditambah field multidimensi + `who_references`. |
| | §7.3 | Aturan 7 diubah, "tepat tiga kunci" → empat, ditambah aturan 13–22 (§6.3). |
| | §7.5 | Baris "`measurements` tidak menambah kolom" dikoreksi. |
| | §13 | Catatan riwayat perubahan fitur ini. |
| `posyandu-backend/.ai/rules/kontrak-growth.md` | — | Aturan 7, "tepat tiga kunci", dan larangan TB/U dikoreksi; tambah larangan menghitung klasifikasi di PHP dan aturan `UNION ALL` (query tetap dua). |
| `docs/API_CONTRACT.md` | bagian growth | Tambah field multidimensi + `who_references`. |
| `docs/DATABASE_SCHEMA.md` | tabel WHO + `measurements` | Catat tabel HFA/BFA/WFH dan kolom multidimensi (sudah ada sejak P0-2, kemungkinan belum terdokumentasi). |

---

## 12. Pertanyaan / Keputusan Terbuka

| Pertanyaan | Rekomendasi | Status |
| :--- | :--- | :--- |
| BB/TB menyimpan statusnya sendiri? | **Ya** — migration aditif `status_wfh` (§4.6 Opsi A), agar "status hanya dari PostgreSQL" tetap utuh | **Diputuskan 15 Okt 2026** |
| Nama kunci `who_references` (jamak) diterima, atau lebih suka `who_bands`? | `who_references` | **Dipakai 15 Okt 2026** |
| Grafik jadi pemilih satu metrik (dual-axis dihapus) — diterima? | Ya, karena IMT/U bersatuan kg/m² (§4.7) | **Disetujui 15 Okt 2026** |

---

## 13. Riwayat Perubahan

| Tanggal | Perubahan |
| :--- | :--- |
| 15 Okt 2026 | Rancangan awal. Memutuskan: aditif di `/growth` (bukan endpoint baru), `data` jadi empat kunci, pita HFA/BFA di SQL (inverse LMS), BMI di SQL, BB/TB tanpa pita, mobile jadi pemilih tiga metrik. Aturan 13–22 dipetakan ke nama test. Satu perubahan skema (opsional): `status_wfh`. Belum ada kode fitur yang ditulis. |
| 15 Okt 2026 | **Implementasi backend selesai.** Migration `2026_10_15_052851_add_status_wfh_to_measurements_and_trigger.php` (Opsi A). `GrowthChartService` diubah ke `UNION ALL` tiga pita + `bmi` + field multidimensi + `who_references`. `GrowthChartTest` 33 test (aturan 13–21), `WhoZScoreTriggerTest` 4 test. Docs `RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md`, `kontrak-growth.md`, `API_CONTRACT.md`, `DATABASE_SCHEMA.md` diamendemen. `uji-api.ps1` grup 8b diperbarui. |
| 15 Okt 2026 | **Implementasi mobile selesai.** `growth_chart.dart` (field multidim + `bmi`, `WhoBandPoint`/`WhoBandReference`, `whoBands`, `bandUntuk`, `bmiUnit`, `titikMultidimTerakhir`), `growth_line_chart.dart` ditulis ulang jadi pemilih satu metrik (`GrowthMetric` BB/U, TB/U, IMT/U; `jumlahBarisGrafik = 4`; dual-axis dihapus), `growth_chart_view.dart` (tiga tombol metrik, legenda generik, kartu ringkas multidimensi). Test: `kontrak_api_test.dart` diperluas, `grafik_tumbuh_widget_test.dart` ditulis ulang. Verifikasi: `flutter analyze` bersih, `flutter test` 214 test. |
