<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Jadikan `birth_height` kolom generated dari `birth_length`.
 *
 * `birth_length` adalah nama kanonis. `birth_height` dipertahankan hanya
 * sebagai alias baca untuk mobile/timeline lama, sehingga tidak ada lagi
 * dual-write yang bisa membuat kedua nilai berbeda.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::table('children')
            ->whereNull('birth_length')
            ->whereNotNull('birth_height')
            ->update(['birth_length' => DB::raw('birth_height')]);

        DB::statement('ALTER TABLE children DROP COLUMN birth_height');
        DB::statement(
            'ALTER TABLE children ADD COLUMN birth_height DOUBLE PRECISION '
            .'GENERATED ALWAYS AS (birth_length::double precision) STORED'
        );
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE children DROP COLUMN birth_height');
        DB::statement('ALTER TABLE children ADD COLUMN birth_height DOUBLE PRECISION NULL');
        DB::statement('UPDATE children SET birth_height = birth_length');
    }
};
