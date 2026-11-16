<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Menambahkan role `admin` sebagai role internal.
 *
 * Role ini tidak boleh dibuat lewat endpoint registrasi publik. Akun admin
 * dibuat lewat seeder/CLI. Constraint lama dibuang dan dibuat ulang karena
 * PostgreSQL tidak mendukung `ADD CONSTRAINT IF NOT EXISTS`.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement('ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check');

        DB::statement(
            'ALTER TABLE users ADD CONSTRAINT users_role_check '
            ."CHECK (role IN ('ibu', 'kader', 'admin'))"
        );
    }

    public function down(): void
    {
        $adminCount = DB::table('users')->where('role', 'admin')->count();

        if ($adminCount > 0) {
            throw new RuntimeException(
                "Rollback ditolak: ada {$adminCount} user dengan role admin. "
                .'Pindahkan atau hapus user tersebut sebelum kembali ke schema lama.'
            );
        }

        DB::statement('ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check');

        DB::statement(
            'ALTER TABLE users ADD CONSTRAINT users_role_check '
            ."CHECK (role IN ('ibu', 'kader'))"
        );
    }
};
