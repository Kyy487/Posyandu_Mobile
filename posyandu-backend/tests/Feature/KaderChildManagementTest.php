<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class KaderChildManagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_daftar_anak_kader_dipaginasi(): void
    {
        $kader = User::factory()->kader()->create();
        Child::factory()->count(12)->create();

        $response = $this->actingAs($kader)
            ->getJson('/api/kader/children?per_page=5&page=2');

        $response->assertOk()
            ->assertJsonCount(5, 'data')
            ->assertJsonPath('meta.current_page', 2)
            ->assertJsonPath('meta.per_page', 5)
            ->assertJsonPath('meta.total', 12)
            ->assertJsonPath('meta.last_page', 3);
    }

    public function test_kader_menambah_anak_untuk_ibu_dengan_consent(): void
    {
        $kader = User::factory()->kader()->create();
        $ibu = User::factory()->ibu()->create(['status' => 'active']);

        $response = $this->actingAs($kader)->postJson('/api/kader/children', [
            'user_id' => $ibu->id,
            'name' => 'Balita Baru',
            'place_of_birth' => 'Bandung',
            'date_of_birth' => '2024-01-01',
            'gender' => 'L',
            'consent_type' => 'data_processing',
            'consent_document_version' => '1.0',
        ]);

        $response->assertCreated()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.user_id', $ibu->id);

        $this->assertDatabaseHas('children', [
            'id' => $response->json('data.id'),
            'user_id' => $ibu->id,
            'name' => 'Balita Baru',
        ]);
        $this->assertDatabaseHas('consents', [
            'child_id' => $response->json('data.id'),
            'granted_by' => $ibu->id,
            'consent_type' => 'data_processing',
        ]);
    }

    public function test_kader_memperbarui_data_anak(): void
    {
        $kader = User::factory()->kader()->create();
        $ibu = User::factory()->ibu()->create();
        $anak = Child::factory()->milik($ibu)->create([
            'name' => 'Nama Lama',
            'date_of_birth' => '2024-01-01',
        ]);

        $this->actingAs($kader)
            ->patchJson('/api/children/'.$anak->id, [
                'name' => 'Nama Baru',
                'medical_flags' => 'Alergi telur',
            ])
            ->assertOk()
            ->assertJsonPath('data.name', 'Nama Baru');

        $this->assertDatabaseHas('children', [
            'id' => $anak->id,
            'name' => 'Nama Baru',
            'medical_flags' => 'Alergi telur',
        ]);
    }

    public function test_kader_menghapus_anak_secara_soft_delete(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create();

        $this->actingAs($kader)
            ->deleteJson('/api/children/'.$anak->id)
            ->assertOk()
            ->assertJsonPath('data.id', $anak->id);

        $this->assertSoftDeleted($anak);
    }

    public function test_ibu_tidak_bisa_menghapus_anak(): void
    {
        $ibu = User::factory()->ibu()->create();
        $anak = Child::factory()->milik($ibu)->create();

        $this->actingAs($ibu)
            ->deleteJson('/api/children/'.$anak->id)
            ->assertForbidden();
    }
}
