<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * Migration ini bersifat ADDITIVE (Aturan #5: migration lama tidak boleh diubah).
 *
 * Migration ini memperbaiki tiga masalah pada trigger lama
 * (2026_09_24_005327_create_zscore_calculation_trigger):
 *   1. BUG: query `SELECT birth_date FROM children` — kolom aslinya `date_of_birth`.
 *      Akibatnya trigger gagal 100% dan e-KMS tidak bisa dipakai.
 *   2. Z-Score masih placeholder (0.00 / 'Normal') sehingga status gizi selalu dianggap 'Normal'.
 *   3. Trigger hanya BEFORE INSERT, sehingga data hasil revisi tidak dihitung ulang.
 *
 * Standar yang dipakai: WHO Child Growth Standards (2006), Weight-for-Age.
 */
return new class extends Migration
{
    /**
     * Tabel referensi standar WHO Weight-for-Age (BB/U).
     * Indeks: [0] = Median (kg), [1] = Standard Deviation (kg)
     * Sumber: WHO Child Growth Standards 2006, weight-for-age, 0-60 bulan.
     */
    private const WHO_WFA_STANDARDS = [
        // L: Laki-laki
        'L' => [
            0 => [3.3, 0.4],   1 => [4.5, 0.5],   2 => [5.6, 0.6],   3 => [6.4, 0.7],
            4 => [7.0, 0.7],   5 => [7.5, 0.8],   6 => [7.9, 0.8],   7 => [8.3, 0.9],
            8 => [8.6, 0.9],   9 => [8.9, 0.9],   10 => [9.2, 1.0],  11 => [9.4, 1.0],
            12 => [9.6, 1.0],  13 => [9.9, 1.0],  14 => [10.1, 1.1], 15 => [10.3, 1.1],
            16 => [10.5, 1.1], 17 => [10.7, 1.1], 18 => [10.9, 1.2], 19 => [11.1, 1.2],
            20 => [11.3, 1.2], 21 => [11.5, 1.2], 22 => [11.8, 1.2], 23 => [12.0, 1.3],
            24 => [12.2, 1.3], 25 => [12.4, 1.3], 26 => [12.5, 1.3], 27 => [12.7, 1.3],
            28 => [12.9, 1.4], 29 => [13.1, 1.4], 30 => [13.3, 1.4], 31 => [13.5, 1.4],
            32 => [13.7, 1.4], 33 => [13.8, 1.4], 34 => [14.0, 1.4], 35 => [14.2, 1.5],
            36 => [14.3, 1.5], 37 => [14.5, 1.5], 38 => [14.7, 1.5], 39 => [14.8, 1.5],
            40 => [15.0, 1.5], 41 => [15.2, 1.6], 42 => [15.3, 1.6], 43 => [15.5, 1.6],
            44 => [15.7, 1.6], 45 => [15.8, 1.6], 46 => [16.0, 1.6], 47 => [16.2, 1.6],
            48 => [16.3, 1.7], 49 => [16.5, 1.7], 50 => [16.7, 1.7], 51 => [16.8, 1.7],
            52 => [17.0, 1.7], 53 => [17.2, 1.7], 54 => [17.3, 1.8], 55 => [17.5, 1.8],
            56 => [17.7, 1.8], 57 => [17.8, 1.8], 58 => [18.0, 1.8], 59 => [18.2, 1.8],
            60 => [18.3, 1.9],
        ],
        // P: Perempuan
        'P' => [
            0 => [3.2, 0.4],   1 => [4.2, 0.5],   2 => [5.1, 0.6],   3 => [5.8, 0.6],
            4 => [6.4, 0.7],   5 => [6.9, 0.7],   6 => [7.3, 0.8],   7 => [7.6, 0.8],
            8 => [7.9, 0.8],   9 => [8.2, 0.9],   10 => [8.5, 0.9],  11 => [8.7, 0.9],
            12 => [8.9, 0.9],  13 => [9.2, 1.0],  14 => [9.4, 1.0],  15 => [9.6, 1.0],
            16 => [9.8, 1.0],  17 => [10.0, 1.0], 18 => [10.2, 1.1], 19 => [10.4, 1.1],
            20 => [10.6, 1.1], 21 => [10.9, 1.1], 22 => [11.1, 1.1], 23 => [11.3, 1.2],
            24 => [11.5, 1.2], 25 => [11.7, 1.2], 26 => [11.9, 1.2], 27 => [12.1, 1.2],
            28 => [12.3, 1.3], 29 => [12.5, 1.3], 30 => [12.7, 1.3], 31 => [12.9, 1.3],
            32 => [13.1, 1.3], 33 => [13.3, 1.4], 34 => [13.5, 1.4], 35 => [13.7, 1.4],
            36 => [13.9, 1.4], 37 => [14.0, 1.4], 38 => [14.2, 1.5], 39 => [14.4, 1.5],
            40 => [14.6, 1.5], 41 => [14.8, 1.5], 42 => [15.0, 1.5], 43 => [15.2, 1.6],
            44 => [15.3, 1.6], 45 => [15.5, 1.6], 46 => [15.7, 1.6], 47 => [15.9, 1.6],
            48 => [16.1, 1.7], 49 => [16.3, 1.7], 50 => [16.4, 1.7], 51 => [16.6, 1.7],
            52 => [16.8, 1.7], 53 => [17.0, 1.8], 54 => [17.2, 1.8], 55 => [17.3, 1.8],
            56 => [17.5, 1.8], 57 => [17.7, 1.8], 58 => [17.9, 1.9], 59 => [18.0, 1.9],
            60 => [18.2, 1.9],
        ],
    ];

    public function up(): void
    {
        $this->createWhoWfaStandardsTable();
        $this->seedWhoWfaStandards();
        $this->dropLegacyTrigger();
        $this->createZScoreFunction();
        $this->createTrigger();
        $this->backfillExistingMeasurements();
    }

    /**
     * Tabel referensi standar WHO. Mengikuti aturan arsitektur: UUID sebagai Primary Key.
     */
    private function createWhoWfaStandardsTable(): void
    {
        Schema::create('who_wfa_standards', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->unsignedSmallInteger('age_in_months'); // 0 - 60 bulan
            $table->char('gender', 1); // L: Laki-laki, P: Perempuan
            $table->decimal('median_kg', 5, 2); // Median WHO (M)
            $table->decimal('sd_kg', 5, 2); // Standard Deviation WHO (S)
            $table->timestamps();

            $table->unique(['age_in_months', 'gender']);
        });
    }

    private function seedWhoWfaStandards(): void
    {
        $now = now();
        $rows = [];

        foreach (self::WHO_WFA_STANDARDS as $gender => $standards) {
            foreach ($standards as $ageInMonths => [$median, $sd]) {
                $rows[] = [
                    'id' => (string) Str::uuid(),
                    'age_in_months' => $ageInMonths,
                    'gender' => $gender,
                    'median_kg' => $median,
                    'sd_kg' => $sd,
                    'created_at' => $now,
                    'updated_at' => $now,
                ];
            }
        }

        DB::table('who_wfa_standards')->insert($rows);
    }

    private function dropLegacyTrigger(): void
    {
        DB::unprepared('DROP TRIGGER IF EXISTS before_insert_measurement_trigger ON measurements;');
        DB::unprepared('DROP FUNCTION IF EXISTS calculate_measurement_data();');
    }

    /**
     * Logika Z-Score sepenuhnya di sisi database (Aturan #9).
     * Z-Score Weight-for-Age = (berat_badut - median) / standard_deviation
     */
    private function createZScoreFunction(): void
    {
        $function = <<<'SQL'
        CREATE OR REPLACE FUNCTION calculate_measurement_who_zscore()
        RETURNS TRIGGER AS $$
        DECLARE
            v_date_of_birth DATE;
            v_gender        VARCHAR(1);
            v_age_months    INTEGER;
            v_median        NUMERIC(6, 3);
            v_sd            NUMERIC(6, 3);
            v_z_score       NUMERIC(5, 2);
        BEGIN
            -- 1. Ambil tanggal lahir & jenis kelamin anak.
            --    CATATAN: nama kolomnya `date_of_birth` (bukan `birth_date`).
            SELECT c.date_of_birth, c.gender
              INTO v_date_of_birth, v_gender
              FROM children c
             WHERE c.id = NEW.child_id;

            IF v_date_of_birth IS NULL THEN
                RAISE EXCEPTION 'Data anak dengan id % tidak ditemukan.', NEW.child_id;
            END IF;

            -- 2. Validasi: tanggal penimbangan tidak boleh mendahului tanggal lahir.
            IF NEW.measurement_date < v_date_of_birth THEN
                RAISE EXCEPTION 'Tanggal penimbangan (%) tidak boleh lebih awal dari tanggal lahir anak (%).',
                    NEW.measurement_date, v_date_of_birth;
            END IF;

            -- 3. Hitung umur dalam bulan (lengkap, berbasis kalender).
            v_age_months := (
                EXTRACT(YEAR  FROM age(NEW.measurement_date, v_date_of_birth)) * 12
              + EXTRACT(MONTH FROM age(NEW.measurement_date, v_date_of_birth))
            )::INTEGER;

            NEW.age_in_months := v_age_months;

            -- 4. Ambil median & standar deviasi WHO sesuai umur & jenis kelamin.
            SELECT w.median_kg, w.sd_kg
              INTO v_median, v_sd
              FROM who_wfa_standards w
             WHERE w.age_in_months = v_age_months
               AND w.gender = v_gender;

            -- 5. Di luar rentang standar WHO (0-60 bulan) atau data referensi tidak ada:
            --    jangan dipaksa jadi "Normal". Biarkan kosong agar tidak menyesatkan.
            IF v_median IS NULL OR v_sd IS NULL OR v_sd = 0 THEN
                NEW.z_score_wfa := NULL;
                NEW.status_gizi  := NULL;
                RETURN NEW;
            END IF;

            -- 6. Kalkulasi Z-Score Weight-for-Age.
            v_z_score := ROUND((NEW.weight_kg - v_median) / v_sd, 2);
            NEW.z_score_wfa := v_z_score;

            -- 7. Penentuan status gizi (nilai string mengikuti terminologi Indonesia).
            IF v_z_score < -3 THEN
                NEW.status_gizi := 'Gizi Buruk';
            ELSIF v_z_score < -2 THEN
                NEW.status_gizi := 'Gizi Kurang';
            ELSIF v_z_score > 2 THEN
                NEW.status_gizi := 'Risiko Gizi Lebih';
            ELSE
                NEW.status_gizi := 'Normal';
            END IF;

            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        SQL;

        DB::unprepared($function);
    }

    private function createTrigger(): void
    {
        $trigger = <<<'SQL'
        CREATE TRIGGER trg_measurements_who_zscore
        BEFORE INSERT OR UPDATE ON measurements
        FOR EACH ROW
        EXECUTE FUNCTION calculate_measurement_who_zscore();
        SQL;

        DB::unprepared($trigger);
    }

    /**
     * Hitung ulang baris yang sudah terlanjur tersimpan sebelum trigger ini dipasang.
     * UPDATE ke kolom itself akan memicu BEFORE UPDATE trigger.
     */
    private function backfillExistingMeasurements(): void
    {
        DB::unprepared('UPDATE measurements SET weight_kg = weight_kg;');
    }

    public function down(): void
    {
        DB::unprepared('DROP TRIGGER IF EXISTS trg_measurements_who_zscore ON measurements;');
        DB::unprepared('DROP FUNCTION IF EXISTS calculate_measurement_who_zscore();');

        Schema::dropIfExists('who_wfa_standards');
    }
};
