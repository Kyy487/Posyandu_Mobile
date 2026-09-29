# Laporan Pengerjaan — Catatan Keluhan Kader (Opsi C)

**Tanggal:** 27 September 2026
**Status:** Selesai — backend, mobile, dan dokumentasi

---

## 1. Ringkasan

Dulu satu Posyandu mencatat keluhan anak hanya di kepala kader atau di buku
tulis. Theorinya tidak ada yang tahu kalau Posyandu melakukan penimbangan dan
mengukur berat, tapi tidak ada catatan apakah anak itu demam, rewel, atau perlu
dirujuk. Ibu juga tidak punya cara tahu hal itu sudah dicek atau belum.

Opsi C menutup celah itu: kader mencatat keluhan saat penimbangan, Ibu bisa
melihatnya (read-only), dan catatan bisa dikoreksi kalau ada salah tulis.

| | |
| :--- | :--- |
| Tabel | `medical_notes` |
| Migration | `2026_09_27_010000_create_medical_notes_table.php` |
| Endpoint | 4 (1 baca bersama Ibu/Kader, 3 tulis khusus Kader) |
| Layar mobile | 2 (Kader tulis, Ibu baca) |
| Total route API | 24 → **28** (34 termasuk non-API) |
| `uji-api.ps1` | 228 → **288** pemeriksaan |
| `flutter test` | 52 → **67** |

---

## 2. Keputusan yang Diambil

### 2.1 Tiga kolom boolean, bukan satu daftar

Awalnya keluhan bisa dimodelkan jadi `jenis_keluhan = 'demam,rewel'` atau satu
baris per keluhan. Keduanya ditolak karena Opsi E (rekap bulanan) nanti harus
menjawab "berapa anak bulan ini punya demam" dengan satu aggregate:

```sql
SELECT count(DISTINCT child_id) FROM medical_notes
WHERE demam = true AND note_date BETWEEN '2026-09-01' AND '2026-09-30';
```

Dengan kolom boolean, jawaban itu tersedia dari index. Dengan array atau baris
per keluhan, PostgreSQL harus aggregating baris per keluhan dulu, dan index pada
kolom tanggal tidak bisa dipakai untuk itu.

Konsekuensinya: menambah jenis keluhan baru berarti menambah kolom lewat
migration baru, bukan menambah item ke daftar.

### 2.2 Satu anak satu catatan per tanggal

Partial unique index `(child_id, note_date) WHERE deleted_at IS NULL`.

Kenapa satu baris per tanggal, bukan satu baris per keluhan: sehari mungkin anak
demam **dan** diare. Kalau terpisah, rekap "berapa anak yang punya keluhan
apapun hari ini" butuh dua query.

Kenapa soft delete: salah ketuk tanggal adalah kesalahan yang wajar terjadi di
lapangan. Soft delete membiarkan tanggal yang sama dipakai ulang tanpa menghapus
riwayat kesehatan anak.

### 2.3 `note_date` boleh diubah, berbeda dari suntikan

Koreksi suntikan mengunci tanggal (`ImmunizationRecord` punya
`IMMUTABLE_FIELDS`). Catatan keluhan tidak, dan ini memang beda sifat:

- Salah dosis suntikan = keputusan klinis yang tidak bisa "dibatalkan" begitu
  saja karena dosisnya sudah masuk tubuh anak.
- Salah tanggal catatan = salah pilih hari di kalender. Cara memperbaikinya
  adalah mengoreksi tanggal, bukan membatalkan lalu mencatat ulang.

Aturan ini konsisten dengan `PATCH /kader/immunizations/{record}` yang
memang tidak bisa memindahkan tanggal suntikan.

### 2.4 `tindak_lanjut` ditambahkan, tidak ada di daftar awal

RANCANGAN.md hanya menyebut "catatan saran". Kenyataannya Posyandu perlu tahu
apakah anak cukup ditangani di tempat atau perlu dirujuk — itu keputusan dengan
konsekuensi berbeda. Tiga nilai: `ringan` (observasi), `sedang` (perawatan
aktif), `rujuk`.

