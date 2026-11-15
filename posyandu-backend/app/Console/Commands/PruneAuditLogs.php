<?php

namespace App\Console\Commands;

use App\Models\AuditLog;
use Illuminate\Console\Command;

class PruneAuditLogs extends Command
{
    protected $signature = 'audit:prune
                            {--days= : Jumlah hari retensi; default dari config}
                            {--dry-run : Hanya tampilkan jumlah yang akan dihapus}
                            {--force : Hapus tanpa konfirmasi}';

    protected $description = 'Hapus audit log yang lebih lama dari periode retensi';

    public function handle(): int
    {
        $daysOption = $this->option('days');

        if ($daysOption !== null && ! is_numeric($daysOption)) {
            $this->error('Opsi --days harus berupa angka.');

            return self::FAILURE;
        }

        $days = $daysOption !== null
            ? (int) $daysOption
            : (int) config('posyandu.audit.retention_days', 1825);

        if ($days < 1) {
            $this->error('Periode retensi harus minimal 1 hari.');

            return self::FAILURE;
        }

        $cutoff = now()->subDays($days);
        $query = AuditLog::query()->where('created_at', '<', $cutoff);
        $count = $query->count();

        if ($count === 0) {
            $this->info("Tidak ada audit log sebelum {$cutoff->toIso8601String()}.");

            return self::SUCCESS;
        }

        if ($this->option('dry-run')) {
            $this->info(
                "{$count} audit log lebih lama dari {$days} hari "
                ."(sebelum {$cutoff->toIso8601String()}). Tidak ada yang dihapus."
            );

            return self::SUCCESS;
        }

        if (! $this->option('force') && ! $this->confirm(
            "Hapus {$count} audit log sebelum {$cutoff->toIso8601String()}?"
        )) {
            $this->warn('Dibatalkan.');

            return self::SUCCESS;
        }

        $deleted = $query->delete();

        $this->info("{$deleted} audit log dihapus.");

        return self::SUCCESS;
    }
}
