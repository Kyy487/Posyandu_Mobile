<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Melengkapi profil Ibu/Wali dan status onboarding.
     *
     * Catatan desain:
     * - `no_kk` TIDAK dibuat unik. Satu Kartu Keluarga dipakai bersama oleh
     *   beberapa anggota keluarga (ibu, ayah, beberapa anak). Unik hanya pada
     *   NIK. Ini berbeda dari spesifikasi awal yang menyebut KK unik.
     * - `verification_status` sengaja TIDAK disimpan sebagai kolom baru karena
     *   sudah ada `status` (pending/active/rejected) yang dipakai di seluruh
     *   aplikasi. Nilai `verification_status` diekspos sebagai accessor pada
     *   model User agar API tetap mengikuti penamaan yang diminta tanpa
     *   menduplikasi sumber kebenaran.
     * - `nik_hash` diberi unique index. Kolom `nik` terenkripsi acak (IV
     *   berbeda tiap baris), sehingga `unique(nik)` TIDAK bisa mencegah NIK
     *   ganda. `nik_hash` deterministik dan selama ini dipakai untuk login.
     */
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('no_kk', 16)->nullable()->after('nik_hash');
            $table->string('blood_type', 3)->nullable()->after('gender');
            $table->string('rt_rw', 10)->nullable()->after('address');
            $table->string('education', 20)->nullable()->after('rt_rw');
            $table->string('occupation', 100)->nullable()->after('education');
            $table->string('onboarding_status', 20)->default('need_child_data')->after('status');

            $table->index('no_kk');
            $table->index('status');
            $table->index('onboarding_status');
            $table->unique('nik_hash');
        });

        // Data yang sudah ada sebelum fitur onboarding dianggap sudah selesai.
        // Tanpa backfill ini, seluruh Ibu lama akan tiba-tiba terkunci dari
        // dashboard sampai menambah anak baru.
        DB::table('users')->update(['onboarding_status' => 'completed']);
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropUnique(['nik_hash']);
            $table->dropIndex(['no_kk']);
            $table->dropIndex(['status']);
            $table->dropIndex(['onboarding_status']);
            $table->dropColumn([
                'no_kk',
                'blood_type',
                'rt_rw',
                'education',
                'occupation',
                'onboarding_status',
            ]);
        });
    }
};
