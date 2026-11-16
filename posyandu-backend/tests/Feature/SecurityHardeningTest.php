<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class SecurityHardeningTest extends TestCase
{
    use RefreshDatabase;

    public function test_no_kk_tersimpan_encrypted_dan_terbaca_kembali(): void
    {
        $noKk = '3273012345678901';

        $user = User::factory()->create(['no_kk' => $noKk]);
        $raw = DB::table('users')->where('id', $user->id)->value('no_kk');

        $this->assertNotEquals($noKk, $raw);
        $this->assertStringStartsWith('eyJ', $raw);
        $this->assertSame($noKk, $user->fresh()->no_kk);
    }

    public function test_birth_height_mengikuti_birth_length_sebagai_generated_column(): void
    {
        $anak = Child::factory()->create(['birth_length' => 50.25]);

        $this->assertEquals(50.25, (float) $anak->fresh()->birth_height);

        $anak->update(['birth_length' => 51.5]);

        $this->assertEquals(51.5, (float) $anak->fresh()->birth_height);
    }

    public function test_verification_status_adalah_kolom_generated_dari_status(): void
    {
        $user = User::factory()->create(['status' => 'active']);

        $this->assertSame('approved', $user->fresh()->verification_status);
        $this->assertSame(
            1,
            DB::table('users')->where('verification_status', 'approved')->count(),
        );

        $user->update(['status' => 'rejected']);

        $this->assertSame('rejected', $user->fresh()->verification_status);
    }

    public function test_check_constraint_menolak_onboarding_status_tidak_valid(): void
    {
        $user = User::factory()->create();

        $this->expectException(QueryException::class);

        DB::table('users')
            ->where('id', $user->id)
            ->update(['onboarding_status' => 'status_ngawur']);
    }

    public function test_check_constraint_menolak_birth_order_di_luar_batas(): void
    {
        $anak = Child::factory()->create();

        $this->expectException(QueryException::class);

        DB::table('children')
            ->where('id', $anak->id)
            ->update(['birth_order' => 0]);
    }
}
