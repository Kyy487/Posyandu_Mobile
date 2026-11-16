<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('who_wfh_standards', function (Blueprint $table) {
            $table->uuid('id')->primary()->default(DB::raw('gen_random_uuid()'));
            $table->decimal('length_cm', 5, 1);
            $table->char('gender', 1);
            $table->decimal('l', 8, 6);
            $table->decimal('m', 8, 4);
            $table->decimal('s', 8, 6);
            $table->timestamps();

            $table->unique(['length_cm', 'gender']);
        });

        Schema::table('measurements', function (Blueprint $table) {
            $table->decimal('z_score_wfh', 5, 2)->nullable()->after('z_score_hfa');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('measurements', function (Blueprint $table) {
            $table->dropColumn('z_score_wfh');
        });

        Schema::dropIfExists('who_wfh_standards');
    }
};
