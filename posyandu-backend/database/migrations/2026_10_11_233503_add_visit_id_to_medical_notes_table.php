<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Menautkan catatan keluhan ke kunjungan (P0-1).
 *
 * `visit_id` nullable agar keluhan yang dicatat di luar sesi kunjungan tetap
 * sah. `nullOnDelete`: menghapus fisik kunjungan tidak menghapus catatan
 * keluhan anak, hanya melepas tautannya.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('medical_notes', function (Blueprint $table) {
            $table->foreignUuid('visit_id')
                ->nullable()
                ->after('child_id')
                ->constrained('visits')
                ->nullOnDelete();

            $table->index('visit_id', 'medical_notes_visit_id_index');
        });
    }

    public function down(): void
    {
        Schema::table('medical_notes', function (Blueprint $table) {
            $table->dropForeign(['visit_id']);
            $table->dropIndex('medical_notes_visit_id_index');
            $table->dropColumn('visit_id');
        });
    }
};
