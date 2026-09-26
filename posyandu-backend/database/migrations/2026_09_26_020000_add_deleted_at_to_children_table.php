<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Menambahkan soft delete pada tabel `children`.
 *
 * Latar belakang: `measurements.child_id` dan `immunization_records.child_id`
 * memakai `ON DELETE CASCADE`. Hard delete pada anak akan ikut menghapus seluruh
 * riwayat penimbangan dan imunisasi — data kesehatan yang tidak boleh hilang
 * diam-diam. Dengan `deleted_at`, data tetap tersimpan dan bisa dipulihkan.
 *
 * Catatan: NIK anak tetap unik termasuk baris yang sudah di-soft delete, agar
 * NIK tidak pernah dipakai ulang oleh anak yang berbeda.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('children', function (Blueprint $table) {
            $table->softDeletes();
            $table->index('deleted_at');
        });
    }

    public function down(): void
    {
        Schema::table('children', function (Blueprint $table) {
            $table->dropIndex(['deleted_at']);
            $table->dropColumn('deleted_at');
        });
    }
};
