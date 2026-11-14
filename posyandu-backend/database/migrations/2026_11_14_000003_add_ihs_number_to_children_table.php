<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * IHS number anak untuk referensi Patient SATUSEHAT.
 *
 * Fase 1 hanya menyimpan nilai; pengambilan otomatis dari API masuk Fase 2.
 * Unique nullable: anak yang belum punya IHS tetap boleh ada.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('children', function (Blueprint $table): void {
            $table->string('ihs_number', 50)->nullable()->after('nik_hash');
            $table->unique('ihs_number');
        });
    }

    public function down(): void
    {
        Schema::table('children', function (Blueprint $table): void {
            $table->dropUnique(['ihs_number']);
            $table->dropColumn('ihs_number');
        });
    }
};
