# Laporan Pengerjaan - Fitur Imunisasi & Jadwal Posyandu (Fase 3)

**Status:** Selesai
**Commit:** `23d0702` — *Fitur imunisasi anak dan jadwal kegiatan posyandu*
**Tanggal:** 26 September 2026
**Lingkup:** Backend (Laravel 13) + Mobile (Flutter)

> **Catatan:** angka-angka pada dokumen ini menunjuk commit `23d0702`.
> Dilanjutkan dengan **Opsi A (rapikan kualitas)** pada 27 September 2026 -
> lihat bagian 11. Daftar temuan terbuka di bagian 7 juga sudah diperbarui.

---

## 1. Ringkasan

Fase ini menambah dua fitur yang sebelumnya belum ada sama sekali:

1. **Imunisasi** — daftar 16 dosis untuk setiap anak, lengkap dengan
   status `sudah` / `belum` / `terlambat`. Kader mencatat dan mengoreksi
   suntikan; Ibu hanya membaca.
2. **Jadwal Posyandu** — agenda kegiatan (bukan jadwal kunjungan per anak).
   Satu agenda bisa ditangani beberapa petugas sekaligus. Kader membuat,
   mengubah, menghapus; Ibu hanya membaca.

| | |
| :--- | :--- |
| File diubah / ditambah | 36 |
| Baris ditambahkan | 6.064 |
| Migration baru | 5 |
| Endpoint API baru | 9 (total API jadi **23 route**) |
| Pemeriksaan API | **210/210 lulus** |
| Test Flutter | **49/49 lulus** |

---

## 2. Masalah yang Diselesaikan

| Masalah | Solusi |
| :--- | :--- |
| Riwayat suntikan hilang kalau akun petugas dihapus | `immunization_records.kader_id` jadi nullable dengan `ON DELETE SET NULL`. Data kesehatan tidak lagi ikut terhapus karena alasan administratif |
| Tidak ada cara mengoreksi salah input suntikan | `PATCH /kader/immunizations/{record}`. Dosis terkunci unique constraint `(child_id, immunization_type_id)`, jadi koreksi cukup ubah tanggal/batch |
| Sulit tahu dosis anak mana yang tertinggal | Checklist 16 dosis dengan status yang dihitung otomatis + `sisa_bulan` (countdown) |
| Tidak ada jadwal kegiatan posyandu | Tabel `posyandu_schedules` + pivot penugasan banyak petugas |
| Seeder membuat agenda ganda setiap kali dijalankan | Kunci alami agenda = `title`, bukan `title` + `scheduled_date` |
| Ibu tidak bisa melihat riwayat imunisasi anaknya | `GET /children/{id}/immunizations` terbuka untuk Ibu, dengan pembatasan kepemilikan |
| Risiko NIK kader bocor ke semua client | `GET /petugas` hanya mengirim `id`, `name`, `jabatan`, `phone_number` |

---

## 3. Master Data: 16 Dosis

Program imunisasi dasar Indonesia. Disimpan di tabel `immunization_types`
(di-seed, **bukan** hardcode di PHP).

| Vaksin | Dosis | Target usia (bulan) | Jarak dari dosis sebelumnya |
| :--- | :--- | :--- | :--- |
| Hepatitis B (HB) | 1–4 | 0, 2, 4, 6 | —, 2, 2, 2 |
| BCG | 1 | 2 | — |
| Polio Oral | 1–5 | 0, 2, 3, 4, 6 | —, 2, 1, 1, 2 |
| DPT-HB-Hib | 1–4 | 2, 3, 4, 6 | —, 1, 1, 2 |
| Campak-Rubella (MR) | 1–2 | 9, 18 | —, 9 |

> Nama kolom di atas sudah disederhanakan; kolom sebenarnya
> `code`, `name`, `dose_number`, `target_age_months`, `interval_months`.

Unique constraint: `immunization_types_code_dose_unique (code, dose_number)`.
Seeder memakai `updateOrCreate` dengan kunci yang **persis sama** dengan
constraint itu, jadi seeder tidak mungkin membuat baris ganda.

