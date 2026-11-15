<?php

namespace Tests\Unit;

use App\Logging\RedactSensitiveData;
use App\Support\SensitiveDataRedactor;
use Illuminate\Database\QueryException;
use Illuminate\Log\Logger as IlluminateLogger;
use Monolog\Level;
use Monolog\Logger as MonologLogger;
use Monolog\LogRecord;
use PHPUnit\Framework\TestCase;

class SensitiveDataRedactorTest extends TestCase
{
    public function test_nik_disamarkan_di_array_dan_string(): void
    {
        $hasil = SensitiveDataRedactor::redact([
            'nik' => '3201012345678901',
            'nik_anak' => '3201012345678902',
            'profil' => [
                'nik_ibu' => '3201012345678903',
                'nama' => 'Siti',
            ],
            'catatan' => 'NIK 3201012345678901 harus hilang.',
        ]);

        $this->assertSame('[REDACTED]', $hasil['nik']);
        $this->assertSame('[REDACTED]', $hasil['nik_anak']);
        $this->assertSame('[REDACTED]', $hasil['profil']['nik_ibu']);
        $this->assertSame('Siti', $hasil['profil']['nama']);
        $this->assertSame(
            'NIK [REDACTED_NIK] harus hilang.',
            $hasil['catatan'],
        );
    }

    public function test_password_token_dan_kredensial_disamarkan(): void
    {
        $hasil = SensitiveDataRedactor::redact([
            'password' => 'rahasia',
            'password_confirmation' => 'rahasia',
            'client_secret' => 'secret-satusehat',
            'access_token' => 'token-abc',
            'authorization' => 'Bearer token-abc',
            'api_key' => 'key-abc',
            'nama' => 'Siti',
        ]);

        foreach ([
            'password',
            'password_confirmation',
            'client_secret',
            'access_token',
            'authorization',
            'api_key',
        ] as $kunci) {
            $this->assertSame('[REDACTED]', $hasil[$kunci], $kunci);
        }

        $this->assertSame('Siti', $hasil['nama']);
    }

    public function test_pesan_exception_query_tidak_memuat_nik(): void
    {
        $exception = new QueryException(
            'pgsql',
            'insert into users (nik) values (?)',
            ['3201012345678901'],
            new \PDOException('duplicate key'),
        );

        $hasil = SensitiveDataRedactor::exception($exception);

        $this->assertStringContainsString('[REDACTED_NIK]', $hasil['message']);
        $this->assertStringNotContainsString('3201012345678901', $hasil['message']);
    }

    public function test_processor_monolog_menyaring_record(): void
    {
        $monolog = new MonologLogger('test');
        (new RedactSensitiveData)(new IlluminateLogger($monolog));

        $processor = $monolog->getProcessors()[0];
        $record = new LogRecord(
            new \DateTimeImmutable,
            'test',
            Level::Info,
            'Login gagal untuk NIK 3201012345678901',
            ['nik' => '3201012345678901', 'nama' => 'Siti'],
        );

        $hasil = $processor($record);

        $this->assertSame(
            'Login gagal untuk NIK [REDACTED_NIK]',
            $hasil->message,
        );
        $this->assertSame('[REDACTED]', $hasil->context['nik']);
        $this->assertSame('Siti', $hasil->context['nama']);
    }
}
