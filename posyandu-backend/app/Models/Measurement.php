<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Measurement extends Model
{
    use HasFactory, HasUuids;

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

    // Relasi balik ke Kader yang menginput data
    public function kader()
    {
        return $this->belongsTo(User::class, 'kader_id');
    }
}
