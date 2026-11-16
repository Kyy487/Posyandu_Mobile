<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Child;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class AuditLogPruneTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function dry_run_tidak_menghapus_audit_log_lama(): void
    {
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01']);
        $log = $this->auditLog($anak, now()->subDays(1826));

        $this->artisan('audit:prune', ['--days' => 1825, '--dry-run' => true])
            ->expectsOutputToContain('Tidak ada yang dihapus.')
            ->assertSuccessful();

        $this->assertDatabaseHas('audit_logs', ['id' => $log->id]);
    }

    #[Test]
    public function force_menghapus_hanya_audit_log_yang_melewati_retensi(): void
    {
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01']);
        $lama = $this->auditLog($anak, now()->subDays(1826));
        $baru = $this->auditLog($anak, now()->subDays(10));

        $this->artisan('audit:prune', ['--days' => 1825, '--force' => true])
            ->expectsOutputToContain('1 audit log dihapus.')
            ->assertSuccessful();

        $this->assertDatabaseMissing('audit_logs', ['id' => $lama->id]);
        $this->assertDatabaseHas('audit_logs', ['id' => $baru->id]);
    }

    #[Test]
    public function retensi_default_diambil_dari_config(): void
    {
        config(['posyandu.audit.retention_days' => 30]);

        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01']);
        $lama = $this->auditLog($anak, now()->subDays(31));
        $baru = $this->auditLog($anak, now()->subDays(10));

        $this->artisan('audit:prune', ['--force' => true])
            ->assertSuccessful();

        $this->assertDatabaseMissing('audit_logs', ['id' => $lama->id]);
        $this->assertDatabaseHas('audit_logs', ['id' => $baru->id]);
    }

    #[Test]
    public function retensi_kurang_dari_satu_hari_ditolak(): void
    {
        $this->artisan('audit:prune', ['--days' => 0])
            ->expectsOutputToContain('minimal 1 hari')
            ->assertFailed();
    }

    private function auditLog(Child $anak, \DateTimeInterface $createdAt): AuditLog
    {
        $log = AuditLog::create([
            'auditable_type' => Child::class,
            'auditable_id' => $anak->id,
            'event' => 'updated',
        ]);

        $log->forceFill([
            'created_at' => $createdAt,
            'updated_at' => $createdAt,
        ])->saveQuietly();

        return $log;
    }
}