---

## 4. Perubahan Backend

### 4.1 Migration (5 baru)

| File | Isi |
| :--- | :--- |
| `2026_09_26_030000_add_jabatan_to_users_table.php` | Kolom `jabatan` (nullable) pada `users`. Terpisah dari `role` karena `role` hanya punya 2 nilai (`ibu`/`kader`) dan dipakai untuk otorisasi |
| `2026_09_26_031000_create_immunization_types_table.php` | Master 16 dosis + scope `orderedForDosing()` |
| `2026_09_26_032000_rework_immunization_records_table.php` | Tambah `batch_number`, `notes`; `kader_id` jadi nullable + `SET NULL`; unique `(child_id, immunization_type_id)` |
| `2026_09_26_033000_create_posyandu_schedules_table.php` | Tabel agenda + CHECK constraint status |
| `2026_09_26_034000_create_posyandu_schedule_petugas_table.php` | Pivot penugasan (banyak-ke-banyak) |

Semua migration sudah diuji **rollback** lalu **re-apply** tanpa merusak
foreign key.

### 4.2 Status Agenda

Dibatasi CHECK constraint di database (bukan hanya validasi PHP):
`terjadwal`, `berlangsung`, `selesai`, `dibatalkan`.

### 4.3 Perhitungan Status Imunisasi

`app/Services/ImmunizationChecklistService.php` — **status tidak disimpan di
database**, selalu dihitung ulang tiap request:

```
1. Ada record suntikan untuk dosis itu              -> sudah
2. Belum ada, usia anak < target + toleransi         -> belum
3. Belum ada, usia anak >= target + toleransi        -> terlambat
```

**Kenapa tidak disimpan?** Status bergantung pada tanggal lahir anak. Anak
berumur 5 bulan yang belum disuntik BCG hari ini akan berstatus `terlambat`
bulan depan **tanpa ada satu pun pencatatan baru**. Disimpan, datanya akan
segera basi.

Toleransi: `config('posyandu.immunization.terlambat_setelah_bulan')`,
default **2 bulan** (env `IMMUNIZATION_LATE_AFTER_MONTHS`). Tujuannya supaya
kategori `terlambat` tidak langsung aktif di hari pertama anak melewati usia
target —ibu sering datang terlambat sedikit.

Usia dalam bulan memakai definisi **bulan penuh** yang sama dengan trigger
Z-Score PostgreSQL, supaya checklist dan status gizi tidak memakai dua
penghitungan "bulan" yang berbeda.

Performa: 1 query untuk semua dosis, di-index `keyBy` → pengecekan status
O(1) per dosis, bukan N+1.

### 4.4 Endpoint Baru (9)

| Method | Endpoint | Role |
| :--- | :--- | :--- |
| `GET` | `/immunization-types` | Ibu / Kader |
| `GET` | `/children/{id}/immunizations` | Ibu (anaknya) / Kader |
| `POST` | `/kader/children/{child}/immunizations` | Kader |
| `PATCH` | `/kader/immunizations/{record}` | Kader |
| `GET` | `/petugas` | Ibu / Kader |
| `GET` | `/schedules` | Ibu / Kader |
| `POST` | `/kader/schedules` | Kader |
| `PATCH` | `/kader/schedules/{id}` | Kader |
| `DELETE` | `/kader/schedules/{id}` | Kader |

> **Tidak ada `GET /kader/schedules`.** Membaca daftar agenda tidak perlu
> prefix `kader` — Ibu dan Kader memakai `GET /api/schedules` yang sama.
> Prefix `kader` hanya untuk operasi tulis.

### 4.5 Perbaikan Auth (Penting)

`bootstrap/app.php` — request API tamu **tanpa** header
`Accept: application/json` sebelumnya membalas **500**, bukan 401.

