<?php

namespace Database\Factories;

use App\Models\Child;
use App\Models\Measurement;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Measurement>
 */
class MeasurementFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            // Tanggal lahir anak yang dibuat otomatis DIBATAS di sini, bukan
            // mengandalkan rentang default `ChildFactory` ('-5 tahun' sampai
            // '-1 bulan'). Alasannya: trigger `trg_measurements_who_zscore`
            // menolak `measurement_date` yang lebih awal dari tanggal lahir,
            // jadi anak yang kebetulan baru lahir 1 bulan lalu akan menggagalkan
            // factory ini. Dengan lahir 2 tahun lalu, rentang 300 hari ke
            // belakang selalu sah.
            'child_id' => Child::factory()->state([
                'date_of_birth' => CarbonImmutable::now()->subYears(2)->toDateString(),
            ]),
            'kader_id' => User::factory()->kader(),
            'measurement_date' => CarbonImmutable::now()
                ->subDays(fake()->numberBetween(0, 300))->toDateString(),
            'weight_kg' => fake()->randomFloat(1, 4.0, 18.0),
            'height_cm' => fake()->randomFloat(1, 45.0, 100.0),
            'head_circumference_cm' => fake()->randomFloat(1, 33.0, 48.0),
            // `age_in_months` dan `z_score_wfa` sengaja tidak diisi: keduanya
            // dihitung trigger. Mengisi manual akan ditimpa trigger, dan
            // mengisi `z_score_wfa` tanpa trigger membuat test false positive.
        ];
    }

    /**
     * Penimbangan untuk anak tertentu.
     *
     * Tanggal digeser supaya tidak lebih awal dari tanggal lahir anak, karena
     * trigger akan menolaknya kalau iya.
     */
    public function untukAnak(Child $child): static
    {
        return $this->state(fn (array $attributes) => [
            'child_id' => $child->id,
            'measurement_date' => $this->tanggalSesudahLahir($child),
        ]);
    }

    /** Dicatat oleh kader tertentu. */
    public function olehKader(User $kader): static
    {
        return $this->state(fn (array $attributes) => [
            'kader_id' => $kader->id,
        ]);
    }

    /** Penimbangan pada tanggal tertentu (`Y-m-d`). */
    public function padaTanggal(string $tanggal): static
    {
        return $this->state(fn (array $attributes) => [
            'measurement_date' => $tanggal,
        ]);
    }

    /**
     * Penimbangan yang sudah dibatalkan (soft delete).
     *
     * Dipakai test rekap: baris seperti ini harus hilang dari perhitungan,
     * tapi tidak boleh hilang secara fisik.
     */
    public function dibatalkan(): static
    {
        return $this->state(fn (array $attributes) => [
            'deleted_at' => CarbonImmutable::now(),
        ]);
    }

    /**
     * Penimbangan tanpa kader.
     *
     * Ini kondisi yang harus didukung setelah migration
     * `2026_09_27_020000`: `kader_id` nullable karena `ON DELETE SET NULL`.
     */
    public function tanpaKader(): static
    {
        return $this->state(fn (array $attributes) => [
            'kader_id' => null,
        ]);
    }

    /**
     * Tanggal acak yang sah untuk anak tertentu: setelah lahir, tidak lebih
     * dari hari ini.
     *
     * Dipisah supaya `untukAnak()` dan test memakai aturan yang sama.
     */
    private function tanggalSesudahLahir(Child $child): string
    {
        $lahir = CarbonImmutable::parse((string) $child->date_of_birth)->startOfDay();
        $kandidat = CarbonImmutable::now()->subDays(fake()->numberBetween(1, 300))->startOfDay();

        return $kandidat->lessThan($lahir) ? $lahir->toDateString() : $kandidat->toDateString();
    }
}
