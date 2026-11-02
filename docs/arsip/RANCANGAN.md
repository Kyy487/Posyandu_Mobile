RANCANGAN SISTEM APLIKASI "SMART POSYANDU"
Fase Pengembangan Dasar (Minimum Viable Product - MVP)

1. Pendahuluan
Dokumen ini menguraikan rancangan sistem untuk aplikasi Smart Posyandu pada fase pengembangan awal (MVP). Pengembangan saat ini difokuskan pada pemenuhan kebutuhan fitur esensial yang menjadi pondasi utama aplikasi. Sistem dirancang untuk menyederhanakan proses administrasi, mendigitalkan rekam medis dasar, serta memberikan edukasi dan intervensi gizi berbasis teknologi yang mudah diakses oleh masyarakat.

2. Batasan Ruang Lingkup Sistem
Agar pengembangan lebih terarah dan aplikatif, sistem pada fase ini dibatasi pada pedoman berikut:

Fokus Pengguna (Aktor): Sistem dibatasi hanya untuk dua role utama, yaitu Kader dan Ibu (User). Pengaturan jabatan yang lebih kompleks atau sistem super-admin dikesampingkan sementara.

Fokus Kategori Pasien: Data difokuskan pada manajemen pendataan Balita dan Ibu Hamil. (Kategori Lansia bersifat opsional dan dikembangkan pada fase berikutnya).

Kalkulasi Gizi AI: Fitur analisis makanan berfokus pada penilaian kualitatif dan umpan balik edukatif, tanpa melakukan kalkulasi skor gizi atau kalori numerik yang kompleks.

3. Spesifikasi Fitur Berdasarkan Aktor (Role)
3.1. Aktor: Kader (Fokus Administrasi & Pemantauan Medis)
Antarmuka untuk Kader dirancang dengan prinsip efisiensi (fast-input) untuk mempermudah pencatatan dan pemantauan di lapangan.

A. Modul Administrasi & Rekam Medis Berkesinambungan (EHR)

Pemisahan Kategori Pasien: Navigasi utama yang memisahkan data Balita dan Ibu Hamil secara jelas.

Buku Medis Digital (Profil Pasien): Halaman profil komprehensif yang memuat histori kesehatan pasien secara berkesinambungan.

Data Demografi: Foto, nama, dan usia/usia kandungan.

Data Antropometri (Vital Sign): Pencatatan Berat Badan (BB), Tinggi Badan (TB), dan Lingkar Kepala.

Kondisi Khusus (Tagging): Penanda visual (label/warna) untuk riwayat medis penting seperti Alergi dan Penyakit Bawaan.

Catatan Medis Historis: Kolom pengisian keluhan kesehatan pasien saat kunjungan (misal: demam, rewel, diare) yang tersimpan sebagai rekam jejak bulanan.

B. Modul Integrasi Smart Triage System (IoT)

Dashboard Pemantauan Triage: Antarmuka khusus (Ruang Periksa) yang menampilkan data secara real-time dari perangkat perangkat keras fisik (alat Smart Triage).

Indikator Peringatan Dini: Menampilkan parameter Suhu Tubuh dan Denyut Jantung dengan indikator warna (misal: layar berubah merah jika suhu terdeteksi tinggi) untuk mempercepat tindakan rujukan kader.

3.2. Aktor: Ibu / User (Fokus Monitoring, Edukasi & Intervensi)
Antarmuka untuk Ibu dirancang agar ramah pengguna (user-friendly), interaktif, dan informatif untuk memotivasi penggunaan aplikasi secara rutin.

A. Modul Monitoring Tumbuh Kembang (e-KMS Mandiri)

Grafik Pertumbuhan Anak: Visualisasi data pertumbuhan (BB, TB) anak dalam bentuk grafik interaktif yang mudah dipahami.

Riwayat Pemeriksaan Bulanan: Akses transparansi bagi Ibu untuk melihat data penimbangan, status gizi (Z-Score), dan catatan keluhan/saran yang diinput oleh Kader pada bulan-bulan sebelumnya.

B. Modul Edukasi Kesehatan Berbasis Animasi

Pusat Multimedia: Galeri konten edukasi interaktif berupa video pendek dan animasi (dihasilkan melalui teknik multimedia) mengenai panduan menyusui, MPASI, sanitasi, dan kesehatan anak.

C. Modul "Sepiring Bergizi" (AI Computer Vision)

Analisis Makanan Berbasis Foto: Ibu dapat memotret porsi makanan anak menggunakan kamera ponsel.

Deteksi Komponen Gizi (Computer Vision): AI mengidentifikasi jenis makanan yang ada di piring (misal: karbohidrat, protein hewani, protein nabati, sayuran).

Umpan Balik Kualitatif (Feedback): Memberikan evaluasi sederhana berbasis visual/warna (Cukup/Kurang) dan saran praktis (Contoh: "Sayur dan nasinya sudah bagus Bunda! Tambahkan telur rebus atau ayam untuk protein si Kecil ya.").
