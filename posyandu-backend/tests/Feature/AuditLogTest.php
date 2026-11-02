<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Child;
use App\Models\ImmunizationRecord;
use App\Models\ImmunizationType;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Menguji pencatatan riwayat audit dan endpoint `GET /api/kader/audit-logs`.
 *
 * Yang diuji:
 *  - Setiap perubahan model audited menulis satu baris `audit_logs`
 *  - Soft delete tercatat sebagai `deleted`, bukan `updated`
 *  - Restore tercatat sebagai `restored`
 *  - Perubahan hanya timestamp tidak menulis baris
 *  - Endpoint hanya untuk Kader
 */
class AuditLogTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function pencatatan_suntikan_mencatat_riwayat_audit(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01']);
        $dosis = ImmunizationType::factory()->dosisPertama('Hepatitis B', 'HB')->create();

        $respons = $this->withToken($this->token($kader))
            ->postJson("/api/kader/children/{$anak->id}/immunizations", [
                'immunization_type_id' => $dosis->id,
                'date_given' => '2025-10-01',
            ])
            ->assertCreated();

        $recordId = $respons->json('data.id');

        $log = AuditLog::query()
            ->where('auditable_type', ImmunizationRecord::class)
            ->where('auditable_id', $recordId)
            ->first();

        $this->assertNotNull($log, 'pencatatan suntikan harus menulis riwayat audit');
        $this->assertSame('created', $log->event);
        $this->assertSame($kader->id, $log->actor_id);
        $this->assertNull($log->old_values);
        $this->assertNotNull($log->new_values);
        $this->assertSame($anak->id, $log->new_values['child_id']);
        $this->assertSame($dosis->id, $log->new_values['immunization_type_id']);
    }

    #[Test]
    public function perubahan_anak_mencatat_nilai_lama_dan_baru(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create([
            'date_of_birth' => '2024-01-01',
            'name' => 'Nama Lama',
        ]);

        $this->withToken($this->token($kader));

        $anak->update(['name' => 'Nama Baru']);

        $log = AuditLog::query()
            ->where('auditable_type', Child::class)
            ->where('auditable_id', $anak->id)
            ->where('event', 'updated')
            ->first();

        $this->assertNotNull($log, 'perubahan nama harus menulis riwayat audit');
        $this->assertSame('Nama Lama', $log->old_values['name']);
        $this->assertSame('Nama Baru', $log->new_values['name']);
        $this->assertArrayNotHasKey('updated_at', $log->new_values);
    }

    #[Test]
    public function soft_delete_mencatat_event_deleted_bukan_updated(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01']);

        $this->withToken($this->token($kader));

        $anak->delete();

        $semuaLog = AuditLog::query()
            ->where('auditable_type', Child::class)
            ->where('auditable_id', $anak->id)
            ->get();

        $logDeleted = $semuaLog->where('event', 'deleted');
        $logUpdated = $semuaLog->where('event', 'updated');

        $this->assertCount(1, $logDeleted, 'soft delete harus menulis tepat satu baris deleted');
        $this->assertCount(0, $logUpdated, 'soft delete tidak boleh menulis baris updated tambahan');
        $this->assertNotNull($logDeleted->first()->old_values);
    }

    #[Test]
    public function restore_mencatat_event_restored(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01']);

        $this->withToken($this->token($kader));

        $anak->delete();
        $anak->restore();

        $log = AuditLog::query()
            ->where('auditable_type', Child::class)
            ->where('auditable_id', $anak->id)
            ->where('event', 'restored')
            ->first();

        $this->assertNotNull($log, 'restore harus menulis riwayat audit');
        $this->assertNotNull($log->new_values);
    }

    #[Test]
    public function perubahan_hanya_timestamp_tidak_mencatat_riwayat(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01']);

        $this->withToken($this->token($kader));

        $anak->update(['name' => $anak->name]);

        $log = AuditLog::query()
            ->where('auditable_type', Child::class)
            ->where('auditable_id', $anak->id)
            ->where('event', 'updated')
            ->first();

        $this->assertNull($log, 'perubahan hanya timestamp tidak boleh menulis riwayat');
    }

    #[Test]
    public function endpoint_audit_hanya_untuk_kader(): void
    {
        $ibu = User::factory()->ibu()->create();
        $kader = User::factory()->kader()->create();

        $this->actingAs($ibu, 'sanctum')
            ->getJson('/api/kader/audit-logs')
            ->assertForbidden();

        $this->actingAs($kader, 'sanctum')
            ->getJson('/api/kader/audit-logs')
            ->assertOk()
            ->assertJsonPath('success', true);
    }

    #[Test]
    public function endpoint_audit_mendukung_filter_event(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01']);

        $this->withToken($this->token($kader));

        $anak->update(['name' => 'Nama Baru']);

        $respons = $this->withToken($this->token($kader))
            ->getJson('/api/kader/audit-logs?event=created')
            ->assertOk();

        $data = $respons->json('data');
        $this->assertNotEmpty($data);
        $this->assertTrue(
            collect($data)->every(fn ($log) => $log['event'] === 'created'),
            'semua baris harus ber-event created'
        );
    }

    private function token(User $user): string
    {
        return $user->createToken('uji')->plainTextToken;
    }
}
