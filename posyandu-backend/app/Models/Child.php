<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Child extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'user_id',
        'nik',
        'name',
        'date_of_birth',
        'gender',
        'birth_weight',
        'birth_height',
    ];

    public function mother()
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    // Relasi balik: Anak ini milik siapa (Ibu)
    // CATATAN: kolom foreign key di tabel `children` adalah `user_id`.
    public function parent()
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    // Relasi: Satu Anak memiliki banyak riwayat pengukuran
    public function measurements()
    {
        return $this->hasMany(Measurement::class);
    }

    // Relasi: Satu Anak memiliki banyak riwayat imunisasi
    public function immunizationRecords()
    {
        return $this->hasMany(ImmunizationRecord::class);
    }
}
