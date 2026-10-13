<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('children', function (Blueprint $table) {
            $table->text('nik_encrypted')->nullable()->after('id');
            $table->string('nik_hash', 64)->nullable()->after('nik_encrypted');
        });

        $children = DB::table('children')->whereNotNull('nik')->get();

        foreach ($children as $child) {
            $encrypted = encrypt($child->nik);
            $hash = hash('sha256', $child->nik);

            DB::table('children')
                ->where('id', $child->id)
                ->update([
                    'nik_encrypted' => $encrypted,
                    'nik_hash' => $hash,
                ]);
        }

        $count = DB::table('children')
            ->whereNotNull('nik')
            ->whereNull('nik_encrypted')
            ->count();

        if ($count > 0) {
            throw new RuntimeException("Backfill gagal: {$count} baris children belum terenkripsi.");
        }

        Schema::table('children', function (Blueprint $table) {
            $table->dropUnique(['nik']);
            $table->dropColumn('nik');
        });

        Schema::table('children', function (Blueprint $table) {
            $table->renameColumn('nik_encrypted', 'nik');
        });

        Schema::table('children', function (Blueprint $table) {
            $table->unique('nik');
            $table->index('nik_hash');
        });
    }

    public function down(): void
    {
        Schema::table('children', function (Blueprint $table) {
            $table->dropIndex(['nik_hash']);
            $table->dropUnique(['nik']);
        });

        Schema::table('children', function (Blueprint $table) {
            $table->renameColumn('nik', 'nik_encrypted');
            $table->string('nik', 16)->nullable()->after('id');
        });

        $children = DB::table('children')->whereNotNull('nik_encrypted')->get();

        foreach ($children as $child) {
            try {
                $decrypted = decrypt($child->nik_encrypted);
            } catch (Throwable) {
                $decrypted = null;
            }

            DB::table('children')
                ->where('id', $child->id)
                ->update(['nik' => $decrypted]);
        }

        Schema::table('children', function (Blueprint $table) {
            $table->dropColumn(['nik_encrypted', 'nik_hash']);
        });

        Schema::table('children', function (Blueprint $table) {
            $table->unique('nik');
        });
    }
};
