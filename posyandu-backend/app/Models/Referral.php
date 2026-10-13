<?php

namespace App\Models;

use App\Models\Concerns\Auditable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Satu rujukan anak ke fasilitas kesehatan.
 *
 * Rujukan adalah bagian dari satu kunjungan dan selalu terhubung ke satu anak
 * (lihat docs/RANCANGAN_RUJUKAN.md). Tabelnya dibuat oleh migration
 * `2026_10_13_152047_create_referrals_table`.
 *
 * Rujukan dicatat soft delete: rujukan yang salah input dibatalkan, bukan
 * dihapus, supaya tindak lanjutnya tetap bisa diaudit.
 */
class Referral extends Model
{
    use Auditable, HasFactory, HasUuids, SoftDeletes;

    protected $fillable = [
        'visit_id',
        'child_id',
        'referral_date',
        'referral_type',
        'reason',
        'facility_name',
        'status',
        'kader_id',
    ];

    protected function casts(): array
    {
        return [
            'referral_date' => 'date:Y-m-d',
        ];
    }

    // -----------------------------------------------------------------
    // Tipe rujukan
    // -----------------------------------------------------------------

    /** Rujukan ke Puskesmas. */
    public const TYPE_PUSKESMAS = 'puskesmas';

    /** Rujukan ke Rumah Sakit. */
    public const TYPE_RS = 'rs';

    /** Rujukan ke fasilitas kesehatan lain. */
    public const TYPE_FASKES_LAIN = 'faskes_lain';

    /**
     * Daftar tipe rujukan yang diizinkan.
     *
     * Cerminan CHECK constraint `referrals_referral_type_check`. Controller
     * memakainya untuk validasi supaya salah ketik ditolak sebagai 422, bukan
     * jadi 500 dari error PostgreSQL.
     */
    public const REFERRAL_TYPES = [
        self::TYPE_PUSKESMAS,
        self::TYPE_RS,
        self::TYPE_FASKES_LAIN,
    ];

    // -----------------------------------------------------------------
    // Status tindak lanjut
    // -----------------------------------------------------------------

    /** Rujukan baru dibuat. */
    public const STATUS_DIBUAT = 'dibuat';

    /** Rujukan sudah dilaporkan/diserahkan ke fasilitas tujuan. */
    public const STATUS_DILAPORKAN = 'dilaporkan';

    /** Tindak lanjut rujukan selesai. */
    public const STATUS_SELESAI = 'selesai';

    /**
     * Daftar status yang diizinkan.
     *
     * Cerminan CHECK constraint `referrals_status_check`.
     */
    public const STATUSES = [
        self::STATUS_DIBUAT,
        self::STATUS_DILAPORKAN,
        self::STATUS_SELESAI,
    ];

    // -----------------------------------------------------------------
    // Relasi
    // -----------------------------------------------------------------

    /** Kunjungan tempat rujukan ini dicatat. */
    public function visit(): BelongsTo
    {
        return $this->belongsTo(Visit::class);
    }

    /** Anak yang dirujuk. */
    public function child(): BelongsTo
    {
        return $this->belongsTo(Child::class);
    }

    /** Kader yang mencatat rujukan. Null kalau akunnya sudah dihapus. */
    public function kader(): BelongsTo
    {
        return $this->belongsTo(User::class, 'kader_id');
    }

    // -----------------------------------------------------------------
    // Scope
    // -----------------------------------------------------------------

    /** Rujukan milik satu kunjungan. */
    public function scopeForVisit(Builder $query, string $visitId): Builder
    {
        return $query->where('visit_id', $visitId);
    }
}
