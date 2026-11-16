<?php

namespace Tests\Feature;

use App\Models\PosyanduSchedule;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class KaderScheduleTest extends TestCase
{
    use RefreshDatabase;

    public function test_kader_membuat_agenda_dengan_petugas(): void
    {
        $kader = User::factory()->kader()->create();
        $petugas = User::factory()->kader()->create();

        $response = $this->actingAs($kader)->postJson('/api/kader/schedules', [
            'title' => 'Penimbangan Rutin',
            'description' => 'Agenda bulanan',
            'scheduled_date' => '2026-12-01',
            'start_time' => '08:00',
            'end_time' => '10:00',
            'location' => 'Posyandu Melati',
            'petugas_ids' => [$petugas->id],
        ]);

        $response->assertCreated()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.title', 'Penimbangan Rutin')
            ->assertJsonPath('data.petugas_ids.0', $petugas->id);

        $this->assertDatabaseHas('posyandu_schedules', [
            'id' => $response->json('data.id'),
            'created_by' => $kader->id,
            'scheduled_date' => '2026-12-01',
        ]);

        $this->assertDatabaseHas('posyandu_schedule_petugas', [
            'schedule_id' => $response->json('data.id'),
            'petugas_id' => $petugas->id,
        ]);
    }

    public function test_kader_memperbarui_agenda_dan_mengganti_petugas(): void
    {
        $kader = User::factory()->kader()->create();
        $petugasLama = User::factory()->kader()->create();
        $petugasBaru = User::factory()->kader()->create();

        $agenda = PosyanduSchedule::create([
            'title' => 'Agenda Lama',
            'scheduled_date' => '2026-12-01',
            'status' => PosyanduSchedule::STATUS_TERJADWAL,
            'created_by' => $kader->id,
        ]);
        $agenda->petugas()->attach($petugasLama->id);

        $response = $this->actingAs($kader)
            ->patchJson('/api/kader/schedules/'.$agenda->id, [
                'title' => 'Agenda Baru',
                'status' => PosyanduSchedule::STATUS_SELESAI,
                'petugas_ids' => [$petugasBaru->id],
            ]);

        $response->assertOk()
            ->assertJsonPath('data.title', 'Agenda Baru')
            ->assertJsonPath('data.status', PosyanduSchedule::STATUS_SELESAI)
            ->assertJsonPath('data.petugas_ids.0', $petugasBaru->id);

        $this->assertDatabaseMissing('posyandu_schedule_petugas', [
            'schedule_id' => $agenda->id,
            'petugas_id' => $petugasLama->id,
        ]);
        $this->assertDatabaseHas('posyandu_schedule_petugas', [
            'schedule_id' => $agenda->id,
            'petugas_id' => $petugasBaru->id,
        ]);
    }

    public function test_kader_menghapus_agenda_beserta_pivot(): void
    {
        $kader = User::factory()->kader()->create();
        $petugas = User::factory()->kader()->create();

        $agenda = PosyanduSchedule::create([
            'title' => 'Agenda Dihapus',
            'scheduled_date' => '2026-12-01',
            'status' => PosyanduSchedule::STATUS_TERJADWAL,
            'created_by' => $kader->id,
        ]);
        $agenda->petugas()->attach($petugas->id);

        $this->actingAs($kader)
            ->deleteJson('/api/kader/schedules/'.$agenda->id)
            ->assertOk()
            ->assertJsonPath('data.id', $agenda->id);

        $this->assertDatabaseMissing('posyandu_schedules', ['id' => $agenda->id]);
        $this->assertDatabaseMissing('posyandu_schedule_petugas', ['schedule_id' => $agenda->id]);
    }

    public function test_ibu_tidak_bisa_mengelola_agenda(): void
    {
        $ibu = User::factory()->ibu()->create();

        $this->actingAs($ibu)->postJson('/api/kader/schedules', [
            'title' => 'Agenda Ibu',
            'scheduled_date' => '2026-12-01',
        ])->assertForbidden();
    }

    public function test_petugas_agenda_harus_role_kader(): void
    {
        $kader = User::factory()->kader()->create();
        $ibu = User::factory()->ibu()->create();

        $this->actingAs($kader)->postJson('/api/kader/schedules', [
            'title' => 'Agenda Salah Petugas',
            'scheduled_date' => '2026-12-01',
            'petugas_ids' => [$ibu->id],
        ])->assertStatus(422)
            ->assertJsonValidationErrors('petugas_ids');
    }

    public function test_daftar_petugas_hanya_mengembalikan_kader_tanpa_nik(): void
    {
        $ibu = User::factory()->ibu()->create();
        $kader = User::factory()->kader()->create();

        $response = $this->actingAs($ibu)->getJson('/api/petugas');

        $response->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $kader->id);

        $this->assertArrayNotHasKey('nik', $response->json('data.0'));
        $this->assertArrayNotHasKey('nik_hash', $response->json('data.0'));
    }
}
