<?php

namespace App\Models;

use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Catatan penimbangan anak (e-KMS).
 *
 * `kader_id` sengaja dibuat bisa NULL di database. Sebelumnya kolom ini
 * `ON DELETE CASCADE`, artinya menghapus satu akun kader ikut menghapus
 * seluruh riwayat penimbangan yang ia catat. Untuk tabel lain sudah
 * dikoreksi ke `SET NULL`; baris iniinggal tertinggal. Seiring dengan itu,
 * `kader()` bisa `null` dan pemanggil wajib mengeceknya.
 */
class Measurement extends Model
{
    use HasFactory, HasUuids, SoftDeletes;

    protected $fillable = [
        'child_id',
        'kader_id',
        'measurement_date',
        'weight_kg',
        'height_cm',
        'head_circumference_cm',
        'age_in_months',
        'z_score_wfa',
        'status_gizi',
    ];

    // Relasi balik ke Anak
    public function child()
    {
        return $this->belongsTo(Child::class);
    }

    /**
     * Relasi balik ke Kader yang menginput data.
     *
     * Bisa `null` dua alasan: kadernya sudah dihapus (`SET NULL` di FK), atau
     * data lama yang memang tidak di-backfill. Pemanggil wajib mengecek
     * sebelum membaca `->name`.
     */
    public function kader()
    {
        return $this->belongsTo(User::class, 'kader_id');
    }

    /**
     * Catatan keluhan yang dilampirkan ke penimbangan ini.
     *
     * Satu penimbangan punya banyak catatan, bukan satu: penimbangan bisa
     * berbarengan dengan keluhan demam sekaligus keluhan lain yang dicatat
     * terpisah pada hari yang sama.
     */
    public function medicalNotes(): HasMany
    {
        return $this->hasMany(MedicalNote::class);
    }

    // -----------------------------------------------------------------
    // Scope
    // -----------------------------------------------------------------

    /**
     * Penimbangan pada satu bulan, format `YYYY-MM`.
     *
     * Menggandakan `MedicalNote::scopeForMonth` dengan sengaja, bukan
     * mengekstrak trait bersama: bentuk kueri rekap nanti berbeda per
     * tabel, jadi menyamakan bentuk di sini lebih mudah dibaca daripada
     * abstraksi yang belum jelas pemakainya.
     *
     * Batas akhir dihitung dari kalender, bukan `$month.'-31'`, karena
     * PostgreSQL menolak tanggal yang tidak ada. Lihat
     * `MedicalNote::scopeForMonth`.
     */
    public function scopeForMonth(Builder $query, string $month): Builder
    {
        $awal = CarbonImmutable::createFromFormat('!Y-m', $month)->startOfMonth();

        return $query->whereBetween('measurement_date', [
            $awal->toDateString(),
            $awal->endOfMonth()->toDateString(),
        ]);
    }

    /** Penimbangan dalam rentang tanggal, inklusif di kedua ujung (`Y-m-d`). */
    public function scopeBetweenDates(Builder $query, string $from, string $to): Builder
    {
        return $query->whereBetween('measurement_date', [$from, $to]);
    }
}
