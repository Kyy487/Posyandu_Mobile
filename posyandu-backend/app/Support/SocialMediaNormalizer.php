<?php

namespace App\Support;

use InvalidArgumentException;

/**
 * Menormalkan handle sosial media sebelum disimpan.
 *
 * Database menyimpan handle bersih, bukan URL. Dengan begitu aplikasi mobile
 * tidak perlu menebak apakah nilai berisi `@`, URL lengkap, atau nomor telepon.
 */
class SocialMediaNormalizer
{
    public static function whatsapp(?string $value): ?string
    {
        if ($value === null) {
            return null;
        }

        $value = trim($value);

        if ($value === '') {
            return null;
        }

        $hasPlus = str_starts_with($value, '+');
        $digits = preg_replace('/\D/', '', $value) ?? '';

        if (str_starts_with($digits, '0')) {
            $digits = '62'.substr($digits, 1);
        } elseif (str_starts_with($digits, '8')) {
            $digits = '62'.$digits;
        } elseif (str_starts_with($digits, '620')) {
            $digits = '62'.substr($digits, 3);
        } elseif (! $hasPlus && ! str_starts_with($digits, '62')) {
            $digits = '62'.$digits;
        }

        if (! preg_match('/^62[0-9]{8,13}$/', $digits)) {
            throw new InvalidArgumentException(
                'Nomor WhatsApp harus berupa nomor Indonesia yang valid, misalnya 081234567890.'
            );
        }

        return '+'.$digits;
    }

    public static function instagram(?string $value): ?string
    {
        return self::handle($value, 'instagram', 50);
    }

    public static function facebook(?string $value): ?string
    {
        return self::handle($value, 'facebook', 100);
    }

    private static function handle(?string $value, string $platform, int $maxLength): ?string
    {
        if ($value === null) {
            return null;
        }

        $value = trim($value);

        if ($value === '') {
            return null;
        }

        $value = preg_replace(
            '#^https?://(www\.|m\.)?'.preg_quote($platform, '#').'\.com/#i',
            '',
            $value
        ) ?? $value;

        $value = preg_split('/[?#]/', $value, 2)[0] ?? $value;
        $value = trim($value, "/ \t\n\r\0\x0B");
        $value = ltrim($value, '@');

        if (! preg_match('/^[A-Za-z0-9._]{1,'.$maxLength.'}$/', $value)) {
            throw new InvalidArgumentException(
                ucfirst($platform).' hanya boleh berisi huruf, angka, titik, dan garis bawah.'
            );
        }

        return $value;
    }
}
