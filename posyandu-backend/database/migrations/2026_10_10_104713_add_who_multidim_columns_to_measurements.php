<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('measurements', function (Blueprint $table) {
            $table->decimal('z_score_hfa', 5, 2)->nullable()->after('z_score_wfa');
            $table->decimal('z_score_bfa', 5, 2)->nullable()->after('z_score_hfa');
            $table->string('status_stunting', 20)->nullable()->after('z_score_bfa');
            $table->string('status_gizi_imt', 30)->nullable()->after('status_stunting');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('measurements', function (Blueprint $table) {
            //
        });
    }
};
