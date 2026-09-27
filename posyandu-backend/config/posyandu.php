<?php

return [

    /*
    |---------------------------------------------------------------------------
    | Kode Pendaftaran Kader
    |---------------------------------------------------------------------------
    |
    | Role TIDAK pernah diambil dari input pengguna. `POST /api/register` selalu
    | membuat akun dengan role `ibu`. Untuk membuat akun `kader`, klien harus
    | mengirim `kader_code` yang sama persis dengan nilai di bawah.
    |
    | Jika nilai ini KOSONG, pendaftaran kader dimatikan dan endpoint membalas 403.
    | Itu kondisi paling aman untuk produksi: akun kader dibuat oleh petugas
    | posyandu, bukan oleh orang yang sedang mendaftar sendiri.
    |
    */

    'kader_registration_code' => env('KADER_REGISTRATION_CODE'),

    /*
    |---------------------------------------------------------------------------
    | Batas Percobaan Login
    |---------------------------------------------------------------------------
    |
    | Mencegah brute force NIK + password. Format: "jumlah_permenit, jumlah_menit".
    |
    */

    'login_throttle' => env('LOGIN_THROTTLE', '5,1'),

    'register_throttle' => env('REGISTER_THROTTLE', '10,1'),

    /*
    |---------------------------------------------------------------------------
    | Nama Posyandu
    |---------------------------------------------------------------------------
    |
    | Untuk tahap ini aplikasi hanya menangani SATU posyandu, jadi tidak ada
    | tabel lokasi. Nama ini dipakai sebagai nilai default `location` pada
    | agenda kegiatan posyandu, dan bisa dioverride per kegiatan bila acara
    | dilakukan di tempat lain.
    |
    */

    'posyandu_name' => env('POSYANDU_NAME', 'Posyandu Desa Sukamaju'),

    /*
    |---------------------------------------------------------------------------
    | Nilai Default Immunization
    |---------------------------------------------------------------------------
    |
    | Master vaksin sendiri ada di tabel `immunization_types` (lihat seeder),
    | bukan di config, karena isinya data referensi kesehatan yang perlu
    | di-query bersama-sama dengan catatan suntikan anak.
    |
    */

    'immunization' => [
        // Catatan suntikan dianggap belum tentu bila berumur lebih dari ini.
        // Setelah ambang ini status berubah dari "belum" jadi "terlambat".
        'terlambat_setelah_bulan' => env('IMMUNIZATION_LATE_AFTER_MONTHS', 2),
    ],

];
