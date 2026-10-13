<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Entitas rujukan (lihat docs/RANCANGAN_RUJUKAN.md).
 *
 * Rujukan mencatat tindak lanjut anak dari Posyandu ke fasilitas kesehatan,
 * selalu terhubung ke satu kunjungan (`visit_id`) dan satu anak (`child_id`).
 * Keputusan desain yang penting:
 *
 *  1. `visit_id` wajib dengan `cascadeOnDelete`: rujukan adalah bagian dari
 *     satu kunjungan (PERANCANGAN_PERKUATAN.md bagian 1.3 langkah 3). Menghapus
 *     kunjungan secara fisik ikut menghapus rujukannya; penghapusan normal
 *     lewat aplikasi memakai soft delete, bukan hapus fisik.
 *
 *  2. `referral_type` dan `status` memakai string + CHECK constraint, konsisten
 *     dengan `visits.visit_type` dan `medical_notes.tindak_lanjut`, bukan enum
 *     PostgreSQL. Menambah nilai baru cukup migration biasa.
 *
 *  3. `kader_id` nullable + `nullOnDelete`, sama seperti tabel data kesehatan
 *     lain. Riwayat rujukan tidak boleh hilang hanya karena akun kader dihapus.
 *
 *  4. Soft delete. Rujukan yang salah input dibatalkan, bukan dihapus, supaya
 *     tetap bisa diaudit.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('referrals', function (Blueprint $table) {
            $table->uuid('id')->primary();

            $table->foreignUuid('visit_id')
                ->constrained('visits')
                ->cascadeOnDelete();

            $table->foreignUuid('child_id')
                ->constrained('children')
                ->cascadeOnDelete();

            $table->date('referral_date');

            $table->string('referral_type', 20);

            $table->text('reason');
            $table->string('facility_name', 255);

            $table->string('status', 20);

            $table->foreignUuid('kader_id')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();

            $table->timestamps();

            $table->timestamp('deleted_at')->nullable();

            $table->index(['child_id', 'referral_date'], 'referrals_child_date_index');
        });

        DB::statement(
            'ALTER TABLE referrals ADD CONSTRAINT referrals_referral_type_check '
            ."CHECK (referral_type IN ('puskesmas', 'rs', 'faskes_lain'))"
        );

        DB::statement(
            'ALTER TABLE referrals ADD CONSTRAINT referrals_status_check '
            ."CHECK (status IN ('dibuat', 'dilaporkan', 'selesai'))"
        );
    }

    public function down(): void
    {
        Schema::dropIfExists('referrals');
    }
};
