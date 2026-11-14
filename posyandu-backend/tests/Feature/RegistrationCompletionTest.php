<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
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
}
