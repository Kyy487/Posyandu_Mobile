# Rancangan Buku Medis Digital (EHR) — Balita

**Tanggal:** 28 September 2026
**Status:** Rancangan selesai, implementasi belum mulai
**Acuan:** `RANCANGAN.md` bagian 3.1 A, `RENCANA_SELANJUTNYA.md` Opsi B
**Estado repo saat ditulis:** semua pekerjaan rekap masih belum di-commit

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

## 5. Keputusan yang Menunggu User

> **Keputusan 1 (paling penting, belum dijawab):** kondisi khusus disimpan
> sebagai kolom di `children`, atau sebagai tabel terpisah?
>
> | Opsi | Bentuk | Untung | Rugi |
> |------|--------|--------|------|
> | **Kolom** | `children.medical_flags` (text) | 1 migration kecil, tanpa endpoint baru, cepat | Tidak bisa melacak kapan/how penanda berubah |
> | **Tabel** | `child_medical_flags` | Ada riwayat dan tanggal | Migration + endpoint + CRUD + 1 layar lagi |
>
> **Rekomendasi: kolom.** Untuk MVP,Most Posyandu menulis penanda sekali dan
> tidak pernah mengubahnya. Tabel terpisah baru layak kalau nanti ada
> pertanyaan "alergi ini sejak kapan" atau lebih dari satu jenis penanda per
> anak.
>
> Kalau pilih kolom, format yang disarankan: teks bebas, satu baris per penanda,
> contoh `alergi: penicillin` / `asma`. Tidak diparsing, ditampilkan apa adanya.
> Kalau pilih tabel, rancangan tabelnya ada di bagian 6.2.

> **Keputusan 2 (kecil):** timeline ditampilkan per kunjungan (dikelompokkan
> per tanggal) atau per kejadian (satu baris = satu data)?
>
> **Rekomendasi: per kunjungan.** Kunjungan biasanya menghasilkan penimbangan,
> keluhan, dan suntikan pada tanggal yang sama. Kalau dipisah, satu kunjungan
> jadi tiga baris yang terpisah dan sulit dibaca. Lihat bagian 7.2.

---

## 6. Rancangan Data

### 6.1 Timeline: tidak butuh tabel baru

Timeline bukan tabel. Dia hasil penggabungan tiga tabel yang sudah ada
(`measurements`, `immunization_records`, `medical_notes`) berdasarkan
`child_id`, lalu dikelompokkan per tanggal. Tidak ada tabel baru dan tidak ada
duplikasi data.

### 6.2 Pilihan tabel jika Keputusan 1 diambil "tabel"

Hanya perlu kalau opsi tabel yang dipilih. Disimpan di sini supaya tidak hilang:

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

Tidak memakai soft delete: penanda kesehatan tidak "dibatalkan", dan kalau
salah, dihapus lalu diisi ulang.

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

| Parameter | Default | Keterangan |
|-----------|---------|------------|
| `limit` | 50 | Jumlah tanggal kunjungan, bukan jumlah baris data |
| `before` | - | Cursor tanggal, untuk load halaman berikutnya |

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

Aturan ini sama sifatnya dengan aturan rekap. Disusun sebagai daftar supaya
bisa dipakai langsung sebagai bahan feature test.

1. **Tanggal turun.** `entries` selalu urut dari yang terbaru.
2. **Baris yang dibatalkan tidak muncul.** Semua tiga tabel memakai
   `deleted_at`; timeline hanya membaca yang `deleted_at IS NULL`.
3. **Keluhan tetap tampil walau penimbangannya dibatalkan.** Ini konsekuensi
   dari perilaku `medical_notes.measurement_id` yang sudah didokumentasikan di
   `DATABASE_SCHEMA.md:107`. Timeline **tidak boleh** menyembunyikan keluhan
   hanya karena `measurement` di entri itu `null`.
4. **Tidak ada penghitungan ulang.** Z-score, status gizi, dan status
   immunisasi semuanya dibaca apa adanya dari server. Klien tidak menghitung.
5. **Satu tanggal satu entri.** Kalau dua penimbangan pada tanggal yang sama
   tidak mungkin terjadi (partial unique index), tapi dua suntikan pada tanggal
   yang sama boleh, dan keduanya masuk ke array `immunizations`.
6. **Tanpa data tetap 200.** Anak yang belum pernah ditimbang punya
   `entries: []`, bukan 404.
7. **`limit` menghitung tanggal, bukan baris.** Kalau satu tanggal punya 3
   suntikan, itu tetap satu entri.

### 7.4 Endpoint lain yang berubah

`GET /children/{id}` ikut mengirim `medical_flags` kalau kolomnya jadi
dipakai, supaya layar profil tidak perlu request tambahan. Kalau backward
compatibility jadi concern, field baru bisa dikirim tanpa mengubah field lama.

---

## 8. Rancangan Layar Mobile

Bukan layar baru. `detail_anak_screen.dart` yang sekarang sudah jadi tempat
yang tepat; tugasnya ditambah, bukan dipecah.

### 8.1 Penanda kondisi khusus

