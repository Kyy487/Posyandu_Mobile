<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Menambahkan kolom `children.medical_flags` - penanda kondisi khusus anak
 * (alergi, penyakit bawaan) yang diminta `RANCANGAN.md` 3.1.A.
 *
 * Keputusan desain ada di `docs/RANCANGAN_BUKU_MEDIS.md` bagian 5.1: kondisi
 * khusus memakai KOLOM di tabel `children`, bukan tabel terpisah
 * `child_medical_flags`. Alasannya, tabel terpisah baru layak kalau nanti ada
 * pertanyaan "alergi ini sejak kapan" atau lebih dari satu jenis penanda per
 * anak yang perlu dilacak sejarahnya.
 *
 * Konsekuensi yang diterima dengan sengaja:
 *
 *  1. Tidak ada riwayat perubahan penanda. Kalau nanti mau tahu siapa yang
 *     menulis, jawabannya memang tidak tersimpan.
 *  2. Isinya TIDAK diparsing. Teks bebas, satu penanda per baris, mis.
 *     `alergi: penisilin` lalu `asma`. Presentasi di mobile menampilkan
 *     teks mentah apa adanya, jadi tidak ada daftar jenis yang perlu
 *     dipelihara di dua tempat.
 *  3. Tidak ada CHECK constraint. Batas 500 karakter divalidasi di
 *     `ChildController@update` supaya jawabannya 422 yang bisa dibaca, bukan
 *     error PostgreSQL. Database tetap menerima teks panjang supaya
 *     mengimpor data lama tidak ikut gagal.
 *
 * Tidak ada index: kolom ini tidak pernah dipakai untuk menyaring daftar anak,
 * hanya dibaca per anak yang sedang dibuka, dan tabelnya sudah punya primary
 * key. Index di sini hanya menambah biaya tulis pada setiap penambahan anak.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('children', function (Blueprint $table) {
            $table->text('medical_flags')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('children', function (Blueprint $table) {
            $table->dropColumn('medical_flags');
        });
    }
};
