<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\ImmunizationType;
use App\Models\PosyanduSchedule;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Menguji endpoint pengingat: `GET /api/ibu/reminders` dan
 * `GET /api/kader/reminders`.
 *
 * Yang diuji:
 *  - Agenda dalam 7 hari ke depan muncul
 *  - Agenda di luar 7 hari tidak muncul
 *  - Imunisasi yang sudah melewati toleransi muncul sebagai "terlambat"
 *  - Imunisasi yang belum jatuh tempo tidak muncul
 *  - Kader hanya melihat agenda yang ia petugasi
 *  - Ibu hanya melihat anaknya sendiri
 */
class ReminderTest extends TestCase
{
    use RefreshDatabase;

    // =================================================================
    // GET /api/ibu/reminders
    // =================================================================

    #[Test]
    public function ibu_melihat_agenda_dalam_7_hari(): void
    {
        $ibu = User::factory()->ibu()->create();

        PosyanduSchedule::factory()->create([
            'title' => 'Penimbangan Rutin',
            'scheduled_date' => now()->addDays(3)->toDateString(),
            'status' => PosyanduSchedule::STATUS_TERJADWAL,
        ]);

        $this->actingAs($ibu, 'sanctum')
            ->getJson('/api/ibu/reminders')
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.agenda.0.judul', 'Penimbangan Rutin')
            ->assertJsonPath('data.agenda.0.jarak_hari', 3);
    }

    #[Test]
    public function ibu_tidak_melihat_agenda_di_luar_7_hari(): void
    {
        $ibu = User::factory()->ibu()->create();

        PosyanduSchedule::factory()->create([
            'title' => 'Agenda Jauh',
            'scheduled_date' => now()->addDays(30)->toDateString(),
            'status' => PosyanduSchedule::STATUS_TERJADWAL,
        ]);

        $this->actingAs($ibu, 'sanctum')
            ->getJson('/api/ibu/reminders')
            ->assertOk()
            ->assertJsonPath('data.agenda', []);
    }

    #[Test]
    public function ibu_melihat_imunisasi_terlambat(): void
    {
        $ibu = User::factory()->ibu()->create();

        $this->seedMasterDosis();

        // Anak lahir 6 bulan lalu — seharusnya sudah dapat BCG (target 0 bulan)
        // dan Polio 1 (target 1 bulan), tapi belum disuntik sama sekali.
        $anak = Child::factory()->milik($ibu)->create([
            'date_of_birth' => now()->subMonths(6)->toDateString(),
        ]);

        $this->actingAs($ibu, 'sanctum')
            ->getJson('/api/ibu/reminders')
            ->assertOk()
            ->assertJsonPath('success', true);

        $imunisasi = $this->actingAs($ibu, 'sanctum')
            ->getJson('/api/ibu/reminders')
            ->json('data.imunisasi');

        $this->assertNotEmpty($imunisasi);
        $this->assertEquals($anak->id, $imunisasi[0]['child_id']);
        $this->assertEquals('terlambat', $imunisasi[0]['status']);
    }

    #[Test]
    public function ibu_tidak_melihat_imunisasi_yang_belum_jatuh_tempo(): void
    {
        $ibu = User::factory()->ibu()->create();

        $this->seedMasterDosis();

        // Anak baru lahir 1 bulan — belum ada dosis yang terlambat.
        Child::factory()->milik($ibu)->create([
            'date_of_birth' => now()->subMonth()->toDateString(),
        ]);

        $this->actingAs($ibu, 'sanctum')
            ->getJson('/api/ibu/reminders')
            ->assertOk()
            ->assertJsonPath('data.imunisasi', []);
    }

    #[Test]
    public function ibu_hanya_melihat_anaknya_sendiri(): void
    {
        $ibu1 = User::factory()->ibu()->create();
        $ibu2 = User::factory()->ibu()->create();

        $this->seedMasterDosis();

        $anak1 = Child::factory()->milik($ibu1)->create([
            'date_of_birth' => now()->subMonths(6)->toDateString(),
        ]);

        $anak2 = Child::factory()->milik($ibu2)->create([
            'date_of_birth' => now()->subMonths(6)->toDateString(),
        ]);

        $response = $this->actingAs($ibu1, 'sanctum')
            ->getJson('/api/ibu/reminders')
            ->assertOk();

        $childIds = array_column($response->json('data.imunisasi'), 'child_id');

        $this->assertContains($anak1->id, $childIds);
        $this->assertNotContains($anak2->id, $childIds);
    }

