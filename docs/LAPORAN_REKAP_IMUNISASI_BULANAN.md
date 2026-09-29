# Laporan Pengerjaan Blokir 3 — Rekap Suntikan Per Bulan

**Tanggal:** 28 September 2026  
**Status:** Selesai — endpoint jalan, regression API 314/314, test suite 50/50, mobile 88/88 + APK berhasil
**Branch:** `main` (belum commit)

> **Catatan koreksi 2.** Test `MeasurementRecapTest` pernah hijau di satu
> putaran lalu gagal di putaran berikutnya, tanpa ada kode yang berubah.
> Penyebabnya bukan regresi: `ChildFactory` mengisi `date_of_birth` acak
> (5 tahun s.d. 1 bulan lalu), sementara test itu memakai tanggal penimbangan
> hardcode Februari 2026, dan trigger PostgreSQL menolak penimbangan yang
> lebih awal dari tanggal lahir. Test ini gagal sekitar 1 dari 8 kali secara
> acak. Sudah diperbaiki dengan tanggal lahir tetap lewat helper `anak()`. Lihat
> bagian "Test Flaky Yang Ketemu Saat Verifikasi Akhir".

> **Catatan koreksi.** Versi pertama laporan ini menulis "Selesai, regression
> 288/288" padahal endpoint rekap belum pernah dipanggil sekali pun oleh
> `uji-api.ps1`, dan **semua request-nya balas 500**. Angka 288/288 hanya
> membuktikan 288 pemeriksaan lain tidak rusak. Laporan ini diperbarui setelah
> bug-nya diperbaiki dan ditambahkan 26 pemeriksaan baru.

---

## Ringkasan Apa Yang Dibangun

Endpoint baru: `GET /api/kader/immunizations/recap?month=YYYY-MM`

Dilindungi middleware `RoleCheck::class.:'kader'` — Ibu tidak bisa akses karena rekap mengekspos data seluruh Posyandu (privacy). Ibu sudah punya `GET /children/{id}/immunizations` untuk anaknya sendiri.

Respons JSON satu permintaan, dua bagian yang **tidak boleh dijumlahkan**:

| Bagian | Pertanyaan yang dijawab | Kegunaan |
|--------|-------------------------|----------|
| `activity` | Berapa dosis yang disuntik bulan itu, per jenis vaksin | Stok vaksin: "Bulan ini habis 40 dosis, bulan depan perkirakan butuh 38" |
| `coverage` | Kelengkapan tiap anak di akhir bulan itu | Laporan ke BIDAN + menyiapkan kunjungan rumah: "4 anak terlambat, siapa dulu?" |

---

## Keputusan Produk (Dikonfirmasi User)

| Keputusan | Pilihan | Alasan |
|-----------|---------|--------|
| **Isi rekap** | Keduanya: aktivitas + status akhir bulan | Satu endpoint melayani stok vaksin DAN laporan BIDAN |
| **Acuan waktu** | Akhir bulan yang diminta (mis. 30 Sep) | Laporan historis reproduktif: minta Sept di Nov = angka sama dengan minta Sept di Okt |
| **Anak ter-archive** | Dikecualikan dari hitungan, tapi jumlahnya dilaporkan di `excluded_archived` | Rata-rata Posyandu punya 1–2 anak pindah/keluar; angka tidak "tersembunyi" |

---

## File Yang Ditambah / Diubah

### Baru
| File | Fungsi |
|------|--------|
| `app/Services/ImmunizationRecapService.php` | Logika rekap: dua query utama (`activityForMonth`, `coverageAt`) + sorting anak terlambat |
| `posyandu_mobile/lib/models/immunization_recap.dart` | Model rekap di sisi Flutter: `ImmunizationRecap`, `RecapActivity`, `RecapCoverage`, `RecapOverdueChild` |
| `posyandu_mobile/lib/services/immunization_recap_service.dart` | Akses `GET /kader/immunizations/recap`, satu method baca saja |
| `posyandu_mobile/lib/screens/kader/rekap_imunisasi_screen.dart` | Layar rekap: navigasi bulan, aktivitas suntikan, kelengkapan anak, daftar anak terlambat |
| `posyandu_mobile/lib/utils/month_label.dart` | Format `YYYY-MM` dan `YYYY-MM-DD` jadi bahasa manusia + geser bulan |
| `docs/LAPORAN_REKAP_IMUNISASI_BULANAN.md` | File ini |

