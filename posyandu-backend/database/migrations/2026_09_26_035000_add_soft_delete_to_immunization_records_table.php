<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Mengizinkan pembatalan satu catatan suntikan (soft delete).
 *
 * Latar belakang: unique constraint `immunization_child_type_unique` dulu
 * menutup semua kemungkinan pembatalan. Kader yang salah memilih dosis tidak
 * bisa membatalkan catatannya. Migration `2026_09_26_032000` memang memakai
 * trade-off dengan asumsi "koreksi cukup lewat PATCH", tapi asumsi itu tidak
 * menutup kasus "salah pilih dosis", karena `PATCH` sengaja tidak bisa
 * memindahkan `immunization_type_id`.
 *
 * Yang berubah:
 *  1. Tambah `deleted_at` + index. Catatan tidak dihapus fisik, jadi riwayat
 *     kesehatan tetap bisa diaudit. Pada buku pencatatan, entri yang salah
     dibatalkan, bukan dihapus.
 *  2. Unique constraint dibikin PARTIAL: hanya berlaku untuk baris yang belum
 *     dihapus. Ini yang membuat pembatalan berguna - setelah membatalkan
 *     dosis 1, kader boleh mencatat ulang dosis 1 tanpa menabrak unique
 *     constraint.
 *
 * Kenapa bukan unique constraint biasa? Kalau tetap unique penuh, baris yang
 * sudah di-soft-delete akan tetap memblokir pencatatan ulang, dan soft delete
 * jadi tidak berguna sama sekali.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('immunization_records', function (Blueprint $table) {
            $table->timestamp('deleted_at')->nullable()->index();
        });

        // Ganti unique penuh dengan unique partial. Nama indexnya sengaja
        // sama supaya tidak ada dua objek berbeda dengan nama mirip di database.
        Schema::table('immunization_records', function (Blueprint $table) {
            $table->dropUnique('immunization_child_type_unique');
        });

        DB::statement(
            'CREATE UNIQUE INDEX immunization_child_type_unique '
            .'ON immunization_records (child_id, immunization_type_id) '
            .'WHERE deleted_at IS NULL'
        );
    }

    public function down(): void
    {
        // Kembalikan unique penuh hanya kalau tidak ada baris yang akan
        // bentrok. Bila ada, migration digagalkan dengan pesan jelas, bukan
        // error PostgreSQL yang membingungkan.
        $duplikat = DB::table('immunization_records as r')
            ->whereNotNull('r.deleted_at')
            ->whereExists(function ($query) {
                $query->select(DB::raw(1))
                    ->from('immunization_records as a')
                    ->whereColumn('a.child_id', 'r.child_id')
                    ->whereColumn('a.immunization_type_id', 'r.immunization_type_id')
                    ->where('a.deleted_at', '=', null);
            })
            ->count();

        if ($duplikat > 0) {
            throw new RuntimeException(
                "Ada {$duplikat} baris immunization_records yang di-soft-delete dan "
                .'duplikat dengan baris lain pada (child_id, immunization_type_id). '
                .'Unique constraint penuh tidak bisa dipulihkan selama duplikat itu ada. '
                .'Hapus permanen baris duplikatnya lebih dulu.'
            );
        }

        DB::statement('DROP INDEX IF EXISTS immunization_child_type_unique');

        Schema::table('immunization_records', function (Blueprint $table) {
            $table->dropIndex(['deleted_at']);
            $table->dropColumn('deleted_at');
        });

        Schema::table('immunization_records', function (Blueprint $table) {
            $table->unique(
                ['child_id', 'immunization_type_id'],
                'immunization_child_type_unique'
            );
        });
    }
};