**Penyebab:** middleware `Authenticate` memanggil `route('login')`. Aplikasi
ini API-only, jadi route web `login` tidak ada → `RouteNotFoundException`.
Flutter tidak bisa membaca `500` sebagai "sesi berakhir".

**Perbaikan:** `redirectGuestsTo()` mengembalikan `null` untuk path `api/*`,
sehingga `AuthenticationException` tidak punya URL tujuan redirect dan
renderer mengembalikan JSON 401 yang benar.

### 4.6 Seeder Idempotent

Tabel dan kunci alaminya:

| Tabel | Kunci | Perilaku |
| :--- | :--- | :--- |
| `users` | `nik` | Password yang **sudah diganti pengguna tidak ditimpa** |
| `children` | `nik` | Tidak digandakan |
| `immunization_types` | `code` + `dose_number` | Tidak digandakan |
| `posyandu_schedules` | **`title`** | Tetap 3 baris, berapa pun selisih hari |

**Soal kunci agenda:** tanggal agenda dihitung relatif terhadap hari ini
(`now()->addDays(7)`). Kalau `scheduled_date` ikut jadi kunci, setiap
`db:seed` pada hari berikutnya mencocokkan nol baris dan membuat 3 agenda
baru — berulang kali sampai tabel penuh. Karena itu kuncinya `title` saja.

Sudah diverifikasi dengan menyimulasikan tanggal `+0`, `+3`, dan `+30`:
hasil selalu **3 agenda, 9 penugasan, 6 anak, 16 master**, dan jumlah akun
tidak bertambah.

Data demo: 7 akun (2 Ibu + 5 Kader), password `password123`, 6 anak,
3 agenda. Rinciannya di `docs/Cara_menjalankan.md`.

---

## 5. Perubahan Mobile

### 5.1 Layar Baru

| File | Untuk | Isi |
| :--- | :--- | :--- |
| `kader/imunisasi_screen.dart` | Kader | Checklist per anak, form catat suntikan, koreksi |
| `kader/jadwal_posyandu_screen.dart` | Kader | Daftar agenda + hapus, filter tanggal |
| `kader/form_agenda.dart` | Kader | Form buat/ubah agenda, pilih banyak petugas |
| `ibu/status_imunisasi_screen.dart` | Ibu | Checklist **read-only** + status berikutnya |
| `ibu/jadwal_posyandu_screen.dart` | Ibu | Daftar agenda **read-only**, upcoming/riwayat |

### 5.2 Lapisan Dasar (Model, Service, Widget)

| File | Isi |
| :--- | :--- |
| `models/immunization.dart` | Parser respons checklist, aman terhadap `null` |
| `models/posyandu_schedule.dart` | Model agenda + petugas |
| `services/immunization_service.dart` | Client checklist & suntikan |
| `services/schedule_service.dart` | Client jadwal & petugas |
| `widgets/immunization_checklist.dart` | Widget checklist **dipakai bersama** Kader & Ibu |

Widget bersama ini disengaja: Kader dan Ibu melihat baris dosis yang sama,
hanya aksi yang berbeda. Kalau tiap role punya checklist sendiri, keduanya
akan menyimpang begitu salah satu diubah.

### 5.3 Navigasi

Dashboard Kader & Ibu, serta tombol imunisasi di `detail_anak_screen.dart`.

---

## 6. Hasil Verifikasi

Angka di bawah adalah hasil pada commit `23d0702`. Setelah Opsi A, angka
tersebut menjadi: **228/228** pemeriksaan API dan **52/52** test Flutter
(lihat bagian 11).

| Pemeriksaan | Hasil |
| :--- | :--- |
| `uji-api.ps1` | **210/210 lulus** |
| `flutter test` | **49/49 lulus** |
| `flutter analyze` | `No issues found!` |
| `php -l` (17 file berubah) | 0 error |
| `route:list --path=api` | 23 route |
| Scan karakter rusak (93 file) | Bersih |

`uji-api.ps1` menambah **4 pemeriksaan baru**: tamu tanpa header JSON pada
4 endpoint yang wajib dapat 401 (bukan 500).

