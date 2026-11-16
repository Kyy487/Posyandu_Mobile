<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\MedicalNote;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class MedicalNoteRedFlagsTest extends TestCase
{
    use RefreshDatabase;

    public function test_red_flags_saja_dapat_disimpan_sebagai_isi_catatan(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01']);

        $response = $this->actingAs($kader, 'sanctum')
            ->postJson("/api/kader/children/{$anak->id}/medical-notes", [
                'note_date' => '2026-08-01',
                'red_flags' => ['demam_tinggi', 'sesak_napas'],
                'icd10_code' => 'A09',
            ]);

        $response->assertCreated()
            ->assertJsonPath('data.red_flags.0', 'demam_tinggi')
            ->assertJsonPath('data.icd10_code', 'A09');

        $note = MedicalNote::query()->sole();

        $this->assertSame(['demam_tinggi', 'sesak_napas'], $note->red_flags);
        $this->assertSame('A09', $note->icd10_code);
    }

    public function test_red_flag_di_luar_allowlist_ditolak(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01']);

        $this->actingAs($kader, 'sanctum')
            ->postJson("/api/kader/children/{$anak->id}/medical-notes", [
                'note_date' => '2026-08-01',
                'red_flags' => ['kode_tidak_dikenal'],
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('red_flags.0');

        $this->assertDatabaseCount('medical_notes', 0);
    }

    public function test_icd10_tidak_valid_ditolak(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01']);

        $this->actingAs($kader, 'sanctum')
            ->postJson("/api/kader/children/{$anak->id}/medical-notes", [
                'note_date' => '2026-08-01',
                'demam' => true,
                'icd10_code' => 'bukan-icd',
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('icd10_code');
    }

    public function test_red_flags_dapat_dikoreksi_lewat_patch(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01']);
        $note = MedicalNote::factory()
            ->untukAnak($anak)
            ->demam()
            ->create(['note_date' => '2026-08-01']);

        $this->actingAs($kader, 'sanctum')
            ->patchJson("/api/kader/medical-notes/{$note->id}", [
                'red_flags' => ['kejang'],
                'icd10_code' => 'R56.0',
            ])
            ->assertOk()
            ->assertJsonPath('data.red_flags.0', 'kejang')
            ->assertJsonPath('data.icd10_code', 'R56.0');

        $this->assertSame(['kejang'], $note->fresh()->red_flags);
    }

    public function test_red_flags_kosong_tidak_dianggap_isi(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01']);

        $this->actingAs($kader, 'sanctum')
            ->postJson("/api/kader/children/{$anak->id}/medical-notes", [
                'note_date' => '2026-08-01',
                'red_flags' => [],
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('demam');
    }
}
