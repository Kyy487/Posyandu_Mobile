<?php

namespace Database\Factories;

use App\Models\Child;
use App\Models\User;
use App\Support\NikHasher;
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
            // dan `ChildController` memvalidasi `size:16`. Uniqueness dijaga
            // oleh `children_nik_hash_unique`, bukan oleh kolom `nik` yang
            // berisi ciphertext acak.
            'nik' => (string) fake()->unique()->numerify('3273############'),
            'nik_hash' => fn (array $attributes) => NikHasher::hash($attributes['nik']),
            'name' => fake()->name(),
            'date_of_birth' => fake()->dateTimeBetween('-5 years', '-1 month')->format('Y-m-d'),
            'gender' => fake()->randomElement(['L', 'P']),
            'birth_order' => fake()->numberBetween(1, 4),
            'birth_weight' => fake()->randomFloat(2, 2.5, 4.0),
            'birth_length' => fake()->randomFloat(1, 45, 52),
            'birth_head_circumference' => fake()->randomFloat(1, 30, 36),
            'birth_status' => 'normal',
            'buku_kia_id' => null,
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
