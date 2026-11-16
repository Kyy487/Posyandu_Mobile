<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Hapus index NIK yang sudah tidak berguna.
 *
 * - `users_nik_unique` / `children_nik_unique` mengindeks kolom `nik` yang
 *   isinya ciphertext non-deterministik. Index itu tidak pernah bisa dipakai
 *   untuk lookup dan hanya menambah biaya tulis.
 * - `users_nik_hash_index` / `children_nik_hash_index` duplikat dengan
 *   `*_nik_hash_unique` (unique index juga bisa dipakai untuk lookup).
 * - `users_no_kk_index` akan ikut dihapus karena `no_kk` dienkripsi pada
 *   migration berikutnya sehingga lookup langsung tidak mungkin lagi.
 */
return new class extends Migration
{
    public function up(): void
    {
        // `users_nik_unique` / `children_nik_unique` dibuat sebagai constraint
        // oleh `$table->unique()`, jadi harus dihapus lewat constraint (index
        // ikut hilang). `DROP INDEX` tetap dipanggil untuk berjaga-jaga bila
        // di database lain keduanya hanya berupa index.
        DB::statement('ALTER TABLE users DROP CONSTRAINT IF EXISTS users_nik_unique');
        DB::statement('DROP INDEX IF EXISTS users_nik_unique');
        DB::statement('ALTER TABLE children DROP CONSTRAINT IF EXISTS children_nik_unique');
        DB::statement('DROP INDEX IF EXISTS children_nik_unique');

        DB::statement('DROP INDEX IF EXISTS users_nik_hash_index');
        DB::statement('DROP INDEX IF EXISTS users_no_kk_index');
        DB::statement('DROP INDEX IF EXISTS children_nik_hash_index');
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE users ADD CONSTRAINT users_nik_unique UNIQUE (nik)');
        DB::statement('CREATE INDEX IF NOT EXISTS users_nik_hash_index ON users (nik_hash)');
        DB::statement('CREATE INDEX IF NOT EXISTS users_no_kk_index ON users (no_kk)');
        DB::statement('ALTER TABLE children ADD CONSTRAINT children_nik_unique UNIQUE (nik)');
        DB::statement('CREATE INDEX IF NOT EXISTS children_nik_hash_index ON children (nik_hash)');
    }
};
