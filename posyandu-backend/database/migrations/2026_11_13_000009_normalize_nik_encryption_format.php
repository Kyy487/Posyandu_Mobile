<?php

use App\Support\NikHasher;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;

/**
 * Normalisasi ciphertext NIK lama.
 *
 * Migration 2026_10_13 memakai `encrypt()` yang menyertakan serialisasi PHP.
 * Cast `encrypted` di model memakai `decrypt($payload, false)`, sehingga nilai
 * yang dibaca aplikasi menjadi `s:16:"3273...";` — bukan NIK asli. Migration
 * ini mengubah ciphertext ke format `encryptString()` dan sekaligus memastikan
 * `nik_hash` adalah HMAC dari NIK asli.
 *
 * `down()` sengaja no-op: format baru adalah format yang benar dan aman.
 */
return new class extends Migration
{
    public function up(): void
    {
        foreach (['users', 'children'] as $table) {
            DB::table($table)
                ->select(['id', 'nik'])
                ->whereNotNull('nik')
                ->orderBy('id')
                ->chunkById(100, function ($rows) use ($table): void {
                    foreach ($rows as $row) {
                        try {
                            $plain = $this->plainNik((string) $row->nik);
                        } catch (Throwable) {
                            continue;
                        }

                        DB::table($table)
                            ->where('id', $row->id)
                            ->update([
                                'nik' => Crypt::encryptString($plain),
                                'nik_hash' => NikHasher::hash($plain),
                            ]);
                    }
                });
        }
    }

    public function down(): void
    {
        //
    }

    private function plainNik(string $encrypted): string
    {
        $value = (string) Crypt::decryptString($encrypted);

        if (preg_match('/^s:\d+:".*";$/s', $value) === 1) {
            $unserialized = @unserialize($value, ['allowed_classes' => false]);

            if (is_string($unserialized)) {
                return $unserialized;
            }
        }

        return $value;
    }
};
