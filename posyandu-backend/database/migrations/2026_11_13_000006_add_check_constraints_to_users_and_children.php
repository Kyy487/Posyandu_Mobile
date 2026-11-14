<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Tambahkan CHECK constraint untuk kolom yang sebelumnya hanya divalidasi
 * di aplikasi. Ini mencegah data kotor masuk lewat seeder, tinker, atau
 * perubahan manual di database.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement(
            'ALTER TABLE users ADD CONSTRAINT users_onboarding_status_check '
            ."CHECK (onboarding_status IN ('need_child_data', 'completed'))"
        );

        DB::statement(
            'ALTER TABLE users ADD CONSTRAINT users_blood_type_check '
            ."CHECK (blood_type IS NULL OR blood_type IN ('A', 'B', 'AB', 'O'))"
        );

        DB::statement(
            'ALTER TABLE users ADD CONSTRAINT users_education_check '
            ."CHECK (education IS NULL OR education IN ('SD', 'SMP', 'SMA', 'SMK', 'D3', 'S1', 'S2', 'S3', 'other'))"
        );

        DB::statement(
            'ALTER TABLE users ADD CONSTRAINT users_rt_rw_check '
            ."CHECK (rt_rw IS NULL OR rt_rw ~ '^[0-9]{1,3}\\s*/\\s*[0-9]{1,3}$')"
        );

        DB::statement(
            'ALTER TABLE children ADD CONSTRAINT children_birth_status_check '
            ."CHECK (birth_status IS NULL OR birth_status IN ('normal', 'premature'))"
        );

        DB::statement(
            'ALTER TABLE children ADD CONSTRAINT children_birth_order_check '
            .'CHECK (birth_order IS NULL OR birth_order BETWEEN 1 AND 20)'
        );
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE users DROP CONSTRAINT IF EXISTS users_onboarding_status_check');
        DB::statement('ALTER TABLE users DROP CONSTRAINT IF EXISTS users_blood_type_check');
        DB::statement('ALTER TABLE users DROP CONSTRAINT IF EXISTS users_education_check');
        DB::statement('ALTER TABLE users DROP CONSTRAINT IF EXISTS users_rt_rw_check');
        DB::statement('ALTER TABLE children DROP CONSTRAINT IF EXISTS children_birth_status_check');
        DB::statement('ALTER TABLE children DROP CONSTRAINT IF EXISTS children_birth_order_check');
    }
};
