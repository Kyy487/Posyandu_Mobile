<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Backfill kunjungan "legacy" untuk penimbangan lama (P0-1).
 *
 * Penimbangan yang dibuat sebelum entitas `visits` ada tidak punya
 * `visit_id`. Keputusan (docs/RANCANGAN_VISIT.md bagian 7.3): dibuatkan satu
 * kunjungan sintetis per (anak, tanggal) supaya seluruh riwayat terhubung,
 * bukan dibiarkan `NULL`.
 *
 * Tipe kunjungan memakai `posyandu` karena penimbangan dari periode lama
 * dicatat pada sesi posyandu. `kader_id` disalin dari penimbangan agar
 * atribusi pencatat tetap terjaga; baris yang kadernya sudah dihapus membiarkan
 * `kader_id` NULL - sama seperti perilaku `ON DELETE SET NULL`.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (DB::getDriverName() !== 'pgsql') {
            return;
        }

        // Satu kunjungan per (anak, tanggal) untuk penimbangan aktif yang belum
        // punya kunjungan. Unique partial index `measurements_child_date_unique`
        // menjamin satu penimbangan per anak per tanggal, jadi satu baris di
        // sini mewakili paling banyak satu penimbangan.
        DB::statement(
            'INSERT INTO visits (id, child_id, visit_date, visit_type, kader_id,'
            .' anamnesis, catatan_kader, created_at, updated_at, deleted_at)'
            .' SELECT gen_random_uuid(), m.child_id, m.measurement_date,'
            ." 'posyandu', m.kader_id, NULL, NULL, NOW(), NOW(), NULL"
            .' FROM measurements m'
            .' WHERE m.deleted_at IS NULL'
            .' AND m.visit_id IS NULL'
            .' AND NOT EXISTS ('
            .'  SELECT 1 FROM visits v'
            .'  WHERE v.child_id = m.child_id'
            .'   AND v.visit_date = m.measurement_date'
            .' )'
        );

        // Tautkan penimbangan lama ke kunjungan legacy-nya.
        DB::statement(
            'UPDATE measurements m'
            .' SET visit_id = ('
            .'  SELECT v.id FROM visits v'
            .'  WHERE v.child_id = m.child_id'
            .'   AND v.visit_date = m.measurement_date'
            .'  LIMIT 1'
            .' )'
            .' WHERE m.deleted_at IS NULL'
            .' AND m.visit_id IS NULL'
        );
    }

    public function down(): void
    {
        if (DB::getDriverName() !== 'pgsql') {
            return;
        }

        // Lepas tautan penimbangan, lalu buang kunjungan yang menjadi yatim
        // (tidak dirujuk tabel mana pun). Kunjungan asli dari API tetap aman
        // selama masih memiliki minimal satu penimbangan/imunisasi/keluhan.
        DB::statement('UPDATE measurements SET visit_id = NULL WHERE visit_id IS NOT NULL');

        DB::statement(
            'DELETE FROM visits v'
            .' WHERE NOT EXISTS (SELECT 1 FROM measurements m WHERE m.visit_id = v.id)'
            .' AND NOT EXISTS (SELECT 1 FROM immunization_records ir WHERE ir.visit_id = v.id)'
            .' AND NOT EXISTS (SELECT 1 FROM medical_notes mn WHERE mn.visit_id = v.id)'
        );
    }
};
