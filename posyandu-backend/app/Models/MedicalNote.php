<?php

namespace App\Models;

use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Catatan keluhan yang dicatat kader saat kunjungan posyandu.
 *
 * Satu baris = satu catatan untuk satu anak pada satu tanggal (dibatasi unique
 * partial `medical_notes_child_date_unique`). Lihat migration
 * `2026_09_27_010000_create_medical_notes_table.php` untuk alasan desain
 * kenapa keluhan disimpan sebagai kolom boolean terpisah, bukan satu baris per
 * keluhan.
 *
 * Keluhan dicatat soft delete: entri yang salah input dibatalkan, bukan
 * dihapus, supaya riwayat kesehatan tetap bisa diaudit.
 */
class MedicalNote extends Model
{
    use HasFactory, HasUuids, SoftDeletes;

    protected $fillable = [
        'child_id',
        'measurement_id',
        'kader_id',
        'note_date',
        'demam',
        'rewel',
        'diare',
        'catatan',
        'tindak_lanjut',
    ];

    /**
     * Tanpa cast `boolean`, PostgreSQL mengirim `true`/`false` yang dibaca
     * Flutter sebagai string, dan `checkbox` di UI jadi tidak tercentang
     * padahal isinya benar. Bandingkan `measurements` yang memang mengirim
     * angka sebagai string - untuk kolom boolean itu tidak bisa ditoleransi.
     */
    protected function casts(): array
    {
        return [
            'note_date' => 'date:Y-m-d',
            'demam' => 'boolean',
            'rewel' => 'boolean',
            'diare' => 'boolean',
        ];
    }

    // -----------------------------------------------------------------
    // Tindak lanjut
    // -----------------------------------------------------------------

    /** Keluhan ditangani dengan observasi dan saran saja. */
    public const TINDAK_LANJUT_RINGAN = 'ringan';

    /** Perlu tindakan lebih aktif, misalnya perawatan atau pemberian obat. */
    public const TINDAK_LANJUT_SEDANG = 'sedang';

    /** Perlu dirujuk ke fasilitas yang lebih lengkap. */
    public const TINDAK_LANJUT_RUJUK = 'rujuk';

    /**
     * Daftar tindak lanjut yang diizinkan.
     *
     * Cerminan CHECK constraint `medical_notes_tindak_lanjut_check` di
     * database. Controller memakainya untuk validasi supaya kesalahan ketik
     * ketahuan lebih awal sebagai 422, bukan jadi 500 dari error PostgreSQL.
     */
    public const TINDAK_LANJUTS = [
        self::TINDAK_LANJUT_RINGAN,
        self::TINDAK_LANJUT_SEDANG,
        self::TINDAK_LANJUT_RUJUK,
    ];

    // -----------------------------------------------------------------
    // Relasi
    // -----------------------------------------------------------------

    public function child(): BelongsTo
    {
        return $this->belongsTo(Child::class);
    }

    /** Penimbangan yang dilampirkan. Null bila keluhan dicatat tanpa menimbang. */
    public function measurement(): BelongsTo
    {
        return $this->belongsTo(Measurement::class);
    }

    /** Kader yang mencatat. Null kalau akunnya sudah dihapus. */
    public function kader(): BelongsTo
    {
        return $this->belongsTo(User::class, 'kader_id');
    }

    // -----------------------------------------------------------------
    // Accessor
    // -----------------------------------------------------------------

    /**
     * Daftar keluhan dalam bahasa manusia, mis. `['Demam', 'Diare']`.
     *
     * Disimpan di server supaya Kader dan Ibu menampilkan teks yang sama
     * dari sumber yang sama. Client tidak perlu tahu nama kolomnya.
     */
    public function getKeluhanListAttribute(): array
    {
        $daftar = [];

        if ($this->demam) {
            $daftar[] = 'Demam';
        }

        if ($this->rewel) {
            $daftar[] = 'Rewel';
        }

        if ($this->diare) {
            $daftar[] = 'Diare';
        }

        return $daftar;
    }

    /**
     * Ringkasan satu baris untuk ditampilkan di daftar.
     *
     * Kalau ada catatan tapi tidak ada keluhan yang dicentang, catatan saran
     * itu sendiri yang jadi isi ringkasan - supaya tidak tampil sebagai baris
     * kosong yang membingungkan.
     */
    public function getRingkasanAttribute(): string
    {
        $keluhan = $this->keluhan_list;
        $catatan = is_string($this->catatan) ? trim($this->catatan) : '';

        if ($keluhan === []) {
            return $catatan !== '' ? $catatan : 'Catatan tanpa keluhan khusus';
        }

        return $catatan !== ''
            ? implode(', ', $keluhan).' - '.$catatan
            : implode(', ', $keluhan);
    }

    // -----------------------------------------------------------------
    // Scope
    // -----------------------------------------------------------------

    /**
     * Catatan pada satu bulan, format `YYYY-MM`.
     *
     * Dipakai endpoint daftar karena kebutuhan lapangan: kader dan Ibu
     * hampir selalu ingin melihat "bulan ini" atau "bulan lalu", bukan
     * seluruh riwayat. Default controller memakai bulan berjalan.
     *
     * Batas akhir dihitung dari kalender, bukan `$month.'-31'`. PostgreSQL
     * menolak tanggal yang tidak ada ("date/time field value out of range"),
     * jadi cara itu akan 500 setiap kali yang diminta bulan dengan 30 atau
     * 29 hari - termasuk Februari dan April.
     */
    public function scopeForMonth(Builder $query, string $month): Builder
    {
        $awal = CarbonImmutable::createFromFormat('!Y-m', $month)->startOfMonth();

        return $query->whereBetween('note_date', [
            $awal->toDateString(),
            $awal->endOfMonth()->toDateString(),
        ]);
    }

    /** Catatan dalam rentang tanggal, inklusif di kedua ujung (`Y-m-d`). */
    public function scopeBetweenDates(Builder $query, string $from, string $to): Builder
    {
        return $query->whereBetween('note_date', [$from, $to]);
    }
}
