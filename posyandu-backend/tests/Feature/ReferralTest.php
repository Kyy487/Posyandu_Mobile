<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\Referral;
use App\Models\User;
use App\Models\Visit;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Menguji entitas rujukan, lihat docs/RANCANGAN_RUJUKAN.md.
 *
 * Endpoint:
 *  - `POST   /referrals`                 (Kader)
 *  - `GET    /children/{id}/referrals`   (Ibu anaknya / Kader)
 *  - `GET    /referrals/{id}`            (pemilik / Kader)
 *  - `PATCH  /referrals/{id}`            (Kader)
 *  - `DELETE /referrals/{id}`            (Kader, soft delete)
 *  - `rujukan` muncul pada `GET /visits/{id}`.
 *
 * Test memakai PostgreSQL sungguhan seperti test lain: yang diuji termasuk
 * soft delete, CHECK constraint `referrals_referral_type_check` /
 * `referrals_status_check`, dan FK penautan kunjungan - perilaku yang tidak ada
 * di SQLite.
 */
class ReferralTest extends TestCase
{
    use RefreshDatabase;

    // =================================================================
    // POST /referrals
    // =================================================================

    #[Test]
    public function kader_membuat_rujukan_membalas_201(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $kunjungan = $this->kunjungan($anak, '2026-08-15');

        $respons = $this->sebagai($kader)->postJson('/api/referrals', [
            'child_id' => $anak->id,
            'visit_id' => $kunjungan->id,
            'referral_date' => '2026-08-15',
            'referral_type' => Referral::TYPE_PUSKESMAS,
            'reason' => '  Demam tinggi lebih dari 3 hari  ',
            'facility_name' => 'Puskesmas Ciputat',
        ]);

        $respons->assertCreated();
        $this->assertTrue($respons->json('success'));
        $this->assertSame($anak->id, $respons->json('data.child_id'));
        $this->assertSame($kunjungan->id, $respons->json('data.visit_id'));
        $this->assertSame('2026-08-15', $respons->json('data.referral_date'));
        $this->assertSame(Referral::TYPE_PUSKESMAS, $respons->json('data.referral_type'));
        // Status default saat tidak dikirim.
        $this->assertSame(Referral::STATUS_DIBUAT, $respons->json('data.status'));
        // Kader yang login otomatis menjadi pencatat.
        $this->assertSame($kader->id, $respons->json('data.kader_id'));
        $this->assertSame($kader->name, $respons->json('data.kader.name'));
        // Teks dirapikan: spasi berlebih dibuang.
        $this->assertSame('Demam tinggi lebih dari 3 hari', $respons->json('data.reason'));

        $this->assertDatabaseHas('referrals', [
            'child_id' => $anak->id,
            'visit_id' => $kunjungan->id,
            'kader_id' => $kader->id,
            'referral_type' => Referral::TYPE_PUSKESMAS,
        ]);
    }

    #[Test]
    public function ibu_tidak_bisa_membuat_rujukan(): void
    {
        $ibu = User::factory()->ibu()->create();
        $anak = Child::factory()->milik($ibu)->create(['date_of_birth' => '2024-01-01']);
        $kunjungan = $this->kunjungan($anak, '2026-08-15');

        $this->sebagai($ibu)->postJson('/api/referrals', [
            'child_id' => $anak->id,
            'visit_id' => $kunjungan->id,
            'referral_date' => '2026-08-15',
            'referral_type' => Referral::TYPE_PUSKESMAS,
            'reason' => 'Demam',
            'facility_name' => 'Puskesmas Ciputat',
        ])->assertForbidden();
    }

    #[Test]
    public function rujukan_tanpa_field_wajib_membalas_422(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $kunjungan = $this->kunjungan($anak, '2026-08-15');

        $respons = $this->sebagai($kader)->postJson('/api/referrals', [
            'child_id' => $anak->id,
            'visit_id' => $kunjungan->id,
        ]);

        $respons->assertStatus(422);
        $respons->assertJsonValidationErrors(['referral_date', 'referral_type', 'reason', 'facility_name']);
    }

    #[Test]
    public function tipe_rujukan_tidak_dikenal_membalas_422(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $kunjungan = $this->kunjungan($anak, '2026-08-15');

        $respons = $this->sebagai($kader)->postJson('/api/referrals', [
            'child_id' => $anak->id,
            'visit_id' => $kunjungan->id,
            'referral_date' => '2026-08-15',
            'referral_type' => 'palsu',
            'reason' => 'Demam',
            'facility_name' => 'Puskesmas Ciputat',
        ]);

        $respons->assertStatus(422);
        $respons->assertJsonValidationErrors(['referral_type']);
    }

