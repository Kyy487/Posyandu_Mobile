<?php

namespace App\Models\Concerns;

use App\Models\AuditLog;
use Illuminate\Database\Eloquent\Model;

/**
 * Mencatat perubahan model ke tabel `audit_logs`.
 *
 * Dipasang dengan `use Auditable;` pada model. Setiap event database menulis
 * SATU baris `audit_logs`:
 *
 *   - `created`  -> `new_values` berisi isi baris (tanpa timestamp)
 *   - `updated`  -> `old_values`/`new_values` hanya kolom yang benar-benar berubah
 *   - `deleted`  -> `old_values` berisi isi baris; menangkap soft delete maupun
 *                   force delete, karena `SoftDeletes` menyalakan event `deleted`
 *   - `restored` -> `new_values` berisi isi baris setelah dipulihkan
 *
 * Dua kolom sengaja tidak pernah masuk diff: `updated_at` (selalu berubah) dan
 * `deleted_at` (penanda soft delete, bukan nilai klinis). Karena itu soft delete
 * benar-benar jadi SATU baris: event `updated` yang terpicu lebih dulu (soft
 * delete menyimpan `deleted_at`) menghasilkan diff kosong setelah `deleted_at`
 * disaring, sehingga tidak menulis apa pun; yang menulis adalah `deleted`.
 * Begitu juga saat restore.
 *
 * Nilai seperti Z-score yang dihitung trigger PostgreSQL memang tidak tercatat:
 * `getChanges()` hanya berisi atribut yang diubah lewat PHP, bukan efek samping
 * database. Riwayat ini merekam apa yang dikatakan aplikasi, bukan apa yang
 * terjadi di dalam database.
 */
trait Auditable
{
    public static function bootAuditable(): void
    {
        static::created(fn (Model $model) => $model->recordAudit('created'));
        static::updated(fn (Model $model) => $model->recordAudit('updated'));
        static::deleted(fn (Model $model) => $model->recordAudit('deleted'));
        static::restored(fn (Model $model) => $model->recordAudit('restored'));
    }

    public function recordAudit(string $event): void
    {
        $oldValues = null;
        $newValues = null;

        if ($event === 'created') {
            $newValues = $this->auditSnapshot($this->getAttributes());
        } elseif ($event === 'updated') {
            foreach ($this->getChanges() as $column => $value) {
                if ($this->isIgnoredDiffColumn($column)) {
                    continue;
                }

                $oldValues[$column] = $this->getOriginal($column);
                $newValues[$column] = $value;
            }

            // Hanya timestamp (dan `deleted_at` soft delete) yang berubah:
            // soft delete akan tercatat oleh event `deleted`, tidak perlu
            // baris `updated` tambahan.
            if ($oldValues === null) {
                return;
            }
        } elseif ($event === 'deleted') {
            $oldValues = $this->auditSnapshot($this->getAttributes());
        } else {
            // restored.
            $newValues = $this->auditSnapshot($this->getAttributes());
        }

        AuditLog::create([
            'auditable_type' => $this->getMorphClass(),
            'auditable_id' => $this->getKey(),
            'event' => $event,
            'actor_id' => request()->user()?->id,
            'old_values' => $oldValues,
            'new_values' => $newValues,
            'ip_address' => app()->runningInConsole() ? null : request()->ip(),
        ]);
    }

    /**
     * Salinan atribut tanpa kolom yang nilainya bukan data (timestamp).
     *
     * @return array<string, mixed>
     */
    private function auditSnapshot(array $attributes): array
    {
        return array_filter(
            $attributes,
            fn (string $column): bool => ! in_array($column, $this->auditNeverStoredColumns(), true),
            ARRAY_FILTER_USE_KEY
        );
    }

    /**
     * Kolom yang diabaikan pada diff `updated`: timestamp + `deleted_at`.
     */
    private function isIgnoredDiffColumn(string $column): bool
    {
        if (in_array($column, $this->auditNeverStoredColumns(), true)) {
            return true;
        }

        return method_exists($this, 'getDeletedAtColumn') && $column === $this->getDeletedAtColumn();
    }

    /**
     * @return list<string>
     */
    private function auditNeverStoredColumns(): array
    {
        return ['created_at', 'updated_at'];
    }
}
