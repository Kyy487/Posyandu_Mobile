<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\Consent;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ConsentManagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_consent_dicatat_saat_registrasi_anak(): void
    {
        $ibu = User::factory()->ibu()->create();

        $response = $this->actingAs($ibu)->postJson('/api/children', [
            'name' => 'Anak Test',
            'date_of_birth' => '2024-01-01',
            'gender' => 'L',
            'consent_type' => 'data_processing',
            'consent_document_version' => '1.0',
        ]);

        $response->assertCreated();

        $childId = $response->json('data.id');

        $this->assertDatabaseHas('consents', [
            'child_id' => $childId,
            'granted_by' => $ibu->id,
            'consent_type' => 'data_processing',
            'document_version' => '1.0',
        ]);
    }

    public function test_registrasi_anak_gagal_tanpa_consent_type(): void
    {
        $ibu = User::factory()->ibu()->create();

        $response = $this->actingAs($ibu)->postJson('/api/children', [
            'name' => 'Anak Test',
            'date_of_birth' => '2024-01-01',
            'gender' => 'L',
            'consent_document_version' => '1.0',
        ]);

        $response->assertStatus(422);
        $this->assertArrayHasKey('consent_type', $response->json('errors'));
    }

    public function test_registrasi_anak_gagal_tanpa_document_version(): void
    {
        $ibu = User::factory()->ibu()->create();

        $response = $this->actingAs($ibu)->postJson('/api/children', [
            'name' => 'Anak Test',
            'date_of_birth' => '2024-01-01',
            'gender' => 'L',
            'consent_type' => 'data_processing',
        ]);

        $response->assertStatus(422);
        $this->assertArrayHasKey('consent_document_version', $response->json('errors'));
    }

    public function test_consent_tidak_bisa_duplikat_untuk_tipe_yang_sama(): void
    {
        $ibu = User::factory()->ibu()->create();
        $child = Child::factory()->create(['user_id' => $ibu->id]);

        Consent::factory()->create([
            'child_id' => $child->id,
            'granted_by' => $ibu->id,
            'consent_type' => 'data_processing',
        ]);

        $response = $this->actingAs($ibu)->postJson('/api/children/'.$child->id.'/consents', [
            'consent_type' => 'data_processing',
            'document_version' => '1.0',
        ]);

        $response->assertStatus(409);
    }

    public function test_consent_bisa_dicabut(): void
    {
        $ibu = User::factory()->ibu()->create();
        $child = Child::factory()->create(['user_id' => $ibu->id]);

        $consent = Consent::factory()->create([
            'child_id' => $child->id,
            'granted_by' => $ibu->id,
            'consent_type' => 'data_processing',
        ]);

        $response = $this->actingAs($ibu)->deleteJson('/api/children/'.$child->id.'/consents', [
            'consent_type' => 'data_processing',
        ]);

        $response->assertOk();

        $this->assertNotNull($consent->fresh()->revoked_at);
    }

    public function test_consent_yang_sudah_dicabut_tidak_muncul_di_daftar_aktif(): void
    {
        $ibu = User::factory()->ibu()->create();
        $child = Child::factory()->create(['user_id' => $ibu->id]);

        Consent::factory()->create([
            'child_id' => $child->id,
            'granted_by' => $ibu->id,
            'consent_type' => 'data_processing',
            'revoked_at' => now(),
        ]);

        $response = $this->actingAs($ibu)->getJson('/api/children/'.$child->id.'/consents');

        $response->assertOk();
        $this->assertCount(0, $response->json('data'));
    }

    public function test_kader_bisa_membaca_consent_anak(): void
    {
        $ibu = User::factory()->ibu()->create();
        $kader = User::factory()->kader()->create();
        $child = Child::factory()->create(['user_id' => $ibu->id]);

        Consent::factory()->create([
            'child_id' => $child->id,
            'granted_by' => $ibu->id,
            'consent_type' => 'data_processing',
        ]);

        $response = $this->actingAs($kader)->getJson('/api/children/'.$child->id.'/consents');

        $response->assertOk();
        $this->assertCount(1, $response->json('data'));
    }

    public function test_consent_tidak_bisa_dicabut_oleh_kader(): void
    {
        $ibu = User::factory()->ibu()->create();
        $kader = User::factory()->kader()->create();
        $child = Child::factory()->create(['user_id' => $ibu->id]);

        Consent::factory()->create([
            'child_id' => $child->id,
            'granted_by' => $ibu->id,
            'consent_type' => 'data_processing',
        ]);

        $response = $this->actingAs($kader)->deleteJson('/api/children/'.$child->id.'/consents', [
            'consent_type' => 'data_processing',
        ]);

        $response->assertStatus(403);
    }
}
