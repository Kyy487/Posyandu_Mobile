<?php

namespace App\Services;

use App\Models\Child;
use App\Models\ImmunizationType;
use Carbon\CarbonImmutable;

/**
 * Menyusun checklist imunisasi untuk satu anak.
 *
 * Status TIDAK disimpan di database. Alasannya: status bergantung pada tanggal
 * lahir anak dan tanggal suntikan, jadi harus dihitung ulang setiap request.
 * Menyimpannya akan cepat basi begitu anak bertambah umurnya - anak yang
 * berumur 5 bulan dan belum disuntik BCG hari ini akan berstatus "terlambat"
 * bulan depan tanpa ada satu pun pencatatan baru.
 *
 * Aturan perhitungan:
 *
 *  1. Ada record suntikan untuk dosis tersebut            -> `sudah`.
 *  2. Belum ada record, dan usia anak < target + toleransi -> `belum`.
 *  3. Belum ada record, dan usia anak >= target + toleransi -> `terlambat`.
 *
 * Toleransi diambil dari `config('posyandu.immunization.terlambat_setelah_bulan')`
 * (default 2 bulan) supaya kategorisasi "terlambat" tidak langsung aktif di
 * hari pertama anak melewati usia target. Ini tetap harus disepakati petugas
 * karena ibu sering datang terlambat sedikit.
 */
class ImmunizationChecklistService
{
    /**
     * Checklist lengkap untuk satu anak: seluruh master dosis, masing-masing
     * sudah atau belum, beserta catatan suntikanya bila ada.
     *
     * Mengembalikan array (bukan Collection) supaya langsung bisa
     * di-`json_encode` oleh controller tanpa wrapper tambahan.
     */
    public function checklistFor(Child $child): array
    {
        $birthDate = CarbonImmutable::parse($child->date_of_birth)->startOfDay();
        $today = CarbonImmutable::today();

        // Toleransi dalam bulan, minimal 0.
        $toleransi = max(0, (int) config('posyandu.immunization.terlambat_setelah_bulan', 2));

        // Satu query untuk semua dosis, lalu di-index agar pengecekan status
        // O(1) per dosis - bukan N+1.
        $records = $child->immunizationRecords()
            ->with('immunizationType:id,code,name,dose_number')
            ->get()
            ->keyBy('immunization_type_id');

        return ImmunizationType::query()
            ->orderedForDosing()
            ->get()
            ->map(fn (ImmunizationType $type) => $this->buildItem(
                $type,
                $records->get($type->id),
                $birthDate,
                $today,
                $toleransi,
            ))
            ->all();
    }

    /**
     * Satu baris checklist: master dosis + status + catatan suntikan bila ada.
     */
    private function buildItem(
        ImmunizationType $type,
        ?object $record,
        CarbonImmutable $birthDate,
        CarbonImmutable $today,
        int $toleransi,
    ): array {
        // Usia anak dalam bulan (lengkap, dibulatkan ke bawah).
        $umurBulan = $this->ageInMonths($birthDate, $today);

        $status = ImmunizationType::STATUS_PENDING;
        $sisaBulan = null;

        if ($record) {
            $status = ImmunizationType::STATUS_DONE;
        } else {
            $target = $type->target_age_months;
            $batas = $target === null ? null : $target + $toleransi;

            if ($batas !== null && $umurBulan >= $batas) {
                $status = ImmunizationType::STATUS_OVERDUE;
            }

            // Sisa waktu menuju status "terlambat", untuk ditampilkan sebagai
            // countdown di layar Kader. Null = tidak punya usia target.
            $sisaBulan = $batas === null ? null : $batas - $umurBulan;
        }

        return [
            'immunization_type_id' => $type->id,
            'code' => $type->code,
            'name' => $type->name,
            'label' => $type->label,
            'dose_number' => (int) $type->dose_number,
            'target_age_months' => $type->target_age_months === null ? null : (int) $type->target_age_months,
            'interval_months' => $type->interval_months === null ? null : (int) $type->interval_months,
            'status' => $status,
            // Sisa bulan menuju terlambat; negatif = sudah terlambat.
            'sisa_bulan' => $sisaBulan,
            'record' => $record ? [
                'id' => $record->id,
                'date_given' => $record->date_given?->format('Y-m-d'),
                'batch_number' => $record->batch_number,
                'notes' => $record->notes,
                'kader_id' => $record->kader_id,
            ] : null,
        ];
    }

    /**
     * Usia anak dalam bulan, dibulatkan ke bawah.
     *
     * Sama dengan definisi "bulan" yang dipakai trigger z-score PostgreSQL
     * (`age_in_months`): jumlah bulan penuh sejak tanggal lahir. Tanggal lahir
     * 15 dan hari ini 26 September -> 5 bulan (bukan 5,4).
     */
    private function ageInMonths(CarbonImmutable $birthDate, CarbonImmutable $today): int
    {
        if ($today->lessThan($birthDate)) {
            return 0;
        }

        return ($today->year - $birthDate->year) * 12
            + ($today->month - $birthDate->month)
            - ($today->day < $birthDate->day ? 1 : 0);
    }
}
