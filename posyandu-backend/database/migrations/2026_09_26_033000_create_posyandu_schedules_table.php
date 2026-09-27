<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Tabel agenda kegiatan posyandu.
 *
 * Yang dimodelkan adalah ACARA, bukan jadwal kunjungan per anak: satu baris =
 * satu kegiatan (Penimbangan Rutin Bulanan, Vaccination, Kunjungan Rumah)
 * pada tanggal tertentu, di lokasi tertentu, yang ditangani beberapa petugas.
 *
 * `status` memakai string + CHECK constraint (bukan enum Postgres) supaya
 * menambah status baru cukup lewat migration, dan supaya nilainya terbaca
 * dan dipakai apa adanya di respons API. Alur status:
 *
 *   terjadwal -> berlangsung -> selesai
 *        \                      \
 *         -> dibatalkan          -> dibatalkan
 *
 * `location` sengaja nullable: untuk tahap ini aplikasi hanya menangani satu
 * posyandu (nama diambil dari `config('posyandu.posyandu_name')`), tapi kolomnya
 * disimpan supaya kegiatan di lokasi lain (mis. ber momentary di tempat umum)
 * tetap bisa dicatat tanpa perlu perubahan schema.
 *
 * Penugasan petugas ada di tabel terpisah `posyandu_schedule_petugas`.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('posyandu_schedules', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('title');
            $table->text('description')->nullable();
            $table->date('scheduled_date');
            $table->time('start_time')->nullable();
            $table->time('end_time')->nullable();
            $table->string('location', 160)->nullable();
            $table->string('status', 20)->default('terjadwal');
            $table->text('notes')->nullable();

            $table->foreignUuid('created_by')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();

            $table->timestamps();

            // Daftar jadwal hampir selalu difilter per tanggal lalu urut.
            $table->index(['scheduled_date', 'status']);
        });

        // Konsisten dengan pola `users.role` di proyek ini: nilai dibatasi lewat
        // CHECK constraint, bukan enum Postgres, supaya menambah status baru
        // tetap migration biasa dan nilainya terbaca apa adanya di API.
        DB::statement(
            'ALTER TABLE posyandu_schedules ADD CONSTRAINT posyandu_schedules_status_check '
            ."CHECK (status IN ('terjadwal', 'berlangsung', 'selesai', 'dibatalkan'))"
        );
    }

    public function down(): void
    {
        Schema::dropIfExists('posyandu_schedules');
    }
};
