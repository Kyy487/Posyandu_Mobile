<?php

namespace App\Support;

use InvalidArgumentException;

/**
 * Normalisasi dan validasi awal IHS number.
 *
 * Format final menunggu konfirmasi IG SATUSEHAT. Validasi di sini sengaja
 * permisif: trim spasi, tolak kosong, dan batasi karakter yang aman untuk
 * disimpan/dikirim. Jangan menambah aturan panjang/prefix sebelum IG final.
 */
class IhsNumber
{
    public static function normalize(?string $value): ?string
    {
        if ($value === null) {
            return null;
        }

        $value = trim($value);

        if ($value === '') {
            throw new InvalidArgumentException('IHS number wajib diisi.');
        }

        if (! preg_match('/^[A-Za-z0-9._-]{1,50}$/', $value)) {
            throw new InvalidArgumentException(
                'IHS number hanya boleh berisi huruf, angka, titik, garis bawah, dan tanda hubung.'
            );
        }

        return $value;
    }
}
