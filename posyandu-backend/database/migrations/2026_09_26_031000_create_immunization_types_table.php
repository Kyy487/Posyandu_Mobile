<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Master Holistic Integrated Immunization (HB) per Posyandu.
 *
 * Dipisah dari `immunization_records` karena daftar ini adalah *data referensi*
 * yang relatif tetap (dari national immunization program), sedangkan
 * `immunization_records` adalah hasil pencatatan per anak.
 *
 * Setiap baris = satu dosis. Hepatitis B punya 4 dosis (0, 2, 4, 6 bulan),
 * campak-rubella punya 2 dosis (9, 18 bulan), dan seterusnya. Karena itu
 * `kode` TIDAK unik sendirian; yang unik adalah pasangan `code` + `dose_number`.
 *
 * Nama kolom memakai Bahasa Inggris agar konsisten dengan seluruh tabel lain
 * di proyek ini: `children.name`, `children.date_of_birth`,
 * `measurements.measurement_date`, `users.role`.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('immunization_types', function (Blueprint $table) {
            $table->uuid('id')->primary();

            // Kode singkatan program imunisasi, mis. "HB", "BCG", "POLIO",
            // "DPT-HB-HIB", "MR". Dicari lewat `LIKE 'HB%'` di layar Kader.
            $table->string('code', 20);

            // Nama yang tampil ke pengguna, mis. "Hepatitis B".
            $table->string('name');

            // Dosis ke-berapa dari rangkaian ini (1-based).
            $table->unsignedSmallInteger('dose_number')->default(1);

            // Usia target dalam bulan sejak lahir. 0 = saat lahir.
            $table->unsignedSmallInteger('target_age_months')->nullable();

            // Jarak dari dosis sebelumnya, dipakai untuk memvalidasi bahwa
            // tanggal suntikan masuk akal (dosis 2 tidak boleh dicatat sebelum
            // dosis 1). Null untuk dosis pertama.
            $table->unsignedSmallInteger('interval_months')->nullable();

            $table->text('notes')->nullable();

            $table->timestamps();

            // Cegah satu vaksin punya dua dosis dengan nomor yang sama.
            $table->unique(['code', 'dose_number'], 'immunization_types_code_dose_unique');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('immunization_types');
    }
};
