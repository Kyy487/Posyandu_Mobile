<?php

namespace App\Services;

use App\Models\Child;
use App\Models\ImmunizationRecord;
use App\Models\ImmunizationType;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;

/**
 * Rekap imunisasi satu bulan untuk seluruh Posyandu.
 *
 * Menjawab dua pertanyaan yang berbeda dan sengaja tidak digabung:
 *
 *  1. `activity` - berapa dosis yang benar-benar disuntik bulan itu, per jenis
 *     vaksin. Ini untuk stok: "bulan ini habis 40 dosis, bulan depan
 *     perkirakan butuh 38".
 *  2. `coverage` - kelengkapan tiap anak di akhir bulan itu. Ini untuk
 *     laporan ke BIDAN dan untuk menyiapkan kunjungan rumah.
 *
 * Dua angka ini tidak boleh dijumlahkan. Aktivitas menjawab "apa yang terjadi",
 * coverage menjawab "keadaan apa yang tersisa". Satu Posyandu bisa punya
 * aktivitas tinggi dan coverage-nya tetap jelek.
 *
 * Acuan waktu adalah AKHIR bulan yang diminta, bukan hari ini. Kalau tidak,
 * laporan September yang dibuat di November akan berbeda angkanya dari laporan
 * September yang dibuat di Oktober, dan tidak bisa dipakai sebagai arsip.
 * Karena itu semua suntikan dengan `date_given` setelah tanggal acuan
 * diabaikan, termasuk saat menghitung coverage.
 *
 * Anak yang sudah di-archive (soft delete) tidak dihitung, karena rekap ini
 * dipakai untuk memutuskan siapa yang dikunjungi. Jumlahnya tetap dilaporkan
 * di `excluded_archived` supaya angka yang muncul tidak menutupi ada anak
 * yang tidak ikut dihitung.
 */
class ImmunizationRecapService
{
    public function __construct(private readonly ImmunizationChecklistService $checklist) {}

    /**
     * @return array{
     *     filter: array{month: string, reference_date: string},
     *     activity: array{total_doses: int, total_children: int, by_type: list<array<string, mixed>>},
     *     coverage: array{total_children: int, complete: int, incomplete: int, overdue: int, excluded_archived: int, overdue_children: list<array<string, mixed>>}
     * }
     */
    public function recapForMonth(CarbonImmutable $bulan): array
    {
        $bulan = $bulan->startOfMonth();
        $akhirBulan = $bulan->endOfMonth();

        return [
            'filter' => [
                'month' => $bulan->format('Y-m'),
                // Acuan waktu ikut dikirim supaya konsumen tidak perlu menghitung
                // ulang sendiri, dan tidak bisa salah mengira rekap ini memakai
                // hari ini.
                'reference_date' => $akhirBulan->toDateString(),
            ],
            'activity' => $this->activityForMonth($bulan),
            'coverage' => $this->coverageAt($akhirBulan),
        ];
    }

    /**
     * Dosis yang disuntik sepanjang bulan itu, dikelompokkan per jenis vaksin.
     *
     * Semua jenis vaksin dari master dikembalikan, termasuk yang jumlahnya nol.
     * Kader butuh melihat "tidak ada yang disuntik bulan ini" untuk satu jenis
     * vaksin tertentu, bukan cuma yang ada isinya. Kalau hanya yang ada, mereka
     * tidak bisa membedakan "memang tidak ada suntikan" dari "tidak sempat
     * dicatat".
     *
     * @return array{total_doses: int, total_children: int, by_type: list<array<string, mixed>>}
     */
    private function activityForMonth(CarbonImmutable $bulan): array
    {
        $mulai = $bulan->toDateString();
        $selesai = $bulan->endOfMonth()->toDateString();

        // Soft-deleted record otomatis tersaring oleh global scope, jadi
        // suntikan yang sudah dibatalkan tidak ikut terhitung.
        $jumlahPerTipe = ImmunizationRecord::query()
            ->betweenDates($mulai, $selesai)
            ->selectRaw('immunization_type_id, count(*)::int AS aggregate')
            ->groupBy('immunization_type_id')
            ->pluck('aggregate', 'immunization_type_id');

        $jumlahAnak = ImmunizationRecord::query()
            ->betweenDates($mulai, $selesai)
            ->distinct()
            ->count('child_id');

        $byType = ImmunizationType::query()
            ->orderedForDosing()
            ->get()
            ->map(fn (ImmunizationType $type) => [
                'immunization_type_id' => $type->id,
                'code' => $type->code,
                'name' => $type->name,
                'label' => $type->label,
                'dose_number' => (int) $type->dose_number,
                'count' => (int) ($jumlahPerTipe[$type->id] ?? 0),
            ])
            ->all();

        return [
            'total_doses' => array_sum(array_column($byType, 'count')),
            'total_children' => $jumlahAnak,
            'by_type' => $byType,
        ];
    }

