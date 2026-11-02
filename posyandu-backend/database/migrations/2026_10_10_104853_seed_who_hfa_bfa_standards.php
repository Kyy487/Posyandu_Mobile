<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        $seedFile = database_path('seeders').'/who_hfa_bfa_seed.sql';

        if (file_exists($seedFile)) {
            $sql = file_get_contents($seedFile);
            $sql = preg_replace('/^\xEF\xBB\xBF/', '', $sql);
            $sql = preg_replace('/INSERT INTO (\w+)/', 'INSERT INTO $1', $sql);
            $sql = preg_replace('/(INSERT INTO (?:who_hfa_standards|who_bfa_standards)\s*\([^)]+\)\s*VALUES\s*\([^)]+)\);/', '$1) ON CONFLICT DO NOTHING;', $sql);
            DB::unprepared($sql);
        }
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        //
    }
};
