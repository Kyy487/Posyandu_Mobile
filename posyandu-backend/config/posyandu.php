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

];
