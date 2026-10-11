# RANCANGAN_NOTIFIKASI

## 1. Ringkasan

| | |
|---|---|
| **Nama** | Notifikasi & Pengingat (Opsi F) |
| **Target** | Ibu (pengingat agenda & imunisasi), Kader (pengingat agenda) |
| **Estimasi** | 4–6 hari |
| **Kesulitan** | Sedang (FCM/Sulit, Lokal = Sedang) |
| **Status** | Rancangan |

---

## 2. Masalah

Ibu saat ini harus **membuka aplikasi untuk tahu** ada agenda posyandu atau
imunisasi yang jatoh tempo. Kalau tidak membuka, ia tidak tahu — dan anak
terlewat ditimbang atau disuntik.

Ini masalah nyata: seluruh nilai aplikasi ini adalah pencatatan. Pencatatan
hanya berguna kalau petugas dan ibu hadir di posyandu. Tidak hadir = tidak ada
data, dan tidak ada data berarti status gizi anak tidak bisa dihitung.

---

## 3. Dua Jalur Implementasi

### Jalur A — Push Notifikasi (FCM/Firebase)

| | |
|---|---|
| **Kelebihan** | Ibu tidak perlu membuka aplikasi. Pengingat sampai di lock screen. |
| **Kekurangan** | Butuh Firebase project, Server Key, `google-services.json`, izin notifikasi iOS/Android. Server Key **tidak boleh** masuk klien — butuh backend service terpisah atau secret management. Untuk 1 posyandu, biaya setup dan risiko keamanannya tidak sebanding. |
| **Kesimpulan** | **Tidak sekarang.** Baru relevan kalau aplikasi dipakai banyak posyandu. |

### Jalur B — Notifikasi Lokal (dipilih)

| | |
|---|---|
| **Cara** | Backend menandai event mana yang "perlu diingatkan". Mobile membacanya saat aplikasi dibuka, lalu menjadwalkan notifikasi **lokal** dengan `flutter_local_notifications`. |
| **Kelebihan** | Tanpa Firebase, tanpa server key, tanpa internet untuk notifikasi. Bisa bekerja offline. |
| **Kekurangan** | Hanya jalan saat aplikasi pernah dibuka setidaknya sekali. |
| **Kesimpulan** | **Cocok untuk MVP.** Risiko rendah, tanpa infra baru. |

**Rekomendasi: Jalur B.** Alasan detail ada di §3.

---

## 4. Data yang Tersedia

Tidak ada yang perlu ditambah ke database untuk versi pertama. Semua data
yang dibutuhkan sudah ada:

| Sumber | Untuk | Ketersediaan |
|---|---|---|
| `posyandu_schedules` | Pengingat agenda H-1 | `scheduled_date`, `start_time`, `status` |
| `immunization_types.target_age_months` | Kapan imunisasi jatuh tempo | `code`, `dose_number`, `target_age_months` |
| `immunization_records.date_given` | Apakah dosis sudah diberikan | `child_id`, `immunization_type_id` |
| `children.date_of_birth` | Menghitung usia anak | `date_of_birth` |

**Tidak ada kolom baru, tidak ada tabel baru** untuk versi pertama.

---

## 5. Rancangan Endpoint

### `GET /api/ibu/reminders`

Mengembalikan daftar hal yang perlu diketahui Ibu saat ini.

**Struktur respons:**

```json
{
  "success": true,
  "data": {
    "agenda": [
      {
        "id": "uuid",
        "judul": "Penimbangan Rutin Bulanan",
        "tanggal": "2026-10-05",
        "lokasi": "Posyandu Desa Sukamaju",
        "jarak_hari": 2
      }
    ],
    "imunisasi": [
      {
        "child_id": "uuid",
        "child_name": "Naya",
        "dosis": "Hepatitis B (Dosis 2)",
        "status": "terlambat",
        "terlambat_bulan": 1
      }
    ]
  }
}
```

**Aturan:**

1. `agenda` — agenda dengan `status = terjadwal` dan `scheduled_date` dalam
   7 hari ke depan. Urut dari terdekat.
2. `imunisasi` — anak Ibu yang ada dosis dengan status `terlambat` berdasarkan
   `ImmunizationChecklistService` (logika yang sama dengan checklist).