Kalau Keputusan 1 = kolom, tampilan paling sederhana: badge berwarna di
bawah nama anak, merah untuk alergi, kuning untuk penyakit bawaan. Teks mentah
ditampilkan apa adanya, tanpa ikon per jenis — karena daftar jenis tidak
dikunci database.

### 8.2 Timeline

- Dikelompokkan per bulan, judul memakai `labelBulan()` dari
  `month_label.dart` supaya konsisten dengan layar lain.
- Inside satu tanggal, urutan tampilan: penicillin, lalu suntikan, lalu
  keluhan. Alasan: kader paling sering datang untuk "berapa beratnya" dulu.
- Tanggal yang punya keluhan tapi tanpa penimbangan tetap tampil, dengan
  catatan visual bahwa penimbangan tidak ada.
- Tombol "Muat lebih banyak" untuk `meta.has_more`.
- It internal dengan pull-to-refresh yang sudah ada (`_loadRiwayat`).

### 8.3 Apa yang tidak berubah

Judul layar, warna header, dan navigasi ke layar imunisasi serta keluhan yang
sudah ada. Tetap satu layar yang sama: ini tambahan isi, bukan layar baru.

---

## 9. Rencana Pengujian

Mengikuti pola yang sudah dipakai proyek ini, karena polanya sudah terbukti
menangkap bug nyata.

| Lapisan | Isi |
|---------|-----|
| Feature test PHP | Hit HTTP endpoint sungguhan, cek aturan 1–7 satu per satu |
| `uji-api.ps1` grup baru | Cek aturan 1–7 lewat HTTP, termasuk 403 untuk Ibu |
| Flutter test | Parsing model timeline terhadap JSON asli, bukan JSON buatan |
| Manual | Buka di emulator, scroll ke bawah |

> **Peringatan dari pelajaran terakhir.** `MeasurementRecapTest` pernah hijau
> karena kebetulan: `ChildFactory` mengisi `date_of_birth` acak sementara test
> memakai tanggal hardcode, dan trigger menolak penimbangan sebelum tanggal
> lahir. Peluang gagalnya sekitar 12% per jalannya.
>
> Untuk fitur ini: kalau test memakai tanggal hardcode, anak di dalamnya **wajib**
> dibuat dengan `date_of_birth` pasti lewat helper, bukan `Child::factory()`
> polos. Jangan mengulang kesalahan yang sama.

Feature test minimal yang harus ada:

- [ ] Timeline anak tanpa data → 200, `entries: []`
- [ ] Ibu buka timeline anaknya → 200
- [ ] Ibu buka timeline anak orang → 403
- [ ] Penimbangan + keluhan + suntikan tanggal sama → **satu** entri
- [ ] Tanggal turun urut
- [ ] Penimbangan dibatalkan → tidak muncul di timeline
- [ ] Keluhan tetap muncul walau penimbangan tertaut dibatalkan (aturan 3)
- [ ] Dua suntikan tanggal sama → satu entri, array berisi dua
- [ ] `limit=2` → tepat 2 tanggal, `has_more` benar
- [ ] Flagungi terisi terbaca benar (kalau kolom dipakai)

---

## 10. Urutan Kerja

Urutan ini disengaja supaya tidak pernah ada layar yang memakai endpoint yang
belum ada.

1. **Commit dulu** apa yang sekarang ada. Repo masih belum commit, dan menambah
   fitur di atas pekerjaan yang belum diamankan hanya memperbesar masalah.
2. **Perbaiki urutan dosis kronologi** (sudah tercatat di
   `LAPORAN_REKAP_IMUNISASI_BULANAN.md` bagian "Yang Masih Butuh
   Dilakukan"). Beberapa baris, tapi membingungkan kader sekarang, dan
   buku medis akan menampliakannya.
3. **Migration** kolom `medical_flags` (kalau kolom yang dipilih).
4. **Model + service** timeline di backend.
5. **Endpoint + feature test.** Jangan lanjut ke mobile sebelum test hijau.
6. **Dokumentasi** di `API_CONTRACT.md` dan `DATABASE_SCHEMA.md`.
7. **Mobile**: model, service, lalu perubahan `detail_anak_screen.dart`.
8. **Verifikasi akhir**: Pint, test backend, `uji-api.ps1`, `flutter analyze`,
   `flutter test`, `periksa-teks.ps1`.

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

Kalau Keputusan 1 diambil "tabel", tambah 1–1,5 hari.

---

## 12. Pertanyaan yang Masih Terbuka

 besides dua keputusan di bagian 5, tiga hal ini belum diputuskan dan
tidak menghambat mulai:

- Apakah Ibu boleh melihat `medical_flags` anak sendiri? Rekomendasi: ya, itu
  hak informasi orang tua dan tidak memuat data Posyandu.
- Siapa yang boleh mengubah penanda? Rekomendasi: Kader saja, supaya tidak
  ada dua sumber perubahan.
- Apakah timeline perlu batas waktu? Rekomendasi: tidak, cursors sudah
  menangani itu.

---

## 13. Riwayat Perubahan

| Tanggal | Perubahan |
|---------|-----------|
| 28 Sep 2026 | Rancangan awal ditulis. Belum ada kode yang dibuat untuk fitur ini. |