    #[Test]
    public function tanggal_rujukan_di_masa_depan_membalas_422(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $kunjungan = $this->kunjungan($anak, '2026-08-15');

        $respons = $this->sebagai($kader)->postJson('/api/referrals', [
            'child_id' => $anak->id,
            'visit_id' => $kunjungan->id,
            'referral_date' => '2030-01-01',
            'referral_type' => Referral::TYPE_RS,
            'reason' => 'Demam',
            'facility_name' => 'RSUD',
        ]);

        $respons->assertStatus(422);
        $respons->assertJsonValidationErrors(['referral_date']);
    }

    #[Test]
    public function rujukan_untuk_kunjungan_anak_lain_membalas_422(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $anakLain = $this->anak();
        $kunjunganAnakLain = $this->kunjungan($anakLain, '2026-08-15');

        $respons = $this->sebagai($kader)->postJson('/api/referrals', [
            'child_id' => $anak->id,
            'visit_id' => $kunjunganAnakLain->id,
            'referral_date' => '2026-08-15',
            'referral_type' => Referral::TYPE_PUSKESMAS,
            'reason' => 'Demam',
            'facility_name' => 'Puskesmas Ciputat',
        ]);

        $respons->assertStatus(422);
        $respons->assertJsonValidationErrors(['visit_id']);
        $this->assertDatabaseCount('referrals', 0);
    }

    #[Test]
    public function rujukan_untuk_anak_tidak_dikenal_membalas_422(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $kunjungan = $this->kunjungan($anak, '2026-08-15');

        $respons = $this->sebagai($kader)->postJson('/api/referrals', [
            'child_id' => '01a135ca-00f7-7000-8000-000000000000',
            'visit_id' => $kunjungan->id,
            'referral_date' => '2026-08-15',
            'referral_type' => Referral::TYPE_PUSKESMAS,
            'reason' => 'Demam',
            'facility_name' => 'Puskesmas Ciputat',
        ]);

        $respons->assertStatus(422);
        $respons->assertJsonValidationErrors(['child_id']);
    }

    // =================================================================
    // GET /children/{id}/referrals
    // =================================================================

    #[Test]
    public function ibu_melihat_daftar_rujukan_anaknya(): void
    {
        $ibu = User::factory()->ibu()->create();
        $anak = Child::factory()->milik($ibu)->create(['date_of_birth' => '2024-01-01']);
        Referral::factory()->untukAnak($anak)->create();

        $respons = $this->sebagai($ibu)->getJson("/api/children/{$anak->id}/referrals");

        $respons->assertOk();
        $this->assertSame($anak->id, $respons->json('data.child.id'));
        $this->assertCount(1, $respons->json('data.referrals'));
    }

    #[Test]
    public function ibu_tidak_bisa_melihat_rujukan_anak_orang_lain(): void
    {
        $ibu = User::factory()->ibu()->create();
        $ibuLain = User::factory()->ibu()->create();
        $anakLain = Child::factory()->milik($ibuLain)->create(['date_of_birth' => '2024-01-01']);
        Referral::factory()->untukAnak($anakLain)->create();

        $this->sebagai($ibu)->getJson("/api/children/{$anakLain->id}/referrals")
            ->assertForbidden();
    }

    #[Test]
    public function kader_bisa_melihat_daftar_rujukan_anak(): void
    {
        $kader = User::factory()->kader()->create();
        $ibu = User::factory()->ibu()->create();
        $anak = Child::factory()->milik($ibu)->create(['date_of_birth' => '2024-01-01']);
        Referral::factory()->untukAnak($anak)->create();

        $respons = $this->sebagai($kader)->getJson("/api/children/{$anak->id}/referrals");

        $respons->assertOk();
        $this->assertCount(1, $respons->json('data.referrals'));
    }

    #[Test]
    public function daftar_rujukan_mengurutkan_terbaru_lebih_dulu(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $kunjungan = $this->kunjungan($anak, '2026-08-15');

        Referral::factory()->untukKunjungan($kunjungan)->padaTanggal('2026-08-01')->create();
        Referral::factory()->untukKunjungan($kunjungan)->padaTanggal('2026-08-20')->create();

        $respons = $this->sebagai($kader)->getJson("/api/children/{$anak->id}/referrals");

        $respons->assertOk();
        $this->assertSame('2026-08-20', $respons->json('data.referrals.0.referral_date'));
        $this->assertSame('2026-08-01', $respons->json('data.referrals.1.referral_date'));
    }

    #[Test]
    public function rujukan_yang_dibatalkan_tidak_muncul_di_daftar(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        Referral::factory()->untukAnak($anak)->dibatalkan()->create();

        $respons = $this->sebagai($kader)->getJson("/api/children/{$anak->id}/referrals");

        $respons->assertOk();
        $this->assertCount(0, $respons->json('data.referrals'));
    }

    // =================================================================
    // GET /referrals/{id}
    // =================================================================

