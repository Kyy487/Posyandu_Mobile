<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\ImmunizationRecord;
use App\Models\ImmunizationType;
use App\Models\Measurement;
use App\Models\MedicalNote;
use App\Models\User;
use App\Models\Visit;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Menguji entitas kunjungan (P0-1), lihat docs/RANCANGAN_VISIT.md.
 *
 * Endpoint:
 *  - `POST   /visits`                 (Kader)
 *  - `GET    /children/{id}/visits`   (Ibu anaknya / Kader)
 *  - `GET    /visits/{id}`            (pemilik / Kader)
 *  - `PATCH  /visits/{id}`            (Kader)
 *  - `visit_id` opsional di endpoint pencatatan penimbangan/imunisasi/keluhan.
 *
 * Test memakai PostgreSQL sungguhan seperti test lain: yang diuji termasuk
 * soft delete, CHECK constraint `visits_visit_type_check`, dan FK penautan -
 * perilaku yang tidak ada di SQLite.
 */
class VisitTest extends TestCase
{
    use RefreshDatabase;

    // =================================================================
    // POST /visits
    // =================================================================

    #[Test]
    public function kader_membuat_kunjungan_membalas_201(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();

        $respons = $this->sebagai($kader)->postJson('/api/visits', [
            'child_id' => $anak->id,
            'visit_date' => '2026-08-15',
            'visit_type' => Visit::VISIT_TYPE_POSYANDU,
            'anamnesis' => '  Demam sejak semalam  ',
        ]);

        $respons->assertCreated();
        $this->assertTrue($respons->json('success'));
        $this->assertSame($anak->id, $respons->json('data.child_id'));
        $this->assertSame('2026-08-15', $respons->json('data.visit_date'));
        $this->assertSame(Visit::VISIT_TYPE_POSYANDU, $respons->json('data.visit_type'));
        // Kader yang login otomatis menjadi pemegang kunjungan.
        $this->assertSame($kader->id, $respons->json('data.kader_id'));
        $this->assertSame($kader->name, $respons->json('data.kader.name'));
        // Teks dirapikan: spasi berlebih dibuang.
        $this->assertSame('Demam sejak semalam', $respons->json('data.anamnesis'));

        $this->assertDatabaseHas('visits', [
            'child_id' => $anak->id,
            'kader_id' => $kader->id,
            'visit_type' => Visit::VISIT_TYPE_POSYANDU,
        ]);
    }

    #[Test]
    public function ibu_tidak_bisa_membuat_kunjungan(): void
    {
        $ibu = User::factory()->ibu()->create();
        $anak = Child::factory()->milik($ibu)->create(['date_of_birth' => '2024-01-01']);

        $this->sebagai($ibu)->postJson('/api/visits', [
            'child_id' => $anak->id,
            'visit_date' => '2026-08-15',
            'visit_type' => Visit::VISIT_TYPE_POSYANDU,
        ])->assertForbidden();
    }

    #[Test]
    public function kunjungan_tanpa_field_wajib_membalas_422(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();

        $respons = $this->sebagai($kader)->postJson('/api/visits', [
            'child_id' => $anak->id,
        ]);

        $respons->assertStatus(422);
        $respons->assertJsonValidationErrors(['visit_date', 'visit_type']);
    }

    #[Test]
    public function tipe_kunjungan_tidak_dikenal_membalas_422(): void
    {
        $kader = User::factory()->kader()->create();

        $respons = $this->sebagai($kader)->postJson('/api/visits', [
            'child_id' => $this->anak()->id,
            'visit_date' => '2026-08-15',
            'visit_type' => 'palsu',
        ]);

        $respons->assertStatus(422);
        $respons->assertJsonValidationErrors(['visit_type']);
    }

    #[Test]
    public function tanggal_kunjungan_di_masa_depan_membalas_422(): void
    {
        $kader = User::factory()->kader()->create();

        $respons = $this->sebagai($kader)->postJson('/api/visits', [
            'child_id' => $this->anak()->id,
            'visit_date' => '2030-01-01',
            'visit_type' => Visit::VISIT_TYPE_POSYANDU,
        ]);

        $respons->assertStatus(422);
        $respons->assertJsonValidationErrors(['visit_date']);
    }

    #[Test]
    public function kunjungan_untuk_anak_tidak_dikenal_membalas_422(): void
    {
        $kader = User::factory()->kader()->create();

        $respons = $this->sebagai($kader)->postJson('/api/visits', [
            'child_id' => '00000000-0000-0000-0000-000000000000',
            'visit_date' => '2026-08-15',
            'visit_type' => Visit::VISIT_TYPE_POSYANDU,
        ]);

        $respons->assertStatus(422);
        $respons->assertJsonValidationErrors(['child_id']);
    }

