<?php

namespace Database\Factories;

use App\Models\Child;
use App\Models\Referral;
use App\Models\User;
use App\Models\Visit;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Referral>
 */
class ReferralFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            // Kunjungan dibuat lebih dulu (kunci `visit_id` diproses sebelum
            // `child_id`), lalu anak diambil dari kunjungan itu supaya
            // `child_id` dan `visit_id` selalu konsisten.
            'visit_id' => Visit::factory(),
            'child_id' => fn (array $attributes) => Visit::find($attributes['visit_id'])->child_id,
            'referral_date' => CarbonImmutable::now()
                ->subDays(fake()->numberBetween(0, 30))->toDateString(),
            'referral_type' => fake()->randomElement(Referral::REFERRAL_TYPES),
            'reason' => fake()->sentence(),
            'facility_name' => 'Puskesmas '.fake()->city(),
            'status' => Referral::STATUS_DIBUAT,
            'kader_id' => User::factory()->kader(),
        ];
    }

    /** Rujukan yang terhubung ke kunjungan tertentu (anak ikut dari kunjungan). */
    public function untukKunjungan(Visit $visit): static
    {
        return $this->state(fn (array $attributes) => [
            'visit_id' => $visit->id,
            'child_id' => $visit->child_id,
        ]);
    }

    /** Rujukan untuk anak tertentu; membuat satu kunjungan bila diperlukan. */
    public function untukAnak(Child $child): static
    {
        return $this->state(function () use ($child) {
            $visit = Visit::factory()->untukAnak($child)->create();

            return [
                'visit_id' => $visit->id,
                'child_id' => $child->id,
            ];
        });
    }

    /** Rujukan pada tanggal tertentu (`Y-m-d`). */
    public function padaTanggal(string $tanggal): static
    {
        return $this->state(fn (array $attributes) => [
            'referral_date' => $tanggal,
        ]);
    }

    /** Rujukan yang dicatat kader tertentu. */
    public function olehKader(User $kader): static
    {
        return $this->state(fn (array $attributes) => [
            'kader_id' => $kader->id,
        ]);
    }

    /** Rujukan yang sudah selesai ditindaklanjuti. */
    public function selesai(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => Referral::STATUS_SELESAI,
        ]);
    }

    /** Rujukan yang sudah dibatalkan (soft delete). */
    public function dibatalkan(): static
    {
        return $this->state(fn (array $attributes) => [
            'deleted_at' => CarbonImmutable::now(),
        ]);
    }
}
