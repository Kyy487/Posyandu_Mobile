<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Melengkapi data lahir anak untuk kebutuhan skrining awal dan koreksi
     * usia (bayi prematur).
     *
     * `birth_length` adalah nama kanonis baru untuk panjang lahir.
     * `birth_height` lama tetap dipertahankan agar timeline, factory, seeder,
     * dan mobile yang sudah berjalan tidak rusak. Nilai keduanya disinkronkan
     * oleh service saat membuat/mengubah anak.
     */
    public function up(): void
    {
        Schema::table('children', function (Blueprint $table) {
            $table->unsignedSmallInteger('birth_order')->nullable()->after('date_of_birth');
            $table->decimal('birth_length', 5, 2)->nullable()->after('birth_weight');
            $table->decimal('birth_head_circumference', 5, 2)->nullable()->after('birth_length');
            $table->string('birth_status', 20)->nullable()->after('birth_head_circumference');
            $table->string('buku_kia_id', 50)->nullable()->after('birth_status');

            $table->unique('nik_hash');
        });

        DB::table('children')
            ->whereNull('birth_length')
            ->whereNotNull('birth_height')
            ->update(['birth_length' => DB::raw('birth_height')]);
    }

    public function down(): void
    {
        Schema::table('children', function (Blueprint $table) {
            $table->dropUnique(['nik_hash']);
            $table->dropColumn([
                'birth_order',
                'birth_length',
                'birth_head_circumference',
                'birth_status',
                'buku_kia_id',
            ]);
        });
    }
};
