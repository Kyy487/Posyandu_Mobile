<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Tabel catatan keluhan kader saat kunjungan posyandu.
 *
 * Yang dimodelkan: satu baris = satu catatan keluhan untuk satu anak pada satu
 * tanggal. Ini memenuhi RANCANGAN 3.1.A ("kolom keluhan ... yang tersimpan
 * sebagai rekam jejak bulanan") sekaligus kebutuhan Ibu di RANCANGAN 3.2.A
 * untuk membaca catatan keluhan/saran yang diinput kader.
 *
 * Keputusan desain yang penting:
 *
 *  1. Keluhan disimpan sebagai KOLOM BOOLEAN TERPISAIN (`demam`, `rewel`,
 *     `diare`), bukan satu baris per keluhan dan bukan array JSON.
 *     Alasannya: Opsi E (rekap) nanti perlu menghitung "berapa anak bulan ini
 *     punya demam" dan "berapa anak perlu rujukan". Dengan kolom boolean itu
 *     jadi satu `WHERE demam = true` yang murah, sekaligus bisa di-aggregate
 *     di database. Array JSON tidak bisa difilter seperti itu tanpa casting
 *     per baris. Pemisahan per kolom juga konsisten dengan `measurements` yang
 *     sudah memisahkan setiap parameter.
 *
 *  2. `measurement_id` nullable. Keluhan sering muncul di baris penimbangan
 *     yang sama, tapi tidak selalu - kader bisa mencatat keluhan saat kunjungan
 *     rumah tanpa menimbang. Karena itu relasinya opsional, bukan wajib.
 *     Catatan yang terhubung ke penimbangan tetap dipakai walau penimbangannya
 *     dihapus (`nullOnDelete`), karena keluhan adalah informasi kesehatan
 *     yang tidak boleh ikut hilang.
 *
 *  3. `kader_id` nullable + `nullOnDelete`, sama seperti
 *     `immunization_records.kader_id`. Data kesehatan tidak boleh ikut terhapus
 *     karena alasan administratif (petugas pindah tugas atau akun dihapus).
 *
 *  4. Soft delete. Catatan keluhan yang salah input tidak boleh hilang begitu
 *     saja - pada buku pencatatan, entri yang salah dibatalkan, bukan dihapus.
 *     Pola ini sama dengan `immunization_records` setelah migration `035000`.
 *
 *  5. `tindak_lanjut` memakai string + CHECK constraint, bukan enum Postgres,
 *     konsisten dengan `posyandu_schedules.status`. Rujukan ke petugas lain
 *     ('rujuk') adalah keputusan yang sering diambil kader di lapangan, jadi
 *     nilainya harus bisa langsung dibaca lewat API.
 *
 * Unique `(child_id, note_date)` dipakai sebagai pagar anti-catatan-ganda:
 * satu anak punya paling banyak satu catatan keluhan per hari, sehingga
 *     salah ketuk dua kali tidak menghasilkan dua baris yang bertentangan.
 * Index-nya dibuat PARTIAL `WHERE deleted_at IS NULL` supaya catatan yang sudah
 * dibatalkan tidak memblokir pencatatan ulang di hari yang sama.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('medical_notes', function (Blueprint $table) {
            $table->uuid('id')->primary();

            $table->foreignUuid('child_id')->constrained('children')->cascadeOnDelete();

            // Nullable: keluhan tidak selalu dibarengi penimbangan.
            // nullOnDelete: keluhan tidak ikut hilang kalau penimbangan dihapus.
            $table->foreignUuid('measurement_id')
                ->nullable()
                ->constrained('measurements')
                ->nullOnDelete();

            $table->foreignUuid('kader_id')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();

            $table->date('note_date');

            // Keluhan yang paling sering dicatat kader di posyandu.
            $table->boolean('demam')->default(false);
            $table->boolean('rewel')->default(false);
            $table->boolean('diare')->default(false);

            // Catatan saran /-complaint lain yang tidak punya kolom sendiri.
            $table->text('catatan')->nullable();

            $table->string('tindak_lanjut', 20)->nullable();

            $table->timestamps();

            $table->timestamp('deleted_at')->nullable();

            // Daftar keluhan satu anak selalu difilter per bulan, jadi index-nya
            // mengikuti pola akses itu, bukan `child_id` saja.
            $table->index(['child_id', 'note_date'], 'medical_notes_child_date_index');
        });

        // Pagar anti-catatan-ganda per anak per hari, hanya untuk catatan aktif.
        DB::statement(
            'CREATE UNIQUE INDEX medical_notes_child_date_unique '
            .'ON medical_notes (child_id, note_date) '
            .'WHERE deleted_at IS NULL'
        );

        // Konsisten dengan `posyandu_schedules_status_check`: string + CHECK,
        // bukan enum Postgres, supaya menambah nilai baru tetap migration biasa.
        DB::statement(
            'ALTER TABLE medical_notes ADD CONSTRAINT medical_notes_tindak_lanjut_check '
            ."CHECK (tindak_lanjut IS NULL OR tindak_lanjut IN ('ringan', 'sedang', 'rujuk'))"
        );

        // Catatan yang tidak berisi informasi apa pun tidak berguna dan biasanya
        // terjadi karena kader menekan tombol simpan tanpa mengisi apa pun.
        // Database menolak, jadi tidak ada baris kosong yang membingungkan
        // saat Ibu membaca riwayatnya.
        DB::statement(
            'ALTER TABLE medical_notes ADD CONSTRAINT medical_notes_isi_check '
            ."CHECK (demam OR rewel OR diare OR (catatan IS NOT NULL AND btrim(catatan) <> ''))"
        );
    }

    public function down(): void
    {
        Schema::dropIfExists('medical_notes');
    }
};
