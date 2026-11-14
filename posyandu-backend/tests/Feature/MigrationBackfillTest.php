<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\Measurement;
use App\Models\User;
use App\Models\Visit;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class MigrationBackfillTest extends TestCase
{
    use RefreshDatabase;

    public function test_backfill_mengisi_waktu_dari_tanggal_tanpa_mengubah_z_score(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01']);

        $kunjungan = Visit::factory()
            ->untukAnak($anak)
            ->olehKader($kader)
            ->padaTanggal('2026-08-01')
            ->create([
                'visit_started_at' => null,
                'visit_ended_at' => null,
            ]);

        $pengukuran = Measurement::factory()
            ->untukAnak($anak)
            ->olehKader($kader)
            ->padaTanggal('2026-08-01')
            ->create([
                'measured_at' => null,
                'weight_kg' => 10.5,
                'height_cm' => 80.0,
            ]);

        $sebelum = $pengukuran->fresh();

        $this->assertNull($sebelum->measured_at);
        $this->assertNotNull($sebelum->z_score_wfa);
        $this->assertNotNull($sebelum->status_gizi);

        $this->migrationBackfill()->up();

        $kunjungan->refresh();
        $pengukuran->refresh();

        $this->assertSame(
            '2026-07-31 17:00:00',
            $kunjungan->visit_started_at?->utc()->format('Y-m-d H:i:s'),
        );
        $this->assertNull($kunjungan->visit_ended_at);
        $this->assertSame(
            '2026-07-31 17:00:00',
            $pengukuran->measured_at?->utc()->format('Y-m-d H:i:s'),
        );

        $this->assertSame($sebelum->z_score_wfa, $pengukuran->z_score_wfa);
        $this->assertSame($sebelum->status_gizi, $pengukuran->status_gizi);
    }

    public function test_backfill_tidak_menimpa_waktu_yang_sudah_diisi(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01']);

        $kunjungan = Visit::factory()
            ->untukAnak($anak)
            ->olehKader($kader)
            ->padaTanggal('2026-08-01')
            ->create([
                'visit_started_at' => '2026-08-02 03:00:00',
                'visit_ended_at' => '2026-08-02 04:00:00',
            ]);

        $pengukuran = Measurement::factory()
            ->untukAnak($anak)
            ->olehKader($kader)
            ->padaTanggal('2026-08-01')
            ->create(['measured_at' => '2026-08-02 03:00:00']);

        $this->migrationBackfill()->up();

        $this->assertSame(
            '2026-08-02 03:00:00',
            $kunjungan->fresh()->visit_started_at?->format('Y-m-d H:i:s'),
        );
        $this->assertSame(
            '2026-08-02 04:00:00',
            $kunjungan->fresh()->visit_ended_at?->format('Y-m-d H:i:s'),
        );
        $this->assertSame(
            '2026-08-02 03:00:00',
            $pengukuran->fresh()->measured_at?->format('Y-m-d H:i:s'),
        );
    }

    private function migrationBackfill(): object
    {
        return require database_path(
            'migrations/2026_11_14_000008_backfill_visit_and_measurement_timestamps.php'
        );
    }
}
