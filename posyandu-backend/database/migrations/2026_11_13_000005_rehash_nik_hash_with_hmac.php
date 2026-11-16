<?php

use App\Support\NikHasher;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;

/**
 * Ganti hash NIK dari SHA-256 tanpa kunci menjadi HMAC-SHA256.
 *
 * NIK hanya 16 digit, sehingga hash biasa bisa di-brute-force dengan cepat
 * bila database bocor. HMAC memakai `APP_KEY` sebagai kunci, tetapi nilainya
 * tetap deterministik agar unique index dan login tetap bekerja.
 */
return new class extends Migration
{
    public function up(): void
    {
        $this->rehash(fn (string $nik): string => (string) NikHasher::hash($nik));
    }

    public function down(): void
    {
        $this->rehash(fn (string $nik): string => hash('sha256', $nik));
    }

    private function rehash(Closure $hasher): void
    {
        foreach (['users', 'children'] as $table) {
            DB::table($table)
                ->select(['id', 'nik'])
                ->whereNotNull('nik')
                ->orderBy('id')
                ->chunkById(100, function ($rows) use ($table, $hasher): void {
                    foreach ($rows as $row) {
                        try {
                            $nik = $this->plainNik((string) $row->nik);
                        } catch (Throwable) {
                            // Bukan ciphertext Laravel; lewati agar migration
                            // tidak menghapus data yang tidak bisa dibaca.
                            continue;
                        }

                        DB::table($table)
                            ->where('id', $row->id)
                            ->update(['nik_hash' => $hasher($nik)]);
                    }
                });
        }
    }

    /**
     * Migration lama memakai `encrypt()` yang menyertakan serialisasi PHP,
     * sedangkan cast `encrypted` sekarang memakai `encryptString()`. Ambil
     * nilai asli dari kedua format agar hash tidak dihitung dari string
     * serialisasi seperti `s:16:"3273...";`.
     */
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