    #[Test]
    public function ibu_tidak_bisa_mengakses_kader_reminders(): void
    {
        $ibu = User::factory()->ibu()->create();

        $this->actingAs($ibu, 'sanctum')
            ->getJson('/api/kader/reminders')
            ->assertForbidden();
    }

    // =================================================================
    // GET /api/kader/reminders
    // =================================================================

    #[Test]
    public function kader_melihat_agenda_yang_ia_petugasi(): void
    {
        $kader = User::factory()->kader()->create();

        $agenda = PosyanduSchedule::factory()->create([
            'title' => 'Penimbangan Rutin',
            'scheduled_date' => now()->addDays(2)->toDateString(),
            'status' => PosyanduSchedule::STATUS_TERJADWAL,
        ]);

        $agenda->petugas()->attach($kader->id);

        $this->actingAs($kader, 'sanctum')
            ->getJson('/api/kader/reminders')
            ->assertOk()
            ->assertJsonPath('data.agenda.0.judul', 'Penimbangan Rutin')
            ->assertJsonPath('data.agenda.0.jarak_hari', 2);
    }

    #[Test]
    public function kader_tidak_melihat_agenda_yang_bukan_tugasnya(): void
    {
        $kader1 = User::factory()->kader()->create();
        $kader2 = User::factory()->kader()->create();

        $agenda = PosyanduSchedule::factory()->create([
            'title' => 'Penimbangan Rutin',
            'scheduled_date' => now()->addDays(2)->toDateString(),
            'status' => PosyanduSchedule::STATUS_TERJADWAL,
        ]);

        $agenda->petugas()->attach($kader2->id);

        $this->actingAs($kader1, 'sanctum')
            ->getJson('/api/kader/reminders')
            ->assertOk()
            ->assertJsonPath('data.agenda', []);
    }

    #[Test]
    public function kader_melihat_jumlah_anak_terlambat(): void
    {
        $kader = User::factory()->kader()->create();

        $this->seedMasterDosis();

        // Dua anak yang sama-sama terlambat
        Child::factory()->create([
            'date_of_birth' => now()->subMonths(6)->toDateString(),
        ]);
        Child::factory()->create([
            'date_of_birth' => now()->subMonths(8)->toDateString(),
        ]);

        $response = $this->actingAs($kader, 'sanctum')
            ->getJson('/api/kader/reminders')
            ->assertOk();

        // Setiap anak punya beberapa dosis yang terlambat, jadi jumlahnya
        // lebih dari 2. Yang penting: angkanya lebih dari 0.
        $this->assertGreaterThan(0, $response->json('data.terlambat'));
    }

    #[Test]
    public function kader_tidak_bisa_mengakses_ibu_reminders(): void
    {
        $kader = User::factory()->kader()->create();

        $this->actingAs($kader, 'sanctum')
            ->getJson('/api/ibu/reminders')
            ->assertForbidden();
    }

    #[Test]
    public function kader_melihat_agenda_dan_terlambat_sekaligus(): void
    {
        $kader = User::factory()->kader()->create();

        $this->seedMasterDosis();

        $agenda = PosyanduSchedule::factory()->create([
            'title' => 'Penimbangan Rutin',
            'scheduled_date' => now()->addDays(1)->toDateString(),
            'status' => PosyanduSchedule::STATUS_TERJADWAL,
        ]);
        $agenda->petugas()->attach($kader->id);

        Child::factory()->create([
            'date_of_birth' => now()->subMonths(6)->toDateString(),
        ]);

        $response = $this->actingAs($kader, 'sanctum')
            ->getJson('/api/kader/reminders')
            ->assertOk();

        $this->assertNotEmpty($response->json('data.agenda'));
        $this->assertGreaterThan(0, $response->json('data.terlambat'));
    }

    /**
     * Master dosis imunisasi yang dibutuhkan test.
     *
     * `RefreshDatabase` tidak menjalankan `DatabaseSeeder`, jadi tanpa ini
     * tabel `immunization_types` kosong dan tidak ada dosis yang bisa
     * "terlambat". Test lain (mis. `ImmunizationTypeOrderTest`) juga
     * menyiapkan master-nya sendiri, bukan mengandalkan seeder.
     *
     * Dua dosis dengan target 0 dan 2 bulan: anak 6 bulan sudah melewati
     * toleransi (default 2 bulan) untuk keduanya, anak 1 bulan belum.
     */
    private function seedMasterDosis(): void
    {
        ImmunizationType::factory()->create([
            'code' => 'HB',
            'dose_number' => 1,
            'target_age_months' => 0,
        ]);

        ImmunizationType::factory()->create([
            'code' => 'BCG',
            'dose_number' => 1,
            'target_age_months' => 2,
        ]);
    }
}
