<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Waktu kunjungan dan edukasi gizi.
 *
 * `visit_date` tetap dipertahankan untuk kompatibilitas dan rekap harian.
 * Backfill dilakukan terpisah agar migration kolom tetap ringan.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('visits', function (Blueprint $table): void {
            $table->timestampTz('visit_started_at')->nullable()->after('visit_date');
            $table->timestampTz('visit_ended_at')->nullable()->after('visit_started_at');
            $table->text('edukasi_gizi')->nullable()->after('catatan_kader');
        });
    }

    public function down(): void
    {
        Schema::table('visits', function (Blueprint $table): void {
            $table->dropColumn(['visit_started_at', 'visit_ended_at', 'edukasi_gizi']);
        });
    }
};
