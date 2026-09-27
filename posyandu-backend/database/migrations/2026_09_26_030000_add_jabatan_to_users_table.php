<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Menambahkan kolom `jabatan` pada tabel `users`.
 *
 * Latar belakang: aplikasi butuh lebih dari sekadar "kader" - ada Admin,
 * Bidan, Kader Posyandu, dan Tenaga Gizi yang berbeda tugasannya.
 *
 * Sengaja TIDAK menambah role baru. `users.role` punya CHECK constraint
 * `('ibu','kader')` di PostgreSQL, dan seluruh permission di aplikasi
 * diturunkan dari role tersebut (lihat middleware `RoleCheck`). Menambah role
 * berarti menambah cabang permission di mana-mana, sementara untuk tahap ini
 * semua petugas masih punya kewenangan yang sama. `jabatan` karena itu purely
 * deskriptif: ditampilkan di layar dan dipakai untuk membedakan tugas, tapi tidak
 * mengubah hak akses.
 *
 * Nullable karena akun Ibu tidak punya jabatan, dan supaya migration ini
 * tidak perlu mengisi nilai untuk baris yang sudah ada.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('jabatan')->nullable()->after('role');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('jabatan');
        });
    }
};
