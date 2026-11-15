<?php

namespace App\Support;

use Illuminate\Contracts\Support\Arrayable;
use JsonSerializable;
use Throwable;

/**
 * Menyamarkan data pribadi sebelum ditulis ke log.
 *
 * NIK adalah 16 digit dan sering muncul di pesan QueryException karena Laravel
 * menyalin binding query ke pesan exception. Jangan mengandalkan pemanggil log
 * untuk membersihkan data; semua channel file memakai processor ini.
 */
final class SensitiveDataRedactor
{
    public const REDACTED = '[REDACTED]';

    public const REDACTED_NIK = '[REDACTED_NIK]';

    private const SENSITIVE_SEGMENTS = [
        'nik',
        'kk',
        'ktp',
        'password',
        'passphrase',
        'token',
        'secret',
        'authorization',
        'credential',
        'key',
        'apikey',
    ];

    public static function redact(mixed $value, ?string $key = null): mixed
    {
        if ($key !== null && self::isSensitiveKey($key)) {
            return self::REDACTED;
        }

        if (is_array($value)) {
            $result = [];

            foreach ($value as $itemKey => $item) {
                $result[$itemKey] = self::redact(
                    $item,
                    is_string($itemKey) ? $itemKey : null,
                );
            }

            return $result;
        }

        if ($value instanceof Throwable) {
            return self::exception($value);
        }

        if ($value instanceof JsonSerializable) {
            return self::redact($value->jsonSerialize(), $key);
        }

        if ($value instanceof Arrayable) {
            return self::redact($value->toArray(), $key);
        }

        if (is_string($value)) {
            return self::redactString($value);
        }

        return $value;
    }

    public static function redactString(?string $value): ?string
    {
        if ($value === null) {
            return null;
        }

        $value = preg_replace(
            '/(?<!\d)\d{16}(?!\d)/',
            self::REDACTED_NIK,
            $value,
        ) ?? $value;

        $value = preg_replace(
            '/\bBearer\s+[A-Za-z0-9\-._~+\/]+=*/i',
            'Bearer '.self::REDACTED,
            $value,
        ) ?? $value;

        return preg_replace(
            '/(client_secret|password|access_token|refresh_token|authorization)'
            .'(["\']?\s*[:=]\s*["\']?)([^"\',\s]+)/i',
            '$1$2'.self::REDACTED,
            $value,
        ) ?? $value;
    }

    /**
     * @return array<string, mixed>
     */
    public static function exception(Throwable $exception): array
    {
        return [
            'class' => $exception::class,
            'message' => self::redactString($exception->getMessage()),
            'code' => $exception->getCode(),
            'file' => $exception->getFile(),
            'line' => $exception->getLine(),
            'trace' => array_map(
                fn (array $frame): array => array_filter(
                    [
                        'file' => $frame['file'] ?? null,
                        'line' => $frame['line'] ?? null,
                        'function' => $frame['function'] ?? null,
                        'class' => $frame['class'] ?? null,
                        'type' => $frame['type'] ?? null,
                    ],
                    fn (mixed $value): bool => $value !== null,
                ),
                $exception->getTrace(),
            ),
        ];
    }

    private static function isSensitiveKey(string $key): bool
    {
        $snake = preg_replace('/(?<!^)[A-Z]/', '_$0', $key) ?? $key;
        $segments = explode('_', strtolower(str_replace(['-', ' '], '_', $snake)));

        foreach ($segments as $segment) {
            if (in_array($segment, self::SENSITIVE_SEGMENTS, true)) {
                return true;
            }
        }

        return false;
    }
}
