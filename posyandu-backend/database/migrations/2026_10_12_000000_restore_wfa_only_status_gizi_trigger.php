<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Mengembalikan `measurements.status_gizi` ke semantik BB/U (Weight-for-Age).
 *
 * Migration P0-2 (`2026_10_10_104811_update_zscore_trigger_for_lms`) mengubah
 * `calculate_measurement_who_zscore` menjadi agregasi "status gizi komposit":
 * status terburuk dari BB/U, TB/U, BB/TB, dan IMT/U. Perubahan itu punya dua
 * cacat yang melanggar kontrak yang sudah di-commit:
 *
 *   1. Hasil komposit selalu di-`COALESCE(..., 'Normal')`, sehingga anak di
 *      luar rentang WHO (di atas 60 bulan) dan anak tanpa acuan justru
 *      dilabeli "Normal" - padahal `docs/RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md`
 *      bagian 5 dan `docs/LAPORAN_ZSCORE_TRIGGER.md` sudah memutuskan bahwa
 *      di luar rentang `z_score_wfa` dan `status_gizi` harus `NULL`, bukan
 *      "Normal".
 *   2. `v_wfa_status` dihitung tetapi tidak pernah dipakai; akibatnya berat
 *      badan (BB/U) - indikator yang selama ini menentukan `status_gizi` -
 *      tidak punya pengaruh sama sekali, dan status bisa "naik" karena IMT/U
 *      walaupun titiknya berada di dalam pita BB/U. Kader melihat "Gizi Buruk"
 *      dengan titik di area normal.
 *
 * Kontrak yang berlaku (dikunci di `docs/RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md`,
 * `docs/DATABASE_SCHEMA.md`, dan `docs/API_CONTRACT.md`): `status_gizi` adalah
 * status BB/U. Indikator multidimensi tetap tersedia, tetapi di kolomnya
 * sendiri (`z_score_hfa`/`status_stunting`, `z_score_bfa`/`status_gizi_imt`,
 * `z_score_wfh`) - itulah nilai tambah P0-2, dan itu TIDAK dihapus di sini.
 *
 * Karena migration P0-2 sudah pernah jalan, perbaikan ini ditulis sebagai
 * migration baru (`CREATE OR REPLACE FUNCTION`), bukan dengan mengedit
 * migration lama (`.ai/rules/yang-jangan-diubah.md`).
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::unprepared("
            CREATE OR REPLACE FUNCTION calculate_measurement_who_zscore() RETURNS TRIGGER AS $$
            DECLARE
                v_child record;
                v_age_months integer;
                v_hfa record;
                v_bfa record;
                v_bmi numeric;
                v_wfa_median numeric;
                v_wfa_sd numeric;
                v_wfa_z numeric;
                v_wfh record;
            BEGIN
                IF NEW.measurement_date IS NULL THEN
                    RETURN NEW;
                END IF;

                SELECT * INTO v_child FROM children WHERE id = NEW.child_id;
                IF NOT FOUND THEN
                    RETURN NEW;
                END IF;

                IF NEW.measurement_date < v_child.date_of_birth THEN
                    NEW.measurement_date := v_child.date_of_birth;
                END IF;

                v_age_months := EXTRACT(YEAR FROM age(NEW.measurement_date, v_child.date_of_birth)) * 12
                    + EXTRACT(MONTH FROM age(NEW.measurement_date, v_child.date_of_birth));
                IF v_age_months < 0 THEN
                    v_age_months := 0;
                END IF;
                NEW.age_in_months := v_age_months;

                -- Semua turunan dikosongkan lebih dulu lalu diisi hanya bila
                -- acuan yang cocok ada. Ini membuat UPDATE yang menghapus
                -- tinggi badan (atau memindahkan anak ke luar rentang)
                -- benar-benar mengosongkan status lamanya.
                NEW.z_score_wfa := NULL;
                NEW.status_gizi := NULL;
                NEW.z_score_hfa := NULL;
                NEW.status_stunting := NULL;
                NEW.z_score_bfa := NULL;
                NEW.status_gizi_imt := NULL;
                NEW.z_score_wfh := NULL;

                -- BB/U - satu-satunya penentu `status_gizi`.
                IF v_age_months <= 60 THEN
                    SELECT median_kg, sd_kg INTO v_wfa_median, v_wfa_sd FROM who_wfa_standards
                    WHERE age_in_months = v_age_months AND gender = v_child.gender;
                    IF FOUND AND NEW.weight_kg IS NOT NULL AND v_wfa_sd > 0 THEN
                        v_wfa_z := round((NEW.weight_kg - v_wfa_median) / v_wfa_sd, 2);
                        NEW.z_score_wfa := v_wfa_z;
                        NEW.status_gizi := CASE
                            WHEN v_wfa_z < -3 THEN 'Gizi Buruk'
                            WHEN v_wfa_z < -2 THEN 'Gizi Kurang'
                            WHEN v_wfa_z > 2 THEN 'Risiko Gizi Lebih'
                            ELSE 'Normal'
                        END;
                    END IF;
                END IF;

                -- TB/U - status stunting, kolom terpisah.
                IF NEW.height_cm IS NOT NULL AND v_age_months <= 60 THEN
                    SELECT l, m, s INTO v_hfa FROM who_hfa_standards
                    WHERE age_in_months = v_age_months AND gender = v_child.gender;
                    IF FOUND THEN
                        NEW.z_score_hfa := calculate_who_zscore_lms(NEW.height_cm, v_hfa.l, v_hfa.m, v_hfa.s);
                        NEW.status_stunting := CASE
                            WHEN NEW.z_score_hfa < -3 THEN 'Stunting'
                            WHEN NEW.z_score_hfa < -2 THEN 'Stunting'
                            ELSE 'Normal'
                        END;
                    END IF;
                END IF;

                -- IMT/U - kolom terpisah.
                IF NEW.weight_kg IS NOT NULL AND NEW.height_cm IS NOT NULL AND NEW.height_cm > 0 AND v_age_months <= 60 THEN
                    v_bmi := NEW.weight_kg / power(NEW.height_cm / 100.0, 2);
                    SELECT l, m, s INTO v_bfa FROM who_bfa_standards
                    WHERE age_in_months = v_age_months AND gender = v_child.gender;
                    IF FOUND THEN
                        NEW.z_score_bfa := calculate_who_zscore_lms(v_bmi, v_bfa.l, v_bfa.m, v_bfa.s);
                        NEW.status_gizi_imt := CASE
                            WHEN NEW.z_score_bfa < -3 THEN 'Gizi Buruk'
                            WHEN NEW.z_score_bfa < -2 THEN 'Gizi Kurang'
                            WHEN NEW.z_score_bfa > 2 THEN 'Risiko Gizi Lebih'
                            ELSE 'Normal'
                        END;
                    END IF;
                END IF;

                -- BB/TB (0-24 bulan) - kolom terpisah.
                IF NEW.weight_kg IS NOT NULL AND NEW.height_cm IS NOT NULL AND NEW.height_cm > 0 AND v_age_months < 24 THEN
                    SELECT l, m, s INTO v_wfh FROM who_wfh_standards
                    WHERE length_cm = round(NEW.height_cm, 1) AND gender = v_child.gender;
                    IF FOUND THEN
                        NEW.z_score_wfh := calculate_who_zscore_lms(NEW.weight_kg, v_wfh.l, v_wfh.m, v_wfh.s);
                    END IF;
                END IF;

                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;
        ");
    }

    /**
     * Tidak ada yang perlu dibalik.
     *
     * Migration ini hanya mengganti isi function; membaliknya berarti
     * mengembalikan bug `COALESCE(..., 'Normal')` dan agregasi komposit yang
     * membuat `status_gizi` bertentangan dengan pita BB/U. Membiarkan function
     * yang benar lebih aman daripada menyediakan `down()` yang menghidupkan
     * bug itu kembali.
     */
    public function down(): void
    {
        //
    }
};
