<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class TokenExpirationTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function token_sanctum_kedaluwarsa_setelah_30_hari(): void
    {
        $kader = User::factory()->kader()->create();
        $token = $kader->createToken('uji')->plainTextToken;

        $this->travel(31)->days();

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/user')
            ->assertUnauthorized();
    }
}
