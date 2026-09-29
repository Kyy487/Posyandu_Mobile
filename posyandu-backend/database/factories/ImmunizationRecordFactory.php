<?php

namespace Database\Factories;

use App\Models\Child;
use App\Models\ImmunizationRecord;
use App\Models\ImmunizationType;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<ImmunizationRecord>
 */
class ImmunizationRecordFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'child_id' => Child::factory(),
            'kader_id' => User::factory()->kader(),
            'immunization_type_id' => ImmunizationType::factory(),
            // Tidak dibatasi `now()` ke belakang saja: dosis tertunda yang
            // baru dicatat hari ini juga sah, begitu pun koreksi tanggal
            // suntikan lama lewat PATCH. Yang tidak boleh adalah tanggal
            // sebelum anak lahir, dan itu dicek controller, bukan factory.
            'date_given' => CarbonImmutable::now()
                ->subDays(fake()->numberBetween(0, 400))->toDateString(),
            'batch_number' => fake()->bothify('??-####'),
            'notes' => null,
        ];
    }

    /** Suntikan untuk anak tertentu. */
    public function untukAnak(Child $child): static
    {
        return $this->state(fn (array $attributes) => [
            'child_id' => $child->id,
        ]);
    }

    /** Suntikan untuk satu dosis master tertentu. */
    public function untukDosis(ImmunizationType $type): static
    {
        return $this->state(fn (array $attributes) => [
            'immunization_type_id' => $type->id,
        ]);
    }

    /** Dicatat oleh kader tertentu. */
    public function olehKader(User $kader): static
    {
        return $this->state(fn (array $attributes) => [
            'kader_id' => $kader->id,
        ]);
    }

    /** Suntikan pada tanggal tertentu (`Y-m-d`). */
    public function padaTanggal(string $tanggal): static
    {
        return $this->state(fn (array $attributes) => [
            'date_given' => $tanggal,
        ]);
    }

    /** Catatan suntikan yang sudah dibatalkan (soft delete). */
    public function dibatalkan(): static
    {
        return $this->state(fn (array $attributes) => [
            'deleted_at' => CarbonImmutable::now(),
        ]);
    }

    /** Suntikan tanpa kader, untuk menguji `kader_id` nullable. */
    public function tanpaKader(): static
    {
        return $this->state(fn (array $attributes) => [
            'kader_id' => null,
        ]);
    }
}
