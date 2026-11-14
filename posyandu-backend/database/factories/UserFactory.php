<?php

namespace Database\Factories;

use App\Models\User;
use App\Support\NikHasher;
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
            'nik_hash' => fn (array $attributes) => NikHasher::hash($attributes['nik']),
            'name' => fake()->name(),
            'password' => static::$password ??= Hash::make(self::PASSWORD),
            // Literal string, bukan konstanta: seluruh aplikasi membandingkan
            // role dengan literal (lihat `ChildController`, `PetugasController`).
            'role' => 'ibu',
            'phone_number' => fake()->numerify('08##########'),
            'jabatan' => null,
            'status' => 'active',
            'place_of_birth' => 'Bandung',
            'date_of_birth' => '1990-01-01',
            'gender' => 'P',
            'address' => 'Jl. Test',
            // Factory mewakili akun yang sudah lama terdaftar, jadi onboarding
            // dianggap selesai. Test alur onboarding wajib mengeset state ini
            // secara eksplisit ke `need_child_data`.
            'onboarding_status' => 'completed',
            'no_kk' => null,
            'blood_type' => null,
            'rt_rw' => null,
            'education' => null,
            'occupation' => null,
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
            'status' => 'active',
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

    /** Ibu yang sudah mendaftar tetapi belum disetujui Kader. */
    public function menungguVerifikasi(): static
    {
        return $this->state(fn (array $attributes) => [
            'role' => 'ibu',
            'status' => 'pending',
            'onboarding_status' => 'need_child_data',
        ]);
    }

    /** Ibu yang pendaftarannya ditolak Kader. */
    public function ditolak(): static
    {
        return $this->state(fn (array $attributes) => [
            'role' => 'ibu',
            'status' => 'rejected',
            'onboarding_status' => 'need_child_data',
            'rejection_reason' => 'Data tidak lengkap.',
        ]);
    }

    /** Ibu terverifikasi yang belum melengkapi data anak. */
    public function perluDataAnak(): static
    {
        return $this->state(fn (array $attributes) => [
            'role' => 'ibu',
            'status' => 'active',
            'onboarding_status' => 'need_child_data',
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