Database kembali persis ke baseline setelah pengujian:
8 user, 6 anak, 0 archived, 0 suntikan, 3 agenda.

Pemeriksaan idempotensi seeder (tanggal `+0`/`+3`/`+30`) — lulus.

---

## 7. Temuan yang Masih Terbuka

Dua temuan masih terbuka. Sisanya sudah ditutup pada Opsi A (bagian 11).

| # | Temuan | Dampak | Saran |
| :--- | :--- | :--- | :--- |
| 7 | Tidak ada notifikasi/pengingat agenda | Ibu tidak tahu ada kegiatan posyandu tanpa membuka aplikasi | Lihat rencana Fase 4 |
| 8 | Rekap jumlah suntikan per bulan untuk Kader | Kader tidak punya vista cepat "berapa anak yang belum lengkap" | Lihat rencana Fase 4 |

### 7.1 Temuan yang Sudah Ditutup (Opsi A)

| # | Temuan | Bagaimana ditutup |
| :--- | :--- | :--- |
| 1 | `interval_months` belum divalidasi server | `ImmunizationController` membandingkan `date_given` dengan dosis tetangga N-1 dan N+1 pada `POST` dan `PATCH` |
| 2 | Tidak ada endpoint `DELETE` untuk suntikan | `DELETE /kader/immunizations/{record}` + soft delete + tombol di aplikasi |
| 3 | `vendor/bin/pint --test` gagal untuk seluruh repo | Pint dijalankan untuk 22 file, sekarang lulus |
| 4 | `laravel/boost` belum dipasang | Terpasang v2.10.0, guideline tailored masuk ke `AGENTS.md` |
| 5 | Commit belum di-push | `git push` dijalankan, `main` sinkron dengan `origin/main` |
| 6 | Akun nyasar `Haji haji` di DB lokal | Dihapus, DB kembali ke baseline seeder |

**Catatan soal temuan #1:** validasi yang dipasang membandingkan tanggal yang
benar-benar dicatat, bukan mengukum dari master `interval_months`. Alasannya
anak boleh datang dengan dosis 2 tanpa dose 1 (dosis 1 diberikan di fasilitas
lain), dan menolak kasus itu akan menghambat kerja lapangan.

---

## 8. Cara Menjalankan & Menguji

```powershell
# 1. Backend
cd C:\laragon\www\posyandu\posyandu-backend
php artisan migrate --seed
php artisan serve

# 2. Isi data demo
php artisan db:seed        # idempotent, aman diulang

# 3. Mobile
cd C:\laragon\www\posyandu\posyandu_mobile
flutter pub get
flutter run -d emulator-5554
```

Akun demo (password `password123`):

| NIK | Nama | Role |
| :--- | :--- | :--- |
| `1111222233334444` | Ibu Annisa | ibu |
| `1111222233334445` | Ibu Ceri | ibu |
| `5555666677778888` | Kader Siti | kader |
| `5555666677778889` | Bidan Rina | kader |
| `5555666677778890` | Kader Dewi | kader |
| `5555666677778891` | Kader Tati | kader |
| `5555666677778892` | Bidan Yuni | kader |

Uji API menyeluruh (butuh `php artisan serve` menyala):

```powershell
cd C:\laragon\www\posyandu
powershell -ExecutionPolicy Bypass -File .\uji-api.ps1
```

---

## 9. Cara Rollback

Untuk membatalkan **Fase 3** saja:

```powershell
cd C:\laragon\www\posyandu\posyandu-backend
php artisan migrate:rollback --step=6   # 5 migration Fase 3 + 1 Opsi A
```

Untuk membatalkan **Opsi A** saja:

```powershell
php artisan migrate:rollback --step=1
```

Rollback `--step=1` mengembalikan unique constraint penuh pada
`immunization_records` dan menghapus kolom `deleted_at`. Dijaga agar gagal
dengan pesan jelas bila sudah ada suntikan yang dibatalkan, karena mengembalikan
constraint penuh bisa melanggar unique.