### Diubah
| File | Perubahan Utama |
|------|-----------------|
| `app/Services/ImmunizationChecklistService.php` | **Refactor besar**: <br>• Tambah param `$asOf` di `checklistFor()` untuk laporan historis<br>• Ekstrak `evaluate()` — **satu-satunya tempat aturan status ditulis**<br>• Tambah `summarizeFor()` dipakai rekap (bukan query per anak, terima array `givenTypeIds`)<br>• Backward compatible: caller lama tanpa `$asOf` tetap jalan (pakai hari ini) |
| `app/Models/ImmunizationRecord.php` | Tambah 3 scope: `forMonth()`, `betweenDates()`, `givenOnOrBefore()` |
| `app/Http/Controllers/Api/ImmunizationController.php` | Constructor inject `ImmunizationRecapService` + method `recap(Request $request)` |
| `routes/api.php` | Route `GET /kader/immunizations/recap` di dalam group `RoleCheck:kader` |
| `posyandu_mobile/lib/utils/constants.dart` | `kaderImmunizationRecapEndpoint` |
| `posyandu_mobile/lib/models/medical_note.dart` | `labelFilter` sekarang memanggil helper bulan bersama, bukan daftar nama bulan sendiri |
| `tests/Feature/MeasurementRecapTest.php` | Test flaky: tanggal lahir anak dikunci lewat helper `anak()` (lihat catatan koreksi 2) |
| `posyandu_mobile/lib/screens/kader/kader_dashboard_screen.dart` | Tombol menu "Rekap Imunisasi" |
| `posyandu_mobile/test/kontrak_api_test.dart` | 23 test baru: kontrak rekap + helper label bulan + penjaga path endpoint |

> **Kenapa `medical_note.dart` ikut disentuh** padahal tidak berkaitan dengan
> rekap: daftar catatan keluhan punya salinan sendiri daftar nama bulan. Kalau
> rekap punya salinan kedua, dua layar akan menampilkan nama bulan berbeda
> suatu saat ("September 2026" vs "Sept 2026") dan kader akan mengira itu dua
> bulan yang berbeda. Sekarang keduanya memanggil satu helper. Test lama
> `labelFilter == 'September 2026'` tetap lulus, jadi ini refactor tanpa
> perubahan perilaku.

---

## Detail Teknis Penting

### 1. Satu Sumber Kebenaran Aturan Status
`ImmunizationChecklistService::evaluate()` adalah **satu-satunya** tempat aturan `sudah`/`belum`/`terlambat` dihitung. Checklist per anak (`checklistFor`) DAN rekap lintas anak (`summarizeFor`) keduanya memakainya. Kalau aturan berubah (mis. toleransi 3 bulan), cukup ganti config — kedua output konsisten otomatis.

### 2. Efisiensi Query Rekap
Rekap tidak melakukan N+1. Polanya:
- **Activity**: 1 query `ImmunizationRecord` + group by `immunization_type_id` (soft-deleted otomatis tersaring).
- **Coverage**:
  - 1 query `Child` (exclude archived)
  - 1 query `ImmunizationRecord` `whereIn(child_id)` + `givenOnOrBefore(tanggal_acuan)` + `groupBy(child_id)`
  - 1 query `ImmunizationType` ordered
  - Semua evaluasi per anak di PHP loop — data kecil (tanggal lahir + daftar id dosis), 200 anak < 20 ms.

### 3. Filter Tanggal Acuan di Coverage
`suntikanPerAnak` di-filter `givenOnOrBefore(tanggal_acuan)` supaya suntikan yang baru dicatat *setelah* bulan itu tidak masuk hitungan laporan lama. Tanpa ini, laporan September yang dibuat di November akan berubah angkanya.

### 4. Urutan Anak Terlambat
`overdue_children` diurutkan:
1. Paling banyak dosis terlambat dulu
2. Jika sama, paling lama terlambat (`sisa_bulan` paling negatif)

Kader langsung tahu siapa dikunjungi dulu tanpa harus sort manual.

### 5. Field `reference_date` di Respons
Biar konsumen (mobile / PDF generator) tahu acuan waktu tanpa perlu tebak. Contoh respons September 2026:

