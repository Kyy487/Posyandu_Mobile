<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    use HasApiTokens, HasFactory, Notifiable, HasUuids;

    protected $fillable = [
        'nik',
        'name',
        //'email',
        'password',
        'role',
        'phone_number',
    ];

    protected $hidden = [
        'password',
        'remember_token',
    ];

   

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
}
