<?php

namespace App\Services;

use App\Models\Child;
use App\Models\ImmunizationType;
use App\Models\PosyanduSchedule;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;

/**
 * Menyusun daftar pengingat untuk Ibu dan Kader.
 *
 * Dua sumber data:
 *  1. Agenda posyandu yang akan datang (tabel `posyandu_schedules`)
 *  2. Imunisasi yang sudah melewati batas toleransi (dihitung via
 *     `ImmunizationChecklistService`)
 *
 * Tidak ada status yang disimpan di database. Semua dihitung ulang setiap
 * request, sama seperti checklist imunisasi — anak yang bulan lalu "belum"
 * dan bulan ini "terlambat" akan berubah sendiri tanpa intervensi.
 */
class ReminderService
{
    /**
     * Berapa hari ke depan agenda dianggap "akan datang".
     */
    private const AGENDA_HARI_KE_DEPAN = 7;

    /**
     * Pengingat untuk Ibu: agenda mendatang + imunisasi terlambat anaknya.
     *
     * @return array{agenda: list<array<string, mixed>>, imunisasi: list<array<string, mixed>>}
     */
    public function untukIbu(User $ibu): array
    {
        $anakList = Child::where('user_id', $ibu->id)->get();

        return [
            'agenda' => $this->agendaMendatang(),
            'imunisasi' => $this->imunisasiTerlambat($anakList),
        ];
    }

    /**
     * Pengingat untuk Kader: agenda yang ia petugasi + jumlah anak terlambat.
     *
     * @return array{agenda: list<array<string, mixed>>, terlambat: int}
     */
    public function untukKader(User $kader): array
    {
        $agenda = PosyanduSchedule::query()
            ->where('status', PosyanduSchedule::STATUS_TERJADWAL)
            ->whereDate('scheduled_date', '>=', CarbonImmutable::today())
            ->whereDate('scheduled_date', '<=', CarbonImmutable::today()->addDays(self::AGENDA_HARI_KE_DEPAN))
            ->whereHas('petugas', fn ($q) => $q->where('users.id', $kader->id))
            ->orderBy('scheduled_date')
            ->orderBy('start_time')
            ->get()
            ->map(fn (PosyanduSchedule $s) => $this->formatAgenda($s))
            ->all();

        $semuaAnak = Child::all();
        $terlambat = 0;

        foreach ($semuaAnak as $anak) {
            $checklist = $this->checklist->checklistFor($anak);
            foreach ($checklist as $dosis) {
                if ($dosis['status'] === ImmunizationType::STATUS_OVERDUE) {
                    $terlambat++;
                }
            }
        }

        return [
            'agenda' => $agenda,
            'terlambat' => $terlambat,
        ];
    }

    /**
     * Agenda posyandu dalam 7 hari ke depan.
     *
     * @return list<array<string, mixed>>
     */
    private function agendaMendatang(): array
    {
        $hariIni = CarbonImmutable::today();
        $batas = $hariIni->addDays(self::AGENDA_HARI_KE_DEPAN);

        return PosyanduSchedule::query()
            ->where('status', PosyanduSchedule::STATUS_TERJADWAL)
            ->whereDate('scheduled_date', '>=', $hariIni)
            ->whereDate('scheduled_date', '<=', $batas)
            ->orderBy('scheduled_date')
            ->orderBy('start_time')
            ->get()
            ->map(fn (PosyanduSchedule $s) => $this->formatAgenda($s))
            ->all();
    }

    /**
     * Imunisasi yang statusnya `terlambat` untuk sekumpulan anak.
     *
     * @param  Collection<int, Child>  $anakList
     * @return list<array<string, mixed>>
     */
    private function imunisasiTerlambat(Collection $anakList): array
    {
        $hasil = [];

        foreach ($anakList as $anak) {
            $checklist = $this->checklist->checklistFor($anak);

            foreach ($checklist as $dosis) {
                if ($dosis['status'] !== ImmunizationType::STATUS_OVERDUE) {
                    continue;
                }

                $hasil[] = [
                    'child_id' => $anak->id,
                    'child_name' => $anak->name,
                    'dosis' => $dosis['label'],
                    'status' => $dosis['status'],
                    'terlambat_bulan' => $this->bulanTerlambat($anak, $dosis),
                ];
            }
        }

        return $hasil;
    }

    /**
     * Format satu agenda untuk respons API.
     *
     * @return array<string, mixed>
     */
    private function formatAgenda(PosyanduSchedule $s): array
    {
        $jarak = CarbonImmutable::today()->diffInDays($s->scheduled_date, false);

        return [
            'id' => $s->id,
            'judul' => $s->title,
            'tanggal' => $s->scheduled_date->format('Y-m-d'),
            'lokasi' => $s->location_name,
            'jarak_hari' => max(0, (int) $jarak),
        ];
    }

    /**
     * Berapa bulan dosis ini sudah terlambat.
     *
     * @param  array<string, mixed>  $dosis
     */
    private function bulanTerlambat(Child $anak, array $dosis): int
    {
        $lahir = CarbonImmutable::parse($anak->date_of_birth)->startOfDay();
        $target = $dosis['target_age_months'];

        if ($target === null) {
            return 0;
        }

        $toleransi = max(0, (int) config('posyandu.immunization.terlambat_setelah_bulan', 2));
        $bulanTerlambat = $this->checklist->ageInMonths($lahir, CarbonImmutable::today()) - ($target + $toleransi);

        return max(0, $bulanTerlambat);
    }

    public function __construct(
        private readonly ImmunizationChecklistService $checklist,
    ) {}
}
