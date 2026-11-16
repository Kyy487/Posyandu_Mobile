<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Catatan keluhan yang hanya berisi red flag tetap dianggap berisi.
 *
 * Constraint lama `medical_notes_isi_check` hanya mengenal demam/rewel/diare
 * dan catatan. Tanpa migration ini, menyimpan `red_flags` saja akan ditolak
 * database meskipun validasi aplikasi meloloskannya.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement(
            'ALTER TABLE medical_notes '
            .'DROP CONSTRAINT IF EXISTS medical_notes_isi_check'
        );

        DB::statement(
            'ALTER TABLE medical_notes ADD CONSTRAINT medical_notes_isi_check '
            .'CHECK ('
            .'demam OR rewel OR diare '
            .'OR (red_flags IS NOT NULL AND jsonb_array_length(red_flags) > 0) '
            ."OR (catatan IS NOT NULL AND btrim(catatan) <> '')"
            .')'
        );
    }

    public function down(): void
    {
        DB::statement(
            'ALTER TABLE medical_notes '
            .'DROP CONSTRAINT IF EXISTS medical_notes_isi_check'
        );

        DB::statement(
            'ALTER TABLE medical_notes ADD CONSTRAINT medical_notes_isi_check '
            .'CHECK ('
            .'demam OR rewel OR diare '
            ."OR (catatan IS NOT NULL AND btrim(catatan) <> '')"
            .') NOT VALID'
        );
    }
};