    // =================================================================
    // GET /children/{id}/visits
    // =================================================================

    #[Test]
    public function daftar_kunjungan_urut_dari_tanggal_terbaru(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();

        foreach (['2026-05-10', '2026-08-20', '2026-06-15'] as $tanggal) {
            Visit::factory()->untukAnak($anak)->olehKader($kader)->padaTanggal($tanggal)->create();
        }

        $respons = $this->sebagai($kader)->getJson("/api/children/{$anak->id}/visits");

        $respons->assertOk();
        $this->assertSame($anak->id, $respons->json('data.child.id'));
        $this->assertSame(
            ['2026-08-20', '2026-06-15', '2026-05-10'],
            array_column($respons->json('data.visits'), 'visit_date')
        );
    }

    #[Test]
    public function daftar_kunjungan_menyertakan_jumlah_data_tertaut(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $kunjungan = Visit::factory()->untukAnak($anak)->olehKader($kader)
            ->padaTanggal('2026-08-01')->create();

        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-08-01')
            ->create(['visit_id' => $kunjungan->id]);
        ImmunizationRecord::factory()->untukAnak($anak)->untukDosis(ImmunizationType::factory()->create())
            ->padaTanggal('2026-08-01')->create(['visit_id' => $kunjungan->id]);
        MedicalNote::factory()->untukAnak($anak)->demam()
            ->create(['note_date' => '2026-08-01', 'visit_id' => $kunjungan->id]);

        $respons = $this->sebagai($kader)->getJson("/api/children/{$anak->id}/visits");

        $respons->assertOk();
        $this->assertSame(1, $respons->json('data.visits.0.jumlah_pengukuran'));
        $this->assertSame(1, $respons->json('data.visits.0.jumlah_imunisasi'));
        $this->assertSame(1, $respons->json('data.visits.0.jumlah_keluhan'));
    }

    #[Test]
    public function ibu_melihat_daftar_kunjungan_anaknya_sendiri(): void
    {
        $ibu = User::factory()->ibu()->create();
        $anak = Child::factory()->milik($ibu)->create(['date_of_birth' => '2024-01-01']);
        Visit::factory()->untukAnak($anak)->padaTanggal('2026-08-01')->create();

        $respons = $this->sebagai($ibu)->getJson("/api/children/{$anak->id}/visits");

        $respons->assertOk();
        $this->assertCount(1, $respons->json('data.visits'));
    }

    #[Test]
    public function ibu_melihat_daftar_kunjungan_anak_orang_ditolak(): void
    {
        $ibu = User::factory()->ibu()->create();
        $ibuLain = User::factory()->ibu()->create();
        $anakOrangLain = Child::factory()->milik($ibuLain)->create(['date_of_birth' => '2024-01-01']);

        $this->sebagai($ibu)
            ->getJson("/api/children/{$anakOrangLain->id}/visits")
            ->assertForbidden();
    }

    #[Test]
    public function id_anak_bukan_uuid_membalas_404(): void
    {
        $kader = User::factory()->kader()->create();

        $this->sebagai($kader)->getJson('/api/children/bukan-uuid/visits')->assertNotFound();
    }

    // =================================================================
    // GET /visits/{id}
    // =================================================================

    #[Test]
    public function detail_kunjungan_menyertakan_data_tertaut(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $kunjungan = Visit::factory()->untukAnak($anak)->olehKader($kader)
            ->padaTanggal('2026-08-01')->create();

        $dosis = ImmunizationType::factory()->create(['code' => 'BCG']);

        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-08-01')
            ->create(['visit_id' => $kunjungan->id]);
        ImmunizationRecord::factory()->untukAnak($anak)->untukDosis($dosis)
            ->padaTanggal('2026-08-01')->create(['visit_id' => $kunjungan->id]);
        MedicalNote::factory()->untukAnak($anak)->demam()
            ->create(['note_date' => '2026-08-01', 'visit_id' => $kunjungan->id]);

        $respons = $this->sebagai($kader)->getJson("/api/visits/{$kunjungan->id}");

        $respons->assertOk();
        $this->assertSame($kunjungan->id, $respons->json('data.id'));
        $this->assertCount(1, $respons->json('data.pengukuran'));
        $this->assertCount(1, $respons->json('data.imunisasi'));
        $this->assertCount(1, $respons->json('data.catatan_keluhan'));
        $this->assertSame('BCG', $respons->json('data.imunisasi.0.type'));
        $this->assertTrue($respons->json('data.catatan_keluhan.0.demam'));
    }

