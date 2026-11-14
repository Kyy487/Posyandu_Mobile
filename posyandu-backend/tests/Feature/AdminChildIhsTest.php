<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Child;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Tests\TestCase;

class AdminChildIhsTest extends TestCase
{
    use RefreshDatabase;

    public function test_admin_dapat_mengoreksi_ihs_dan_audit_tercatat(): void
    {
        $admin = User::factory()->admin()->create();
        $child = Child::factory()->create(['ihs_number' => null]);

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/admin/children/{$child->id}/ihs", [
                'ihs_number' => ' IHS-001 ',
                'reason' => 'Koreksi hasil verifikasi.',
            ])
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.ihs_number', 'IHS-001');

        $this->assertDatabaseHas('children', [
            'id' => $child->id,
            'ihs_number' => 'IHS-001',
        ]);

        $audit = AuditLog::query()
            ->where('event', 'updated')
            ->where('auditable_id', $child->id)
            ->sole();

        $this->assertSame('updated', $audit->event);
        $this->assertSame($admin->id, $audit->actor_id);
        $this->assertSame(['ihs_number' => null], $audit->old_values);
        $this->assertEquals([
            'ihs_number' => 'IHS-001',
            'reason' => 'Koreksi hasil verifikasi.',
        ], $audit->new_values);
    }

    public function test_admin_tidak_dapat_memakai_ihs_yang_sudah_dipakai(): void
    {
        $admin = User::factory()->admin()->create();
        Child::factory()->create(['ihs_number' => 'IHS-001']);
        $child = Child::factory()->create(['ihs_number' => null]);

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/admin/children/{$child->id}/ihs", [
                'ihs_number' => 'IHS-001',
                'reason' => 'Koreksi.',
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('ihs_number');
    }

    public function test_alasan_koreksi_wajib_diisi(): void
    {
        $admin = User::factory()->admin()->create();
        $child = Child::factory()->create(['ihs_number' => null]);

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/admin/children/{$child->id}/ihs", [
                'ihs_number' => 'IHS-001',
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('reason');
    }

    public function test_kader_dan_ibu_tidak_dapat_mengakses_endpoint_admin(): void
    {
        $child = Child::factory()->create();

        foreach ([
            User::factory()->kader()->create(),
            User::factory()->ibu()->create(),
        ] as $user) {
            $this->actingAs($user, 'sanctum')
                ->patchJson("/api/admin/children/{$child->id}/ihs", [
                    'ihs_number' => 'IHS-001',
                    'reason' => 'Koreksi.',
                ])
                ->assertForbidden();
        }
    }

    public function test_import_dry_run_tidak_mengubah_data(): void
    {
        $admin = User::factory()->admin()->create();
        $child = Child::factory()->create(['ihs_number' => null]);

        $response = $this->actingAs($admin, 'sanctum')->post('/api/admin/children/ihs/import', [
            'file' => $this->csv("child_id,ihs_number\n{$child->id},IHS-001\n"),
            'dry_run' => true,
        ]);

        $response->assertOk()
            ->assertJsonPath('data.dry_run', true)
            ->assertJsonPath('data.total', 1)
            ->assertJsonPath('data.updated', 1)
            ->assertJsonPath('data.failed', 0);

        $this->assertNull($child->fresh()->ihs_number);
        $this->assertSame(0, AuditLog::query()
            ->where('event', 'updated')
            ->where('auditable_id', $child->id)
            ->count());
    }

    public function test_import_menyimpan_ihs_dan_audit(): void
    {
        $admin = User::factory()->admin()->create();
        $child = Child::factory()->create(['ihs_number' => null]);

        $this->actingAs($admin, 'sanctum')->post('/api/admin/children/ihs/import', [
            'file' => $this->csv("child_id,ihs_number\n{$child->id},IHS-001\n"),
        ])->assertOk()
            ->assertJsonPath('data.updated', 1)
            ->assertJsonPath('data.failed', 0);

        $this->assertSame('IHS-001', $child->fresh()->ihs_number);
        $this->assertSame(1, AuditLog::query()
            ->where('event', 'updated')
            ->where('auditable_id', $child->id)
            ->count());
    }

    public function test_import_mencari_anak_lewat_nik_dan_tanggal_lahir(): void
    {
        $admin = User::factory()->admin()->create();
        $child = Child::factory()->create([
            'nik' => '3273012345678901',
            'date_of_birth' => '2024-01-01',
            'ihs_number' => null,
        ]);

        $this->actingAs($admin, 'sanctum')->post('/api/admin/children/ihs/import', [
            'file' => $this->csv(
                "nik_anak,tanggal_lahir,ihs_number\n"
                ."3273012345678901,2024-01-01,IHS-001\n"
            ),
        ])->assertOk()
            ->assertJsonPath('data.updated', 1)
            ->assertJsonPath('data.failed', 0);

        $this->assertSame('IHS-001', $child->fresh()->ihs_number);
    }

    public function test_import_menolak_ihs_duplikat_di_file(): void
    {
        $admin = User::factory()->admin()->create();
        $anakA = Child::factory()->create(['ihs_number' => null]);
        $anakB = Child::factory()->create(['ihs_number' => null]);

        $this->actingAs($admin, 'sanctum')->post('/api/admin/children/ihs/import', [
            'file' => $this->csv(
                "child_id,ihs_number\n"
                ."{$anakA->id},IHS-001\n"
                ."{$anakB->id},IHS-001\n"
            ),
            'dry_run' => true,
        ])->assertOk()
            ->assertJsonPath('data.total', 2)
            ->assertJsonPath('data.updated', 1)
            ->assertJsonPath('data.failed', 1)
            ->assertJsonPath('data.errors.0.line', 3);
    }

    public function test_import_menolak_timpa_ihs_lama_tanpa_mode_koreksi(): void
    {
        $admin = User::factory()->admin()->create();
        $child = Child::factory()->create(['ihs_number' => 'IHS-LAMA']);

        $this->actingAs($admin, 'sanctum')->post('/api/admin/children/ihs/import', [
            'file' => $this->csv("child_id,ihs_number\n{$child->id},IHS-BARU\n"),
        ])->assertOk()
            ->assertJsonPath('data.updated', 0)
            ->assertJsonPath('data.failed', 1);

        $this->assertSame('IHS-LAMA', $child->fresh()->ihs_number);
    }

    public function test_import_mode_koreksi_menimpa_ihs_lama(): void
    {
        $admin = User::factory()->admin()->create();
        $child = Child::factory()->create(['ihs_number' => 'IHS-LAMA']);

        $this->actingAs($admin, 'sanctum')->post('/api/admin/children/ihs/import', [
            'file' => $this->csv("child_id,ihs_number\n{$child->id},IHS-BARU\n"),
            'correct_existing' => true,
        ])->assertOk()
            ->assertJsonPath('data.updated', 1)
            ->assertJsonPath('data.failed', 0);

        $this->assertSame('IHS-BARU', $child->fresh()->ihs_number);
    }

    public function test_import_menolak_ihs_dengan_format_tidak_valid(): void
    {
        $admin = User::factory()->admin()->create();
        $child = Child::factory()->create(['ihs_number' => null]);

        $response = $this->actingAs($admin, 'sanctum')->post('/api/admin/children/ihs/import', [
            'file' => $this->csv("child_id,ihs_number\n{$child->id},IHS 001\n"),
        ]);

        $response->assertOk()
            ->assertJsonPath('data.updated', 0)
            ->assertJsonPath('data.failed', 1);

        $this->assertStringContainsString(
            'hanya boleh berisi huruf, angka',
            $response->json('data.errors.0.message'),
        );
        $this->assertNull($child->fresh()->ihs_number);
    }

    public function test_import_menolak_child_id_yang_tidak_ditemukan(): void
    {
        $admin = User::factory()->admin()->create();

        $response = $this->actingAs($admin, 'sanctum')->post('/api/admin/children/ihs/import', [
            'file' => $this->csv(
                "child_id,ihs_number\n"
                ."00000000-0000-0000-0000-000000000000,IHS-001\n"
            ),
        ]);

        $response->assertOk()
            ->assertJsonPath('data.updated', 0)
            ->assertJsonPath('data.failed', 1)
            ->assertJsonPath('data.errors.0.message', 'child_id tidak ditemukan.');
    }

    public function test_import_menolak_csv_tanpa_kolom_ihs_number(): void
    {
        $admin = User::factory()->admin()->create();

        $this->actingAs($admin, 'sanctum')->post('/api/admin/children/ihs/import', [
            'file' => $this->csv("child_id,nama_anak\nabc,Budi\n"),
        ])->assertUnprocessable()
            ->assertJsonValidationErrors('file');
    }

    public function test_import_mendukung_bom_dan_delimiter_titik_koma(): void
    {
        $admin = User::factory()->admin()->create();
        $child = Child::factory()->create(['ihs_number' => null]);

        $this->actingAs($admin, 'sanctum')->post('/api/admin/children/ihs/import', [
            'file' => $this->csv(
                "\xEF\xBB\xBFchild_id;ihs_number\n{$child->id};IHS-001\n"
            ),
        ])->assertOk()
            ->assertJsonPath('data.updated', 1)
            ->assertJsonPath('data.failed', 0);

        $this->assertSame('IHS-001', $child->fresh()->ihs_number);
    }

    public function test_import_menolak_file_lebih_dari_lima_ribu_baris(): void
    {
        $admin = User::factory()->admin()->create();

        $content = "child_id,ihs_number\n";

        for ($i = 1; $i <= 5001; $i++) {
            $content .= "00000000-0000-0000-0000-000000000000,IHS-{$i}\n";
        }

        $this->actingAs($admin, 'sanctum')->post('/api/admin/children/ihs/import', [
            'file' => $this->csv($content),
        ])->assertUnprocessable()
            ->assertJsonValidationErrors('file');
    }

    public function test_template_csv_memiliki_header_lengkap(): void
    {
        $admin = User::factory()->admin()->create();

        $response = $this->actingAs($admin, 'sanctum')
            ->get('/api/admin/children/ihs/template');

        $response->assertOk();

        $this->assertStringContainsString(
            'child_id,nik_anak,nama_anak,tanggal_lahir,nik_ibu,ihs_number',
            $response->streamedContent(),
        );
    }

    private function csv(string $content): UploadedFile
    {
        return UploadedFile::fake()->createWithContent('ihs.csv', $content);
    }
}
