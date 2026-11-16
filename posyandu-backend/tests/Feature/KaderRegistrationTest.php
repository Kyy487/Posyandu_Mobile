<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class KaderRegistrationTest extends TestCase
{
    use RefreshDatabase;

    public function test_kader_dapat_mengoreksi_data_permohonan_pending(): void
    {
        $kader = User::factory()->kader()->create();
        $ibu = User::factory()->ibu()->create([
            'status' => 'pending',
            'name' => 'Budi Ibu',
            'address' => 'Jl. Alamat Lama',
        ]);

        $response = $this->actingAs($kader)->patchJson('/api/kader/registrations/'.$ibu->id, [
            'address' => 'Jl. Alamat Baru',
            'phone_number' => '08987654321',
        ]);

        $response->assertOk();
        $response->assertJsonPath('success', true);
        $response->assertJsonPath('data.address', 'Jl. Alamat Baru');

        $this->assertDatabaseHas('users', [
            'id' => $ibu->id,
            'address' => 'Jl. Alamat Baru',
        ]);
    }

    public function test_kader_tidak_dapat_mengoreksi_permohonan_non_pending(): void
    {
        $kader = User::factory()->kader()->create();
        $ibu = User::factory()->ibu()->create(['status' => 'active']);

        $response = $this->actingAs($kader)->patchJson('/api/kader/registrations/'.$ibu->id, [
            'address' => 'Jl. Alamat Baru',
        ]);

        $response->assertStatus(422);
    }

    public function test_approve_langsung_mengembalikan_verification_status_approved(): void
    {
        $kader = User::factory()->kader()->create();
        $ibu = User::factory()->ibu()->create(['status' => 'pending']);

        $response = $this->actingAs($kader)
            ->postJson('/api/kader/registrations/'.$ibu->id.'/approve');

        $response->assertOk()
            ->assertJsonPath('data.status', 'active')
            ->assertJsonPath('data.verification_status', 'approved');
    }

    public function test_approve_mencatat_audit_dan_tidak_bisa_diulang(): void
    {
        $kader = User::factory()->kader()->create();
        $ibu = User::factory()->menungguVerifikasi()->create();

        $this->actingAs($kader)
            ->postJson('/api/kader/registrations/'.$ibu->id.'/approve')
            ->assertOk();

        $log = AuditLog::query()
            ->where('auditable_type', User::class)
            ->where('auditable_id', $ibu->id)
            ->where('event', 'updated')
            ->first();

        $this->assertNotNull($log);
        $this->assertSame($kader->id, $log->actor_id);
        $this->assertSame('pending', $log->old_values['status']);
        $this->assertSame('active', $log->new_values['status']);
        $this->assertSame($kader->id, $log->new_values['approved_by']);

        $this->actingAs($kader)
            ->postJson('/api/kader/registrations/'.$ibu->id.'/approve')
            ->assertStatus(422);

        $this->assertSame(1, AuditLog::query()
            ->where('auditable_type', User::class)
            ->where('auditable_id', $ibu->id)
            ->count());
    }

    public function test_reject_mencatat_alasan_dan_audit(): void
    {
        $kader = User::factory()->kader()->create();
        $ibu = User::factory()->menungguVerifikasi()->create();

        $this->actingAs($kader)
            ->postJson('/api/kader/registrations/'.$ibu->id.'/reject', [
                'rejection_reason' => 'Data tidak lengkap',
            ])
            ->assertOk()
            ->assertJsonPath('data.status', 'rejected');

        $log = AuditLog::query()
            ->where('auditable_type', User::class)
            ->where('auditable_id', $ibu->id)
            ->where('event', 'updated')
            ->first();

        $this->assertNotNull($log);
        $this->assertSame('pending', $log->old_values['status']);
        $this->assertSame('rejected', $log->new_values['status']);
        $this->assertSame('Data tidak lengkap', $log->new_values['rejection_reason']);
    }

    public function test_koreksi_mencatat_nilai_lama_dan_baru(): void
    {
        $kader = User::factory()->kader()->create();
        $ibu = User::factory()->menungguVerifikasi()->create([
            'address' => 'Jl. Lama',
        ]);

        $this->actingAs($kader)
            ->patchJson('/api/kader/registrations/'.$ibu->id, [
                'address' => 'Jl. Baru',
            ])
            ->assertOk();

        $log = AuditLog::query()
            ->where('auditable_type', User::class)
            ->where('auditable_id', $ibu->id)
            ->where('event', 'updated')
            ->first();

        $this->assertNotNull($log);
        $this->assertSame($kader->id, $log->actor_id);
        $this->assertSame('Jl. Lama', $log->old_values['address']);
        $this->assertSame('Jl. Baru', $log->new_values['address']);
    }

    public function test_daftar_permohonan_dipaginasi_dan_tidak_membocorkan_nik(): void
    {
        $kader = User::factory()->kader()->create();
        User::factory()->menungguVerifikasi()->count(12)->create();

        $response = $this->actingAs($kader)
            ->getJson('/api/kader/registrations?per_page=5&page=2');

        $response->assertOk()
            ->assertJsonCount(5, 'data')
            ->assertJsonPath('meta.current_page', 2)
            ->assertJsonPath('meta.per_page', 5)
            ->assertJsonPath('meta.total', 12)
            ->assertJsonPath('meta.last_page', 3);

        $this->assertArrayNotHasKey('nik', $response->json('data.0'));
        $this->assertArrayNotHasKey('nik_hash', $response->json('data.0'));
    }
}
