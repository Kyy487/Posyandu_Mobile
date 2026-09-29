<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Master satu dosis imunisasi, mis. "Hepatitis B dosis 2".
 *
 * Baris ini bukan data anak; ini referensi program imunisasi yang dibaca semua
 * anak untuk menyusun checklist. Lihat migration
 * `2026_09_26_031000_create_immunization_types_table.php` untuk arti kolom.
 */
class ImmunizationType extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'code',
        'name',
        'dose_number',
        'target_age_months',
        'interval_months',
        'notes',
    ];

    /** Catatan suntikan anak yang memakai master ini. */
    public function records(): HasMany
    {
        return $this->hasMany(ImmunizationRecord::class);
    }

    /**
     * Status untuk satu anak: `sudah`, `belum`, atau `terlambat`.
     *
     * Disini JANGAN menyimpan status. Status bergantung pada tanggal lahir
     * anak dan tanggal suntikan, jadi harus dihitung ulang setiap request
     * (lihat `ImmunizationChecklistService`). Menyimpannya di database akan
     * cepat basi begitu anak bertambah umurnya.
     */
    public const STATUS_DONE = 'sudah';

    public const STATUS_PENDING = 'belum';

    public const STATUS_OVERDUE = 'terlambat';

    /**
     * Master diurutkan sesuai urutan suntikan, bukan urutan abjad.
     *
     * Kuncinya `target_age_months`, lalu `code` dan `dose_number` sebagai
     * pemutus ties. Urutannya penting untuk kader: checklist anak dan rekap
     * bulanan menampilkan dosis dalam urutan ini, dan urutannya harus sama
     * dengan urutan menyuntik. Dulu urutannya `code` saja, yang menghasilkan
     * BCG, DPT-HB-Hib, HB, MR, POLIO - abjad, bukan kronologis. Kader yang
     * membaca daftar itu melihat campak sebelum hepatitis B.
     *
     * `code` dan `dose_number` tetap dipakai sebagai pemutus supaya dua dosis
     * dengan target usia sama (mis. pada bulan ke-2 ada BCG, HB ke-2, dan polio
     * ke-2) selalu dapat urutan yang sama. Tanpa itu, urutannya bisa berubah
     * antar-request dan laporan tentang satu anak bisa jadi berbeda.
     *
     * Dosis tanpa `target_age_months` (`NULL`) selalu di akhir. PostgreSQL
     * menempatkan NULL terakhir pada `ORDER BY ... ASC`, jadi itu tidak perlu
     * penanganan khusus - tapi ditulis eksplisit di sini karena kalau suatu saat
     * default itu berubah, daftar dosis akan berantakan tanpa ada yang
     * mengeluarkannya.
     */
    public function scopeOrderedForDosing(Builder $query): Builder
    {
        return $query
            ->orderByRaw('target_age_months ASC NULLS LAST')
            ->orderBy('code')
            ->orderBy('dose_number');
    }

    /**
     * Label yang ditampilkan ke pengguna, mis. "Hepatitis B (Dosis 2)".
     *
     * Dosis 1 tidak diberi embel-embel: "Hepatitis B" lebih enak dibaca
     * daripada "Hepatitis B (Dosis 1)".
     */
    public function getLabelAttribute(): string
    {
        if ((int) $this->dose_number <= 1) {
            return (string) $this->name;
        }

        return sprintf('%s (Dosis %d)', $this->name, (int) $this->dose_number);
    }
}
