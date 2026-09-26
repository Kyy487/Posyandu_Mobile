<?php


namespace Database\Seeders;

use App\Models\User;
use App\Models\Child; // Pastikan model Child di-import
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;


class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        // 1. Buat Akun Uji Coba Ibu Balita
        $ibu = User::create([
            'name' => 'Ibu Annisa',
            'nik' => '1111222233334444',
            'password' => Hash::make('password123'),
            'role' => 'ibu',
        ]);

        $ibu = User::create([
            'name' => 'Ibu Ceri',
            'nik' => '1111222233334445',
            'password' => Hash::make('password123'),
            'role' => 'ibu',
        ]);


        // 2. Buat Data Anak untuk Ibu Annisa
        Child::create([
            'user_id' => $ibu->id, // Mengambil UUID dari Ibu Annisa yang baru dibuat
            'nik' => '1234567890123456',
            'name' => 'Budi Santoso',
            'date_of_birth' => '2025-05-10',
            'gender' => 'L',
            'birth_weight' => 3.2,
            'birth_height' => 50.0,
        ]);


        Child::create([
            'user_id' => $ibu->id, // Mengambil UUID dari Ibu Annisa yang baru dibuat
            'nik' => '1234567890123459',
            'name' => 'Ceril Ganteng',
            'date_of_birth' => '2025-05-11',
            'gender' => 'L',
            'birth_weight' => 3.2,
            'birth_height' => 50.0,
        ]);

        // 3. Buat Akun Uji Coba Kader Posyandu
        User::create([
            'name' => 'Kader Siti',
            'nik' => '5555666677778888',
            'password' => Hash::make('password123'),
            'role' => 'kader',
        ]);
    }
}