```json
{
  "success": true,
  "message": "Rekap imunisasi berhasil diambil.",
  "data": {
    "filter": { "month": "2026-09", "reference_date": "2026-09-30" },
    "activity": {
      "total_doses": 12,
      "total_children": 9,
      "by_type": [
        { "immunization_type_id": "...", "code": "HB", "name": "Hepatitis B", "label": "Hepatitis B", "dose_number": 1, "count": 4 },
        { "immunization_type_id": "...", "code": "BCG", "name": "BCG", "label": "BCG", "dose_number": 1, "count": 3 }
      ]
    },
    "coverage": {
      "total_children": 25,
      "complete": 12,
      "incomplete": 9,
      "overdue": 4,
      "excluded_archived": 2,
      "overdue_children": [
        {
          "child_id": "...",
          "name": "Budi",
          "date_of_birth": "2025-10-15",
          "age_in_months": 11,
          "overdue_doses": [
            { "immunization_type_id": "...", "code": "CAM", "name": "Campak", "label": "Campak", "dose_number": 1, "target_age_months": 9, "sisa_bulan": -2 }
          ]
        }
      ]
    }
  }
}
```

---

## Verifikasi

| Cek | Hasil |
|-----|-------|
| PHP syntax | ✅ semua file baru/ubah `php -l` bersih |
| Pint | ✅ `vendor/bin/pint --dirty --format agent` → `passed` |
| Periksa teks otomatis | ✅ `periksa-teks.ps1` → BERSIH, 345 file |
| Feature test baru | ✅ `tests/Feature/ImmunizationRecapTest.php` 21 test / 115 assertions |
| Test suite penuh | ✅ 50 test / 177 assertions (dari 29 test sebelumnya) |
| Regression API (`uji-api.ps1`) | ✅ **314/314** lulus (288 + 26 pemeriksaan grup 9f) |
| Guard DB test | ✅ test menolak jalan kalau diarahkan ke `posyandu_db` |
| Migration rollback + migrate | ✅ idempoten (diverifikasi di blokir 1) |
| Flutter analyze | ✅ `No issues found!` |
| Flutter test | ✅ **88/88** lulus (dari 65 sebelumnya) |
| Build APK | ✅ `flutter build apk --debug` sukses, layar ikut ter-link ke aplikasi |

### Bug Produksi Yang Ditemukan Saat Verifikasi

Tiga bug ditemukan setelah endpoint dipanggil sungguhan, bukan setelah
`route:list` dan `php -l` lolos. Semuanya dulu lolos "audit tidak-error":

| Bug | Gejala di user | Akar masalah | Perbaikan |
|-----|----------------|--------------|-----------|
| **Endpoint selalu 500** | Semua request rekap balas `500`, tidak ada satu pun yang berhasil | `ImmunizationRecapService::recapForMonth()` mengirim `string` ke `coverageAt(CarbonImmutable $tgl)`. Method itu memanggil `$tgl->copy()` dan `$tgl->addMonthsNoOverflow()` yang butuh objek Carbon, bukan string | `$bulan->endOfMonth()` dipakai utuh, tidak di-`format()` lebih dulu |
| **`sisa_bulan` salah di checklist** | Dosis yang sudah disuntik tepat waktu menampilkan "terlambat 2 bulan" | `evaluate()` mengembalikan `sisa_bulan` untuk semua status, termasuk `sudah` | `sisa_bulan` di-set `null` khusus status `sudah` (countdown tidak relevan di sana) |
| **`filter` salah tempat** | Klien cari `data.month`, dokumentasi bilang `data.filter.month` | Servis mengembalikan `month`/`reference_date` di root `data` | Dibungkus ke `data.filter.*` supaya cocok kontrak dan konvensi filter endpoint lain |

Dua bug pertama **tidak akan ketahuan** oleh 288 pemeriksaan `uji-api.ps1`
lama, karena tidak ada satu pun yang menyentuh `/kader/immunizations/recap`.
Bug `sisa_bulan` bahkan sempat muncul sebagai kegagalan `uji-api` di grup
checklist yang sudah ada sebelumnya (2 dari 288 gagal) — perbaikan `null` itu
sudah ada, tapi belum ada test yang mengunci perilakunya.

Yang paling mahal dari ketiganya adalah bug 500: interface resmi sudah "selesai"
menurut laporan, padahal tidak pernah berhasil dipanggil satu kali pun di
database pengujian.

### Apa Yang Ditambahkan ke `uji-api.ps1` (Grup 9f)

26 pemeriksaan baru, semuanya lewat HTTP nyata ke server yang sedang jalan —
bukan panggilan service langsung:

