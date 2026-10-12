<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\ImmunizationRecord;
use App\Models\ImmunizationType;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Menguji endpoint FHIR R4 — jembatan integrasi SATUSEHAT.
 *
 * Yang diuji:
 *  - Mapper menghasilkan struktur FHIR R4 yang benar
 *  - Endpoint baca mengembalikan data dalam format FHIR
 *  - Endpoint kirim mencatat payload ke log (kredensial belum diisi)
 *  - Endpoint hanya untuk Kader
 */
class FhirTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function endpoint_patient_mengembalikan_fhir_r4(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create([
            'date_of_birth' => '2024-01-01',
            'name' => 'Budi Santoso',
            'gender' => 'L',
            'nik' => '3201234567890123',
        ]);

        $this->actingAs($kader, 'sanctum')
            ->getJson("/api/kader/fhir/Patient/{$anak->id}")
            ->assertOk()
            ->assertJsonPath('resourceType', 'Patient')
            ->assertJsonPath('name.0.text', 'Budi Santoso')
            ->assertJsonPath('gender', 'male')
            ->assertJsonPath('birthDate', '2024-01-01');
    }

    #[Test]
    public function endpoint_immunization_mengembalikan_fhir_r4(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01']);
        $dosis = ImmunizationType::factory()->dosisPertama('Hepatitis B', 'HB')->create();

        $record = ImmunizationRecord::factory()
            ->untukAnak($anak)
            ->untukDosis($dosis)
            ->olehKader($kader)
            ->padaTanggal('2025-10-01')
            ->create();

        $this->actingAs($kader, 'sanctum')
            ->getJson("/api/kader/fhir/Immunization/{$record->id}")
            ->assertOk()
            ->assertJsonPath('resourceType', 'Immunization')
            ->assertJsonPath('status', 'completed')
            ->assertJsonPath('vaccineCode.coding.0.code', 'HB');
    }

    #[Test]
    public function endpoint_kirim_mencatat_payload_ke_log(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01']);

        $this->actingAs($kader, 'sanctum')
            ->postJson("/api/kader/fhir/Patient/{$anak->id}/send")
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.resourceType', 'Patient');
    }

    #[Test]
    public function endpoint_fhir_hanya_untuk_kader(): void
    {
        $ibu = User::factory()->ibu()->create();
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01']);

        $this->actingAs($ibu, 'sanctum')
            ->getJson("/api/kader/fhir/Patient/{$anak->id}")
            ->assertForbidden();
    }

    #[Test]
    public function endpoint_fhir_menolak_resource_type_tidak_dikenal(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01']);

        $this->actingAs($kader, 'sanctum')
            ->getJson("/api/kader/fhir/UnknownResource/{$anak->id}")
            ->assertUnprocessable();
    }

    #[Test]
    public function endpoint_fhir_mengembalikan_404_untuk_id_tidak_ada(): void
    {
        $kader = User::factory()->kader()->create();

        $this->actingAs($kader, 'sanctum')
            ->getJson('/api/kader/fhir/Patient/00000000-0000-0000-0000-000000000000')
            ->assertNotFound();
    }
}
