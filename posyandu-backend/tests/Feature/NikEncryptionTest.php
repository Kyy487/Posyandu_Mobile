<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\User;
use Database\Factories\UserFactory;
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

        $user1 = User::factory()->create(['nik' => $nik]);
        $user2 = User::factory()->create(['nik' => $nik]);

        $this->assertEquals($user1->nik_hash, $user2->nik_hash);
        $this->assertEquals(hash('sha256', $nik), $user1->nik_hash);
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
        $this->assertArrayNotHasKey('nik', $response->json('data.user'));
        $this->assertArrayNotHasKey('nik_hash', $response->json('data.user'));
    }

    public function test_nik_anak_tersimpan_encrypted(): void
    {
        $child = Child::factory()->create();

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
