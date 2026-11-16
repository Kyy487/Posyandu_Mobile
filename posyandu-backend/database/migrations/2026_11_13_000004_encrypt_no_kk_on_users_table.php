<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;

/**
 * Enkripsi `users.no_kk` yang sebelumnya masih plaintext.
 *
 * Nomor KK adalah data pribadi yang sangat sensitif dan dipakai bersama satu
 * keluarga, jadi tidak boleh disimpan apa adanya. Kolom diperlebar ke `text`
 * karena ciphertext Laravel jauh lebih panjang dari 16 digit.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement('ALTER TABLE users ALTER COLUMN no_kk TYPE text');

        DB::table('users')
            ->select(['id', 'no_kk'])
            ->whereNotNull('no_kk')
            ->orderBy('id')
            ->chunkById(100, function ($users): void {
                foreach ($users as $user) {
                    $value = (string) $user->no_kk;

                    if ($value === '') {
                        continue;
                    }

                    try {
                        Crypt::decryptString($value);

                        continue;
                    } catch (Throwable) {
                        // Bukan ciphertext Laravel: masih plaintext.
                    }

                    DB::table('users')
                        ->where('id', $user->id)
                        ->update(['no_kk' => Crypt::encryptString($value)]);
                }
            });
    }

    public function down(): void
    {
        DB::table('users')
            ->select(['id', 'no_kk'])
            ->whereNotNull('no_kk')
            ->orderBy('id')
            ->chunkById(100, function ($users): void {
                foreach ($users as $user) {
                    try {
                        $plain = Crypt::decryptString((string) $user->no_kk);
                    } catch (Throwable) {
                        continue;
                    }

                    DB::table('users')
                        ->where('id', $user->id)
                        ->update(['no_kk' => $plain]);
                }
            });

        DB::statement('ALTER TABLE users ALTER COLUMN no_kk TYPE varchar(16)');
    }
};
