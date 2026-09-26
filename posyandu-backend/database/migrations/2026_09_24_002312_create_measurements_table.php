<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('measurements', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('child_id')->constrained('children')->cascadeOnDelete();
            $table->foreignUuid('kader_id')->constrained('users')->cascadeOnDelete();
            $table->date('measurement_date');
            $table->decimal('weight_kg', 5, 2);
            $table->decimal('height_cm', 5, 2);
            $table->decimal('head_circumference_cm', 5, 2)->nullable(); // Lingkar kepala
            $table->integer('age_in_months')->nullable(); // Akan diisi trigger/logic otomatis
            $table->decimal('z_score_wfa', 5, 2)->nullable(); // Hasil kalkulasi Z-Score
            $table->string('status_gizi')->nullable(); // Normal, Stunting, dll
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('measurements');
    }
};
