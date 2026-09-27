<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Satu catatan suntikan untuk satu anak pada satu dosis master.
 *
 * Kolom `vaccine_name` (teks bebas) sudah dihapus oleh migration
 * `2026_09_26_032000_rework_immunization_records_table.php`. Sebelumnya nama
 * vaksin ditulis bebas oleh kader ("HB 2", "Hepatitis B", "HB-2") sehingga
 * tidak bisa dihitung menjadi checklist dan tidak bisa di-grouping. Sekarang
 * suntikan selalu menunjuk satu baris `immunization_types`.
 *
 * Catatan: satu anak hanya boleh punya satu baris untuk satu dosis, dijamin
 * unique constraint `immunization_child_type_unique` di database. Karena itu
 * koreksi salah input dilakukan lewat PATCH tanggal/batch, bukan hapus lalu
 * catat ulang. Soft delete sengaja tidak dipakai, konsisten dengan
 * `Measurement`.
 */
class ImmunizationRecord extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'child_id',
        'kader_id',
        'immunization_type_id',
        'date_given',
        'batch_number',
        'notes',
    ];

    /**
     * Tanggal suntikan dikirim ke klien sebagai `YYYY-MM-DD`, bukan
     * `YYYY-MM-DD 00:00:00`, supaya Flutter bisa memakainya langsung untuk
     * `DateTime.parse` tanpa pemotongan manual.
     */
    protected function casts(): array
    {
        return [
            'date_given' => 'date:Y-m-d',
        ];
    }

    /** Anak yang menerima suntikan ini. */
    public function child(): BelongsTo
    {
        return $this->belongsTo(Child::class);
    }

    /**
     * Kader yang mencatat suntikan ini.
     *
     * Nullable di database: `ON DELETE SET NULL` supaya data kesehatan anak
     * tidak hilang hanya karena akun petugas dihapus.
     */
    public function kader(): BelongsTo
    {
        return $this->belongsTo(User::class, 'kader_id');
    }

    /** Dosis master yang disuntikkan. */
    public function immunizationType(): BelongsTo
    {
        return $this->belongsTo(ImmunizationType::class);
    }
}
