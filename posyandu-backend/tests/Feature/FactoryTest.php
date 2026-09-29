<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\ImmunizationRecord;
use App\Models\ImmunizationType;
use App\Models\Measurement;
use App\Models\PosyanduSchedule;
use App\Models\User;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Menguji factory yang dibuat untuk mendukung rekap Opsi E.
 *
 * Kedengarannya sepele, tapi factory yang salah adalah sumber kegagalan yang
 * mahal: test hijau karena datanya tidak pernah menyentuh bagian yang penting.
 * Semua test di sini menjalankan factory terhadap skema PostgreSQL sungguhan.
 */
class FactoryTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function factory_penimbangan_membuat_baris_yang_lolos_semua_constraint(): void
    {
        $penimbangan = Measurement::factory()->create();

        $this->assertNotNull($penimbangan->id);
        $this->assertNotNull($penimbangan->child_id);
        $this->assertNotNull($penimbangan->kader_id);
        $this->assertDatabaseHas('measurements', ['id' => $penimbangan->id]);
    }

    #[Test]
    public function factory_penimbangan_mengisi_zscore_lewat_trigger(): void
    {
        $penimbangan = Measurement::factory()->create();

        // `z_score_wfa` dan `age_in_months` sengaja tidak diisi factory: itu
        // pekerjaan trigger `trg_measurements_who_zscore`. Kalau trigger
        // berhenti jalan, test ini yang pertama gagal.
        $penimbangan->refresh();

        $this->assertNotNull($penimbangan->age_in_months);
        $this->assertNotNull($penimbangan->z_score_wfa);
    }

    #[Test]
    public function factory_penimbangan_untuk_anak_baru_lahir_tidak_gagal(): void
    {
        // Anak lahir kemarin: trigger menolak tanggal penimbangan yang lebih
        // awal dari tanggal lahir, jadi factory harus menggeser tanggalnya.
        $anak = Child::factory()->create([
            'date_of_birth' => now()->subDay()->toDateString(),
        ]);

        $penimbangan = Measurement::factory()->untukAnak($anak)->create();

        $this->assertGreaterThanOrEqual(
            $anak->date_of_birth,
            $penimbangan->measurement_date
        );
    }

    #[Test]
    public function factory_penimbangan_bisa_dibuat_tanpa_kader(): void
    {
        $penimbangan = Measurement::factory()->tanpaKader()->create();

        $this->assertNull($penimbangan->kader_id);
        $this->assertNull($penimbangan->kader);
    }

    #[Test]
    public function factory_jenis_vaksin_tidak_menabrak_unique_code_dose(): void
    {
        // 30 baris sekaligus. Kalau `code` atau `dose_number` tidak diacak
        // cukup, `immunization_types_code_dose_unique` akan menolaknya.
        $jenis = ImmunizationType::factory()->count(30)->create();

        $this->assertCount(30, $jenis);
        $this->assertSame(
            30,
            $jenis->map(fn ($t) => $t->code.'-'.$t->dose_number)->unique()->count()
        );
    }

    #[Test]
    public function factory_suntikan_membuat_baris_yang_lolos_semua_constraint(): void
    {
        $suntikan = ImmunizationRecord::factory()->create();

        $this->assertNotNull($suntikan->immunization_type_id);
        $this->assertDatabaseHas('immunization_records', ['id' => $suntikan->id]);
    }

    #[Test]
    public function factory_suntikan_menolak_duplikat_anak_dosis_sama(): void
    {
        $anak = Child::factory()->create();
        $dosis = ImmunizationType::factory()->create();

        ImmunizationRecord::factory()->untukAnak($anak)->untukDosis($dosis)->create();

        $this->expectException(UniqueConstraintViolationException::class);

        ImmunizationRecord::factory()->untukAnak($anak)->untukDosis($dosis)->create();
    }

    #[Test]
    public function factory_suntikan_yang_dibatalkan_melepas_kunci_unik(): void
    {
        $anak = Child::factory()->create();
        $dosis = ImmunizationType::factory()->create();

        $lama = ImmunizationRecord::factory()->untukAnak($anak)->untukDosis($dosis)->create();
        $lama->delete();

        $baru = ImmunizationRecord::factory()->untukAnak($anak)->untukDosis($dosis)->create();

        $this->assertNotSame($lama->id, $baru->id);
        $this->assertFalse($baru->fresh()?->trashed());
    }

    #[Test]
    public function factory_agenda_mengakai_status_yang_diterima_check_constraint(): void
    {
        foreach ([
            PosyanduSchedule::STATUS_TERJADWAL,
            PosyanduSchedule::STATUS_BERLANGSUNG,
            PosyanduSchedule::STATUS_SELESAI,
            PosyanduSchedule::STATUS_DIBATALKAN,
        ] as $status) {
            $agenda = PosyanduSchedule::factory()->create(['status' => $status]);

            $this->assertSame($status, $agenda->status);
        }
    }

    #[Test]
    public function factory_agenda_membuat_waktu_mulai_sebelum_waktu_selesai(): void
    {
        $agenda = PosyanduSchedule::factory()->create();

        $this->assertLessThan(
            $agenda->end_time,
            $agenda->start_time,
            'start_time harus lebih dulu dari end_time'
        );
    }

    #[Test]
    public function factory_kader_membuat_akun_yang_bisa_login(): void
    {
        $kader = User::factory()->kader()->create();

        // NIK harus memenuhi format yang dicek `AuthController`, kalau tidak
        // factory ini menghasilkan akun yang tidak bisa dipakai test endpoint.
        $this->assertMatchesRegularExpression('/^\d{16}$/', $kader->nik);
        $this->assertSame('kader', $kader->role);
        $this->assertSame('Kader Posyandu', $kader->jabatan);
    }

    #[Test]
    public function factory_ibu_tidak_punya_jabatan(): void
    {
        $ibu = User::factory()->ibu()->create();

        $this->assertSame('ibu', $ibu->role);
        $this->assertNull($ibu->jabatan);
    }

    #[Test]
    public function factory_tidak_pernah_membuat_nik_yang_sama(): void
    {
        $nik = User::factory()->count(50)->create()->pluck('nik');

        $this->assertCount(50, $nik->unique());
    }
}