    #[Test]
    public function ibu_bisa_membuka_rujukan_anaknya(): void
    {
        $ibu = User::factory()->ibu()->create();
        $anak = Child::factory()->milik($ibu)->create(['date_of_birth' => '2024-01-01']);
        $rujukan = Referral::factory()->untukAnak($anak)->create();

        $respons = $this->sebagai($ibu)->getJson("/api/referrals/{$rujukan->id}");

        $respons->assertOk();
        $this->assertSame($rujukan->id, $respons->json('data.id'));
    }

    #[Test]
    public function ibu_tidak_bisa_membuka_rujukan_anak_orang_lain(): void
    {
        $ibu = User::factory()->ibu()->create();
        $ibuLain = User::factory()->ibu()->create();
        $anakLain = Child::factory()->milik($ibuLain)->create(['date_of_birth' => '2024-01-01']);
        $rujukan = Referral::factory()->untukAnak($anakLain)->create();

        $this->sebagai($ibu)->getJson("/api/referrals/{$rujukan->id}")
            ->assertForbidden();
    }

    #[Test]
    public function id_rujukan_bukan_uuid_membalas_404(): void
    {
        $kader = User::factory()->kader()->create();

        $this->sebagai($kader)->getJson('/api/referrals/bukan-uuid')
            ->assertNotFound();
    }

    // =================================================================
    // PATCH /referrals/{id}
    // =================================================================

    #[Test]
    public function kader_memperbarui_status_rujukan(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $rujukan = Referral::factory()->untukAnak($anak)->create();

        $respons = $this->sebagai($kader)->patchJson("/api/referrals/{$rujukan->id}", [
            'status' => Referral::STATUS_SELESAI,
        ]);

        $respons->assertOk();
        $this->assertSame(Referral::STATUS_SELESAI, $respons->json('data.status'));
        $this->assertDatabaseHas('referrals', [
            'id' => $rujukan->id,
            'status' => Referral::STATUS_SELESAI,
        ]);
    }

    #[Test]
    public function patch_rujukan_tanpa_field_membalas_422(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $rujukan = Referral::factory()->untukAnak($anak)->create();

        $this->sebagai($kader)->patchJson("/api/referrals/{$rujukan->id}", [])
            ->assertStatus(422);
    }

    // =================================================================
    // DELETE /referrals/{id}
    // =================================================================

    #[Test]
    public function kader_membatalkan_rujukan_dengan_soft_delete(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $rujukan = Referral::factory()->untukAnak($anak)->create();

        $respons = $this->sebagai($kader)->deleteJson("/api/referrals/{$rujukan->id}");

        $respons->assertOk();
        // Baris tidak hilang fisik, hanya ditandai `deleted_at`.
        $this->assertSoftDeleted('referrals', ['id' => $rujukan->id]);
    }

    #[Test]
    public function rujukan_yang_sudah_dibatalkan_membalas_404(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $rujukan = Referral::factory()->untukAnak($anak)->dibatalkan()->create();

        $this->sebagai($kader)->deleteJson("/api/referrals/{$rujukan->id}")
            ->assertNotFound();
    }

    // =================================================================
    // Detail kunjungan
    // =================================================================

    #[Test]
    public function detail_kunjungan_memuat_rujukan_tertaut(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();
        $kunjungan = $this->kunjungan($anak, '2026-08-15');
        $rujukan = Referral::factory()->untukKunjungan($kunjungan)
            ->create(['referral_type' => Referral::TYPE_RS]);

        $respons = $this->sebagai($kader)->getJson("/api/visits/{$kunjungan->id}");

        $respons->assertOk();
        $this->assertCount(1, $respons->json('data.rujukan'));
        $this->assertSame($rujukan->id, $respons->json('data.rujukan.0.id'));
        $this->assertSame(Referral::TYPE_RS, $respons->json('data.rujukan.0.referral_type'));
    }

    // =================================================================
    // Factory
    // =================================================================

    #[Test]
    public function factory_rujukan_default_konsisten_anak_dan_kunjungan(): void
    {
        $rujukan = Referral::factory()->create();

        $this->assertSame(
            $rujukan->visit_id,
            Referral::find($rujukan->id)->visit_id
        );
        $this->assertDatabaseHas('referrals', [
            'id' => $rujukan->id,
            'child_id' => Visit::find($rujukan->visit_id)->child_id,
        ]);
    }

    // -----------------------------------------------------------------
    // Helper
    // -----------------------------------------------------------------

    /** Anak dengan tanggal lahir yang pasti. */
    private function anak(): Child
    {
        return Child::factory()->create(['date_of_birth' => '2024-01-01']);
    }

    /** Kunjungan anak pada tanggal tertentu (`Y-m-d`). */
    private function kunjungan(Child $anak, string $tanggal): Visit
    {
        return Visit::factory()->untukAnak($anak)->padaTanggal($tanggal)->create();
    }

    /** Login lewat Bearer token, sama seperti yang dilakukan mobile. */
    private function sebagai(User $user): self
    {
        return $this->withHeader('Authorization', 'Bearer '.$user->createToken('uji')->plainTextToken);
    }
}
