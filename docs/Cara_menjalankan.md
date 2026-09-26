 Posyandu Mobile

Aplikasi mobile Posyandu berbasis Flutter.

## Cara Menjalankan Project

### 1. Buka Folder Project

Buka terminal di VS Code, kemudian masuk ke folder project:

```powershell
cd C:\laragon\www\posyandu_mobile
2. Install Dependency

Jalankan perintah:

flutter pub get

Tunggu sampai proses selesai.

3. Nyalakan Android Emulator

Buka Android Studio → Device Manager, kemudian jalankan emulator:

Posyandu API 37.2

atau perangkat:

sdk gphone16k x86 64

Tunggu sampai emulator selesai melakukan booting dan masuk ke Home Screen Android.

Jangan menjalankan Flutter ketika emulator masih dalam proses booting.

4. Cek Emulator

Pastikan emulator sudah terdeteksi oleh Flutter:

flutter devices

Jika berhasil, akan muncul perangkat seperti:

sdk gphone16k x86 64 • emulator-5554 • android-x64 • Android 17 (API 37)
5. Jalankan Aplikasi

Jalankan:

flutter run -d emulator-5554

Flutter akan melakukan proses build dan menginstall aplikasi ke emulator.

Jika berhasil, akan muncul:

√ Built build\app\outputs\flutter-apk\app-debug.apk

Setelah proses selesai, aplikasi Posyandu Mobile akan otomatis terbuka pada Android Emulator.

6. Hot Reload

Saat aplikasi sedang berjalan di terminal Flutter:

r  → Hot Reload
R  → Hot Restart
q  → Keluar dari Flutter
Troubleshooting

Jika muncul error:

adb.exe: failed to install ...
Can't find service: package

Pastikan Android Emulator sudah benar-benar selesai booting dan sudah masuk ke Home Screen.

Jika masih mengalami error, lakukan Cold Boot:

Buka Android Studio.
Masuk ke Device Manager.
Cari emulator Posyandu API 37.2.
Klik menu ⋮.
Pilih Cold Boot Now.
Tunggu sampai emulator masuk ke Home Screen.
Jalankan kembali:
flutter devices

Kemudian:

flutter run -d emulator-5554
Quick Start

Jika emulator sudah menyala dan terdeteksi, cukup jalankan:

cd C:\laragon\www\posyandu_mobile
flutter pub get
flutter run -d emulator-5554
