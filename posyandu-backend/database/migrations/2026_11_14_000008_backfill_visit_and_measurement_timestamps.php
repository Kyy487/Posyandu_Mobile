<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Backfill waktu dari tanggal lama.
 *
 * Aturan:
 * - Tanggal lama dianggap terjadi pukul 00:00 Asia/Jakarta.
 * - Hanya baris yang masih NULL yang diisi, jadi migration idempoten.
 * - Trigger Z-Score pada `measurements` dimatikan sementara. Tanpa itu,
 *   UPDATE `measured_at` akan memicu BEFORE UPDATE dan menghitung ulang
 *   z-score/status, padahal migration ini tidak boleh mengubah nilai klinis.
 * - `visit_ended_at` tidak diisi karena durasi lama tidak diketahui.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::table('visits')
            ->whereNull('visit_started_at')
            ->whereNotNull('visit_date')
            ->update([
                'visit_started_at' => DB::raw("visit_date::timestamp AT TIME ZONE 'Asia/Jakarta'"),
            ]);

        DB::statement('ALTER TABLE measurements DISABLE TRIGGER trg_measurements_who_zscore');

        try {
            DB::table('measurements')
                ->whereNull('measured_at')
                ->whereNotNull('measurement_date')
                ->update([
                    'measured_at' => DB::raw("measurement_date::timestamp AT TIME ZONE 'Asia/Jakarta'"),
                ]);
        } finally {
            DB::statement('ALTER TABLE measurements ENABLE TRIGGER trg_measurements_who_zscore');
        }
    }

    /**
     * Backfill tidak dibalik.
     *
     * Nilai hasil backfill tidak bisa dibedakan dari nilai yang diisi eksplisit
     * oleh aplikasi. Kolomnya sendiri dihapus oleh migration 000004 dan 000005
     * pada batch rollback yang sama, jadi tidak ada data yatim yang tertinggal.
     */
    public function down(): void
    {
        //
    }
};
