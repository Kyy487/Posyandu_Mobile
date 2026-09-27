<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Pivot penugasan petugas ke agenda posyandu.
 *
 * Dipisah dari `posyandu_schedules` karena satu kegiatan biasanya ditangani
 * lebih dari satu petugas (bidan + 2 kader posyandu). Kalau kolom tunggal
 * `petugas_id` dipakai, sisanya harus disimpan sebagai JSON atau ditekankan
 * jadi string - keduanya menyimpan data yang tidak bisa dijaga foreign key-nya.
 *
 * `cascadeOnDelete` pada kedua foreign key: kalau petugas atau agenda dihapus,
 * riwayat penugasan ikut hilang, tapi akun petugas dan agenda itu sendiri
 * tidak ikut terhapus. Baris pivot tidak pernah ada tanpa dua induknya, jadi
 * tidak ada gunanya menyimpan jadwal yang sudah tidak punya petugas.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('posyandu_schedule_petugas', function (Blueprint $table) {
            $table->id();

            $table->foreignUuid('schedule_id')
                ->constrained('posyandu_schedules')
                ->cascadeOnDelete();

            $table->foreignUuid('petugas_id')
                ->constrained('users')
                ->cascadeOnDelete();

            $table->timestamps();

            // Satu petugas hanya boleh sekali di satu kegiatan.
            $table->unique(['schedule_id', 'petugas_id'], 'schedule_petugas_unique');
            $table->index('petugas_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('posyandu_schedule_petugas');
    }
};
