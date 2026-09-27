<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        // 1. Membuat Stored Procedure / Function di PostgreSQL
        $function = <<<'SQL'
        CREATE OR REPLACE FUNCTION calculate_measurement_data()
        RETURNS TRIGGER AS $$
        DECLARE
            v_birth_date DATE;
            v_age_months INTEGER;
        BEGIN
            -- Ambil tanggal lahir anak dari tabel children
            SELECT birth_date INTO v_birth_date
            FROM children
            WHERE id = NEW.child_id;

            -- Hitung selisih umur dalam bulan secara akurat menggunakan fungsi age() bawaan PostgreSQL
            v_age_months := (EXTRACT(YEAR FROM age(NEW.measurement_date, v_birth_date)) * 12) +
                            EXTRACT(MONTH FROM age(NEW.measurement_date, v_birth_date));

            -- Set kolom age_in_months otomatis
            NEW.age_in_months := v_age_months;

            -- TODO (Struktur Placeholder untuk Z-Score WFA)
            -- Untuk saat ini kita berikan nilai default agar tidak null.
            -- Logika pasti (mencari Median dan Standar Deviasi dari standar WHO)
            -- akan kita suntikkan ke fungsi ini setelah kita membuat tabel referensi standar WHO.
            NEW.z_score_wfa := 0.00;
            NEW.status_gizi := 'Normal';

            -- Kembalikan baris (row) yang sudah dimodifikasi untuk disimpan
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        SQL;

        // 2. Memasang Trigger ke tabel measurements
        $trigger = <<<'SQL'
        CREATE TRIGGER before_insert_measurement_trigger
        BEFORE INSERT ON measurements
        FOR EACH ROW
        EXECUTE FUNCTION calculate_measurement_data();
        SQL;

        // Eksekusi raw SQL secara berurutan
        DB::unprepared($function);
        DB::unprepared($trigger);
    }

    public function down(): void
    {
        // Untuk rollback/reset database
        DB::unprepared('DROP TRIGGER IF EXISTS before_insert_measurement_trigger ON measurements;');
        DB::unprepared('DROP FUNCTION IF EXISTS calculate_measurement_data();');
    }
};