    #[Test]
    public function ibu_membuka_kunjungan_anak_orang_ditolak(): void
    {
        $ibu = User::factory()->ibu()->create();
        $ibuLain = User::factory()->ibu()->create();
        $anakOrangLain = Child::factory()->milik($ibuLain)->create(['date_of_birth' => '2024-01-01']);
        $kunjungan = Visit::factory()->untukAnak($anakOrangLain)->padaTanggal('2026-08-01')->create();

        $this->sebagai($ibu)->getJson("/api/visits/{$kunjungan->id}")->assertForbidden();
    }

    #[Test]
    public function ibu_membuka_kunjungan_anaknya_sendiri(): void
    {
        $ibu = User::factory()->ibu()->create();
        $anak = Child::factory()->milik($ibu)->create(['date_of_birth' => '2024-01-01']);
        $kunjungan = Visit::factory()->untukAnak($anak)->padaTanggal('2026-08-01')->create();

        $this->sebagai($ibu)->getJson("/api/visits/{$kunjungan->id}")->assertOk();
    }

    #[Test]
    public function kunjungan_bukan_uuid_membalas_404(): void
    {
        $kader = User::factory()->kader()->create();

        $this->sebagai($kader)->getJson('/api/visits/bukan-uuid')->assertNotFound();
    }

    #[Test]
    public function kunjungan_yang_dibatalkan_tidak_bisa_dibuka(): void
    {
        $kader = User::factory()->kader()->create();
        $kunjungan = Visit::factory()->untukAnak($this->anak())->dibatalkan()->create();

        $this->sebagai($kader)->getJson("/api/visits/{$kunjungan->id}")->assertNotFound();
    }

    #[Test]
    public function kunjungan_yang_dibatalkan_hilang_dari_daftar(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();

        Visit::factory()->untukAnak($anak)->padaTanggal('2026-08-01')->create();
        Visit::factory()->untukAnak($anak)->padaTanggal('2026-08-02')->dibatalkan()->create();

        $respons = $this->sebagai($kader)->getJson("/api/children/{$anak->id}/visits");

        $respons->assertOk();
        $this->assertSame(
            ['2026-08-01'],
            array_column($respons->json('data.visits'), 'visit_date')
        );
    }

    // =================================================================
    // PATCH /visits/{id}
    // =================================================================

    #[Test]
    public function kader_memperbarui_anamnesis_kunjungan(): void
    {
        $kader = User::factory()->kader()->create();
        $kunjungan = Visit::factory()->untukAnak($this->anak())->padaTanggal('2026-08-01')->create();

        $respons = $this->sebagai($kader)->patchJson("/api/visits/{$kunjungan->id}", [
            'anamnesis' => 'Batuk pilek',
        ]);

        $respons->assertOk();
        $this->assertSame('Batuk pilek', $respons->json('data.anamnesis'));
        $this->assertSame('Batuk pilek', $kunjungan->fresh()->anamnesis);
    }

    #[Test]
    public function patch_tanpa_data_membalas_422(): void
    {
        $kader = User::factory()->kader()->create();
        $kunjungan = Visit::factory()->untukAnak($this->anak())->create();

        $this->sebagai($kader)
            ->patchJson("/api/visits/{$kunjungan->id}", [])
            ->assertStatus(422);
    }

    #[Test]
    public function ibu_tidak_bisa_memperbarui_kunjungan(): void
    {
        $ibu = User::factory()->ibu()->create();
        $anak = Child::factory()->milik($ibu)->create(['date_of_birth' => '2024-01-01']);
        $kunjungan = Visit::factory()->untukAnak($anak)->padaTanggal('2026-08-01')->create();

        $this->sebagai($ibu)
            ->patchJson("/api/visits/{$kunjungan->id}", ['anamnesis' => 'x'])
            ->assertForbidden();
    }

    // =================================================================
    // Penautan visit_id di endpoint pencatatan
    // =================================================================

    #[Test]
    public function penimbangan_dapat_ditautkan_ke_kunjungan(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $kunjungan = Visit::factory()->untukAnak($anak)->padaTanggal('2026-08-01')->create();

        $respons = $this->sebagai($kader)->postJson('/api/kader/measurements', [
            'child_id' => $anak->id,
            'measurement_date' => '2026-08-01',
            'weight_kg' => 10.5,
            'height_cm' => 80,
            'visit_id' => $kunjungan->id,
        ]);

        $respons->assertCreated();
        $this->assertSame($kunjungan->id, $respons->json('data.visit_id'));
        $this->assertDatabaseHas('measurements', [
            'child_id' => $anak->id,
            'visit_id' => $kunjungan->id,
        ]);
    }

