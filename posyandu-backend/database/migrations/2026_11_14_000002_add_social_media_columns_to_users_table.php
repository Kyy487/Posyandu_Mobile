<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Kolom sosial media disimpan sebagai handle bersih, bukan URL.
 *
 * Normalisasi dilakukan di aplikasi. `whatsapp` memakai format E.164.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->string('whatsapp', 20)->nullable()->after('phone_number');
            $table->string('instagram', 50)->nullable()->after('whatsapp');
            $table->string('facebook', 100)->nullable()->after('instagram');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->dropColumn(['whatsapp', 'instagram', 'facebook']);
        });
    }
};
