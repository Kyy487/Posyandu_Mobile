<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * `verification_status` sebagai kolom generated dari `users.status`.
 *
 * `status` tetap satu-satunya sumber kebenaran (dipakai middleware, approval,
 * dan test). Kolom ini hanya menerjemahkan istilah internal ke istilah API:
 *   pending  -> pending
 *   active   -> approved
 *   rejected -> rejected
 *
 * Karena generated, tidak ada dual-write dan nilainya tidak mungkin berbeda
 * dari `status`. Index disediakan agar filter/reporting di database tetap
 * efisien.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement(
            'ALTER TABLE users ADD COLUMN verification_status VARCHAR(20) '
            .'GENERATED ALWAYS AS (CASE '
            ."WHEN status = 'active' THEN 'approved' "
            ."WHEN status = 'rejected' THEN 'rejected' "
            ."ELSE 'pending' END) STORED"
        );

        DB::statement(
            'CREATE INDEX users_verification_status_index ON users (verification_status)'
        );
    }

    public function down(): void
    {
        DB::statement('DROP INDEX IF EXISTS users_verification_status_index');
        DB::statement('ALTER TABLE users DROP COLUMN verification_status');
    }
};
