<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        DB::unprepared('
            CREATE OR REPLACE FUNCTION calculate_who_zscore_lms(
                measurement NUMERIC,
                l NUMERIC,
                m NUMERIC,
                s NUMERIC
            ) RETURNS NUMERIC AS $$
            DECLARE
                z_score NUMERIC;
            BEGIN
                IF l = 0 THEN
                    z_score := ln(measurement / m) / s;
                ELSE
                    z_score := (power((measurement / m), l) - 1) / (l * s);
                END IF;
                RETURN round(z_score, 2);
            END;
            $$ LANGUAGE plpgsql;
        ');

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
                v_wfa_status text;
                v_hfa_z numeric;
                v_bfa_z numeric;
                v_wfh record;
                v_wfh_z numeric;
                v_wfh_status text;
                v_worst_status text;
                v_status_order int;
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

                IF v_age_months <= 60 THEN
                    SELECT median_kg, sd_kg INTO v_wfa_median, v_wfa_sd FROM who_wfa_standards
                    WHERE age_in_months = v_age_months AND gender = v_child.gender;
                    IF FOUND AND NEW.weight_kg IS NOT NULL AND v_wfa_sd > 0 THEN
                        v_wfa_z := round((NEW.weight_kg - v_wfa_median) / v_wfa_sd, 2);
                        NEW.z_score_wfa := v_wfa_z;
                        v_wfa_status := CASE
                            WHEN v_wfa_z < -3 THEN 'Gizi Buruk'
                            WHEN v_wfa_z < -2 THEN 'Gizi Kurang'
                            WHEN v_wfa_z > 2 THEN 'Risiko Gizi Lebih'
                            ELSE 'Normal'
                        END;
                    END IF;
                END IF;

                IF NEW.height_cm IS NOT NULL AND v_age_months <= 60 THEN
                    SELECT l, m, s INTO v_hfa FROM who_hfa_standards
                    WHERE age_in_months = v_age_months AND gender = v_child.gender;
                    IF FOUND THEN
                        v_hfa_z := calculate_who_zscore_lms(NEW.height_cm, v_hfa.l, v_hfa.m, v_hfa.s);
                        NEW.z_score_hfa := v_hfa_z;
                        NEW.status_stunting := CASE
                            WHEN v_hfa_z < -3 THEN 'Stunting'
                            WHEN v_hfa_z < -2 THEN 'Stunting'
                            ELSE 'Normal'
                        END;
                    END IF;
                END IF;

                IF NEW.weight_kg IS NOT NULL AND NEW.height_cm IS NOT NULL AND NEW.height_cm > 0 AND v_age_months <= 60 THEN
                    v_bmi := NEW.weight_kg / power(NEW.height_cm / 100.0, 2);
                    SELECT l, m, s INTO v_bfa FROM who_bfa_standards
                    WHERE age_in_months = v_age_months AND gender = v_child.gender;
                    IF FOUND THEN
                        v_bfa_z := calculate_who_zscore_lms(v_bmi, v_bfa.l, v_bfa.m, v_bfa.s);
                        NEW.z_score_bfa := v_bfa_z;
                        NEW.status_gizi_imt := CASE
                            WHEN v_bfa_z < -3 THEN 'Gizi Buruk'
                            WHEN v_bfa_z < -2 THEN 'Gizi Kurang'
                            WHEN v_bfa_z > 2 THEN 'Risiko Gizi Lebih'
                            ELSE 'Normal'
                        END;
                    END IF;
                END IF;

                IF NEW.weight_kg IS NOT NULL AND NEW.height_cm IS NOT NULL AND NEW.height_cm > 0 AND v_age_months < 24 THEN
                    SELECT l, m, s INTO v_wfh FROM who_wfh_standards
                    WHERE length_cm = round(NEW.height_cm, 1) AND gender = v_child.gender;
                    IF FOUND THEN
                        v_wfh_z := calculate_who_zscore_lms(NEW.weight_kg, v_wfh.l, v_wfh.m, v_wfh.s);
                        NEW.z_score_wfh := v_wfh_z;
                    END IF;
                END IF;

                v_worst_status := COALESCE(NEW.status_gizi, 'Normal');
                v_status_order := CASE v_worst_status
                    WHEN 'Gizi Buruk' THEN 4
                    WHEN 'Gizi Kurang' THEN 3
                    WHEN 'Stunting' THEN 3
                    WHEN 'Risiko Gizi Lebih' THEN 2
                    ELSE 1
                END;

                IF NEW.status_stunting = 'Stunting' AND v_status_order < 3 THEN
                    v_worst_status := 'Stunting';
                    v_status_order := 3;
                END IF;

                IF NEW.status_gizi_imt = 'Gizi Buruk' AND v_status_order < 4 THEN
                    v_worst_status := 'Gizi Buruk';
                    v_status_order := 4;
                ELSIF NEW.status_gizi_imt = 'Gizi Kurang' AND v_status_order < 3 THEN
                    v_worst_status := 'Gizi Kurang';
                    v_status_order := 3;
                ELSIF NEW.status_gizi_imt = 'Risiko Gizi Lebih' AND v_status_order < 2 THEN
                    v_worst_status := 'Risiko Gizi Lebih';
                    v_status_order := 2;
                END IF;

                IF NEW.z_score_wfh IS NOT NULL THEN
                    v_wfh_status := CASE
                        WHEN NEW.z_score_wfh < -3 THEN 'Gizi Buruk'
                        WHEN NEW.z_score_wfh < -2 THEN 'Gizi Kurang'
                        WHEN NEW.z_score_wfh > 2 THEN 'Risiko Gizi Lebih'
                        ELSE 'Normal'
                    END;

                    IF v_wfh_status = 'Gizi Buruk' AND v_status_order < 4 THEN
                        v_worst_status := 'Gizi Buruk';
                        v_status_order := 4;
                    ELSIF v_wfh_status = 'Gizi Kurang' AND v_status_order < 3 THEN
                        v_worst_status := 'Gizi Kurang';
                        v_status_order := 3;
                    ELSIF v_wfh_status = 'Risiko Gizi Lebih' AND v_status_order < 2 THEN
                        v_worst_status := 'Risiko Gizi Lebih';
                        v_status_order := 2;
                    END IF;
                END IF;

                NEW.status_gizi := v_worst_status;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;
        ");
    }

    public function down(): void
    {
        DB::unprepared('DROP FUNCTION IF EXISTS calculate_who_zscore_lms(NUMERIC, NUMERIC, NUMERIC, NUMERIC)');
    }
};
