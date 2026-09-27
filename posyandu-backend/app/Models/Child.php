<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Database\Eloquent\SoftDeletes;

class Child extends Model
{
    use HasFactory, HasUuids, SoftDeletes;

    protected $fillable = [
        'user_id',
        'nik',
        'name',
        'date_of_birth',
        'gender',
        'birth_weight',
        'birth_height',
    ];

    /**
     * Tidak ikut dikirim ke klien.
     *
     * - `latestMeasurement` memakai nama relasi **camelCase**, bukan
     *   `latest_measurement`. `relationsToArray()` memfilter `$hidden`
     *   berdasarkan nama relasi SEBELUM di-convert ke snake_case, sehingga
     *   `latest_measurement` tidak akan cocok dan tetap terkirim.
     *   Relasi ini tidak perlu dikirim karena respons sudah memuat
     *   `last_measurement_date`, `latest_z_score`, dan `nutritional_status`
     *   lewat `$appends`.
     * - `deleted_at` tidak pernah relevan bagi klien: anak yang sudah di-soft
     *   delete otomatis hilang dari `GET /children` dan `GET /kader/children`,
     *   jadi nilainya selalu `null`.
     */
    protected $hidden = [
        'latestMeasurement',
        'deleted_at',
    ];

    /**
     * Relasi yang SELALU dimuat bersama model ini.
     *
     * Dipakai agar tiga accessor di bawah (`last_measurement_date`,
     * `latest_z_score`, `nutritional_status`) tidak memicu N+1 query di
     * endpoint mana pun yang me-serialize `Child`. Tanpa baris ini, setiap
     * anak dalam daftar akan mengambil measurement-nya satu per satu.
     */
    protected $with = ['latestMeasurement'];

    /**
     * Tiga field ini yang dibaca mobile dari `GET /children` dan
     * `GET /kader/children` untuk menampilkan status gizi terakhir.
     * Semuanya nullable: anak yang belum pernah ditimbang akan null.
     */
    protected $appends = [
        'last_measurement_date',
        'latest_z_score',
        'nutritional_status',
    ];

    public function mother(): BelongsTo
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    /**
     * Relasi balik: Anak ini milik siapa (Ibu)
     * CATATAN: kolom foreign key di tabel `children` adalah `user_id`.
     *
     * Alias dari `mother()`. Dipertahankan agar kode lama yang memakai
     * `parent` tidak rusak; tidak ada lagi kode yang memakai alias ini.
     */
    public function parent(): BelongsTo
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    /** Satu Anak memiliki banyak riwayat pengukuran. */
    public function measurements(): HasMany
    {
        return $this->hasMany(Measurement::class);
    }

    /**
     * Pengukuran terakhir anak, diurutkan dari yang terbaru.
     *
     * Sengaja TIDAK memakai `latestOfMany()`. Metode itu membuat SQL
     * `MAX(measurements.id)` untuk Break halaman hasil, sedangkan primary key
     * tabel ini bertipe UUID dan PostgreSQL tidak menyediakan fungsi
     * `max(uuid)` (SQLSTATE 42883).
     *
     * Subquery korelasi di bawah aman untuk eager loading: saat Eloquent
     * memuat relasi untuk banyak anak sekaligus, kondisi ini dievaluasi per
     * baris hasil, bukan sekali untuk seluruh daftar.
     */
    public function latestMeasurement(): HasOne
    {
        return $this->hasOne(Measurement::class)
            ->whereRaw(
                'measurements.measurement_date = ('
                .'select max(m2.measurement_date) from measurements m2'
                .' where m2.child_id = measurements.child_id)'
            );
    }

    /** Satu Anak memiliki banyak riwayat imunisasi. */
    public function immunizationRecords(): HasMany
    {
        return $this->hasMany(ImmunizationRecord::class);
    }

    /**
     * Satu Anak memiliki banyak catatan keluhan.
     *
     * Catatan yang sudah di-soft delete otomatis tidak ikut, jadi Ibu yang
     * membaca riwayat tidak pernah melihat entri yang sudah dibatalkan kader.
     */
    public function medicalNotes(): HasMany
    {
        return $this->hasMany(MedicalNote::class);
    }

    // -----------------------------------------------------------------
    // Accessor untuk respons API
    // -----------------------------------------------------------------

    /** Tanggal penimbangan terakhir, format `YYYY-MM-DD`. */
    public function getLastMeasurementDateAttribute(): ?string
    {
        return $this->latestMeasurement?->measurement_date;
    }

    /**
     * Z-Score Weight-for-Age terakhir.
     *
     * Dikembalikan sebagai float (bukan string) supaya Flutter bisa langsung
     * memakainya. Kolomnya bertipe `decimal` di PostgreSQL, jadi nilainya
     * tetap bentuk string bila accessor ini dihapus someday.
     */
    public function getLatestZScoreAttribute(): ?float
    {
        $value = $this->latestMeasurement?->z_score_wfa;

        return $value === null ? null : (float) $value;
    }

    /** Status gizi terakhir, mis. `Normal`, `Gizi Kurang`, `Stunting`. */
    public function getNutritionalStatusAttribute(): ?string
    {
        return $this->latestMeasurement?->status_gizi;
    }

    // -----------------------------------------------------------------
    // Scope
    // -----------------------------------------------------------------

    /** Hanya anak milik Ibu tertentu. */
    public function scopeOwnedBy(Builder $query, string $userId): Builder
    {
        return $query->where('user_id', $userId);
    }
}
