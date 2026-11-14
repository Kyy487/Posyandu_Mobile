<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ChildOnboardingTest extends TestCase
{
    use RefreshDatabase;

    public function test_ibu_terverifikasi_tanpa_data_anak_ditolak_dari_dashboard(): void
    {
        $ibu = User::factory()->perluDataAnak()->create();

        $response = $this->actingAs($ibu)->getJson('/api/children');

        $response->assertForbidden()
            ->assertJsonPath('success', false)
            ->assertJsonPath('errors.next_action.0', 'add_child');
    }

    public function test_ibu_pending_tidak_boleh_melengkapi_data_anak(): void
    {
        $ibu = User::factory()->menungguVerifikasi()->create();

        $response = $this->actingAs($ibu)->postJson('/api/registration/child', $this->payloadAnak());

        $response->assertForbidden()
            ->assertJsonPath('success', false)
            ->assertJsonPath('errors.next_action.0', 'complete_registration');
    }

    public function test_onboarding_anak_menyimpan_data_lahir_dan_menyelesaikan_status(): void
    {
        $ibu = User::factory()->perluDataAnak()->create();

        $response = $this->actingAs($ibu)->postJson('/api/registration/child', $this->payloadAnak());

        $response->assertCreated()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.user.onboarding_status', 'completed');

        $anak = Child::query()->where('user_id', $ibu->id)->firstOrFail();

        $this->assertEquals(48.5, (float) $anak->birth_length);
        $this->assertEquals((float) $anak->birth_length, (float) $anak->birth_height);
        $this->assertSame('completed', $ibu->fresh()->onboarding_status);
    }

    public function test_setelah_onboarding_ibu_dapat_mengakses_dashboard(): void
    {
        $ibu = User::factory()->perluDataAnak()->create();

        $this->actingAs($ibu)
            ->postJson('/api/registration/child', $this->payloadAnak())
            ->assertCreated();

        $this->actingAs($ibu)
            ->getJson('/api/children')
            ->assertOk()
            ->assertJsonPath('success', true);
    }

    public function test_nik_anak_ganda_ditolak_saat_onboarding(): void
    {
        $ibu = User::factory()->perluDataAnak()->create();
        $payload = $this->payloadAnak();
        Child::factory()->create([
            'nik' => $payload['nik'],
            'date_of_birth' => '2024-01-01',
        ]);

        $response = $this->actingAs($ibu)->postJson('/api/registration/child', $payload);

        $response->assertUnprocessable()
            ->assertJsonPath('success', false)
            ->assertJsonValidationErrors('nik');
    }

    /**
     * @return array<string, mixed>
     */
    private function payloadAnak(): array
    {
        return [
            'nik' => '3273012345678910',
            'name' => 'Balita Uji',
            'place_of_birth' => 'Bandung',
            'date_of_birth' => '2024-01-01',
            'gender' => 'L',
            'birth_order' => 1,
            'birth_weight' => 3.2,
            'birth_length' => 48.5,
            'birth_head_circumference' => 34,
            'birth_status' => 'normal',
        ];
    }
}
