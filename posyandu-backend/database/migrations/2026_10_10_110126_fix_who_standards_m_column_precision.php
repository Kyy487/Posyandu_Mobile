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
        DB::unprepared('ALTER TABLE who_hfa_standards ALTER COLUMN m TYPE DECIMAL(8,4)');
        DB::unprepared('ALTER TABLE who_bfa_standards ALTER COLUMN m TYPE DECIMAL(8,4)');
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        //
    }
};
