<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Mapping terminologi imunisasi.
 *
 * `code` tetap kode lokal internal. Payload FHIR memakai KFA/CVX dari kolom
 * ini, bukan kode lokal. Nilai mapping diisi setelah verifikasi data.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('immunization_types', function (Blueprint $table): void {
            $table->string('kfa_code', 50)->nullable()->after('code');
            $table->string('cvx_code', 20)->nullable()->after('kfa_code');
            $table->string('cvx_display', 255)->nullable()->after('cvx_code');
            $table->string('cvx_group_code', 20)->nullable()->after('cvx_display');
            $table->string('target_disease_code', 20)->nullable()->after('cvx_group_code');
        });
    }

    public function down(): void
    {
        Schema::table('immunization_types', function (Blueprint $table): void {
            $table->dropColumn([
                'kfa_code',
                'cvx_code',
                'cvx_display',
                'cvx_group_code',
                'target_disease_code',
            ]);
        });
    }
};
