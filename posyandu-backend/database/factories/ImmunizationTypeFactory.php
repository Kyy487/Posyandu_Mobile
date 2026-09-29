<?php

namespace Database\Factories;

use App\Models\ImmunizationType;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/**
 * @extends Factory<ImmunizationType>
 */
class ImmunizationTypeFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            // `code` + `dose_number` punya unique constraint
            // `immunization_types_code_dose_unique`, jadi keduanya perlu
            // di-random. `unique()` pada `code` saja tidak cukup: dua baris
            // dengan `code` sama tapi `dose_number` beda tetap bentrok kalau
            // `dose_number` ikut random.
            'code' => Str::upper(fake()->unique()->bothify('VAX-??##')),
            'name' => fake()->randomElement([
                'Hepatitis B',
                'Polio',
                'Campak Rubella',
                'Difteri',
                'Tetanus',
                'Pertusis',
                'Rotavirus',
                'Pneumokokal',
            ]),
            'dose_number' => fake()->numberBetween(1, 3),
            'target_age_months' => fake()->numberBetween(0, 18),
            'interval_months' => fake()->numberBetween(1, 12),
            'notes' => null,
        ];
    }

    /**
     * Dosis pertama dari satu vaksin.
     *
     * Dua baris dengan `name` sama tetap boleh, karena yang unik adalah
     * gabungan `code` + `dose_number`.
     */
    public function dosisPertama(string $name = 'Hepatitis B', string $code = 'HB'): static
    {
        return $this->state(fn (array $attributes) => [
            'code' => $code,
            'name' => $name,
            'dose_number' => 1,
        ]);
    }

    /** Dosis berikutnya dari vaksin yang sama. */
    public function dosisBerikutnya(string $name, string $code, int $dose): static
    {
        return $this->state(fn (array $attributes) => [
            'code' => $code,
            'name' => $name,
            'dose_number' => $dose,
        ]);
    }
}
