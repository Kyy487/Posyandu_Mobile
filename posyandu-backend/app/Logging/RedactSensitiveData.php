<?php

namespace App\Logging;

use App\Support\SensitiveDataRedactor;
use Illuminate\Log\Logger;
use Monolog\LogRecord;

/**
 * Processor Monolog yang menyamarkan NIK, token, dan kredensial di semua log.
 *
 * Dipasang lewat `tap` pada channel di `config/logging.php`, sehingga pesan
 * exception yang berisi binding query ikut dibersihkan.
 */
final class RedactSensitiveData
{
    public function __invoke(Logger $logger): void
    {
        $monolog = $logger->getLogger();

        if (! method_exists($monolog, 'pushProcessor')) {
            return;
        }

        $monolog->pushProcessor(function (LogRecord $record): LogRecord {
            $context = SensitiveDataRedactor::redact($record->context);
            $extra = SensitiveDataRedactor::redact($record->extra);

            return $record->with(
                message: SensitiveDataRedactor::redactString($record->message) ?? '',
                context: is_array($context) ? $context : [],
                extra: is_array($extra) ? $extra : [],
            );
        });
    }
}
