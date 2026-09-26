# Cara Menjalankan Project

Aplikasi mobile Smart Posyandu berbasis Flutter + backend Laravel.

## 1. Backend (Laravel + PostgreSQL)

Backend **harus jalan lebih dulu** sebelum aplikasi mobile dibuka.

```powershell
cd C:\laragon\www\posyandu\posyandu-backend
php artisan serve
```

> Bila `php` tidak dikenali di terminal, Laragon belum terdaftar di `PATH`.
> Gunakan path penuh:
> `C:\laragon\bin\php\php-8.4.25-Win32-vs17-x64\php.exe artisan serve`

Cek apakah backend hidup:

```
http://127.0.0.1:8000/api/login
```

Yang benar membalas `422` dengan `{"success":false,"message":"Validasi gagal.",...}`
— itu artinya server sudah hidup, bukan error.

## 2. Membuat Akun Kader

Pendaftaran dari aplikasi **hanya membuat akun `ibu`**. Untuk membuat akun
`kader`, isi dulu kode di `.env`:

```dotenv
KADER_REGISTRATION_CODE=POSYANDU-DEV-2026
```

Lalu:

```powershell
php artisan config:clear
```

Sekarang buka aplikasi, layar Daftar Akun, isi kolom **"Kode kader posyandu
(opsional)"** dengan kode tersebut. Akun yang muncul akan ber-role `kader`.

| Yang diisi | Akun jadi |
| :--- | :--- |
| Kode dikosongkan | `ibu` |
| Kode diisi, cocok | `kader` |
| Kode diisi, salah | Ditolak `403` |

> Mengosongkan `KADER_REGISTRATION_CODE` di `.env` **menonaktifkan** pendaftaran
> kader sepenuhnya. Ini kondisi yang disarankan untuk produksi: akun kader
> dibuat oleh koordinator posyandu, bukanKI orang yang mendaftar sendiri.

### Membuat akun kader tanpa aplikasi

```powershell
php artisan tinker
```

```php
App\Models\User::create([
    'nik' => '3273010101990001',
    'name' => 'Kader Posyandu 01',
    'password' => Illuminate\Support\Facades\Hash::make('Rahasia123'),
    'role' => 'kader',
    'phone_number' => null,
]);
```

## 3. Mobile (Flutter)

### Install dependency

```powershell
cd C:\laragon\www\posyandu\posyandu_mobile
flutter pub get
```

### Nyalakan Android Emulator

Buka Android Studio → Device Manager, lalu jalankan emulator
(mis. `Posyandu API 37.2`). Tunggu sampai selesai booting dan sudah di
Home Screen. Jangan jalankan Flutter saat emulator masih booting.

Cek apakah terdeteksi:

```powershell
flutter devices
```

Contoh output:

```
sdk gphone16k x86 64 - emulator-5554 - android-x64 - Android 17 (API 37)
```

### Jalankan aplikasi

```powershell
flutter run -d emulator-5554
```

### Hot reload

Saat aplikasi sedang berjalan di terminal Flutter:

| Tombol | Fungsi |
| :--- | :--- |
| `r` | Hot reload |
  # Terminal 2
| `q` | Keluar dari Flutter |

## 4. Mengganti Alamat Server

Default `http://10.0.2.2:8000/api` adalah alias localhost dari **emulator
Android**, jadi hanya jalan di emulator. Untuk device fisik atau iOS, tulis
IP komputer di jaringan Wi-Fi:

```powershell
#emplace device fisik
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000/api
```

Cek IP komputer:

```powershell
ipconfig
```

> Jangan pakai `localhost` atau `127.0.0.1` di device fisik — itu menunjuk ke
> perangkatnya sendiri, bukan ke komputer.

## 5. Uji API (opsional tapi berguna)

Skrip `uji-api.ps1` menguji seluruh alur API, membuat user uji sendiri, lalu
**menghapus** datanya di akhir. Data asli tidak tersentuh.

```powershell
# Terminal 1
cd C:\laragon\www\posyandu\posyandu-backend
php artisan serve

# Terminal 2
cd C:\laragon\www\posyandu
powershell -ExecutionPolicy Bypass -File .\uji-api.ps1
```

Skrip membaca `KADER_REGISTRATION_CODE` dari `.env` untuk membuat akun kader
uji. Kalau kosong, skrip berhenti dengan pesan agar Anda mengisinya dulu.

## Troubleshooting

### `adb.exe: failed to install ...` / `Can't find service: package`

Emulator belum selesai booting. Lakukan **Cold Boot**: Android Studio → Device
Manager → klik menu `⋮` pada emulator → **Cold Boot Now**.

### Aplikasi stuck di "Terjadi kesalahan koneksi jaringan"

Backend tidak jalan atau alamat server salah.

```powershell
# pastikan backend hidup
curl http://127.0.0.1:8000/api/login
```

Kalau di device fisik, ganti `baseUrl` dengan `--dart-define` (bagian 4).

### `flutter test` gagal

```powershell
cd C:\laragon\www\posyandu\posyandu_mobile
flutter analyze
flutter test
```

### Respons `429 Terlalu banyak percobaan`

Rate limit aktif (`LOGIN_THROTTLE`, default 10 percobaan/menit per IP). Tunggu
satu menit, atau naikkan nilainya di `.env` untuk pengembangan:

```dotenv
LOGIN_THROTTLE=60,1
```