Ditambah ke CHECK constraint, jadi nilai di luar itu tidak bisa masuk walau
validasi aplikasi dilewati.

### 2.5 `kader_id` selalu dari user login

Tidak pernah diambil dari request body. Kader A tidak bisa menuliskan nama
Kader B di catatan anak.

---

## 3. Perubahan Backend

### 3.1 Migration

```
posyandu-backend/database/migrations/2026_09_27_010000_create_medical_notes_table.php
```

Kolom: `id` (UUID), `child_id`, `measurement_id` (nullable),
`kader_id` (nullable), `note_date`, `demam`/`rewel`/`diare` (boolean default
false), `catatan` (text nullable), `tindak_lanjut` (nullable), `deleted_at`,
timestamps.

Constraint:

| Jenis | Isi |
| :--- | :--- |
| FK | `child_id` → `children.id` **cascade delete** |
| FK | `measurement_id` → `measurements.id` **set null** |
| FK | `kader_id` → `users.id` **set null** |
| Index | `(child_id, note_date)` |
| Unique | partial `(child_id, note_date) WHERE deleted_at IS NULL` |
| CHECK | `tindak_lanjut IN ('ringan','sedang','rujuk')` bila tidak null |
| CHECK | minimal satu boolean true **atau** `catatan` tidak kosong |

`measurement_id` dan `kader_id` sengaja nullable dengan `set null`, bukan cascade:
menghapus penimbangan atau akun kader tidak boleh menghapus catatan kesehatan
anak. `child_id` berbeda — itu datacore yang jelas sudah tidak relevan.

> ⚠️ **Diperbarui oleh migration `2026_09_27_020000_prepare_measurements_for_recap.php`.**
>
> `measurements` sekarang memakai **soft delete**, jadi pembatalan penimbangan
> tidak lagi menghapus barisnya. Akibatnya FK `ON DELETE SET NULL` **tidak
> menyala**: `medical_notes.measurement_id` **tetap** menunjuk penimbangan yang
> dibatalkan, bukan `null` seperti sebelumnya.
>
> Yang tetap berlaku: isi catatan tidak ikut terhapus. FK-nya juga tidak
> dihapus, jadi `forceDelete` masih melepas tautan. Lihat
> `docs/DATABASE_SCHEMA.md` bagian `medical_notes` untuk penjelasan lengkap.

### 3.2 Model dan relasi

`app/Models/MedicalNote.php` — `HasFactory`, `HasUuids`, `SoftDeletes`,
fillable, cast boolean/date, konstanta `TINDAK_LANJUT_*`, accessor
`keluhan_list` dan `ringkasan`, scope `scopeForMonth()` dan
`scopeBetweenDates()`, relasi `child()`, `measurement()`, `kader()`.

Relasi ditambahkan di:

- `Child::medicalNotes()` — `HasMany`
- `User::medicalNotes()` — `HasMany` (kader)
- `Measurement::medicalNotes()` — `HasMany`

### 3.3 Endpoint

| Method | Path | Akses |
| :--- | :--- | :--- |
| `GET` | `/api/children/{id}/medical-notes` | Ibu (anaknya sendiri) + Kader |
| `POST` | `/api/kader/children/{child}/medical-notes` | Kader, `201` |
| `PATCH` | `/api/kader/medical-notes/{note}` | Kader, `200` |
| `DELETE` | `/api/kader/medical-notes/{note}` | Kader, `200` |

`GET` menerima `?month=YYYY-MM` (default bulan berjalan) atau `?all=1`.
Respons memuat `child`, `filter`, `summary`, dan `notes`.

`keluhan` dan `ringkasan` dihitung server supaya Kader dan Ibu tidak mungkin
melihat tampilan berbeda untuk catatan yang sama. `summary` juga dikirim
utuh supaya mobile tidak perlu menjumlahkan sendiri.

### 3.4 Factory dan seeder

- `MedicalNoteFactory` — 5 state: `default`, `demam`, `diare`, `catatanSaja`
  (membuktikan CHECK `catatan`), `olehKader`.
