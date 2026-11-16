<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->index(['role', 'status', 'created_at', 'id'], 'users_role_status_created_at_index');
        });

        Schema::table('children', function (Blueprint $table): void {
            $table->index('user_id', 'children_user_id_index');
            $table->index(['deleted_at', 'name', 'id'], 'children_deleted_at_name_index');
        });

        Schema::table('audit_logs', function (Blueprint $table): void {
            $table->index(['created_at', 'id'], 'audit_logs_created_id_index');
        });

        DB::statement(<<<'SQL'
            CREATE INDEX measurements_child_history_index
            ON measurements (child_id, measurement_date DESC, created_at DESC, id DESC)
            WHERE deleted_at IS NULL
        SQL);
    }

    public function down(): void
    {
        DB::statement('DROP INDEX IF EXISTS measurements_child_history_index');

        Schema::table('audit_logs', function (Blueprint $table): void {
            $table->dropIndex('audit_logs_created_id_index');
        });

        Schema::table('children', function (Blueprint $table): void {
            $table->dropIndex('children_user_id_index');
            $table->dropIndex('children_deleted_at_name_index');
        });

        Schema::table('users', function (Blueprint $table): void {
            $table->dropIndex('users_role_status_created_at_index');
        });
    }
};
