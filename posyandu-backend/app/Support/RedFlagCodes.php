<?php

namespace App\Support;

use InvalidArgumentException;

/**
 * Allowlist kode red flag untuk skrining awal.
 *
 * Ini bukan diagnosis. Daftar harus disetujui tenaga kesehatan sebelum
 * dipakai produksi; menambah kode berarti memperbarui allowlist ini dan
 * dokumentasi API.
 */
class RedFlagCodes
{
    public const DEMAM_TINGGI = 'demam_tinggi';

    public const KEJANG = 'kejang';

    public const SESAK_NAPAS = 'sesak_napas';

    public const DEHIDRASI = 'dehidrasi';

    public const MUNTAH_BERULANG = 'muntah_berulang';

    public const TIDAK_MAU_MAKAN = 'tidak_mau_makan';

    public const LEMAS = 'lemas';

    public const BB_TIDAK_NAIK = 'bb_tidak_naik';

    public const BBLR = 'bblr';

    public const IKTERUS = 'ikterus';

    /**
     * @return list<string>
     */
    public static function all(): array
    {
        return [
            self::DEMAM_TINGGI,
            self::KEJANG,
            self::SESAK_NAPAS,
            self::DEHIDRASI,
            self::MUNTAH_BERULANG,
            self::TIDAK_MAU_MAKAN,
            self::LEMAS,
            self::BB_TIDAK_NAIK,
            self::BBLR,
            self::IKTERUS,
        ];
    }

    /**
     * @param  array<int, mixed>  $codes
     *
     * @throws InvalidArgumentException
     */
    public static function assertValid(array $codes): void
    {
        $unknown = array_diff($codes, self::all());

        if ($unknown !== []) {
            throw new InvalidArgumentException(
                'Kode red flag tidak dikenal: '.implode(', ', $unknown)
            );
        }
    }
}
