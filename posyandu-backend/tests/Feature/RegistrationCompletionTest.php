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

    public function test_pending_user_dapat_melengkapi_data_dengan_token(): void
    {
        $nik = '3273012345678903';
        $user = User::factory()->ibu()->create([
            'nik' => $nik,
            'status' => 'pending',
            'name' => 'Ibu Lama',
            'address' => 'Jl. Alamat Lama',
        ]);

        $response = $this->actingAs($user, 'sanctum')
            ->postJson('/api/registration/complete', [
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

    public function test_registrasi_wajib_token_dan_nik_tidak_bisa_dipakai_sebagai_kredensial(): void
    {
        $nik = '3273012345678904';
        $user = User::factory()->ibu()->create([
            'nik' => $nik,
            'status' => 'pending',
            'name' => 'Nama Lama',
            'address' => 'Jl. Alamat Lama',
        ]);

        $this->getJson('/api/registration/status?nik='.$nik)
            ->assertUnauthorized();

        $this->postJson('/api/registration/complete', [
            'nik' => $nik,
            'name' => 'Nama Baru',
            'address' => 'Jl. Alamat Baru',
        ])->assertUnauthorized();

        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'name' => 'Nama Lama',
            'address' => 'Jl. Alamat Lama',
        ]);
    }

    public function test_nik_tidak_dapat_diubah_setelah_registrasi(): void
    {
        $nik = '3273012345678905';
        $user = User::factory()->ibu()->create([
            'nik' => $nik,
            'status' => 'pending',
        ]);

        $this->actingAs($user, 'sanctum')
            ->postJson('/api/registration/complete', [
                'nik' => '3273012345678999',
                'address' => 'Jl. Alamat Baru',
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('nik');

        $this->assertSame($nik, $user->fresh()->nik);
    }

    public function test_status_tidak_mengembalikan_nik_dan_nomor_kk(): void
    {
        $user = User::factory()->menungguVerifikasi()->create([
            'no_kk' => '3273012345678906',
        ]);

        $response = $this->actingAs($user, 'sanctum')
            ->getJson('/api/registration/status')
            ->assertOk();

        $this->assertArrayNotHasKey('nik', $response->json('data'));
        $this->assertArrayNotHasKey('nik_hash', $response->json('data'));
        $this->assertArrayNotHasKey('no_kk', $response->json('data'));
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
