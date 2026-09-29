<?php

namespace Database\Factories;

use App\Models\Child;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Child>
 */
class ChildFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'user_id' => User::factory(),
            // NIK tepat 16 digit karena kolom `children.nik` adalah `varchar(16)`
            // dan `ChildController` memvalidasi `size:16`. `unique()` dipakai
            // karena ada `children_nik_unique`; tanpa itu pembuatan factory
            // kedua dalam satu proses bisa menghasilkan NIK yang sama dan gagal.
            'nik' => (string) fake()->unique()->numerify('3273############'),
            'name' => fake()->name(),
            'date_of_birth' => fake()->dateTimeBetween('-5 years', '-1 month')->format('Y-m-d'),
            'gender' => fake()->randomElement(['L', 'P']),
            'birth_weight' => fake()->randomFloat(2, 2.5, 4.0),
            'birth_height' => fake()->randomFloat(1, 45, 52),
        ];
    }

    /** Anak milik Ibu tertentu. */
    public function milik(User $mother): static
    {
        return $this->state(fn (array $attributes) => [
            'user_id' => $mother->id,
        ]);
    }

    /** Anak laki-laki. */
    public function lakiLaki(): static
    {
        return $this->state(fn (array $attributes) => [
            'gender' => 'L',
        ]);
    }

    /** Anak perempuan. */
    public function perempuan(): static
    {
        return $this->state(fn (array $attributes) => [
            'gender' => 'P',
        ]);
    }
}