- `ChildFactory` — baru dibuat karena `medical_notes` butuh factory child.
- `DatabaseSeeder::seedMedicalNotes()` — 3 catatan demo: demam + rujukan,
  rewel + perawatan ringan, diare bulan lalu. Idempotent lewat
  `updateOrCreate`.

---

## 4. Perubahan Mobile

| File | Isi |
| :--- | :--- |
| `lib/models/medical_note.dart` | `MedicalNote`, `MedicalNoteList`, `MedicalNoteSummary`, `TindakLanjut` |
| `lib/services/medical_note_service.dart` | 4 endpoint + envelope handling |
| `lib/widgets/medical_note_list_view.dart` | Summary card, note card, empty state, format tanggal |
| `lib/screens/kader/catatan_keluhan_screen.dart` | Daftar + form bottom sheet (create/edit/delete) |
| `lib/screens/ibu/catatan_keluhan_screen.dart` | Read-only + pemilih bulan |
| `lib/utils/constants.dart` | `kaderMedicalNotesEndpoint` |

Navigasi:

- **Kader** — ikon denyut jantung di AppBar `detail_anak_screen.dart`, dan baris
  "Buka Catatan Keluhan" di halaman profil anak.
- **Ibu** — kartu "Catatan Keluhan" di dashboard, di bawah "Status Imunisasi".

Widget `medical_note_list_view.dart` dipakai kedua layar supaya angka dan label
keluhan tidak pernah berbeda antara Kader dan Ibu.

### Dua detail yang mudah salah

**Boolean harus dibaca toleran.** `json['demam'] == true` bernilai `false` bila
server mengirim `"true"` sebagai string — checkbox akan tampil terbalik.
`MedicalNote._toBool()` menangani `true`, `1`, `"true"`, `"1"`, `"yes"`.

**`null` bukan "Tidak diketahui".** `tindak_lanjut` null berarti kader belum
memutuskan, dan `TindakLanjut.label(null)` mengembalikan `-`. Menampilkan
"Tidak diketahui" akan menyiratkan ada data yang rusak.

Tidak ada `intl` yang ditambahkan; format tanggal manual mengikuti pola
`jadwal_posyandu_screen.dart`.

---

## 5. Hasil Verifikasi

### Backend

| Yang dijalankan | Hasil |
| :--- | :--- |
| `php -l` (63 file) | 0 error |
| `vendor/bin/pint --dirty --format agent` | passed |
| `vendor/bin/pint --test --format agent` | passed |
| `uji-api.ps1` | **288/288 lulus** (+60 pemeriksaan grup 9e) |
| `php artisan route:list` | 34 route, 28 API |

Grup 9e menguji: list default bulan berjalan, `?month=`, `?all=1`,
kepemilikan data (Ibu tidak bisa baca catatan anak lain), `403` Ibu pada endpoint
tulis, `422` isi kosong, `422` tanggal ganda, `422` `tindak_lanjut` ngawur,
PATCH sebagian, `nullOnDelete` measurement, soft delete lalu catat ulang, dan
`404` untuk UUID tidak valid.

Rollback + apply ulang migration diverifikasi, termasuk CHECK constraint dan
partial unique index langsung di PostgreSQL.

Baseline DB setelah selesai: 7 user, 3 anak, 3 agenda, 3 `medical_notes` aktif.

### Mobile

| Yang dijalankan | Hasil |
| :--- | :--- |
| `flutter analyze` | No issues found |
| `flutter test` | **67/67 lulus** (15 contract test baru) |

Contract test memakai JSON asli dari `MedicalNoteController`, bukan karangan,
supaya parser tidak melenceng diam-diam kalau format server berubah.

---

## 6. Temuan yang Ditemukan dan Diperbaiki

