<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Menambah kolom `measurements.status_wfh` dan mengisinya lewat trigger.
 *
 * Kenapa ada kolom baru: BB/TB (weight-for-length) sudah dihitung trigger
 * menjadi `z_score_wfh`, tetapi statusnya tidak pernah disimpan. Semua
 * indikator WHO lain punya kolom statusnya sendiri (`status_stunting`,
 * `status_gizi_imt`), dan aturan repo mengunci bahwa z-score dan status hanya
 * boleh dihitung PostgreSQL (`posyandu-backend/.ai/rules/yang-jangan-diubah.md`).
 * Memetakan z-score -> teks di PHP akan menggandakan klasifikasi yang sudah
 * hidup di trigger, jadi status BB/TB disimpan di sini, bukan dihitung di
 * aplikasi.
 *
 * Migration ini murni aditif dan mengikuti preseden
 * `2026_10_12_000000_restore_wfa_only_status_gizi_trigger.php`: function
 * diganti lewat `CREATE OR REPLACE FUNCTION`, migration lama tidak disentuh.
 *
 * Function di bawah adalah salinan setia dari trigger yang berlaku sejak
 * 12 Oktober 2026 (status_gizi = BB/U saja), ditambah tiga baris: `status_wfh`
 * dikosongkan di awal dan diisi dari `z_score_wfh` bersama z-score itu.
 * Tidak ada perilaku lain yang berubah, jadi setiap kolom lama tetap dihitung
 * dengan aturan yang sama persis.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('measurements', function (Blueprint $table) {
            $table->string('status_wfh', 20)->nullable()->after('z_score_wfh');
        });

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
                NEW.status_wfh := NULL;

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
                        NEW.status_wfh := CASE
                            WHEN NEW.z_score_wfh < -3 THEN 'Gizi Buruk'
                            WHEN NEW.z_score_wfh < -2 THEN 'Gizi Kurang'
                            WHEN NEW.z_score_wfh > 2 THEN 'Risiko Gizi Lebih'
                            ELSE 'Normal'
                        END;
                    END IF;
                END IF;

                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;
        ");
    }

    /**
     * Kolom dibuang, tetapi function sengaja tidak dikembalikan ke versi lama.
     *
     * Mengembalikan function berarti menghidupkan lagi versi yang tidak
     * mengosongkan `status_wfh`; kolomnya sudah tidak ada saat itu, dan
     * `down()` yang setengah jalan lebih berbahaya daripada tidak ada. Sama
     * dengan `2026_10_12_000000`.
     */
    public function down(): void
    {
        Schema::table('measurements', function (Blueprint $table) {
            $table->dropColumn('status_wfh');
        });
    }
};
