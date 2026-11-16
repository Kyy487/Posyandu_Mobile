<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Waktu pengukuran untuk payload Observation.
 *
 * `measurement_date` tetap menjadi tanggal operasional dan kunci unik harian.
 * Backfill dilakukan terpisah dan tidak memicu ulang trigger Z-Score.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('measurements', function (Blueprint $table): void {
            $table->timestampTz('measured_at')->nullable()->after('measurement_date');
        });
    }

    public function down(): void
    {
        Schema::table('measurements', function (Blueprint $table): void {
            $table->dropColumn('measured_at');
        });
    }
};
