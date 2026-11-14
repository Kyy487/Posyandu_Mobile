<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class RegistrationCompletionTest extends TestCase
{
    use RefreshDatabase;

    public function test_pending_user_dapat_melengkapi_data_dengan_nik(): void
    {
        $nik = '3273012345678903';
        $user = User::factory()->ibu()->create([
            'nik' => $nik,
            'status' => 'pending',
            'name' => 'Ibu Lama',
            'address' => 'Jl. Alamat Lama',
        ]);

        $response = $this->postJson('/api/registration/complete', [
            'nik' => $nik,
            'name' => 'Ibu Baru',
            'address' => 'Jl. Alamat Baru',
        ]);

        $response->assertOk();
        $response->assertJsonPath('success', true);
        $response->assertJsonPath('data.status', 'pending');

        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'name' => 'Ibu Baru',
            'address' => 'Jl. Alamat Baru',
        ]);
    }

    public function test_status_dan_user_tetap_dapat_diakses_selama_drop_off(): void
    {
        foreach ([
            ['pending', 'menungguVerifikasi'],
            ['rejected', 'ditolak'],
            ['active', 'perluDataAnak'],
        ] as [$status, $state]) {
            $user = User::factory()->{$state}()->create();

            $this->actingAs($user, 'sanctum')
                ->getJson('/api/user')
                ->assertOk()
                ->assertJsonPath('data.status', $status)
                ->assertJsonPath('data.onboarding_status', 'need_child_data');

            $this->actingAs($user, 'sanctum')
                ->getJson('/api/registration/status')
                ->assertOk()
                ->assertJsonPath('data.status', $status)
                ->assertJsonPath('data.onboarding_status', 'need_child_data');
        }
    }

    public function test_ibu_ditolak_dapat_mengunggah_ulang_ktp_dan_kk(): void
    {
        Storage::fake('public');

        foreach (['ktp', 'kk'] as $type) {
            $user = User::factory()->ditolak()->create();

            $this->actingAs($user, 'sanctum')
                ->post('/api/registration/complete', [
                    'address' => 'Jl. Alamat Baru',
                    'verification_type' => $type,
                    'verification_file' => UploadedFile::fake()->image($type.'.jpg'),
                ])
                ->assertOk()
                ->assertJsonPath('data.status', 'pending')
                ->assertJsonPath('data.rejection_reason', null);

            $this->assertDatabaseHas('user_verifications', [
                'user_id' => $user->id,
                'type' => $type,
            ]);
        }
    }
}
