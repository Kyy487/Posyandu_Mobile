<?php

namespace Database\Factories;

use App\Models\Child;
use App\Models\User;
use App\Models\Visit;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Visit>
 */
class VisitFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            // Tanggal kunjungan dibatasi acak dalam 90 hari terakhir agar tidak
            // lebih awal dari tanggal lahir anak default factory (2 tahun lalu,
            // lihat MeasurementFactory) dan tidak melewati hari ini.
            'child_id' => Child::factory()->state([
                'date_of_birth' => CarbonImmutable::now()->subYears(2)->toDateString(),
            ]),
            'schedule_id' => null,
            'visit_date' => CarbonImmutable::now()
                ->subDays(fake()->numberBetween(0, 90))->toDateString(),
            'visit_type' => Visit::VISIT_TYPE_POSYANDU,
            'kader_id' => User::factory()->kader(),
            'anamnesis' => null,
            'catatan_kader' => null,
        ];
    }

    /** Kunjungan untuk anak tertentu. */
    public function untukAnak(Child $child): static
    {
        return $this->state(fn (array $attributes) => [
            'child_id' => $child->id,
        ]);
    }

    /** Kunjungan pada tanggal tertentu (`Y-m-d`). */
    public function padaTanggal(string $tanggal): static
    {
        return $this->state(fn (array $attributes) => [
            'visit_date' => $tanggal,
        ]);
    }

    /** Kunjungan yang dipegang kader tertentu. */
    public function olehKader(User $kader): static
    {
        return $this->state(fn (array $attributes) => [
            'kader_id' => $kader->id,
        ]);
    }

    /** Kunjungan rumah. */
    public function kunjunganRumah(): static
    {
        return $this->state(fn (array $attributes) => [
            'visit_type' => Visit::VISIT_TYPE_KUNJUNGAN_RUMAH,
        ]);
    }

    /** Kunjungan yang sudah dibatalkan (soft delete). */
    public function dibatalkan(): static
    {
        return $this->state(fn (array $attributes) => [
            'deleted_at' => CarbonImmutable::now(),
        ]);
    }
}