3. **Tidak ada status yang disimpan.** Dihitung ulang setiap request, sama
   seperti checklist imunisasi. Anak yang bulan lalu "belum" dan bulan ini
   "terlambat" akan berubah sendiri tanpa intervensi.

### `GET /api/kader/reminders`

Untuk kader: agenda yang ia petugasi (`posyandu_schedule_petugas`) dalam 7
hari, plus jumlah anak yang status imunisasi `terlambat` di wilayahnya.

**Kenapa kader perlu mengingat:** kader yang memimpin kegiatan perlu tahu
apa yang harus disiapkan sehari sebelumnya.

---

## 6. Rancangan Mobile

### Dependency baru

```yaml
flutter_local_notifications: ^19.0.0
```

Satu-satunya dependency baru. Package inilah yang dipakai untuk menjadwalkan
notifikasi lokal.

### Alur

1. Ibu membuka aplikasi → `GET /api/ibu/reminders`
2. Mobile menjadwalkan notifikasi lokal untuk setiap item yang belum pernah
   dijadwalkan (dilacak via ID event, disimpan di `SharedPreferences`)
3. Notifikasi muncul di waktu yang ditentukan (mis. 08:00 H-1)
4. Setelah aplikasi dibuka, jadwal lama dibersihkan dan dibuat ulang — supaya
   jadwal tidak menumpuk atau basi

### File yang dibuat

```
posyandu_mobile/lib/services/reminder_service.dart   # fetch + jadwalkan
posyandu_mobile/lib/screens/ibu/reminders_screen.dart # tampilan daftar
posyandu_mobile/lib/widgets/reminder_card.dart       # kartu agenda/imunisasi
```

### Layout

