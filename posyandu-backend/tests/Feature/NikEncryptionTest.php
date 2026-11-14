<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\User;
use App\Support\NikHasher;
use Database\Factories\UserFactory;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class NikEncryptionTest extends TestCase
{
    use RefreshDatabase;

    public function test_nik_tersimpan_encrypted_di_database(): void
    {
        $user = User::factory()->create();

        $rawNik = \DB::table('users')->where('id', $user->id)->value('nik');

        $this->assertNotEquals($user->nik, $rawNik);
        $this->assertStringStartsWith('eyJ', $rawNik);
    }

    public function test_nik_hash_konsisten_untuk_nik_yang_sama(): void
    {
        $nik = '3273012345678901';

        $user = User::factory()->create(['nik' => $nik]);

        $this->assertEquals(NikHasher::hash($nik), $user->nik_hash);
        $this->assertNotEquals(hash('sha256', $nik), $user->nik_hash);
        $this->assertSame(
            $user->id,
            User::query()->where('nik_hash', NikHasher::hash($nik))->value('id'),
        );
    }

    public function test_nik_ganda_ditolak_oleh_unique_nik_hash(): void
    {
        $nik = '3273012345678901';
        User::factory()->create(['nik' => $nik]);

        $this->expectException(QueryException::class);

        User::factory()->create(['nik' => $nik]);
    }

    public function test_login_by_nik_tetap_jalan(): void
    {
        $user = User::factory()->create([
            'nik' => '3273012345678901',
            'password' => Hash::make(UserFactory::PASSWORD),
        ]);

        $response = $this->postJson('/api/login', [
            'nik' => '3273012345678901',
            'password' => UserFactory::PASSWORD,
        ]);

        $response->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.user.id', $user->id);
    }

    public function test_nik_tidak_muncul_di_response_login(): void
    {
        User::factory()->create([
            'nik' => '3273012345678901',
            'password' => Hash::make(UserFactory::PASSWORD),
        ]);

        $response = $this->postJson('/api/login', [
            'nik' => '3273012345678901',
            'password' => UserFactory::PASSWORD,
        ]);

        $response->assertOk();
        $this->assertArrayNotHasKey('nik', $response->json('data.user'));
        $this->assertArrayNotHasKey('nik_hash', $response->json('data.user'));
    }

    public function test_nik_tidak_muncul_di_response_register(): void
    {
        $response = $this->postJson('/api/register', [
            'nik' => '3273012345678902',
            'name' => 'Test Ibu',
            'password' => 'password123',
            'password_confirmation' => 'password123',
        ]);

        $response->assertCreated();
        $response->assertJsonPath('success', true);
        $response->assertJsonPath('data.status', 'pending');
        $response->assertJsonPath(
            'message',
            'Pendaftaran berhasil. Akun Anda menunggu persetujuan dari Kader Posyandu.'
        );

        $responseData = $response->json();
        $this->assertArrayNotHasKey('nik', $responseData['data']['user']);
        $this->assertArrayNotHasKey('nik_hash', $responseData['data']['user']);
        $this->assertArrayHasKey('token', $responseData['data']);
        $this->assertNotEmpty($responseData['data']['token']);
        $this->assertSame('need_child_data', $responseData['data']['user']['onboarding_status']);
    }

    public function test_nik_anak_tersimpan_encrypted(): void
    {
        $user = User::factory()->create();
        $child = Child::factory()->create(['user_id' => $user->id]);

        $rawNik = \DB::table('children')->where('id', $child->id)->value('nik');

        $this->assertNotEquals($child->nik, $rawNik);
        $this->assertStringStartsWith('eyJ', $rawNik);
    }

    public function test_nik_anak_tidak_muncul_di_response(): void
    {
        $user = User::factory()->create();
        $child = Child::factory()->create(['user_id' => $user->id]);

        $response = $this->actingAs($user)->getJson('/api/children/'.$child->id);

        $response->assertOk();
        $this->assertArrayNotHasKey('nik', $response->json('data'));
        $this->assertArrayNotHasKey('nik_hash', $response->json('data'));
    }
}
