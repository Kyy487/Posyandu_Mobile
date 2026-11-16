<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Red flags terstruktur dan kode ICD-10 opsional.
 *
 * Isi kode red flag divalidasi allowlist di aplikasi. Database hanya
 * memastikan bentuknya array JSON, bukan memvalidasi daftar kode.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('medical_notes', function (Blueprint $table): void {
            $table->jsonb('red_flags')->nullable()->after('catatan');
            $table->string('icd10_code', 10)->nullable()->after('red_flags');
        });

        DB::statement(
            'ALTER TABLE medical_notes ADD CONSTRAINT medical_notes_red_flags_array_check '
            ."CHECK (red_flags IS NULL OR jsonb_typeof(red_flags) = 'array')"
        );
    }

    public function down(): void
    {
        DB::statement(
            'ALTER TABLE medical_notes DROP CONSTRAINT IF EXISTS medical_notes_red_flags_array_check'
        );

        Schema::table('medical_notes', function (Blueprint $table): void {
            $table->dropColumn(['red_flags', 'icd10_code']);
        });
    }
};
