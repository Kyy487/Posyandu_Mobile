<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class ImmunizationRecord extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'child_id',
        'kader_id',
        'vaccine_name',
        'date_given',
    ];

    // Relasi balik ke Anak
    public function child()
    {
        return $this->belongsTo(Child::class);
    }

    // Relasi balik ke Kader yang mencatat
    public function kader()
    {
        return $this->belongsTo(User::class, 'kader_id');
    }
}