Rollback `--step=6` menghapus 5 tabel/kolom fase ini. **Data imunisasi dan
agenda akan hilang** - tabel `immunization_records` lama ikut dikembalikan ke
bentuk sebelumnya. Backup dulu bila datanya sudah dipakai sungguhan.

Tidak perlu `migrate:fresh`.

---

## 10. Ringkasan File

### Backend — 12 file

```
app/Http/Controllers/Api/ImmunizationController.php      (baru, 385 baris)
app/Http/Controllers/Api/PetugasController.php         (baru)
app/Http/Controllers/Api/PosyanduScheduleController.php (baru, 391 baris)
app/Models/ImmunizationType.php                         (baru)
app/Models/PosyanduSchedule.php                         (baru)
app/Services/ImmunizationChecklistService.php           (baru)
app/Models/ImmunizationRecord.php                       (diubah)
app/Models/User.php                                     (diubah)
bootstrap/app.php                                       (diubah)
config/posyandu.php                                     (diubah)
database/seeders/DatabaseSeeder.php                     (diubah)
routes/api.php                                          (diubah)
database/migrations/2026_09_26_03*.php                  (5 migration baru)
.env.example                                            (diubah)
```

### Mobile — 12 file

```
lib/models/immunization.dart                    (baru)
lib/models/posyandu_schedule.dart               (baru)
lib/services/immunization_service.dart          (baru)
lib/services/schedule_service.dart              (baru)
lib/widgets/immunization_checklist.dart         (baru)
lib/screens/kader/imunisasi_screen.dart         (baru)
lib/screens/kader/jadwal_posyandu_screen.dart   (baru)
lib/screens/kader/form_agenda.dart              (baru)
lib/screens/ibu/status_imunisasi_screen.dart    (baru)
lib/screens/ibu/jadwal_posyandu_screen.dart     (baru)
lib/screens/ibu/dashboard_ibu_screen.dart       (diubah)
lib/screens/kader/kader_dashboard_screen.dart   (diubah)
lib/screens/kader/detail_anak_screen.dart       (diubah)
lib/utils/constants.dart                        (diubah)
test/kontrak_api_test.dart                      (diubah)
```

### Dokumentasi

```
docs/API_CONTRACT.md     (diubah — +270 baris)
docs/Cara_menjalankan.md (diubah — +92 baris)
docs/LAPORAN_IMUNISASI_JADWAL.md  (dokumen ini)
```

---

## 11. Opsi A - Rapikan Kualitas (27 September 2026)

Fase lanjutan. Menutup 6 dari 8 temuan terbuka di bagian 7.

| | |
| :--- | :--- |
| Migration baru | 1 |
| Endpoint API baru | 1 (total API jadi **24 route**) |
| File disentuh Pint | 22 |
| Pemeriksaan API | **228/228 lulus** (dari 210) |
| Test Flutter | **52/52 lulus** (dari 49) |
| Commit | `b856618` fitur, `38d762b` Pint, `4e15140` Boost |

Semua sudah di-push; `main` sinkron dengan `origin/main`.

### 11.1 Validasi urutan dosis

`ImmunizationController` menolak suntikan yang bertentangan dengan dosis
tetangga pada vaksin yang sama:

- Dosis N tidak boleh lebih awal dari dosis N-1 yang sudah tercatat
- Dosis N tidak boleh lebih baru dari dosis N+1 yang sudah tercatat

Berlaku pada `POST` dan `PATCH`. Record yang sedang diedit dikecualikan dari
perbandingan. Error `422` dengan `errors.date_given`.

Yang dibandingkan hanya dosis yang **sudah ada record-nya** - dosis yang belum
dicatat tidak menghalangi, karena anak boleh datang dengan dosis 2 tanpa
dose 1 (misalnya dosis 1 diberikan di fasilitas lain).

### 11.2 Pembatalan suntikan (soft delete)

