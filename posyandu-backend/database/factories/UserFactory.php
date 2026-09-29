<?php

namespace Database\Factories;

use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * @extends Factory<User>
 */
class UserFactory extends Factory
{
    /**
     * Password semua user hasil factory ini, dalam bentuk plain.
     *
     * Disimpan sebagai konstanta supaya test bisa login dengan
     * `UserFactory::PASSWORD` tanpa melakukan `Hash::make()` sendiri.
     */
    public const PASSWORD = 'password';

    protected static ?string $password;

    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            // Tabel `users` tidak punya kolom `email` sama sekali. Factory
            // bawaan Laravel menghasilkan `email` + `email_verified_at`,
            // sehingga `User::factory()->create()` gagal dengan
            // "column email does not exist". Identitas user di sini NIK.
            //
            // Panjang NIK harus tepat 16 digit: kolom `users.nik` adalah
            // `varchar(16)` dan `AuthController` memvalidasi `size:16`.
            'nik' => (string) fake()->unique()->numerify('3273############'),
            'name' => fake()->name(),
            'password' => static::$password ??= Hash::make(self::PASSWORD),
            // Literal string, bukan konstanta: seluruh aplikasi membandingkan
            // role dengan literal (lihat `ChildController`, `PetugasController`).
            'role' => 'ibu',
            'phone_number' => fake()->numerify('08##########'),
            'jabatan' => null,
            'remember_token' => Str::random(10),
        ];
    }

    /**
     * Akun kader.
     *
     * `role` menentukan endpoint mana yang boleh diakses, `jabatan` hanya
     * keterangan tampilan. Keduanya sengaja dipisah supaya test bisa membuat
     * kader tanpa jabatan, atau sebaliknya.
     */
    public function kader(): static
    {
        return $this->state(fn (array $attributes) => [
            'role' => 'kader',
            'jabatan' => 'Kader Posyandu',
        ]);
    }

    /** Akun ibu. Sama dengan default, tapi eksplisit supaya test lebih terbaca. */
    public function ibu(): static
    {
        return $this->state(fn (array $attributes) => [
            'role' => 'ibu',
            'jabatan' => null,
        ]);
    }

    /** Bidan, untuk test yang butuh kader dengan jabatan tertentu. */
    public function bidan(): static
    {
        return $this->state(fn (array $attributes) => [
            'role' => 'kader',
            'jabatan' => 'Bidan',
        ]);
    }

    /** Akun kader tanpa jabatan. */
    public function kaderTanpaJabatan(): static
    {
        return $this->state(fn (array $attributes) => [
            'role' => 'kader',
            'jabatan' => null,
        ]);
    }
}
