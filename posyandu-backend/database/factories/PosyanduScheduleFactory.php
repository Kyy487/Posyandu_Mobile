<?php

namespace Database\Factories;

use App\Models\PosyanduSchedule;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<PosyanduSchedule>
 */
class PosyanduScheduleFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        $mulai = CarbonImmutable::now()
            ->addDays(fake()->numberBetween(-30, 30))
            ->setTime(fake()->numberBetween(8, 10), 0);

        return [
            'title' => 'Penimbangan '.fake()->randomElement(['Rutin', 'Bulanan', 'Khusus']),
            'description' => fake()->sentence(),
            'scheduled_date' => $mulai->toDateString(),
            'start_time' => $mulai->toTimeString(),
            'end_time' => $mulai->addHours(fake()->numberBetween(2, 5))->toTimeString(),
            'location' => 'Posyandu '.fake()->randomElement(['Melati', 'Mawar', 'Anggrek']),
            // Dipakai dari konstanta model, bukan literal, karena ada CHECK
            // constraint di database yang hanya menerima salah satu dari empat
            // nilai ini.
            'status' => PosyanduSchedule::STATUS_TERJADWAL,
            'notes' => null,
            'created_by' => User::factory()->kader(),
        ];
    }

    /** Agenda yang sudah selesai. */
    public function selesai(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => PosyanduSchedule::STATUS_SELESAI,
        ]);
    }

    /** Agenda yang dibatalkan. */
    public function dibatalkan(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => PosyanduSchedule::STATUS_DIBATALKAN,
        ]);
    }

    /** Agenda yang sedang berlangsung. */
    public function berlangsung(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => PosyanduSchedule::STATUS_BERLANGSUNG,
        ]);
    }

    /** Agenda pada tanggal tertentu. */
    public function padaTanggal(string $tanggal): static
    {
        return $this->state(fn (array $attributes) => [
            'scheduled_date' => $tanggal,
        ]);
    }

    /** Agenda yang dibuat oleh kader tertentu. */
    public function dibuatOleh(User $kader): static
    {
        return $this->state(fn (array $attributes) => [
            'created_by' => $kader->id,
        ]);
    }
}