Migration `2026_09_26_035000_add_soft_delete_to_immunization_records_table`
menambahkan `deleted_at` dan mengganti unique constraint penuh dengan
**partial unique index**:

```sql
CREATE UNIQUE INDEX immunization_child_type_unique
  ON immunization_records (child_id, immunization_type_id)
  WHERE deleted_at IS NULL;
```

Konsekuensinya: satu anak hanya bisa punya satu record **aktif** per dosis,
tetapi boleh punya riwayat suntikan yang dibatalkan. Dosis yang dibatalkan
bisa dicatat ulang tanpa bentrok.

`ImmunizationRecord` memakai `SoftDeletes`, jadi pembatalan:

- Tidak menghapus data fisik - ada jejak audit
- Mengembalikan status dosis di checklist ke `belum` / `terlambat` sesuai
  tanggal target
- Otomatis membuat `findRecord` membalas `404` untuk record yang sudah
  dibatalkan

### 11.3 Tombol "Batalkan suntikan"

Endpoint saja tidak menyelesaikan masalah asli - di lapangan kader hanya
pakai aplikasi. Tombol ditambahkan di form koreksi (`imunisasi_screen.dart`),
hanya muncul saat dosis sudah punya record, dengan dialog konfirmasi.

Kasus yang ditangani: yang salah adalah **dosisnya**, bukan tanggal/batch.
Solusinya tetap dua operasi terpisah - batalkan, lalu catat ulang.

### 11.4 Kualitas alat

| Yang dikerjakan | Hasil |
| :--- | :--- |
| `vendor/bin/pint` | 22 file dirapikan, `pint --test` sekarang `passed` |
| `laravel/boost` v2.10.0 | Guideline tailored menggantikan instruksi generik di `AGENTS.md` |
| `php -l` (53 file `app/database/config/routes/bootstrap`) | 0 error |
| Scan karakter rusak (97 file) | 7 mojibake diperbaiki, 2 BOM dibuang, 0 tersisa |
| Line ending | Working copy dinormalkan sesuai `.gitattributes` |
| DB lokal | Kembali ke 7 user, 3 anak, 0 archived, 0 suntikan |

Pint memperbaiki antara lain `line_ending` (CRLF → LF), `concat_space`,
`ordered_imports`, dan `heredoc_to_nowdoc`. Semua perubahan bersifat format;
`php -l`, `migrate:status`, `route:list`, dan `uji-api.ps1` dijalankan ulang
sesudahnya.

### 11.5 Temuan tambahan: mojibake yang terlewat

Scan karakter rusak di fase sebelumnya hanya mencari huruf CJK, sehingga tidak
menangkap mojibake. Yang ditemukan: 7 sekuens di `Cara_menjalankan.md` yang
mestinya `—` (em dash), `→`, dan `⋮`, tapi muncul sebagai tiga karakter
berantakan karena UTF-8 pernah dibaca sebagai Windows-1252 lalu ditulis ulang.

Detector yang dipakai sekarang mengenali pola yang lebih umum: 3 karakter
yang kalau di-encode ke CP1252 membentuk satu sekuens UTF-8 3-byte yang valid,
atau 2 karakter membentuk sekuens 2-byte. Seluruh repo (97 file) sudah
bersih; emoji yang ada di dokumen terbaca sebagai surrogate pair dan tidak
terganggu.

Dua file juga punya BOM UTF-8 di awal file (`Cara_menjalankan.md`,
`form_agenda.dart`) - dibuang supaya konsisten dengan file lain.

### 11.6 Catatan menjalankan Boost di mesin ini

`boost:install` menulis `.mcp.json` dan `opencode.json` yang memanggil
`php artisan boost:mcp` dengan command `php`. Command itu harus ada di `PATH`.
Kalau tidak, MCP server tidak akan start - tambahkan PHP ke `PATH` atau panggil
dengan path penuh.

`.agents/` dan `.claude/` berisi salinan skill yang sama (~148 KB masing-masing)
untuk agent berbeda. Keduanya memang di-generate dan wajar di-commit.
