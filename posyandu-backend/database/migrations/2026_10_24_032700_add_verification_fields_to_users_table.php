<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->enum('status', ['pending', 'active', 'rejected'])->default('active')->after('role');
            $table->string('place_of_birth', 100)->nullable()->after('status');
            $table->date('date_of_birth')->nullable()->after('place_of_birth');
            $table->enum('gender', ['L', 'P'])->nullable()->after('date_of_birth');
            $table->text('address')->nullable()->after('gender');
            $table->uuid('approved_by')->nullable()->after('address');
            $table->timestamp('approved_at')->nullable()->after('approved_by');
            $table->text('rejection_reason')->nullable()->after('approved_at');
            $table->timestamp('verified_at')->nullable()->after('rejection_reason');

            $table->foreign('approved_by')->references('id')->on('users')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropForeign(['approved_by']);
            $table->dropColumn([
                'status',
                'place_of_birth',
                'date_of_birth',
                'gender',
                'address',
                'approved_by',
                'approved_at',
                'rejection_reason',
                'verified_at',
                'whatsapp',
                'instagram',
                'facebook',
            ]);
        });
    }
};
