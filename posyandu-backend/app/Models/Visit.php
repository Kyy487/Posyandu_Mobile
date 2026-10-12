<?php

namespace App\Models;

use App\Models\Concerns\Auditable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Satu kunjungan layanan untuk satu anak.
 *
 * Kunjungan menjadi penghubung pengukuran, imunisasi, dan keluhan yang terjadi
 * pada satu sesi layanan (lihat docs/RANCANGAN_VISIT.md). Tabelnya dibuat oleh
 * migration `2026_10_11_233500_create_visits_table`.
 *
 * Kunjungan dicatat soft delete: data yang sudah terhubung (mis. penimbangan)
 * tetap bisa diaudit walau sesi kunjungannya dibatalkan.
 */
class Visit extends Model
{
    use Auditable, HasFactory, HasUuids, SoftDeletes;

    protected $fillable = [
        'child_id',
        'schedule_id',
        'visit_date',
        'visit_type',
        'kader_id',
        'anamnesis',
        'catatan_kader',
    ];

    protected function casts(): array
    {
        return [
            'visit_date' => 'date:Y-m-d',
        ];
    }

    // -----------------------------------------------------------------
    // Tipe kunjungan
    // -----------------------------------------------------------------

    /** Sesi posyandu rutin. */
    public const VISIT_TYPE_POSYANDU = 'posyandu';

    /** Kunjungan ke rumah anak. */
    public const VISIT_TYPE_KUNJUNGAN_RUMAH = 'kunjungan_rumah';

    /** Kunjungan terkait rujukan. */
    public const VISIT_TYPE_RUJUKAN = 'rujukan';

    /**
     * Daftar tipe kunjungan yang diizinkan.
     *
     * Cerminan CHECK constraint `visits_visit_type_check` di database.
     * Controller memakainya untuk validasi supaya kesalahan ketik ketahuan
     * lebih awal sebagai 422, bukan jadi 500 dari error PostgreSQL.
     */
    public const VISIT_TYPES = [
        self::VISIT_TYPE_POSYANDU,
        self::VISIT_TYPE_KUNJUNGAN_RUMAH,
        self::VISIT_TYPE_RUJUKAN,
    ];

    // -----------------------------------------------------------------
    // Relasi
    // -----------------------------------------------------------------

    public function child(): BelongsTo
    {
        return $this->belongsTo(Child::class);
    }

    /** Agenda posyandu bila kunjungan terjadi pada sesi terjadwal. Null bila tidak. */
    public function schedule(): BelongsTo
    {
        return $this->belongsTo(PosyanduSchedule::class);
    }

    /** Kader yang memegang kunjungan. Null kalau akunnya sudah dihapus. */
    public function kader(): BelongsTo
    {
        return $this->belongsTo(User::class, 'kader_id');
    }

    /** Penimbangan yang dicatat dalam kunjungan ini. */
    public function measurements(): HasMany
    {
        return $this->hasMany(Measurement::class);
    }

    /** Suntikan yang dicatat dalam kunjungan ini. */
    public function immunizationRecords(): HasMany
    {
        return $this->hasMany(ImmunizationRecord::class);
    }

    /** Catatan keluhan yang dicatat dalam kunjungan ini. */
    public function medicalNotes(): HasMany
    {
        return $this->hasMany(MedicalNote::class);
    }

    // -----------------------------------------------------------------
    // Scope
    // -----------------------------------------------------------------

    /**
     * Kunjungan aktif milik anak tertentu, atau `null`.
     *
     * Dipakai endpoint pencatatan (penimbangan/imunisasi/keluhan) untuk
     * memastikan `visit_id` yang dikirim klien memang milik anak yang sama.
     * Mengembalikan `null` juga untuk kunjungan yang sudah dibatalkan (soft
     * delete), karena global scope Eloquent ikut berlaku.
     */
    public static function findForChild(?string $visitId, ?string $childId): ?self
    {
        if ($visitId === null || $childId === null) {
            return null;
        }

        return static::query()
            ->where('id', $visitId)
            ->where('child_id', $childId)
            ->first();
    }

    /** Kunjungan pada satu tanggal (format `YYYY-MM-DD`). */
    public function scopeOnDate(Builder $query, string $date): Builder
    {
        return $query->whereDate('visit_date', $date);
    }

    /** Kunjungan dalam rentang tanggal, inklusif di kedua ujung (`Y-m-d`). */
    public function scopeBetweenDates(Builder $query, string $from, string $to): Builder
    {
        return $query->whereBetween('visit_date', [$from, $to]);
    }
}
