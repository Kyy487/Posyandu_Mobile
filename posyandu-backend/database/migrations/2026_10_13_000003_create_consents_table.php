<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('consents', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('child_id')->constrained('children')->onDelete('cascade');
            $table->foreignUuid('granted_by')->constrained('users')->onDelete('cascade');
            $table->string('consent_type', 20);
            $table->timestamp('granted_at');
            $table->timestamp('revoked_at')->nullable();
            $table->string('document_version', 20);
            $table->text('notes')->nullable();
            $table->timestamps();

            $table->unique(['child_id', 'consent_type']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('consents');
    }
};
