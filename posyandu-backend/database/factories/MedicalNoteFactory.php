<?php

namespace Database\Factories;

use App\Models\Child;
use App\Models\MedicalNote;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<MedicalNote>
 */
class MedicalNoteFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'child_id' => Child::factory(),
            'measurement_id' => null,
            'kader_id' => null,
            // Tanggal acak dalam 90 hari terakhir. Tidak boleh lebih dari
            // `today` karena controller memvalidasi `before_or_equal:today`.
            'note_date' => fake()->dateTimeBetween('-90 days', 'now')->format('Y-m-d'),
            'demam' => fake()->boolean(30),
            'rewel' => fake()->boolean(30),
            'diare' => fake()->boolean(20),
            'catatan' => null,
            'tindak_lanjut' => null,
        ];
    }

    /**
     * Keluhan demam, tanpa catatan tambahan.
     *
     * State paling sering dipakai skenario "anak demam, kader merujuk".
     */
    public function demam(): static
    {
        return $this->state(fn (array $attributes) => [
            'demam' => true,
            'rewel' => false,
            'diare' => false,
            'catatan' => null,
            'tindak_lanjut' => MedicalNote::TINDAK_LANJUT_RUJUK,
        ]);
    }

    /** Keluhan diare dengan catatan Cascara. */
    public function diare(): static
    {
        return $this->state(fn (array $attributes) => [
            'demam' => false,
            'rewel' => false,
            'diare' => true,
            'catatan' => 'Cascara oral 1 sachet per hari',
            'tindak_lanjut' => MedicalNote::TINDAK_LANJUT_RINGAN,
        ]);
    }

    /**
     * Catatan saran tanpa keluhan yang dicentang.
     *
     * Tetap lolos CHECK constraint karena `catatan` terisi - inilah kasus yang
     * membuat aturan "minimal satu keluhan" tidak boleh hanya mengecek kolom
     * boolean.
     */
    public function catatanSaja(): static
    {
        return $this->state(fn (array $attributes) => [
            'demam' => false,
            'rewel' => false,
            'diare' => false,
            'catatan' => 'Ibu diminta lebih sering menyusui',
            'tindak_lanjut' => MedicalNote::TINDAK_LANJUT_RINGAN,
        ]);
    }

    /** Catatan yang ditautkan ke penimbangan tertentu. */
    public function untukAnak(Child $child): static
    {
        return $this->state(fn (array $attributes) => [
            'child_id' => $child->id,
        ]);
    }

    /** Catatan yang dicatat kader tertentu. */
    public function olehKader(User $kader): static
    {
        return $this->state(fn (array $attributes) => [
            'kader_id' => $kader->id,
        ]);
    }
}
