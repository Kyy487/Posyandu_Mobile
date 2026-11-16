<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->text('nik_encrypted')->nullable()->after('id');
            $table->string('nik_hash', 64)->nullable()->after('nik_encrypted');
        });

        $users = DB::table('users')->whereNotNull('nik')->get();

        foreach ($users as $user) {
            $encrypted = encrypt($user->nik);
            $hash = hash('sha256', $user->nik);

            DB::table('users')
                ->where('id', $user->id)
                ->update([
                    'nik_encrypted' => $encrypted,
                    'nik_hash' => $hash,
                ]);
        }

        $count = DB::table('users')
            ->whereNotNull('nik')
            ->whereNull('nik_encrypted')
            ->count();

        if ($count > 0) {
            throw new RuntimeException("Backfill gagal: {$count} baris users belum terenkripsi.");
        }

        Schema::table('users', function (Blueprint $table) {
            $table->dropUnique(['nik']);
            $table->dropColumn('nik');
        });

        Schema::table('users', function (Blueprint $table) {
            $table->renameColumn('nik_encrypted', 'nik');
        });

        Schema::table('users', function (Blueprint $table) {
            $table->unique('nik');
            $table->index('nik_hash');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropIndex(['nik_hash']);
            $table->dropUnique(['nik']);
        });

        Schema::table('users', function (Blueprint $table) {
            $table->renameColumn('nik', 'nik_encrypted');
            $table->string('nik', 16)->nullable()->after('id');
        });

        $users = DB::table('users')->whereNotNull('nik_encrypted')->get();

        foreach ($users as $user) {
            try {
                $decrypted = decrypt($user->nik_encrypted);
            } catch (Throwable) {
                $decrypted = null;
            }

            DB::table('users')
                ->where('id', $user->id)
                ->update(['nik' => $decrypted]);
        }

        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['nik_encrypted', 'nik_hash']);
        });

        Schema::table('users', function (Blueprint $table) {
            $table->unique('nik');
        });
    }
};
