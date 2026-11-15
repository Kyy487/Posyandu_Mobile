<?php

namespace Tests\Feature;

use App\Logging\RedactSensitiveData;
use Tests\TestCase;

class LogRedactionConfigTest extends TestCase
{
    public function test_channel_log_memakai_processor_redaksi(): void
    {
        foreach ([
            'single',
            'daily',
            'monthly',
            'slack',
            'satusehat',
            'papertrail',
            'stderr',
            'syslog',
            'errorlog',
        ] as $channel) {
            $this->assertContains(
                RedactSensitiveData::class,
                config("logging.channels.{$channel}.tap", []),
                "Channel {$channel} belum memakai redaksi log.",
            );
        }
    }
}
