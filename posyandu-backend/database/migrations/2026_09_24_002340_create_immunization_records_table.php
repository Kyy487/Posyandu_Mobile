<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('immunization_records', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('child_id')->constrained('children')->cascadeOnDelete();
            $table->foreignUuid('kader_id')->constrained('users')->cascadeOnDelete();
            $table->string('vaccine_name');
            $table->date('date_given');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('immunization_records');
    }
};
