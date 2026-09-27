<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

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
}
