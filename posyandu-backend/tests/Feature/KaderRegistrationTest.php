<?php

namespace Tests\Feature;

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
}
