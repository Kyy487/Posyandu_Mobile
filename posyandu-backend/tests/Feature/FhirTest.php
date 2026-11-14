<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\ImmunizationRecord;
use App\Models\ImmunizationType;
use App\Models\Measurement;
use App\Models\User;
use App\Models\Visit;
use Carbon\CarbonImmutable;
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
            'ihs_number' => 'IHS-ANAK-001',
        ]);

        $this->actingAs($kader, 'sanctum')
            ->getJson("/api/kader/fhir/Patient/{$anak->id}")
            ->assertOk()
            ->assertJsonPath('resourceType', 'Patient')
            ->assertJsonPath('name.0.text', 'Budi Santoso')
            ->assertJsonPath('gender', 'male')
            ->assertJsonPath('birthDate', '2024-01-01')
            ->assertJsonPath('id', 'IHS-ANAK-001')
            ->assertJsonPath('identifier.0.system', 'https://fhir.kemkes.go.id/id/nik');
    }

    #[Test]
    public function endpoint_immunization_mengembalikan_fhir_r4(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create([
            'date_of_birth' => '2024-01-01',
            'ihs_number' => 'IHS-ANAK-001',
        ]);
        $dosis = ImmunizationType::factory()->dosisPertama('Hepatitis B', 'HB')->create([
            'kfa_code' => 'KFA-001',
            'cvx_code' => '03',
            'cvx_display' => 'Hep B',
        ]);

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
            ->assertJsonPath('vaccineCode.coding.0.system', 'http://sys-ids.kemkes.go.id/kfa')
            ->assertJsonPath('vaccineCode.coding.0.code', 'KFA-001')
            ->assertJsonPath('vaccineCode.coding.1.system', 'http://hl7.org/fhir/sid/cvx')
            ->assertJsonPath('vaccineCode.coding.1.code', '03')
            ->assertJsonPath('patient.reference', 'Patient/IHS-ANAK-001');
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

    #[Test]
    public function validate_patient_melaporkan_ihs_kosong(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create([
            'date_of_birth' => '2024-01-01',
            'name' => 'Budi Santoso',
            'nik' => '3201234567890123',
            'ihs_number' => null,
        ]);

        $response = $this->actingAs($kader, 'sanctum')
            ->getJson("/api/kader/fhir/Patient/{$anak->id}/validate");

        $response->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.valid', false);

        $this->assertContains('Patient.id (IHS number) wajib ada.', $response->json('data.errors'));
    }

    #[Test]
    public function validate_patient_valid_dengan_ihs_lengkap(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create([
            'date_of_birth' => '2024-01-01',
            'name' => 'Budi Santoso',
            'nik' => '3201234567890123',
            'ihs_number' => 'IHS-ANAK-001',
        ]);

        $this->actingAs($kader, 'sanctum')
            ->getJson("/api/kader/fhir/Patient/{$anak->id}/validate")
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.valid', true);
    }

    #[Test]
    public function validate_immunization_menolak_tanpa_mapping_kfa_cvx(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create([
            'date_of_birth' => '2024-01-01',
            'ihs_number' => 'IHS-ANAK-001',
        ]);
        $dosis = ImmunizationType::factory()->dosisPertama('Hepatitis B', 'HB')->create([
            'kfa_code' => null,
            'cvx_code' => null,
        ]);

        $record = ImmunizationRecord::factory()
            ->untukAnak($anak)
            ->untukDosis($dosis)
            ->olehKader($kader)
            ->padaTanggal('2025-10-01')
            ->create();

        $response = $this->actingAs($kader, 'sanctum')
            ->getJson("/api/kader/fhir/Immunization/{$record->id}/validate");

        $response->assertOk()
            ->assertJsonPath('data.valid', false);

        $this->assertContains(
            'Immunization.vaccineCode wajib punya mapping KFA atau CVX.',
            $response->json('data.errors'),
        );
    }

    #[Test]
    public function validate_immunization_valid_dengan_mapping_cvx(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create([
            'date_of_birth' => '2024-01-01',
            'ihs_number' => 'IHS-ANAK-001',
        ]);
        $dosis = ImmunizationType::factory()->dosisPertama('Hepatitis B', 'HB')->create([
            'cvx_code' => '03',
        ]);

        $record = ImmunizationRecord::factory()
            ->untukAnak($anak)
            ->untukDosis($dosis)
            ->olehKader($kader)
            ->padaTanggal('2025-10-01')
            ->create();

        $this->actingAs($kader, 'sanctum')
            ->getJson("/api/kader/fhir/Immunization/{$record->id}/validate")
            ->assertOk()
            ->assertJsonPath('data.valid', true);
    }

    #[Test]
    public function endpoint_encounter_mengirim_waktu_dalam_utc(): void
    {
        config(['services.satusehat.org_id' => 'ORG-001']);

        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create([
            'date_of_birth' => '2024-01-01',
            'ihs_number' => 'IHS-ANAK-001',
        ]);
        $kunjungan = Visit::factory()
            ->untukAnak($anak)
            ->olehKader($kader)
            ->create([
                'visit_date' => '2026-08-01',
                'visit_started_at' => CarbonImmutable::parse('2026-08-01 08:30:00', 'Asia/Jakarta'),
                'visit_ended_at' => CarbonImmutable::parse('2026-08-01 09:00:00', 'Asia/Jakarta'),
            ]);

        $this->actingAs($kader, 'sanctum')
            ->getJson("/api/kader/fhir/Encounter/{$kunjungan->id}")
            ->assertOk()
            ->assertJsonPath('resourceType', 'Encounter')
            ->assertJsonPath('status', 'finished')
            ->assertJsonPath('subject.reference', 'Patient/IHS-ANAK-001')
            ->assertJsonPath('period.start', '2026-08-01T01:30:00Z')
            ->assertJsonPath('period.end', '2026-08-01T02:00:00Z')
            ->assertJsonPath('serviceProvider.reference', 'Organization/ORG-001');
    }

    #[Test]
    public function endpoint_encounter_memakai_visit_date_bila_waktu_mulai_kosong(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create([
            'date_of_birth' => '2024-01-01',
            'ihs_number' => 'IHS-ANAK-001',
        ]);
        $kunjungan = Visit::factory()
            ->untukAnak($anak)
            ->olehKader($kader)
            ->padaTanggal('2026-08-01')
            ->create(['visit_started_at' => null]);

        $this->actingAs($kader, 'sanctum')
            ->getJson("/api/kader/fhir/Encounter/{$kunjungan->id}")
            ->assertOk()
            ->assertJsonPath('status', 'in-progress')
            ->assertJsonPath('period.start', '2026-07-31T17:00:00Z');
    }

    #[Test]
    public function endpoint_observation_memakai_measured_at_dalam_utc(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create([
            'date_of_birth' => '2024-01-01',
            'ihs_number' => 'IHS-ANAK-001',
        ]);
        $kunjungan = Visit::factory()->untukAnak($anak)->olehKader($kader)->create();
        $pengukuran = Measurement::factory()
            ->untukAnak($anak)
            ->olehKader($kader)
            ->padaTanggal('2026-08-01')
            ->create([
                'visit_id' => $kunjungan->id,
                'height_cm' => 88.5,
                'measured_at' => CarbonImmutable::parse('2026-08-01 08:30:00', 'Asia/Jakarta'),
            ]);

        $this->actingAs($kader, 'sanctum')
            ->getJson("/api/kader/fhir/Observation/{$pengukuran->id}")
            ->assertOk()
            ->assertJsonPath('resourceType', 'Observation')
            ->assertJsonPath('code.coding.0.code', '8302-2')
            ->assertJsonPath('subject.reference', 'Patient/IHS-ANAK-001')
            ->assertJsonPath('encounter.reference', "Encounter/{$kunjungan->id}")
            ->assertJsonPath('effectiveDateTime', '2026-08-01T01:30:00Z')
            ->assertJsonPath('valueQuantity.value', '88.50')
            ->assertJsonPath('valueQuantity.code', 'cm');
    }

    #[Test]
    public function endpoint_observation_bundle_memuat_semua_pengukuran(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create([
            'date_of_birth' => '2024-01-01',
            'ihs_number' => 'IHS-ANAK-001',
        ]);
        $kunjungan = Visit::factory()->untukAnak($anak)->olehKader($kader)->create();
        $pengukuran = Measurement::factory()
            ->untukAnak($anak)
            ->olehKader($kader)
            ->padaTanggal('2026-08-01')
            ->create([
                'visit_id' => $kunjungan->id,
                'weight_kg' => 10.5,
                'height_cm' => 80.0,
                'head_circumference_cm' => 45.0,
            ]);

        $response = $this->actingAs($kader, 'sanctum')
            ->getJson("/api/kader/fhir/Observation/{$pengukuran->id}/bundle");

        $response->assertOk()
            ->assertJsonPath('resourceType', 'Bundle')
            ->assertJsonPath('type', 'collection')
            ->assertJsonCount(4, 'entry')
            ->assertJsonPath('entry.0.resource.subject.reference', 'Patient/IHS-ANAK-001')
            ->assertJsonPath('entry.0.resource.encounter.reference', "Encounter/{$kunjungan->id}")
            ->assertJsonPath('entry.1.resource.valueQuantity.value', '10.50')
            ->assertJsonPath('entry.1.resource.valueQuantity.code', 'kg')
            ->assertJsonPath('entry.2.resource.valueQuantity.value', '45.00')
            ->assertJsonPath('entry.3.resource.valueQuantity.value', 16.41)
            ->assertJsonPath('entry.3.resource.valueQuantity.code', 'kg/m2');

        $this->assertSame(
            ['8302-2', '29463-7', '9843-4', '39156-5'],
            collect($response->json('entry'))
                ->pluck('resource.code.coding.0.code')
                ->all(),
        );
    }

    #[Test]
    public function validate_observation_bundle_menolak_tanpa_encounter(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create([
            'date_of_birth' => '2024-01-01',
            'ihs_number' => 'IHS-ANAK-001',
        ]);
        $pengukuran = Measurement::factory()
            ->untukAnak($anak)
            ->olehKader($kader)
            ->padaTanggal('2026-08-01')
            ->create(['visit_id' => null]);

        $response = $this->actingAs($kader, 'sanctum')
            ->getJson("/api/kader/fhir/Observation/{$pengukuran->id}/bundle/validate");

        $response->assertOk()
            ->assertJsonPath('data.valid', false);

        $this->assertContains(
            'Observation.encounter.reference wajib ada.',
            $response->json('data.errors'),
        );
    }

    #[Test]
    public function validate_observation_bundle_valid_dengan_encounter(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create([
            'date_of_birth' => '2024-01-01',
            'ihs_number' => 'IHS-ANAK-001',
        ]);
        $kunjungan = Visit::factory()->untukAnak($anak)->olehKader($kader)->create();
        $pengukuran = Measurement::factory()
            ->untukAnak($anak)
            ->olehKader($kader)
            ->padaTanggal('2026-08-01')
            ->create(['visit_id' => $kunjungan->id]);

        $this->actingAs($kader, 'sanctum')
            ->getJson("/api/kader/fhir/Observation/{$pengukuran->id}/bundle/validate")
            ->assertOk()
            ->assertJsonPath('data.valid', true);
    }

    #[Test]
    public function validate_observation_menolak_tanpa_encounter(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create([
            'date_of_birth' => '2024-01-01',
            'ihs_number' => 'IHS-ANAK-001',
        ]);
        $pengukuran = Measurement::factory()
            ->untukAnak($anak)
            ->olehKader($kader)
            ->padaTanggal('2026-08-01')
            ->create(['visit_id' => null]);

        $response = $this->actingAs($kader, 'sanctum')
            ->getJson("/api/kader/fhir/Observation/{$pengukuran->id}/validate");

        $response->assertOk()
            ->assertJsonPath('data.valid', false);

        $this->assertContains(
            'Observation.encounter.reference wajib ada.',
            $response->json('data.errors'),
        );
    }
}
