<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('who_bfa_standards', function (Blueprint $table) {
            $table->uuid('id')->primary()->default(DB::raw('gen_random_uuid()'));
            $table->unsignedSmallInteger('age_in_months');
            $table->char('gender', 1);
            $table->decimal('l', 8, 6);
            $table->decimal('m', 8, 4);
            $table->decimal('s', 8, 6);
            $table->timestamps();

            $table->unique(['age_in_months', 'gender']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('who_bfa_standards');
    }
};