    #[Test]
    public function penimbangan_tanpa_visit_id_tetap_bisa_disimpan(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();

        $respons = $this->sebagai($kader)->postJson('/api/kader/measurements', [
            'child_id' => $anak->id,
            'measurement_date' => '2026-08-01',
            'weight_kg' => 10.5,
            'height_cm' => 80,
        ]);

        $respons->assertCreated();
        $this->assertNull($respons->json('data.visit_id'));
    }

    #[Test]
    public function penimbangan_menolak_kunjungan_anak_lain(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $anakLain = $this->anak();
        $kunjunganAnakLain = Visit::factory()->untukAnak($anakLain)->padaTanggal('2026-08-01')->create();

        $respons = $this->sebagai($kader)->postJson('/api/kader/measurements', [
            'child_id' => $anak->id,
            'measurement_date' => '2026-08-01',
            'weight_kg' => 10.5,
            'height_cm' => 80,
            'visit_id' => $kunjunganAnakLain->id,
        ]);

        $respons->assertStatus(422);
        $respons->assertJsonValidationErrors(['visit_id']);
        $this->assertDatabaseMissing('measurements', ['visit_id' => $kunjunganAnakLain->id]);
    }

    #[Test]
    public function imunisasi_dapat_ditautkan_ke_kunjungan(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $kunjungan = Visit::factory()->untukAnak($anak)->padaTanggal('2026-08-01')->create();
        $dosis = ImmunizationType::factory()->create();

        $respons = $this->sebagai($kader)->postJson("/api/kader/children/{$anak->id}/immunizations", [
            'immunization_type_id' => $dosis->id,
            'date_given' => '2026-08-01',
            'visit_id' => $kunjungan->id,
        ]);

        $respons->assertCreated();
        $this->assertSame($kunjungan->id, $respons->json('data.visit_id'));
        $this->assertDatabaseHas('immunization_records', [
            'child_id' => $anak->id,
            'visit_id' => $kunjungan->id,
        ]);
    }

    #[Test]
    public function keluhan_dapat_ditautkan_ke_kunjungan(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $kunjungan = Visit::factory()->untukAnak($anak)->padaTanggal('2026-08-01')->create();

        $respons = $this->sebagai($kader)->postJson("/api/kader/children/{$anak->id}/medical-notes", [
            'note_date' => '2026-08-01',
            'demam' => true,
            'visit_id' => $kunjungan->id,
        ]);

        $respons->assertCreated();
        $this->assertSame($kunjungan->id, $respons->json('data.visit_id'));
        $this->assertDatabaseHas('medical_notes', [
            'child_id' => $anak->id,
            'visit_id' => $kunjungan->id,
        ]);
    }

    #[Test]
    public function keluhan_menolak_kunjungan_anak_lain(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $anakLain = $this->anak();
        $kunjunganAnakLain = Visit::factory()->untukAnak($anakLain)->padaTanggal('2026-08-01')->create();

        $respons = $this->sebagai($kader)->postJson("/api/kader/children/{$anak->id}/medical-notes", [
            'note_date' => '2026-08-01',
            'demam' => true,
            'visit_id' => $kunjunganAnakLain->id,
        ]);

        $respons->assertStatus(422);
        $respons->assertJsonValidationErrors(['visit_id']);
        $this->assertDatabaseMissing('medical_notes', ['visit_id' => $kunjunganAnakLain->id]);
    }

    // -----------------------------------------------------------------
    // Helper
    // -----------------------------------------------------------------

    /**
     * Anak dengan tanggal lahir yang pasti.
     *
     * Tanggal lahir acak dari `ChildFactory` bisa jatuh setelah tanggal
     * penimbangan yang di-hardcode, dan trigger z-score akan menolaknya sebagai
     * 500 - bukan karena kode salah. Ditetapkan di sini supaya test tidak rapuh.
     */
    private function anak(): Child
    {
        return Child::factory()->create(['date_of_birth' => '2024-01-01']);
    }

    /** Login lewat Bearer token, sama seperti yang dilakukan mobile. */
    private function sebagai(User $user): self
    {
        return $this->withHeader('Authorization', 'Bearer '.$user->createToken('uji')->plainTextToken);
    }
}
