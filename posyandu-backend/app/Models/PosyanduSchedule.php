<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;

/**
 * Satu kegiatan posyandu pada tanggal tertentu.
 *
 * Yang dimodelkan adalah ACARA, bukan jadwal kunjungan per anak: satu baris =
 * satu kegiatan (Penimbangan Rutin Bulanan, Vaccination, Kunjungan Rumah) yang
 * ditangani beberapa petugas. Lihat migration
 * `2026_09_26_033000_create_posyandu_schedules_table.php` untuk arti kolom.
 */
class PosyanduSchedule extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'title',
        'description',
        'scheduled_date',
        'start_time',
        'end_time',
        'location',
        'status',
        'notes',
        'created_by',
    ];

    /**
     * `date` untuk tanggal agenda dan `date:H:i` untuk jam, supaya Flutter
     * bisa memakainya langsung tanpa memotong string.
     */
    protected function casts(): array
    {
        return [
            'scheduled_date' => 'date:Y-m-d',
            'start_time' => 'date:H:i',
            'end_time' => 'date:H:i',
        ];
    }

    /**
     * Nama lokasi yang dipakai di respons API.
     *
     * Kolom `location` sengaja tidak wajib diisi karena tahap ini aplikasi
     * hanya menangani satu posyandu. Kalau null, tampilannya memakai nama
     * posyandu dari config.
     */
    public function getLocationNameAttribute(): string
    {
        return $this->location ?: (string) config('posyandu.posyandu_name');
    }

    /** Petugas yang ditugaskan menangani kegiatan ini. */
    public function petugas(): BelongsToMany
    {
        return $this->belongsToMany(User::class, 'posyandu_schedule_petugas', 'schedule_id', 'petugas_id')
            ->withTimestamps();
    }

    /** Kader yang membuat agenda ini. Null kalau akunnya sudah dihapus. */
    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    // -----------------------------------------------------------------
    // Status
    // -----------------------------------------------------------------

    public const STATUS_TERJADWAL = 'terjadwal';

    public const STATUS_BERLANGSUNG = 'berlangsung';

    public const STATUS_SELESAI = 'selesai';

    public const STATUS_DIBATALKAN = 'dibatalkan';

    /**
     * Daftar status yang diizinkan.
     *
     * Cerminan CHECK constraint `posyandu_schedules_status_check` di database.
     * Controller memakainya untuk validasi supaya kesalahan ketik ketahuan
     * lebih awal sebagai 422, bukan jadi 500 dari error PostgreSQL.
     */
    public const STATUSES = [
        self::STATUS_TERJADWAL,
        self::STATUS_BERLANGSUNG,
        self::STATUS_SELESAI,
        self::STATUS_DIBATALKAN,
    ];

    // -----------------------------------------------------------------
    // Scope
    // -----------------------------------------------------------------

    /** Agenda pada satu tanggal (format `YYYY-MM-DD`). */
    public function scopeOnDate(Builder $query, string $date): Builder
    {
        return $query->whereDate('scheduled_date', $date);
    }

    /** Agenda pada rentang tanggal, inklusif di kedua ujung. */
    public function scopeBetweenDates(Builder $query, string $from, string $to): Builder
    {
        return $query->whereBetween('scheduled_date', [$from, $to]);
    }

    /** Agenda yang belum selesai dan belum dibatalkan, urut dari yang terdekat. */
    public function scopeAktif(Builder $query, ?string $today = null): Builder
    {
        $today ??= now()->toDateString();

        return $query->whereIn('status', [self::STATUS_TERJADWAL, self::STATUS_BERLANGSUNG])
            ->whereDate('scheduled_date', '>=', $today)
            ->orderBy('scheduled_date')
            ->orderBy('start_time');
    }
}
