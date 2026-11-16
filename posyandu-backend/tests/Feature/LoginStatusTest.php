<?php

namespace Tests\Feature;

use App\Models\User;
use Database\Factories\UserFactory;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class LoginStatusTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function login_akun_pending_tetap_mendapat_token_dan_status_pending(): void
    {
        $ibu = User::factory()->menungguVerifikasi()->create();

        $response = $this->postJson('/api/login', [
            'nik' => $ibu->nik,
            'password' => UserFactory::PASSWORD,
        ]);

        $response->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('message', 'Akun Anda sedang menunggu verifikasi oleh Kader Posyandu.')
            ->assertJsonPath('data.status', 'pending')
            ->assertJsonPath('data.next_action', 'complete_registration')
            ->assertJsonPath('data.user.id', $ibu->id);

        $this->assertNotEmpty($response->json('data.token'));
    }

    #[Test]
    public function login_akun_ditolak_menampilkan_alasan_penolakan(): void
    {
        $ibu = User::factory()->ditolak()->create([
            'rejection_reason' => 'Foto KTP tidak terbaca.',
        ]);

        $response = $this->postJson('/api/login', [
            'nik' => $ibu->nik,
            'password' => UserFactory::PASSWORD,
        ]);

        $response->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('message', 'Pendaftaran Anda ditolak. Alasan: Foto KTP tidak terbaca.')
            ->assertJsonPath('data.status', 'rejected')
            ->assertJsonPath('data.next_action', 'fix_registration')
            ->assertJsonPath('data.user.id', $ibu->id);

        $this->assertNotEmpty($response->json('data.token'));
    }
}
