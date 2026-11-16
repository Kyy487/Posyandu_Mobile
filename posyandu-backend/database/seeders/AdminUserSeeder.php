<?php

namespace Database\Seeders;

use App\Models\User;
use App\Support\NikHasher;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

/**
 * Membuat akun admin dari environment.
 *
 * Jalankan eksplisit:
 *   php artisan db:seed --class=AdminUserSeeder
 *
 * Tanpa `POSYANDU_ADMIN_NIK` dan `POSYANDU_ADMIN_PASSWORD`, seeder ini tidak
 * melakukan apa pun. Password hanya dipasang saat akun baru dibuat.
 */
class AdminUserSeeder extends Seeder
{
    public function run(): void
    {
        $nik = trim((string) env('POSYANDU_ADMIN_NIK', ''));
        $password = (string) env('POSYANDU_ADMIN_PASSWORD', '');

        if ($nik === '' || $password === '') {
            $this->command?->warn(
                'AdminUserSeeder dilewati: set POSYANDU_ADMIN_NIK dan POSYANDU_ADMIN_PASSWORD.'
            );

            return;
        }

        $nikHash = NikHasher::hash($nik);
        $user = User::query()->firstOrNew(['nik_hash' => $nikHash]);

        if (! $user->exists) {
            $user->nik = $nik;
            $user->nik_hash = $nikHash;
            $user->name = (string) env('POSYANDU_ADMIN_NAME', 'Admin Posyandu');
            $user->password = Hash::make($password);
            $user->role = 'admin';
            $user->status = 'active';
            $user->onboarding_status = 'completed';
            $user->verified_at = now();
        }

        $user->save();

        $this->command?->info('Akun admin siap: '.$user->name);
    }
}