```
┌─────────────────────────────────────┐
│  🔔 Pengingat (3)              ⋮    │
├─────────────────────────────────────┤
│  📅 Agenda Posyandu                 │
│  ┌───────────────────────────────┐  │
│  │ Penimbangan Rutin Bulanan     │  │
│  │ 5 Okt 2026 • 2 hari lagi      │  │
│  └───────────────────────────────┘  │
│                                     │
│  💉 Imunisasi Terlambat             │
│  ┌───────────────────────────────┐  │
│  │ Naya — Hepatitis B (Dosis 2)  │  │
│  │ Terlambat 1 bulan             │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │ Naya — BCG                    │  │
│  │ Terlambat 2 bulan             │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

### State yang harus dipisah

| State | Tampilan |
|---|---|
| Loading | Skeleton/spinner |
| Kosong | "Tidak ada pengingat. Semua sudah beres." |
| Error | Pesan + tombol coba lagi |
| Isi | Daftar kartu |

---

## 7. Jadwal Backend (Opsional, Fase 2)

Untuk notifikasi yang jalan **saat aplikasi tertutup**, dibutuhkan:

- Tabel `user_device_tokens` (menyimpan FCM token per user)
- Tabel `notification_logs` (riwayat kirim, untuk audit)
- Scheduled task Laravel (`php artisan schedule:run`) yang berjalan setiap
  hari pagi
- Integrasi FCM

**Ini bukan bagian dari rancangan ini.** Baru dikerjakan setelah aplikasi
terbukti dipakai.

---

## 8. Yang Tidak Dilakukan (Sengaja)

| Tidak | Alasan |
|---|---|
| Firebase/FCM | Infra terlalu besar untuk 1 posyandu, butuh manajemen secret |
| Notifikasi saat app tertutup | Butuh FCM + tabel token |
| Push ke kader lain saat ada perubahan | Over-engineering untuk MVP |
| Pengingat H-3 atau H-7 | Data menunjukkan ibu datang H-1 atau hari H. Terlalu banyak pengingat justru mengurangi kepatuhan |

---

## 9. Fase Pengerjaan

Dibagi 6 fase kecil. Setiap fase selesai = bisa di-commit dan diuji sendiri.

---

### Fase 1 — Backend: data pengingat Ibu

**Tujuan:** endpoint mengembalikan agenda mendatang + imunisasi terlambat.

- [ ] `ReminderService` (backend): query agenda 7 hari ke depan
- [ ] `ReminderService`: query imunisasi `terlambat` per anak (pakai `ImmunizationChecklistService`)
- [ ] `ReminderController@indexIbu` + route `GET /api/ibu/reminders`
- [ ] Test: agenda kosong, agenda ada, imunisasi terlambat, imunisasi tidak terlambat
- [ ] `php artisan test --filter=ReminderTest` lulus

**File:** `app/Services/ReminderService.php`, `app/Http/Controllers/Api/ReminderController.php`, `routes/api.php`, `tests/Feature/ReminderTest.php`

---

### Fase 2 — Backend: data pengingat Kader

**Tujuan:** endpoint mengembalikan agenda yang ia petugasi + jumlah anak terlambat.

- [ ] `ReminderService`: query agenda petugas (`posyandu_schedule_petugas`)
- [ ] `ReminderService`: hitung anak `terlambat` di wilayah kader
- [ ] `ReminderController@indexKader` + route `GET /api/kader/reminders`
- [ ] Test: kader tanpa tugas, kader dengan tugas, anak terlambat
- [ ] `php artisan test --filter=ReminderTest` lulus

**File:** `app/Services/ReminderService.php`, `app/Http/Controllers/Api/ReminderController.php`, `routes/api.php`, `tests/Feature/ReminderTest.php`

---

### Fase 3 — Mobile: model + service fetch

**Tujuan:** mobile bisa membaca respons endpoint dan menyimpannya sebagai model.

- [ ] `lib/models/reminder.dart` — model `Reminder` + `ReminderResponse`
- [ ] `lib/services/reminder_service.dart` — `fetchIbuReminders()`, `fetchKaderReminders()`
- [ ] Test parsing JSON → model (termasuk data kosong)
- [ ] `flutter test` lulus

**File:** `lib/models/reminder.dart`, `lib/services/reminder_service.dart`, `test/reminder_service_test.dart`

---

### Fase 4 — Mobile: jadwal notifikasi lokal

**Tujuan:** notifikasi lokal muncul di waktu yang ditentukan.

- [ ] Tambah `flutter_local_notifications` ke `pubspec.yaml`
- [ ] `ReminderService.scheduleLocal()` — jadwalkan notifikasi per item
- [ ] `ReminderService.clearScheduled()` — bersihkan jadwal lama sebelum buat ulang
- [ ] Track ID event yang sudah dijadwalkan (via `SharedPreferences`)
- [ ] Test: jadwal dibuat, jadwal tidak duplikat, jadwal dibersihkan
- [ ] `flutter test` lulus

**File:** `lib/services/reminder_service.dart`, `test/reminder_service_test.dart`

---

### Fase 5 — Mobile: tampilan

**Tujuan:** Ibu dan kader bisa melihat daftar pengingat.

- [ ] `lib/screens/ibu/reminders_screen.dart` — screen utama
- [ ] `lib/widgets/reminder_card.dart` — kartu agenda + kartu imunisasi
- [ ] State loading / kosong / error / isi dipisah
- [ ] Tombol refresh
- [ ] Test widget: loading, kosong, error, isi
- [ ] `flutter test` lulus

**File:** `lib/screens/ibu/reminders_screen.dart`, `lib/widgets/reminder_card.dart`, `test/reminders_screen_test.dart`

---

### Fase 6 — Integrasi + dokumentasi

**Tujuan:** semua tersambung dan terdokumentasi.

- [ ] Tambah tombol "Pengingat" di dashboard Ibu
- [ ] Tambah tombol "Pengingat" di dashboard Kader
- [ ] Update `docs/API_CONTRACT.md` — endpoint baru
- [ ] Update `docs/README.md` — status fitur
- [ ] Update `docs/RENCANA_SELANJUTNYA.md` — Opsi F selesai
- [ ] `flutter analyze` bersih
- [ ] `flutter test` full suite lulus
- [ ] `php artisan test` full suite lulus
- [ ] Commit + push

---

**Total: ~5 hari.** Setiap fase bisa diselesaikan dalam 1–2 jam.

---

## 10. Kriteria Penerimaan

- [ ] Ibu membuka aplikasi dan melihat agenda yang akan datang
- [ ] Ibu melihat daftar imunisasi yang terlambat per anak
- [ ] Notifikasi lokal muncul di jadwal yang ditentukan
- [ ] Kader melihat agenda yang ia petugasi
- [ ] `flutter analyze` bersih
- [ ] `flutter test` lulus (termasuk test widget reminders)
- [ ] `php artisan test` lulus (termasuk test endpoint reminders)
- [ ] Tidak ada kolom/tabel baru di database
