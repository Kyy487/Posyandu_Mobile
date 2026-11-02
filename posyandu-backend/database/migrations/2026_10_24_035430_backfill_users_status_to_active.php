<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('users') && Schema::hasColumn('users', 'status')) {
            DB::table('users')
                ->whereNull('status')
                ->orWhere('status', '')
                ->update(['status' => 'active']);
        }
    }

    public function down(): void
    {
        // Tidak perlu rollback
    }
};
