<?php

namespace App\Services;

use App\Models\Child;
use App\Models\ImmunizationType;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;

/**
 * Menyusun checklist imunisasi untuk satu anak, dan kelengkapan untuk
 * banyak anak sekaligus.
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
 *
 * SEMUA perhitungan status melewati `evaluate()`. Rekap bulanan Posyandu
 * (`ImmunizationRecapService`) memakai service yang sama persis, dan itu bukan
 * soal gaya kode: kalau ada dua salinan aturan sendiri, checklist per anak dan
 * rekap lintas anak pasti akan berbeda angkanya pada kasus yang sama, dan tidak
 * ada yang bisa altitud mana yang benar.
 */
class ImmunizationChecklistService
{
    /**
     * Checklist lengkap untuk satu anak: seluruh master dosis, masing-masing
     * sudah atau belum, beserta catatan suntikanya bila ada.
     *
     * `$asOf` dipakai untuk laporan historis. Kalau null, memakai hari ini -
     * itu perilaku lama yang dipakai layar checklist.
     *
     * Mengembalikan array (bukan Collection) supaya langsung bisa
     * di-`json_encode` oleh controller tanpa wrapper tambahan.
     *
     * @return list<array<string, mixed>>
     */
    public function checklistFor(Child $child, ?CarbonImmutable $asOf = null): array
    {
        $birthDate = CarbonImmutable::parse($child->date_of_birth)->startOfDay();
        $asOf ??= CarbonImmutable::today();

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
                $asOf,
            ))
            ->all();
    }

    /**
     * Kelengkapan imunisasi satu anak dalam bentuk ringkas.
     *
     * Dipakai rekap bulanan, yang harus menilai ratusan anak dalam satu
     * request. Karena itu method ini menerima set dosis yang sudah disuntik
     * sebagai array, bukan melakukan query sendiri - pemanggil sudah memuat
     * seluruh data anak dalam satu query.
     *
     * Dosis yang BELUM jatuh tempo diabaikan. Anak usia 2 bulan tidak boleh
     * ditandai "belum lengkap" hanya karena belum waktunya BCG; yang dihitung
     * adalah dosis yang usianya sudah tercapai tapi belum disuntik. Dengan begitu
     * anak yang belum punya dosis jatuh tempo apa pun dianggap `complete`.
     *
     * @param  list<string>  $givenTypeIds  id `immunization_types` yang sudah disuntik
     * @param  Collection<int, ImmunizationType>|null  $types  master dosis, dimuat sekali untuk semua anak
     * @return array{age_in_months: int, complete: bool, missing_doses: list<array<string, mixed>>, overdue_doses: list<array<string, mixed>>}
     */
    public function summarizeFor(
        CarbonImmutable $birthDate,
        CarbonImmutable $asOf,
        array $givenTypeIds,
        ?Collection $types = null,
    ): array {
        $types ??= ImmunizationType::query()->orderedForDosing()->get();

        $sudahDisuntik = array_flip($givenTypeIds);
        $missing = [];
        $overdue = [];

        foreach ($types as $type) {
            if (isset($sudahDisuntik[$type->id])) {
                continue;
            }

            $hasil = $this->evaluate($type, $birthDate, $asOf);

            if (! $hasil['due']) {
                continue;
            }

            $item = $this->presentDose($type, $hasil);

            $missing[] = $item;

            if ($hasil['overdue']) {
                $overdue[] = $item;
            }
        }

        return [
            'age_in_months' => $this->ageInMonths($birthDate, $asOf),
            'complete' => $missing === [],
            'missing_doses' => $missing,
            'overdue_doses' => $overdue,
        ];
    }

    /**
     * Satu baris checklist: master dosis + status + catatan suntikan bila ada.
     */
    private function buildItem(
        ImmunizationType $type,
        ?object $record,
        CarbonImmutable $birthDate,
        CarbonImmutable $asOf,
    ): array {
        $hasil = $this->evaluate($type, $birthDate, $asOf);

        if ($record) {
            $status = ImmunizationType::STATUS_DONE;
        } elseif ($hasil['overdue']) {
            $status = ImmunizationType::STATUS_OVERDUE;
        } else {
            $status = ImmunizationType::STATUS_PENDING;
        }

        return [
            'immunization_type_id' => $type->id,
            'code' => $type->code,
            'name' => $type->name,
            'label' => $type->label,
            'dose_number' => (int) $type->dose_number,
            'target_age_months' => $this->targetAgeMonths($type),
            'interval_months' => $type->interval_months === null ? null : (int) $type->interval_months,
            'status' => $status,
            // Sisa bulan menuju terlambat; negatif = sudah terlambat.
            //
            // Hanya untuk dosis yang BELUM disuntik. Dosis yang sudah `sudah`
            // selalu `null`: countdown-nya tidak relevan, dan angka yang
            // tersisa (mis. -12 untuk anak 14 bulan yang sudah suntik MR)
            // akan terbaca "terlambat 12 bulan" padahal dosisnya justru
            // sudah diberikan tepat waktu. `evaluate()` tetap satu-satunya
            // tempat aturan status; null ini murni aturan tampilan.
            'sisa_bulan' => $record ? null : $hasil['sisa_bulan'],
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
     * Aturan status untuk satu dosis - satu-satunya tempat aturan ini ditulis.
     *
     * `due` dan `overdue` sengaja dipisah. `due` berarti "usianya sudah mencapai
     * usia target", sedangkan `overdue` berarti "sudah melewati target +
     * toleransi". Dosis yang `due` tapi belum disuntik masuk daftar `missing`;
     * yang `overdue` masuk subset dari daftar itu. Dosis yang belum `due` tidak
     * masuk kategori mana pun.
     *
     * @return array{age_in_months: int, due: bool, overdue: bool, sisa_bulan: int|null}
     */
    private function evaluate(ImmunizationType $type, CarbonImmutable $birthDate, CarbonImmutable $asOf): array
    {
        $umurBulan = $this->ageInMonths($birthDate, $asOf);
        $target = $type->target_age_months;
        $batas = $target === null ? null : $target + $this->toleranceInMonths();

        return [
            'age_in_months' => $umurBulan,
            'due' => $target !== null && $umurBulan >= $target,
            'overdue' => $batas !== null && $umurBulan >= $batas,
            // Sisa waktu menuju status "terlambat", untuk ditampilkan sebagai
            // countdown di layar Kader. Null = tidak punya usia target.
            'sisa_bulan' => $batas === null ? null : $batas - $umurBulan,
        ];
    }

    /**
     * Bentuk satu dosis untuk keluaran rekap. Field yang dipakai layar
     * checklist (`status`, `record`) sengaja tidak disertakan - recap tidak
     * menampilkan satu baris checklist.
     *
     * @param  array{age_in_months: int, due: bool, overdue: bool, sisa_bulan: int|null}  $hasil
     * @return array<string, mixed>
     */
    private function presentDose(ImmunizationType $type, array $hasil): array
    {
        return [
            'immunization_type_id' => $type->id,
            'code' => $type->code,
            'name' => $type->name,
            'label' => $type->label,
            'dose_number' => (int) $type->dose_number,
            'target_age_months' => $this->targetAgeMonths($type),
            'sisa_bulan' => $hasil['sisa_bulan'],
        ];
    }

    private function targetAgeMonths(ImmunizationType $type): ?int
    {
        return $type->target_age_months === null ? null : (int) $type->target_age_months;
    }

    /**
     * Toleransi keterlambatan dalam bulan, minimal 0.
     *
     * Nilai negatif diklem jadi 0 supaya konfigurasi yang salah ketik tidak
     * membuat semua anak langsung berstatus "terlambat".
     */
    private function toleranceInMonths(): int
    {
        return max(0, (int) config('posyandu.immunization.terlambat_setelah_bulan', 2));
    }

    /**
     * Usia anak dalam bulan, dibulatkan ke bawah.
     *
     * Sama dengan definisi "bulan" yang dipakai trigger z-score PostgreSQL
     * (`age_in_months`): jumlah bulan penuh sejak tanggal lahir. Tanggal lahir
     * 15 dan hari ini 26 September -> 5 bulan (bukan 5,4).
     */
    private function ageInMonths(CarbonImmutable $birthDate, CarbonImmutable $asOf): int
    {
        if ($asOf->lessThan($birthDate)) {
            return 0;
        }

        return ($asOf->year - $birthDate->year) * 12
            + ($asOf->month - $birthDate->month)
            - ($asOf->day < $birthDate->day ? 1 : 0);
    }
}
