<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('children', function (Blueprint $table) {
            $table->uuid('id')->primary(); // Primary Key UUID
            $table->uuid('user_id'); // Foreign key ke tabel users (Ibu)
            $table->string('nik', 16)->unique()->nullable(); // NIK Balita di KK (Opsional)
            $table->string('name');
            $table->date('date_of_birth');
            $table->enum('gender', ['L', 'P']); // L: Laki-laki, P: Perempuan
            $table->float('birth_weight')->nullable(); // Berat lahir (kg)
            $table->float('birth_height')->nullable(); // Panjang/Tinggi lahir (cm)
            $table->timestamps();

            // Relasi ke tabel users
            $table->foreign('user_id')->references('id')->on('users')->onDelete('cascade');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('children');
    }
};
