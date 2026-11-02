<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\Measurement;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Menguji koreksi penimbangan (e-KMS) lewat `PATCH /kader/measurements/{id}`.
 *
 * Sebelum endpoint ini ada, salah input penimbangan hanya bisa dibatalkan lalu
 * dicatat ulang. Koreksi di sini bersifat parsial: field yang tidak dikirim
 * tidak disentuh, `child_id`/`visit_id` tidak bisa dipindah, dan trigger
 * PostgreSQL menghitung ulang age_in_months, z-score, serta status gizi.
 */
class MeasurementTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function kader_mengoreksi_penimbangan_membalas_200(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $penimbangan = Measurement::factory()->untukAnak($anak)->olehKader($kader)
            ->padaTanggal('2026-08-01')->create([
                'weight_kg' => 9.0,
                'height_cm' => 80.0,
            ]);

        $zAwal = $penimbangan->refresh()->z_score_wfa;

        $respons = $this->sebagai($kader)->patchJson("/api/kader/measurements/{$penimbangan->id}", [
            'weight_kg' => 11.5,
            'height_cm' => 84.0,
        ]);

        $respons->assertOk();
        $this->assertTrue($respons->json('success'));
        // PostgreSQL mengirim kolom numeric sebagai string ("11.50"), jadi
        // dibandingkan sebagai angka, bukan identik.
        $this->assertEquals(11.5, $respons->json('data.weight_kg'));
        $this->assertEquals(84, $respons->json('data.height_cm'));

        // Trigger dijalankan ulang setelah UPDATE: z-score ikut berubah.
        $this->assertNotSame($zAwal, $respons->json('data.z_score_wfa'));
        $this->assertNotNull($respons->json('data.z_score_wfa'));

        $this->assertDatabaseHas('measurements', [
            'id' => $penimbangan->id,
            'weight_kg' => 11.5,
            'height_cm' => 84,
        ]);
    }

    #[Test]
    public function ibu_tidak_bisa_mengoreksi_penimbangan(): void
    {
        $ibu = User::factory()->ibu()->create();
        $anak = Child::factory()->milik($ibu)->create(['date_of_birth' => '2024-01-01']);
        $penimbangan = Measurement::factory()->untukAnak($anak)->padaTanggal('2026-08-01')->create();

        $this->sebagai($ibu)
            ->patchJson("/api/kader/measurements/{$penimbangan->id}", ['weight_kg' => 11.5])
            ->assertForbidden();
    }

    #[Test]
    public function koreksi_penimbangan_tidak_ditemukan_membalas_404(): void
    {
        $kader = User::factory()->kader()->create();

        $this->sebagai($kader)
            ->patchJson('/api/kader/measurements/00000000-0000-0000-0000-000000000000', [
                'weight_kg' => 11.5,
            ])
            ->assertNotFound();
    }

    #[Test]
    public function koreksi_tanggal_masa_depan_membalas_422(): void
    {
        $kader = User::factory()->kader()->create();
        $penimbangan = Measurement::factory()->untukAnak($this->anak())
            ->padaTanggal('2026-08-01')->create();

        $respons = $this->sebagai($kader)
            ->patchJson("/api/kader/measurements/{$penimbangan->id}", [
                'measurement_date' => '2030-01-01',
            ]);

        $respons->assertStatus(422);
        $respons->assertJsonValidationErrors(['measurement_date']);
    }

    #[Test]
    public function koreksi_ke_tanggal_yang_sudah_ada_membalas_422(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-08-01')->create();
        $kedua = Measurement::factory()->untukAnak($anak)->padaTanggal('2026-08-02')->create();

        $respons = $this->sebagai($kader)
            ->patchJson("/api/kader/measurements/{$kedua->id}", [
                'measurement_date' => '2026-08-01',
            ]);

        $respons->assertStatus(422);
        $respons->assertJsonValidationErrors(['measurement_date']);
        $this->assertDatabaseHas('measurements', [
            'id' => $kedua->id,
            'measurement_date' => '2026-08-02',
        ]);
    }

    #[Test]
    public function koreksi_tanggal_sebelum_lahir_dipangkas_ke_tanggal_lahir(): void
    {
        // Trigger `trg_measurements_who_zscore` tidak melempar pengecualian untuk
        // tanggal yang mendahului tanggal lahir; ia memangkas tanggalnya ke
        // tanggal lahir (lihat migration `2026_10_15_052851`, baris 60). Test
        // ini mengunci perilaku itu supaya tidak dilaporkan sebagai bug.
        $kader = User::factory()->kader()->create();
        $penimbangan = Measurement::factory()->untukAnak($this->anak())
            ->padaTanggal('2026-08-01')->create();

        $respons = $this->sebagai($kader)
            ->patchJson("/api/kader/measurements/{$penimbangan->id}", [
                'measurement_date' => '2023-01-01',
            ]);

        $respons->assertOk();
        $this->assertSame('2024-01-01', $respons->json('data.measurement_date'));
    }

    #[Test]
    public function koreksi_parsial_tidak_mengosongkan_lingkar_kepala(): void
    {
        $kader = User::factory()->kader()->create();
        $penimbangan = Measurement::factory()->untukAnak($this->anak())
            ->padaTanggal('2026-08-01')->create(['head_circumference_cm' => 42.0]);

        $this->sebagai($kader)
            ->patchJson("/api/kader/measurements/{$penimbangan->id}", ['weight_kg' => 10.0])
            ->assertOk();

        $this->assertDatabaseHas('measurements', [
            'id' => $penimbangan->id,
            'weight_kg' => 10,
            'head_circumference_cm' => 42,
        ]);
    }

    #[Test]
    public function koreksi_tidak_memindahkan_penimbangan_ke_anak_lain(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $anakLain = $this->anak();
        $penimbangan = Measurement::factory()->untukAnak($anak)->padaTanggal('2026-08-01')->create();

        $this->sebagai($kader)
            ->patchJson("/api/kader/measurements/{$penimbangan->id}", [
                'child_id' => $anakLain->id,
                'weight_kg' => 10.0,
            ])
            ->assertOk();

        $this->assertDatabaseHas('measurements', [
            'id' => $penimbangan->id,
            'child_id' => $anak->id,
        ]);
        $this->assertDatabaseMissing('measurements', [
            'id' => $penimbangan->id,
            'child_id' => $anakLain->id,
        ]);
    }

    // -----------------------------------------------------------------
    // Helper
    // -----------------------------------------------------------------

    private function anak(): Child
    {
        return Child::factory()->create(['date_of_birth' => '2024-01-01']);
    }

    private function sebagai(User $user): self
    {
        return $this->withHeader('Authorization', 'Bearer '.$user->createToken('uji')->plainTextToken);
    }
}
