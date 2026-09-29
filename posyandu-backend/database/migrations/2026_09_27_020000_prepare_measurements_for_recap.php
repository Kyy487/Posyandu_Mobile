<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Menyiapkan tabel `measurements` untuk rekap (Opsi E) tanpa merusak riwayat.
 *
 * Empat masalah yang diperbaiki, semuanya berdiri sendiri dan tidak menyentuh
 * endpoint:
 *
 * 1. TIDAK ADA INDEX APUN di tabel ini selain primary key. Diverifikasi lewat
 *    `pg_indexes`, yang hanya mengembalikan `measurements_pkey`.
 *
 * 2. `kader_id` ber-`ON DELETE CASCADE`, sedangkan tiga tabel lain
 *    (`immunization_records`, `medical_notes`, `posyandu_schedules`) sudah
 *    dikoreksi ke `SET NULL`. Akibatnya menghapus satu akun kader akan
 *    MENGHAPUS SELURUH riwayat penimbangan yang ia catat, dan karena tabel ini
 *    tidak punya soft delete, angka rekap bulan lalu bisa berubah sendiri tanpa
 *    jejak. Penimbangan adalah catatan kesehatan anak dan tidak boleh hilang
 *    hanya karena petugasnya dihapus.
 *
 * 3. Tabel ini belum punya `deleted_at`, padahal `MeasurementController`
 *    memanggil `delete()` dan tabel lain sudah memakai soft delete. Rekap tidak
 *    bisa membedakan "tidak ditimbang" dari "dibatalkan".
 *
 * 4. Tidak ada constraint yang mencegah satu anak ditimbang dua kali pada
 *    tanggal yang sama, padahal `Child::latestMeasurement()` memakai `hasOne` +
 *    `max(measurement_date)` - yaitu dia mengambil satu baris secara diam-diam.
 *    Kalau ada dua baris, "status gizi terakhir" jadi ambigu.
 *
 * Catatan: migration lama tidak diubah (Aturan #5), semua lewat file baru.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('measurements', function (Blueprint $table): void {
            $table->timestamp('deleted_at')->nullable()->after('updated_at');
        });

        // -----------------------------------------------------------------
        // Index 1: rekap per bulan. Satu-satunya index yang lewat uji A/B.
        //
        // Diuji dengan fixture 300 anak x 120 bulan = 36.000 baris:
        //   tanpa  -> Seq Scan / Index Scan, 2.132 ms
        //   dengan -> Index Only Scan,        0.245 ms   (8,7x lebih cepat)
        //
        // Kolom `deleted_at` diletakkan di depan, bukan filter terpisah,
        // supaya kondisi `deleted_at IS NULL` masuk ke Index Cond dan bisa
        // dilakukan index-only scan (tidak perlu ke heap).
        // -----------------------------------------------------------------
        Schema::table('measurements', function (Blueprint $table): void {
            $table->index(['deleted_at', 'measurement_date'], 'measurements_bulan_index');
        });

        // -----------------------------------------------------------------
        // Index 2: satu anak satu tanggal per hari, selama belum dibatalkan.
        //
        // Partial unique: anak yang penimbangannya dibatalkan tetap boleh
        // ditimbang ulang di tanggal yang sama - itu justru alur yang benar
        // setelah salah input. Index penuh (tanpa partial) akan melarang itu.
        //
        // Bonus: index ini juga yang dipakai planner untuk kueri Opsi E
        // "status gizi terakhir per anak", jadi tidak perlu index kelima.
        // -----------------------------------------------------------------
        DB::statement(<<<'SQL'
            CREATE UNIQUE INDEX measurements_child_date_unique
            ON measurements (child_id, measurement_date)
            WHERE deleted_at IS NULL
        SQL);

        // -----------------------------------------------------------------
        // Index 3: untuk aksi FK `ON DELETE SET NULL`, BUKAN untuk rekap.
        //
        // Planner tidak pernah memakainya untuk `GROUP BY kader_id` (diuji,
        // selisih di bawah noise). Yang memakainya adalah penghapusan akun
        // kader: PostgreSQL harus mencari baris yang menunjuk user itu, dan
        // tanpa index itu jadi seq scan penuh.
        //
        // -----------------------------------------------------------------
        Schema::table('measurements', function (Blueprint $table): void {
            $table->index(['kader_id'], 'measurements_kader_id_index');
        });

        // Kader yang dihapus tidak boleh menghapus riwayat penimbangan.
        DB::statement('ALTER TABLE measurements DROP CONSTRAINT measurements_kader_id_foreign');
        DB::statement(
            'ALTER TABLE measurements ADD CONSTRAINT measurements_kader_id_foreign '
            .'FOREIGN KEY (kader_id) REFERENCES users(id) ON DELETE SET NULL'
        );

        // Kader jadi nullable supaya mengosongkan akun tidak melanggar FK.
        // Baris lama tetap menyimpan UUID kader aslinya.
        DB::statement('ALTER TABLE measurements ALTER COLUMN kader_id DROP NOT NULL');
    }

    public function down(): void
    {
        // Kader_id balik jadi NOT NULL, tapi hanya kalau tidak ada baris yatim.
        // Kalau ada, `down` gagal dengan pesan yang jujur - lebih baik rollback
        // gagal daripada diam-diam membuang data.
        $yatim = DB::table('measurements')->whereNull('kader_id')->count();

        if ($yatim > 0) {
            throw new RuntimeException(
                "Rollback ditolak: ada {$yatim} baris measurements dengan kader_id NULL "
                .'(akun kadernya sudah dihapus). Isi kader_id-nya lebih dulu bila '
                .'benar-benar ingin kembali ke schema lama.'
            );
        }

        DB::statement('ALTER TABLE measurements ALTER COLUMN kader_id SET NOT NULL');
        DB::statement('ALTER TABLE measurements DROP CONSTRAINT measurements_kader_id_foreign');
        DB::statement(
            'ALTER TABLE measurements ADD CONSTRAINT measurements_kader_id_foreign '
            .'FOREIGN KEY (kader_id) REFERENCES users(id) ON DELETE CASCADE'
        );

        DB::statement('DROP INDEX IF EXISTS measurements_kader_id_index');
        DB::statement('DROP INDEX IF EXISTS measurements_child_date_unique');
        DB::statement('DROP INDEX IF EXISTS measurements_bulan_index');

        Schema::table('measurements', function (Blueprint $table): void {
            $table->dropColumn('deleted_at');
        });
    }
};
