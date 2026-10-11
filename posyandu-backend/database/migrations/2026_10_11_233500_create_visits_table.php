<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Entitas kunjungan (P0-1, lihat docs/RANCANGAN_VISIT.md).
 *
 * Kunjungan menjadi penghubung pengukuran, imunisasi, dan keluhan yang terjadi
 * pada satu sesi layanan, supaya rekam medis bisa dibaca per-kunjungan, bukan
 * hanya per-tanggal. Keputusan desain yang penting:
 *
 *  1. TIDAK ada unique index `(child_id, visit_date)`. Satu anak boleh punya
 *     lebih dari satu kunjungan di tanggal yang sama (mis. posyandu pagi lalu
 *     kunjungan rumah sore). Ini keputusan yang sudah ditutup di
 *     docs/RANCANGAN_VISIT.md bagian 7.1.
 *
 *  2. `visit_type` memakai string + CHECK constraint, konsisten dengan
 *     `medical_notes.tindak_lanjut` dan `posyandu_schedules.status`, bukan enum
 *     PostgreSQL. Menambah nilai `visit_type` baru cukup migration biasa.
 *
 *  3. `schedule_id` nullable + `nullOnDelete`: menghapus agenda posyandu tidak
 *     boleh menghapus kunjungan yang pernah terjadi di agenda itu.
 *
 *  4. `kader_id` nullable + `nullOnDelete`, sama seperti tabel data kesehatan
 *     lain. Riwayat kunjungan tidak boleh hilang hanya karena akun kader
 *     dihapus.
 *
 *  5. Soft delete. Kunjungan yang salah input dibatalkan, bukan dihapus,
 *     supaya data yang sudah terhubung (mis. penimbangan) tetap bisa diaudit.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('visits', function (Blueprint $table) {
            $table->uuid('id')->primary();

            $table->foreignUuid('child_id')
                ->constrained('children')
                ->cascadeOnDelete();

            $table->foreignUuid('schedule_id')
                ->nullable()
                ->constrained('posyandu_schedules')
                ->nullOnDelete();

            $table->date('visit_date');

            $table->string('visit_type', 20);

            $table->foreignUuid('kader_id')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();

            $table->text('anamnesis')->nullable();
            $table->text('catatan_kader')->nullable();

            $table->timestamps();

            $table->timestamp('deleted_at')->nullable();

            // Daftar kunjungan satu anak selalu difilter per periode tanggal,
            // jadi index-nya mengikuti pola akses itu, bukan `child_id` saja.
            $table->index(['child_id', 'visit_date'], 'visits_child_date_index');
        });

        DB::statement(
            'ALTER TABLE visits ADD CONSTRAINT visits_visit_type_check '
            ."CHECK (visit_type IN ('posyandu', 'kunjungan_rumah', 'rujukan'))"
        );
    }

    public function down(): void
    {
        Schema::dropIfExists('visits');
    }
};
