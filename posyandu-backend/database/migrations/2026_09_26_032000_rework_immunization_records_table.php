<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Menyelaraskan `immunization_records` dengan master `immunization_types`.
 *
 * Yang berubah:
 *  1. `vaccine_name` (teks bebas) di_drop, digantikan `immunization_type_id`.
 *  2. `kader_id` diubah dari `cascadeOnDelete` menjadi `nullOnDelete`.
 *     Sebelumnya kalau petugas dihapus, seluruh catatan imunisasi anak ikut
 *     terhapus - data kesehatan hilang hanya karena akun petugas dihapus.
 *  3. Tambah `unique(child_id, immunization_type_id)` supaya satu anak tidak
 *     bisa punya dua record untuk dosis yang sama. Konsekuensinya: koreksi
 *     salah input dilakukan lewat PATCH (ubah tanggal/batch), bukan hapus lalu
 *     catat ulang. Ini memang trade-off yang disepakati.
 *  4. Tambah `batch_number` dan `notes` - nomor batch wajib ada di buku
 *     pencatatan imunisasi.
 *
 * Soft delete sengaja TIDAK dipakai di sini, konsisten dengan `measurements`:
 * satu anak satu dosis dijamin oleh unique constraint, sehingga koreksi cukup
 * lewat PATCH.
 */
return new class extends Migration
{
    public function up(): void
    {
        // Codec lama menyimpan nama vaksin sebagai teks bebas. Kalau ternyata
        // ada data, tidak ada cara menentukan tipe Master mana yang cocok -
        // menebak risks salah historial kesehatan. migration digagalkan supaya
        // pemindah data dilakukan manusia dengan pertimbangan.
        $ada = DB::table('immunization_records')->count();
        if ($ada > 0) {
            throw new RuntimeException(
                "immunization_records masih berisi {$ada} baris dengan format lama "
                . '(vaccine_name teks bebas). Pindahkan datanya ke immunization_types '
                . 'sebelum menjalankan migration ini.'
            );
        }

        // 1. Lepas constraint kader_id lama sebelum kolomnya diubah.
        Schema::table('immunization_records', function (Blueprint $table) {
            $table->dropForeign(['kader_id']);
            $table->dropColumn('vaccine_name');
        });

        // 2. Tambah kolom baru. Tabel sudah dipastikan kosong, jadi kolom
        //    NOT NULL bisa langsung tanpa langkah backfill.
        Schema::table('immunization_records', function (Blueprint $table) {
            $table->foreignUuid('immunization_type_id')
                ->nullable(false)
                ->constrained('immunization_types')
                ->restrictOnDelete();

            $table->string('batch_number', 60)->nullable();
            $table->text('notes')->nullable();
        });

        // 3. `kader_id` harus jadi NULLABLE. Postgres hanya menerima constraint
        //    `ON DELETE SET NULL` pada kolom NOT NULL, tapi kolom seperti itu
        //    akan meledak begitu ada petugas yang dihapus. Supaya
        //    "petugas dihapus, catatan imunisasi tetap ada" benar-benar
        //    bekerja, kolomnya harus menerima NULL.
        Schema::table('immunization_records', function (Blueprint $table) {
            $table->foreign('kader_id')
                ->references('id')->on('users')
                ->nullOnDelete();
        });

        Schema::table('immunization_records', function (Blueprint $table) {
            $table->uuid('kader_id')->nullable()->change();
        });

        // 4. Cegah suntikan dobel untuk dosis yang sama.
        Schema::table('immunization_records', function (Blueprint $table) {
            $table->unique(
                ['child_id', 'immunization_type_id'],
                'immunization_child_type_unique'
            );
            $table->index('date_given');
        });
    }

    public function down(): void
    {
        Schema::table('immunization_records', function (Blueprint $table) {
            $table->dropUnique('immunization_child_type_unique');
            $table->dropIndex(['date_given']);
            $table->dropForeign(['immunization_type_id']);
            $table->dropColumn(['immunization_type_id', 'batch_number', 'notes']);

            // WAJIB drop dulu: constraint `kader_id` sudah ada (dibuat ulang
            // dengan aksi ON DELETE SET NULL), jadi langsung menambahkan lagi
            // akan kena "Duplicate object".
            $table->dropForeign(['kader_id']);
        });

        // Kembalikan `kader_id` ke NOT NULL + ON DELETE CASCADE seperti semula.
        // Tabel dipastikan kosong oleh pemeriksaan di up(), jadi tidak ada baris
        // dengan kader_id NULL yang menghalangi.
        Schema::table('immunization_records', function (Blueprint $table) {
            $table->uuid('kader_id')->nullable(false)->change();
            $table->foreign('kader_id')
                ->references('id')->on('users')
                ->cascadeOnDelete();
        });

        // Nilai `nama` tidak dapat direkonstruksi persis, jadi kolom dikembalikan
        // sebagai nullable.
        Schema::table('immunization_records', function (Blueprint $table) {
            $table->string('vaccine_name')->nullable();
        });
    }
};
