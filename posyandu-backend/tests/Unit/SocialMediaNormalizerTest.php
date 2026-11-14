<?php

namespace Tests\Unit;

use App\Support\SocialMediaNormalizer;
use InvalidArgumentException;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

class SocialMediaNormalizerTest extends TestCase
{
    #[DataProvider('whatsappValidProvider')]
    public function test_whatsapp_dinormalkan_ke_e164(?string $input, ?string $expected): void
    {
        $this->assertSame($expected, SocialMediaNormalizer::whatsapp($input));
    }

    /**
     * @return array<string, array{0: ?string, 1: ?string}>
     */
    public static function whatsappValidProvider(): array
    {
        return [
            'lokal dengan tanda hubung' => ['0812-3456-7890', '+6281234567890'],
            'internasional dengan spasi' => ['+62 812 3456 7890', '+6281234567890'],
            'tanpa plus' => ['6281234567890', '+6281234567890'],
            'tanpa nol depan' => ['81234567890', '+6281234567890'],
            'awalan 620' => ['62081234567890', '+6281234567890'],
            'spasi di ujung' => [' 081234567890 ', '+6281234567890'],
            'kosong' => ['', null],
            'null' => [null, null],
        ];
    }

    #[DataProvider('whatsappInvalidProvider')]
    public function test_whatsapp_tidak_valid_ditolak(string $input): void
    {
        $this->expectException(InvalidArgumentException::class);

        SocialMediaNormalizer::whatsapp($input);
    }

    /**
     * @return array<string, array{0: string}>
     */
    public static function whatsappInvalidProvider(): array
    {
        return [
            'bukan nomor' => ['bukan-nomor'],
            'terlalu pendek' => ['0812'],
            'tanpa digit' => ['+'],
        ];
    }

    #[DataProvider('instagramProvider')]
    public function test_instagram_dinormalkan_menjadi_handle(?string $input, ?string $expected): void
    {
        $this->assertSame($expected, SocialMediaNormalizer::instagram($input));
    }

    /**
     * @return array<string, array{0: ?string, 1: ?string}>
     */
    public static function instagramProvider(): array
    {
        return [
            'url lengkap dengan query' => ['https://www.instagram.com/@Ibu.Test/?hl=id', 'Ibu.Test'],
            'url mobile' => ['https://m.instagram.com/ibu.test', 'ibu.test'],
            'handle dengan at' => ['@ibu.test', 'ibu.test'],
            'handle dengan slash akhir' => ['ibu.test/', 'ibu.test'],
            'url tanpa www' => ['https://instagram.com/ibu.test?x=1', 'ibu.test'],
            'kosong' => ['', null],
            'null' => [null, null],
        ];
    }

    #[DataProvider('instagramInvalidProvider')]
    public function test_instagram_tidak_valid_ditolak(string $input): void
    {
        $this->expectException(InvalidArgumentException::class);

        SocialMediaNormalizer::instagram($input);
    }

    /**
     * @return array<string, array{0: string}>
     */
    public static function instagramInvalidProvider(): array
    {
        return [
            'mengandung spasi' => ['ibu test'],
            'mengandung slash' => ['ibu/test'],
        ];
    }

    #[DataProvider('facebookProvider')]
    public function test_facebook_dinormalkan_menjadi_handle(?string $input, ?string $expected): void
    {
        $this->assertSame($expected, SocialMediaNormalizer::facebook($input));
    }

    /**
     * @return array<string, array{0: ?string, 1: ?string}>
     */
    public static function facebookProvider(): array
    {
        return [
            'url lengkap' => ['https://facebook.com/ibu.test', 'ibu.test'],
            'url www dengan slash akhir' => ['https://www.facebook.com/ibu.test/', 'ibu.test'],
            'handle dengan at' => ['@ibu.test', 'ibu.test'],
            'kosong' => ['', null],
            'null' => [null, null],
        ];
    }

    public function test_facebook_menolak_url_platform_lain(): void
    {
        $this->expectException(InvalidArgumentException::class);

        SocialMediaNormalizer::facebook('https://instagram.com/ibu.test');
    }
}