- Ibu buka rekap → `403` (privacy lintas anak)
- Validasi bulan: `2026-13` → `422` dengan error di field `month`; `202602` → `422`
- `filter.month` = bulan yang diminta; `filter.reference_date` = **akhir** bulan itu
- `by_type` = 16 baris master, termasuk yang `count`-nya 0
- `complete + incomplete = total_children` (konsistensi aritmetika)
- Aktivitas: suntikan hari ini masuk hitungan, `count HB0 = 1`
- Pembatalan suntikan → `count HB0` turun ke `0` (soft delete tidak boleh dihitung)
- Rekap dua kali pada bulan sama → total anak, jumlah terlambat, dan total dosis identik
- Rekap bulan tanpa aktivitas (`2019-01`) → `200` dengan angka nol, bukan `404`

---

## Layar Mobile (28 September 2026)

Layar rekap untuk Kader sudah jadi, dibaca dari tombol "Rekap Imunisasi" di
dashboard Kader. Read-only: kader tidak mengetik angka apa pun, semuanya dari
suntikan yang sudah tercatat.

Empat keputusan tampilan yang mengikuti aturan kontrak, bukan selera visual:

1. **Aktivitas dan kelengkapan di dua kartu terpisah**, tidak pernah dijumlahkan.
   Aktivitas di atas (untuk stok vaksin), kelengkapan di bawah (untuk kunjungan
   rumah).
2. **Tanggal acuan ditulis di bawah judul bulan**: "Dihitung sampai 30
   September 2026". Kader tidak perlu menghitung sendiri akhir bulan, dan
   laporan lama tahu dirinya terhitung kapan.
3. **Baris master dengan `count: 0` disembunyikan di balik toggle**, bukan
   dihapus. Kader bisa melihat "tidak ada suntikan" kalau memang perlu, tapi
   16 baris tidak akan membanjiri layar. Kontraknya yang meminta semua 16
   baris dikirim adalah sisi server; tampilannya tetap boleh diringkas.
4. **Anak terlambat tidak diurutkan ulang di Flutter.** Urutannya sudah dari
   server (paling banyak dosis terlambat dulu), jadi mengurutkan lagi di klien
   hanya membuka pintu untuk tampilan berbeda dari yang didokumentasikan.

Navigasi bulan memakai tombol panah, dan tombol maju dimatikan di bulan
berjalan atau yang lebih baru. Rekap bulan depan tidak berarti apa-apa untuk
laporan, dan membiarkan kader menekan tombolnya lalu melihat angka nol akan
menyesatkan — terlihat seperti datanya hilang.

Helper `utils/month_label.dart` dipakai bersama oleh layar rekap dan layar
catatan keluhan, jadi "September 2026" tidak mungkin tampil berbeda di dua
layar. `geserBulan` sengaja tidak memakai `DateTime`: `DateTime(2026, 13)`
akan bergeser diam-diam ke Februari 2027, dan input yang rusak sebaiknya
dikembalikan apa adanya.

### Yang Tidak Ada Testnya, dan Mengapa

Layar `RekapImunisasiScreen` **tidak punya widget test**. Service-nya
dibuat di dalam `State`, bukan lewat parameter, jadi tidak bisa dipalsukan
dengan stub.

Ini disengaja supaya tidak berbeda dari layar Kader lain yang semuanya
memakai pola yang sama dan juga tidak punya widget test. Yang diuji otomatis
adalah lapisan yang bisa salah diam-diam: parsing model terhadap JSON asli
dari API, format label, dan path endpoint. Risiko yang tersisa (mis. teks
yang menumpuk di layar kecil) baru ketahuan saat dibuka di emulator — bagian
itu perlu dilihat mata.

---

## Test Flaky Yang Ketemu Saat Verifikasi Akhir

Menarik untuk dicatat, karena ini undermine laporan "test hijau" yang biasa
dibuat orang.

`MeasurementRecapTest::scope_bulan_menangani_bulan_dengan_29_hari` gagal di
verifikasi akhir dengan pesan:

```
Tanggal penimbangan (2026-02-28) tidak boleh lebih awal dari tanggal lahir anak (2026-07-29)
```

Test itu **tidak pernah disentuh** dalam pengerjaan rekap, dan **tidak ada
kode produksi yang berubah** di antara dua jalannya. Rantainya:

- `ChildFactory` mengisi `date_of_birth` dengan `fake()->dateTimeBetween('-5 years', '-1 month')`
- test menginsert penimbangan pada `2026-02-28` dan `2026-03-01`
- trigger `calculate_measurement_who_zscore()` menolak `measurement_date < date_of_birth`

