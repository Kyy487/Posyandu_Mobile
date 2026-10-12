<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Satu baris riwayat audit.
 *
 * Baris ditulis oleh trait `Concerns\Auditable` setiap kali model audited
 * dibuat, diubah, dihapus (termasuk soft delete), atau dipulihkan. Baris ini
 * tidak diubah setelah dibuat - kalau kesalahan perlu dipilih ulang, bukan
 * ditimpa.
 */
class AuditLog extends Model
{
    use HasUuids;

    protected $fillable = [
        'auditable_type',
        'auditable_id',
        'event',
        'actor_id',
        'old_values',
        'new_values',
        'ip_address',
    ];

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'old_values' => 'array',
            'new_values' => 'array',
        ];
    }

    /** Pelaku perubahan; null bila perubahan dilakukan sistem. */
    public function actor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'actor_id');
    }
}
