<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Menandai satu dosis master sebagai aktif atau tidak.
 *
 * Master dosis adalah data referensi yang berubah mengikuti program nasional.
 * Ketika jadwal berganti (mis. jumlah dosis Hepatitis B atau jadwal polio
 * disesuaikan), baris lama tidak boleh dihapus: `immunization_records` memakai
 * foreign key `restrictOnDelete`, jadi menghapus baris telah dipakai akan
 * membuat catatan anak yatim (atau gagal). Karena itu baris lama cukup
 * dinonaktifkan dengan `is_active = false`, sehingga catatan lama tetap utuh
 * dan tidak lagi muncul di checklist/rekap.
 *
 * Kolom diberi default `true` supaya seluruh baris yang sudah ada tetap aktif
 * tanpa backfill manual.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('immunization_types', function (Blueprint $table) {
            $table->boolean('is_active')->default(true)->after('notes');
        });
    }

    public function down(): void
    {
        Schema::table('immunization_types', function (Blueprint $table) {
            $table->dropColumn('is_active');
        });
    }
};
