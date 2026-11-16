<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    use HasApiTokens, HasFactory, HasUuids, Notifiable;

    protected $fillable = [
        'nik',
        'nik_hash',
        'no_kk',
        'name',
        // 'email',
        'password',
        'role',
        'phone_number',
        'jabatan',
        'status',
        'onboarding_status',
        'place_of_birth',
        'date_of_birth',
        'gender',
        'blood_type',
        'address',
        'rt_rw',
        'education',
        'occupation',
        'whatsapp',
        'instagram',
        'facebook',
        'approved_by',
        'approved_at',
        'rejection_reason',
        'verified_at',
    ];

    protected $hidden = [
        'password',
        'remember_token',
        'nik',
        'nik_hash',
        'no_kk',
    ];

    /**
     * Field turunan yang selalu ikut di respons API.
     *
     * Flutter memakai `verification_status` dan `next_action` untuk menentukan
     * layar berikutnya (lengkapi data / tunggu verifikasi / tambah anak /
     * dashboard) tanpa perlu menebak dari kombinasi `status` + jumlah anak.
     */
    protected $appends = [
        'verification_status',
        'next_action',
    ];

    protected function casts(): array
    {
        return [
            'nik' => 'encrypted',
            'no_kk' => 'encrypted',
            'date_of_birth' => 'date',
            'approved_at' => 'datetime',
            'verified_at' => 'datetime',
        ];
    }

    /**
     * Status verifikasi dengan penamaan yang dipakai klien.
     *
     * Selalu dihitung dari `status` agar tidak pernah mengembalikan nilai
     * generated column yang sudah basi setelah `status` diubah pada model yang
     * sama (mis. approval Kader). Kolom generated `verification_status` tetap
     * ada di database untuk filter/reporting SQL.
     */
    public function getVerificationStatusAttribute(): string
    {
        return match ($this->status) {
            'active' => 'approved',
            'rejected' => 'rejected',
            default => 'pending',
        };
    }

    /**
     * Langkah berikutnya yang harus dilakukan Ibu.
     *
     * `null` berarti akun sudah boleh masuk dashboard.
     */
    public function getNextActionAttribute(): ?string
    {
        if ($this->role !== 'ibu') {
            return null;
        }

        return match ($this->verification_status) {
            'pending' => 'complete_registration',
            'rejected' => 'fix_registration',
            'approved' => $this->needsChildData() ? 'add_child' : null,
            default => null,
        };
    }

    public function isVerificationPending(): bool
    {
        return $this->role === 'ibu' && $this->verification_status === 'pending';
    }

    public function isVerified(): bool
    {
        return $this->role !== 'ibu' || $this->verification_status === 'approved';
    }

    public function needsChildData(): bool
    {
        return $this->role === 'ibu' && $this->onboarding_status === 'need_child_data';
    }

    public function hasCompletedOnboarding(): bool
    {
        return $this->role !== 'ibu' || $this->onboarding_status === 'completed';
    }

    // Relasi: Satu Ibu memiliki banyak Anak
    public function children()
    {
        return $this->hasMany(Child::class, 'user_id');
    }

    // Relasi: Satu Kader mencatat banyak Pengukuran
    public function measurements()
    {
        return $this->hasMany(Measurement::class, 'kader_id');
    }

    // Relasi: Satu Kader mencatat banyak Imunisasi
    public function immunizationRecords()
    {
        return $this->hasMany(ImmunizationRecord::class, 'kader_id');
    }

    /**
     * Relasi: Satu Kader mencatat banyak Catatan Keluhan.
     *
     * Dipakai endpoint `GET /kader/children/{child}/medical-notes` untuk
     * menampilkan siapa yang mencatat tiap complain, supaya kader lain yang
     * melakukan kunjungan lanjutan tahu catatan sebelumnya dibuat siapa.
     */
    public function medicalNotes(): HasMany
    {
        return $this->hasMany(MedicalNote::class, 'kader_id');
    }

    // Relasi: Satu Kader membuat banyak Agenda Posyandu
    public function createdSchedules()
    {
        return $this->hasMany(PosyanduSchedule::class, 'created_by');
    }

    // Relasi: Satu Kader bisa ditugaskan menangani banyak Agenda
    public function schedules()
    {
        return $this->belongsToMany(
            PosyanduSchedule::class,
            'posyandu_schedule_petugas',
            'petugas_id',
            'schedule_id'
        )->withTimestamps();
    }

    // Relasi: Satu Ibu bisa memberikan banyak consent
    public function consents(): HasMany
    {
        return $this->hasMany(Consent::class, 'granted_by');
    }

    public function verifications(): HasMany
    {
        return $this->hasMany(UserVerification::class, 'user_id');
    }

    public function userVerifications(): HasMany
    {
        return $this->hasMany(UserVerification::class, 'user_id');
    }

    public function approver(): BelongsTo
    {
        return $this->belongsTo(User::class, 'approved_by');
    }

    public function isPending(): bool
    {
        return $this->status === 'pending';
    }

    public function isActive(): bool
    {
        return $this->status === 'active';
    }

    public function isRejected(): bool
    {
        return $this->status === 'rejected';
    }

    public function isAdmin(): bool
    {
        return $this->role === 'admin';
    }
}
