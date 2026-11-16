<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Migration lama membuat `user_verifications.type` lewat `$table->enum()`,
 * yang di PostgreSQL menjadi varchar + CHECK constraint. Constraint itu belum
 * mengenal `ktp`, padahal alur perbaikan dokumen sekarang menerima KTP.
 *
 * `DROP CONSTRAINT IF EXISTS` membuat migration ini aman untuk database yang
 * constraint-nya sudah tidak ada.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement(
            'ALTER TABLE user_verifications '
            .'DROP CONSTRAINT IF EXISTS user_verifications_type_check'
        );
    }

    public function down(): void
    {
        $hasKtp = DB::table('user_verifications')->where('type', 'ktp')->exists();

        if ($hasKtp) {
            return;
        }

        DB::statement(
            'ALTER TABLE user_verifications '
            .'ADD CONSTRAINT user_verifications_type_check '
            ."CHECK (type IN ('self_photo', 'kk', 'other'))"
        );
    }
};
