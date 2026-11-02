<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Menautkan catatan suntikan ke kunjungan (P0-1).
 *
 * `visit_id` nullable agar suntikan yang dicatat di luar sesi kunjungan tetap
 * sah. `nullOnDelete`: menghapus fisik kunjungan tidak menghapus riwayat
 * suntikan anak, hanya melepas tautannya.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('immunization_records', function (Blueprint $table) {
            $table->foreignUuid('visit_id')
                ->nullable()
                ->after('immunization_type_id')
                ->constrained('visits')
                ->nullOnDelete();

            $table->index('visit_id', 'immunization_records_visit_id_index');
        });
    }

    public function down(): void
    {
        Schema::table('immunization_records', function (Blueprint $table) {
            $table->dropForeign(['visit_id']);
            $table->dropIndex('immunization_records_visit_id_index');
            $table->dropColumn('visit_id');
        });
    }
};