| Temuan | Perbaikan |
| :--- | :--- |
| `scopeForMonth()` memakai `$month.'-31'` | PostgreSQL menolak tanggal tidak valid; diganti `CarbonImmutable::endOfMonth()` |
| Controller return type `response()->json()` adalah `Illuminate\Http\Response`, bukan `JsonResponse` | TypeError → `500`; diperbaiki tipe return helper |
| `measurement_id` saat penimbangan dihapus | `nullOnDelete` diverifikasi: catatan tetap ada. **Nilai `measurement_id` berubah** setelah `measurements` memakai soft delete — sekarang tetap menunjuk penimbangan yang dibatalkan, bukan `null` (lihat catatan di Bagian 3) |
| Migration gagal parse karena kutip | String SQL di dalam `DB::statement` diperbaiki |
| Data uji dari smoke test tertinggal di DB | 9 record soft-deleted dihapus, DB kembali ke baseline |

---

## 7. Temuan yang Masih Terbuka

- **Rekap lintas anak belum ada.** `summary` sekarang hanya per satu anak.
  Rekap Posyandu per bulan (Opsi E) butuh endpoint agregasi baru.
- **Tidak ada riwayat perubahan.** `updated_at` hanya menyimpan waktu terakhir,
  bukan siapa mengubah apa.
- **Tanpa paginasi.** Satu anak bisa punya banyak catatan kalau filter `all=1`.
- **Tidak ada rekap keluhan lintas anak.** `summary` sekarang hanya per satu anak.
  Kader yang mencari "keluhan apa yang perlu rujukan minggu ini" harus membuka
  tiap anak satu per satu, padahal itu yang paling dibutuhkan di lapangan.
- **Tidak ada push ke Ibu.** Ibu harus membuka aplikasi sendiri untuk tahu
  ada catatan baru.

---

## 8. Cara Menjalankan & Menguji

```powershell
# 1. Migration sudah otomatis jalan saat migrate.
#    Kalau DB sudah ada, cukup pastikan tabelnya ada:
cd posyandu-backend
php artisan migrate:status

# 2. Isi data demo
php artisan db:seed

# 3. Regression suite (butuh server hidup)
cd ..
.\uji-api.ps1
```

```powershell
# Mobile
cd posyandu_mobile
C:\src\flutter\bin\flutter.bat analyze
C:\src\flutter\bin\flutter.bat test
C:\src\flutter\bin\flutter.bat run
```

Manual: login sebagai Kader → Profil anak → ikon denyut jantung → catat
keluhan. Login sebagai Ibu → kartu "Catatan Keluhan".

---

## 9. Cara Rollback

```powershell
cd posyandu-backend
php artisan migrate:rollback --step=1
```

Menghapus tabel `medical_notes` beserta constraint dan index-nya. Tidak ada
data lain yang tersentuh karena tidak ada FK dari tabel lain ke tabel ini.

Untuk mengembalikan fitur di mobile, cukup kembalikan `lib/screens/**` dan
`lib/models/medical_note.dart` ke commit sebelumnya.

---

## 10. Ringkasan File

### Backend — 11 file
- `database/migrations/2026_09_27_010000_create_medical_notes_table.php`
- `app/Models/MedicalNote.php`
- `app/Models/Child.php`
- `app/Models/User.php`
- `app/Models/Measurement.php`
- `app/Http/Controllers/Api/MedicalNoteController.php`
- `routes/api.php`
- `database/factories/MedicalNoteFactory.php`
- `database/factories/ChildFactory.php`
- `database/seeders/DatabaseSeeder.php`

### Mobile — 8 file
- `lib/models/medical_note.dart`
- `lib/services/medical_note_service.dart`
- `lib/widgets/medical_note_list_view.dart`
- `lib/screens/kader/catatan_keluhan_screen.dart`
- `lib/screens/ibu/catatan_keluhan_screen.dart`
- `lib/screens/kader/detail_anak_screen.dart`
- `lib/screens/ibu/dashboard_ibu_screen.dart`
- `lib/utils/constants.dart`

### Dokumentasi
- `docs/API_CONTRACT.md` — bagian "Catatan Keluhan Kader (Opsi C)"
- `docs/DATABASE_SCHEMA.md` — bagian `medical_notes`
- `docs/RENCANA_SELANJUTNYA.md` — Opsi C ditandai selesai
- `docs/SETUP_LOG.md` — checklist Opsi C
- `docs/LAPORAN_MEDICAL_NOTES.md` — dokumen ini
