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
        $seedFile = database_path('seeders').'/who_wfh_seed.sql';

        if (file_exists($seedFile)) {
            $sql = file_get_contents($seedFile);
            $sql = preg_replace('/^\xEF\xBB\xBF/', '', $sql);
            $sql = preg_replace('/(INSERT INTO who_wfh_standards\s*\([^)]+\)\s*VALUES\s*\([^)]+)\);/', '$1) ON CONFLICT DO NOTHING;', $sql);
            DB::unprepared($sql);
        }

        DB::unprepared('UPDATE measurements SET weight_kg = weight_kg');
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        DB::table('who_wfh_standards')->truncate();
    }
};
