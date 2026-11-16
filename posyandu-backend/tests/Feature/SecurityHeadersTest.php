<?php

namespace Tests\Feature;

use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class SecurityHeadersTest extends TestCase
{
    #[Test]
    public function respons_api_memakai_header_keamanan_dan_tidak_di_cache(): void
    {
        $response = $this->getJson('/api/user');

        $response->assertUnauthorized()
            ->assertHeader('X-Content-Type-Options', 'nosniff')
            ->assertHeader('X-Frame-Options', 'DENY')
            ->assertHeader('Referrer-Policy', 'strict-origin-when-cross-origin')
            ->assertHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()')
            ->assertHeader(
                'Content-Security-Policy',
                "default-src 'none'; frame-ancestors 'none'; base-uri 'none'"
            )
            ->assertHeader('Cache-Control', 'no-store, private');
    }

    #[Test]
    public function hsts_hanya_dikirim_pada_request_https(): void
    {
        $this->getJson('/api/user')
            ->assertHeaderMissing('Strict-Transport-Security');

        $this->getJson('https://localhost/api/user')
            ->assertHeader(
                'Strict-Transport-Security',
                'max-age=31536000; includeSubDomains'
            );
    }

    #[Test]
    public function cors_hanya_mengizinkan_origin_yang_dikonfigurasi(): void
    {
        config(['cors.allowed_origins' => [
            'https://admin.example.test',
            'https://ops.example.test',
        ]]);

        $this->withHeader('Origin', 'https://admin.example.test')
            ->getJson('/api/user')
            ->assertHeader('Access-Control-Allow-Origin', 'https://admin.example.test');

        $this->withHeader('Origin', 'https://evil.example.test')
            ->getJson('/api/user')
            ->assertHeaderMissing('Access-Control-Allow-Origin');
    }

    #[Test]
    public function preflight_cors_memakai_origin_yang_diizinkan(): void
    {
        config(['cors.allowed_origins' => ['https://admin.example.test']]);

        $response = $this->withHeaders([
            'Origin' => 'https://admin.example.test',
            'Access-Control-Request-Method' => 'POST',
            'Access-Control-Request-Headers' => 'Authorization, Content-Type',
        ])->options('/api/login');

        $response->assertNoContent()
            ->assertHeader('Access-Control-Allow-Origin', 'https://admin.example.test')
            ->assertHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
    }
}
