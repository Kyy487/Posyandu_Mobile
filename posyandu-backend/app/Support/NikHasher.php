<?php

namespace App\Support;

/**
 * Hash deterministik untuk NIK.
 *
 * NIK hanya 16 digit sehingga SHA-256 tanpa kunci mudah di-brute-force bila
 * database bocor. HMAC memakai kunci aplikasi sehingga penyerang juga harus
 * memiliki kunci tersebut. Nilainya tetap deterministik agar bisa dipakai
 * untuk unique index dan lookup login.
 *
 * Catatan: kunci diambil dari `APP_KEY`. Mengganti `APP_KEY` tanpa menghitung
 * ulang seluruh `nik_hash` akan membuat login pengguna lama gagal.
 */
class NikHasher
{
    public static function hash(?string $nik): ?string
    {
        if ($nik === null || $nik === '') {
            return null;
        }

        $key = (string) config('app.key');

        if ($key === '') {
            throw new \RuntimeException('APP_KEY belum diatur; NIK tidak dapat di-hash dengan aman.');
        }

        return hash_hmac('sha256', $nik, $key);
    }
}
