<?php

namespace Database\Factories;

use App\Models\Child;
use App\Models\Consent;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Consent>
 */
class ConsentFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'child_id' => Child::factory(),
            'granted_by' => User::factory(),
            'consent_type' => fake()->randomElement(['data_processing', 'data_sharing', 'research']),
            'granted_at' => fake()->dateTimeBetween('-1 year', 'now'),
            'revoked_at' => null,
            'document_version' => '1.0',
            'notes' => null,
        ];
    }

    public function dataProcessing(): static
    {
        return $this->state(fn (array $attributes) => [
            'consent_type' => 'data_processing',
        ]);
    }

    public function revoked(): static
    {
        return $this->state(fn (array $attributes) => [
            'revoked_at' => now(),
        ]);
    }
}
