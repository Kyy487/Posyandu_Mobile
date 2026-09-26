<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('users', function (Blueprint $table) {
            $table->uuid('id')->primary(); // Menggunakan UUID
            $table->string('nik', 16)->unique();
            $table->string('name');
           // $table->string('email')->unique();
           // $table->timestamp('email_verified_at')->nullable();
            $table->string('password');
            $table->enum('role', ['ibu', 'kader'])->default('ibu');
            $table->string('phone_number')->nullable();
            $table->rememberToken();
            $table->timestamps();
        });

        // Schema untuk password_reset_tokens dan sessions biarkan default bawaan Laravel
        // ...
    }

    public function down(): void
    {
        Schema::dropIfExists('users');
    }
};
