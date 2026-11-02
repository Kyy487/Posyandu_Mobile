<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Menautkan penimbangan ke kunjungan (P0-1).
 *
 * `visit_id` nullable agar penimbangan lama (sebelum entitas kunjungan ada) dan
 * alur pencatatan tanpa kunjungan tetap valid. Relasi ini opsional: menimbang
 * anak di luar sesi kunjungan tidak dilarang.
 *
 * `nullOnDelete`: bila kunjungan dihapus fisik (`forceDelete`), penimbangan yang
 * mencatatnya tidak ikut hilang - tautannya dilepas, isinya tetap. Untuk
 * pembatalan lewat soft delete, tautan ini sengaja dipertahankan, sama seperti
 * perilaku `medical_notes.measurement_id` (lihat docs/DATABASE_SCHEMA.md).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('measurements', function (Blueprint $table) {
            $table->foreignUuid('visit_id')
                ->nullable()
                ->after('child_id')
                ->constrained('visits')
                ->nullOnDelete();

            // Detail kunjungan (GET /visits/{id}) memuat penimbangan
            // berdasarkan `visit_id`, jadi aksesnya butuh index.
            $table->index('visit_id', 'measurements_visit_id_index');
        });
    }

    public function down(): void
    {
        Schema::table('measurements', function (Blueprint $table) {
            $table->dropForeign(['visit_id']);
            $table->dropIndex('measurements_visit_id_index');
            $table->dropColumn('visit_id');
        });
    }
};
