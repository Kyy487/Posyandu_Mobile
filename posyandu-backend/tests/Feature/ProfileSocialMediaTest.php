<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ProfileSocialMediaTest extends TestCase
{
    use RefreshDatabase;

    public function test_profil_menormalkan_whatsapp_dan_handle_sosial_media(): void
    {
        $user = User::factory()->ibu()->create();

        $this->actingAs($user, 'sanctum')
            ->patchJson('/api/profile', [
                'whatsapp' => '0812-3456-7890',
                'instagram' => 'https://www.instagram.com/@Ibu.Test/?hl=id',
                'facebook' => 'https://facebook.com/ibu.test',
            ])
            ->assertOk()
            ->assertJsonPath('data.whatsapp', '+6281234567890')
            ->assertJsonPath('data.instagram', 'Ibu.Test')
            ->assertJsonPath('data.facebook', 'ibu.test');

        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'whatsapp' => '+6281234567890',
            'instagram' => 'Ibu.Test',
            'facebook' => 'ibu.test',
        ]);
    }

    public function test_profil_menolak_nomor_whatsapp_tidak_valid(): void
    {
        $user = User::factory()->ibu()->create();

        $this->actingAs($user, 'sanctum')
            ->patchJson('/api/profile', [
                'whatsapp' => 'bukan-nomor',
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('whatsapp');
    }
}