    /**
     * Kelengkapan imunisasi seluruh anak di satu tanggal.
     *
     * Mengambil SEMUA anak dan SEMUA suntikan dalam dua query, lalu menghitung
     * statusnya di PHP. Alternatifnya satu query per anak akan jadi N+1: pada
     * Posyandu dengan 200 anak itu 200 query untuk satu layar rekap.
     * Trades-off-nya jelas dan disengaja - datanya kecil (tanggal lahir + daftar
     * dosis) dan statusnya memang harus dihitung ulang, bukan disimpan.
     *
     * @return array{total_children: int, complete: int, incomplete: int, overdue: int, excluded_archived: int, overdue_children: list<array<string, mixed>>}
     */
    private function coverageAt(CarbonImmutable $tanggalAcuan): array
    {
        $tanggal = $tanggalAcuan->toDateString();

        // `Child` memakai SoftDeletes, jadi anak ter-archive otomatis tersaring.
        //
        // `without('latestMeasurement')` wajib ada: `Child` punya
        // `protected $with = ['latestMeasurement']`, jadi tanpa itu setiap
        // pemanggilan rekap ikut menjalankan subquery korelasi z-score terakhir
        // untuk seluruh anak, lalu membuang hasilnya. Rekap ini tidak menyentuh
        // gizi sama sekali.
        $anak = Child::query()
            ->without('latestMeasurement')
            ->orderBy('name')
            ->get(['id', 'name', 'date_of_birth']);

        $semuaTipe = ImmunizationType::query()->orderedForDosing()->get();

        $suntikanPerAnak = ImmunizationRecord::query()
            ->whereIn('child_id', $anak->modelKeys())
            ->givenOnOrBefore($tanggal)
            ->get(['child_id', 'immunization_type_id'])
            ->groupBy('child_id')
            ->map(fn (Collection $rows): array => $rows->pluck('immunization_type_id')->all());

        $lengkap = 0;
        $terlambat = 0;
        $daftarTerlambat = [];

        foreach ($anak as $child) {
            $ringkas = $this->checklist->summarizeFor(
                CarbonImmutable::parse($child->date_of_birth)->startOfDay(),
                $tanggalAcuan,
                $suntikanPerAnak->get($child->id, []),
                $semuaTipe,
            );

            if ($ringkas['complete']) {
                $lengkap++;

                continue;
            }

            if ($ringkas['overdue_doses'] === []) {
                continue;
            }

            $terlambat++;

            $daftarTerlambat[] = [
                'child_id' => $child->id,
                'name' => $child->name,
                'date_of_birth' => CarbonImmutable::parse($child->date_of_birth)->toDateString(),
                'age_in_months' => $ringkas['age_in_months'],
                'overdue_doses' => $ringkas['overdue_doses'],
            ];
        }

        // Paling terlambat dulu: paling banyak dosis telat, lalu paling lama
        // telat. Kader butuh urutan ini untuk memutuskan siapa dikunjungi dulu.
        usort($daftarTerlambat, function (array $a, array $b): int {
            $selisih = count($b['overdue_doses']) <=> count($a['overdue_doses']);

            return $selisih !== 0
                ? $selisih
                : min($this->oldestSisaBulan($a)) <=> min($this->oldestSisaBulan($b));
        });

        return [
            'total_children' => $anak->count(),
            'complete' => $lengkap,
            'incomplete' => $anak->count() - $lengkap,
            'overdue' => $terlambat,
            'excluded_archived' => Child::withTrashed()->count() - $anak->count(),
            'overdue_children' => $daftarTerlambat,
        ];
    }

    /**
     * `sisa_bulan` paling negatif = paling lama terlambat.
     *
     * @param  array<string, mixed>  $anak
     * @return list<int|null>
     */
    private function oldestSisaBulan(array $anak): array
    {
        $sisa = array_map(
            fn (array $dosis): ?int => $dosis['sisa_bulan'],
            $anak['overdue_doses'],
        );

        // Dosis tanpa usia target selalu punya `sisa_bulan` null. Null dianggap
        // paling tidak terlambat supaya tidak mengacaukan urutan.
        return array_values(array_filter($sisa, fn (?int $n): bool => $n !== null));
    }
}
