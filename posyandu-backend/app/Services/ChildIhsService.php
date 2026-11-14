<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\Child;
use App\Support\IhsNumber;
use Illuminate\Database\QueryException;
use Illuminate\Validation\ValidationException;
use InvalidArgumentException;

/**
 * Satu pintu perubahan IHS number anak.
 *
 * Semua perubahan lewat sini supaya validasi, pengecekan duplikat, dan audit
 * konsisten antara edit manual admin dan import CSV. Audit ditulis manual
 * (bukan lewat trait Auditable) agar alasan koreksi ikut tersimpan.
 */
class ChildIhsService
{
    /**
     * @throws ValidationException
     */
    public function update(
        Child $child,
        ?string $ihsNumber,
        ?string $reason = null,
        bool $dryRun = false,
    ): Child {
        try {
            $normalized = IhsNumber::normalize($ihsNumber);
        } catch (InvalidArgumentException $exception) {
            throw ValidationException::withMessages([
                'ihs_number' => [$exception->getMessage()],
            ]);
        }

        if ($normalized === null) {
            throw ValidationException::withMessages([
                'ihs_number' => ['IHS number wajib diisi.'],
            ]);
        }

        if ($child->ihs_number === $normalized) {
            return $child;
        }

        $reason = $reason === null ? null : trim($reason);

        if ($child->ihs_number !== null && ($reason === null || $reason === '')) {
            throw ValidationException::withMessages([
                'reason' => ['Alasan koreksi wajib diisi saat mengganti IHS yang sudah ada.'],
            ]);
        }

        $duplicate = Child::query()
            ->where('ihs_number', $normalized)
            ->where('id', '!=', $child->id)
            ->exists();

        if ($duplicate) {
            throw ValidationException::withMessages([
                'ihs_number' => ['IHS number sudah dipakai anak lain.'],
            ]);
        }

        if ($dryRun) {
            return $child;
        }

        $oldIhsNumber = $child->ihs_number;
        $child->ihs_number = $normalized;

        try {
            $child->saveQuietly();
        } catch (QueryException $exception) {
            if ($exception->getCode() === '23505') {
                throw ValidationException::withMessages([
                    'ihs_number' => ['IHS number sudah dipakai anak lain.'],
                ]);
            }

            throw $exception;
        }

        AuditLog::query()->create([
            'auditable_type' => $child->getMorphClass(),
            'auditable_id' => $child->getKey(),
            'event' => 'updated',
            'actor_id' => request()->user()?->id,
            'old_values' => ['ihs_number' => $oldIhsNumber],
            'new_values' => array_filter([
                'ihs_number' => $normalized,
                'reason' => $reason,
            ], fn (mixed $value): bool => $value !== null),
            'ip_address' => app()->runningInConsole() ? null : request()->ip(),
        ]);

        return $child->refresh();
    }
}
