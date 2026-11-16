<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Riwayat audit: siapa mengubah apa, kapan, dan dari nilai apa ke nilai apa.
 *
 * Tidak ada aturan bahwa audit harus dicatat dengan trigger database - yang
 * diwajibkan lewat trigger hanya Z-score WHO. Riwayat ini dicatat di lapisan
 * aplikasi (trait `App\Models\Concerns\Auditable`) supaya dua hal yang hanya
 * diketahui aplikasi ikut tersimpan: pengguna yang beraksi (`actor_id`) dan alamat
 * IP asal permintaan.
 *
 * Konsekuensinya, ditulis lewat Eloquent saja: efektif untuk seluruh perubahan
 * yang dilakukan API. Kolom `old_values`/`new_values` adalah JSONB agar bisa
 * dipakai untuk "apa yang berbeda" tanpa perlu tahu skema entitasnya.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('audit_logs', function (Blueprint $table) {
            $table->uuid('id')->primary();

            // Entitas yang berubah, dicatat "polymorphic": nama class model
            // + primary key-nya. Dipakai untuk memfilter riwayat per anak.
            $table->string('auditable_type');
            $table->uuid('auditable_id');

            $table->string('event', 20);

            // Pelaku perubahan. Null bila dilakukan sistem (seeder, backfill),
            // dan set null bila akunnya dihapus - riwayat audit tidak boleh ikut
            // hilang hanya karena akun kader dihapus.
            $table->foreignUuid('actor_id')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();

            // Nilai sebelum dan sesudah. `created_at`/`updated_at` tidak pernah
            // masuk ke sini (lihat trait Auditable).
            $table->jsonb('old_values')->nullable();
            $table->jsonb('new_values')->nullable();

            $table->string('ip_address', 45)->nullable();

            $table->timestamps();

            // Riwayat selalu ditampilkan per entitas dan per tanggal terbaru.
            $table->index(['auditable_type', 'auditable_id'], 'audit_logs_morph_index');
            $table->index(['created_at']);
            $table->index(['actor_id']);
        });

        DB::statement(
            'ALTER TABLE audit_logs ADD CONSTRAINT audit_logs_event_check '
            ."CHECK (event IN ('created', 'updated', 'deleted', 'restored'))"
        );
    }

    public function down(): void
    {
        Schema::dropIfExists('audit_logs');
    }
};
