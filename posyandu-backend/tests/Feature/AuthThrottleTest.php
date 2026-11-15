<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AuthThrottleTest extends TestCase
{
    use RefreshDatabase;

    public function test_login_dibatasi_setelah_lima_percobaan(): void
    {
        $payload = [
            'nik' => '3201012345678901',
            'password' => 'password-salah',
        ];

        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/api/login', $payload)->assertUnauthorized();
        }

        $this->postJson('/api/login', $payload)
            ->assertTooManyRequests();
    }
}
