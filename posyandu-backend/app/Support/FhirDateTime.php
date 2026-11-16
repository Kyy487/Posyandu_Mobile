<?php

namespace App\Support;

use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;

/**
 * Konversi waktu lokal Posyandu ke format FHIR.
 *
 * FHIR memakai ISO 8601 dengan zona waktu. Payload SATUSEHAT dikirim dalam UTC
 * agar tidak bergantung pada zona waktu server pembaca.
 */
class FhirDateTime
{
    public const LOCAL_TIMEZONE = 'Asia/Jakarta';

    public static function fromDate(?string $date): ?string
    {
        if ($date === null || $date === '') {
            return null;
        }

        return CarbonImmutable::parse($date, self::LOCAL_TIMEZONE)
            ->startOfDay()
            ->utc()
            ->format('Y-m-d\TH:i:s\Z');
    }

    public static function fromDateTime(CarbonInterface|string|null $value): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }

        return CarbonImmutable::parse($value)
            ->utc()
            ->format('Y-m-d\TH:i:s\Z');
    }
}