Kalau anak kebetulan lahir setelah 1 Maret 2026, test gagal. Peluangnya
sekitar 12% per jalannya, jadi "50/50 lulus" yang biasa dipakai sebagai bukti
backend selesai **tidak sepenuhnya bisa dipercaya** — hasilnya bisa hijau
karena kebetulan.

Perbaikannya sengaja tidak ada di factory: `ChildFactory` dipakai puluhan test
yang memang butuh anak usia beragam, jadi mengunci tanggal lahir di sana akan
merusak test lain. Sebagai gantinya, file test itu memakai helper sendiri:

```php
private function anak(): Child
{
    return Child::factory()->create(['date_of_birth' => '2024-01-01']);
}
```

Sekarang seluruh 14 test di file itu memakai anak dengan tanggal lahir pasti.
Bukti: 5 kali berturut-turut `14/14` lulus, angka assertion identik tiap kali.

Yang **tidak** diperbaiki: pola serupa masih mungkin muncul di file lain yang
mencampur anak factory (usia acak) dengan tanggal hardcode. Selama ini tidak
ada yang terpengaruh, karena trigger penjaga tanggal lahir hanya ada di tabel
`measurements` — suntikan dan jadwal tidak punya penjaga setara, jadi test
imunisasi kebetulan kebal. Kalau nanti ditambah trigger serupa, pola yang sama
harus ikut diawasi.

---

## Yang Masih Butuh Dilakukan

1. **Commit** perubahan blokir 1–3 + layar mobile.
2. ~~Dokumentasi endpoint di `docs/API_CONTRACT.md`~~ — **selesai**, sudah ada
   bagian `GET /kader/immunizations/recap` lengkap dengan keempat aturan
   yang tidak boleh dilanggar klien.
3. ~~Update `RENCANA_SELANJUTNYA.md`~~ — **selesai**, blokir 3 ditandai selesai.
4. ~~Layar rekap di aplikasi mobile~~ — **selesai**.
5. **Export CSV** — endpoint terpisah atau query param `?format=csv`? Belum
   diputuskan. Sisa satu-satunya butir Opsi E.
6. **Panggil tim mobile** — apakah butuh field tambahan di respons (mis.
   `batch_number` di `activity` untuk tracking stok)?
7. ~~**Urutan dosis sesuai kronologi**~~ — **selesai 29 September 2026.**
   `scopeOrderedForDosing()` sorting berdasarkan `target_age_months`, lalu
   `code`, lalu `dose_number`. Checklist anak, `by_type` rekap, dan dropdown
   `GET /immunization-types` sekarang satu urutan yang sama: HB-1 dan
   POLIO-1 (bulan 0), lalu BCG/DPT-1/HB-2/POLIO-2 (bulan 2), dan seterusnya.

---

## Catatan Untuk Agent Berikutnya

- Endpoint sudah siap pakai dan **sudah pernah dipanggil sungguhan**. Kalau
  mobile butuh kolom tambahan, tambahkan di
  `ImmunizationRecapService::activityForMonth()` dan `coverageAt()` — bukan di
  controller, supaya respons tetap satu sumber.
- `ImmunizationChecklistService` sudah *public API* yang stabil. Jangan ubah
  signature tanpa update `ImmunizationRecapService` sekalian.
- `scopeGivenOnOrBefore` dipakai cuma di rekap; checklist per anak tetap pakai
  semua record (tanpa filter tanggal) karena menunjukkan keadaan *saat ini*.
- Kalau nanti ada permintaan "rekap per kader" atau "rekap per desa", struktur
  service sudah modular — tambah parameter `kader_id` di
  `ImmunizationRecapService` dan forward ke query.
- **Jangan simpulkan "test hijau berarti endpoint jalan"** dari `php -l` dan
  `route:list`. Keduanya tidak pernah memanggil satu baris pun. Yang menangkap
  bug 500 adalah feature test yang memanggil route-nya lewat HTTP.
- Sebaliknya, **test hijau pun belum tentu konsisten**. Lihat bagian "Test
  Flaky Yang Ketemu Saat Verifikasi Akhir": satu test bisa hijau 8 kali lalu
  gagal di putaran berikutnya tanpa ada kode yang berubah. Kalau sebuah test
  punya fixture acak dan tanggal hardcode, perbaiki tanggalnya, bukan
  menjalankan ulang sampai hijau.
