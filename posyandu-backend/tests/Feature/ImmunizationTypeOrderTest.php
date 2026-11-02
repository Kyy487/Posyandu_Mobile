<?php

namespace Tests\Feature;

use App\Models\ImmunizationType;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Menguji `ImmunizationType::scopeOrderedForDosing()`.
 *
 * Scope ini menentukan urutan master vaksin di tiga tempat sekaligus: endpoint
 * `GET /immunization-types` (dropdown form pencatatan), checklist anak, dan
 * rekap bulanan. Kalau urutannya salah, kader melihat daftar yang tidak sesuai
 * urutan suntikan - dan karena yang salah hanya urutan tampil, bukan nilai,
 * tidak ada satu pun perhitungan angka yang menjatuhkannya. Itu sebabnya bug
 * ini tidak akan pernah ketahuan dari kegagalan perhitungan.
 *
 * Test-test di sini memakai master dosis dasar lengkap yang sama seperti
 * `DatabaseSeeder::seedImmunizationTypes()`. Fixture menyalinnya supaya urutan
 * yang diharapkan ditulis dari jadwal, bukan dari output endpoint. `code`
 * dalam fixture sengaja tidak diurutkan menurut jadwal, jadi fixture ini
 * sekaligus membuktikan bahwa urutannya benar-benar berubah kalau
 * `scopeOrderedForDosing()` kembali ke `orderBy('code')`.
 */
class ImmunizationTypeOrderTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Master dosis aktif, disalin dari `DatabaseSeeder::seedImmunizationTypes()`.
     * `code` di array ini tidak diurutkan menurut jadwal, supaya test bisa
     * membedakan "urutan jadwal" dari "urutan abjad".
     *
     * @return array<int, array{0: string, 1: int, 2: int}>
     */
    private function masterProgramNasional(): array
    {
        return [
            ['HB', 1, 0],
            ['BCG', 1, 1],
            ['POLIO', 1, 1],
            ['POLIO', 2, 2],
            ['POLIO', 3, 3],
            ['POLIO', 4, 4],
            ['DPT-HB-HIB', 1, 2],
            ['DPT-HB-HIB', 2, 3],
            ['DPT-HB-HIB', 3, 4],
            ['DPT-HB-HIB', 4, 18],
            ['IPV', 1, 4],
            ['IPV', 2, 9],
            ['ROTAVIRUS', 1, 2],
            ['ROTAVIRUS', 2, 3],
            ['ROTAVIRUS', 3, 4],
            ['PCV', 1, 2],
            ['PCV', 2, 3],
            ['PCV', 3, 12],
            ['MR', 1, 9],
            ['MR', 2, 18],
            ['JE', 1, 10],
        ];
    }

    /**
     * Menulis master dosis aktif ke database, satu dosis satu baris.
     */
    private function seedProgramNasional(): void
    {
        foreach ($this->masterProgramNasional() as [$code, $dose, $target]) {
            ImmunizationType::factory()->create([
                'code' => $code,
                'dose_number' => $dose,
                'target_age_months' => $target,
            ]);
        }
    }

    /**
     * Urutan master harus mengikuti jadwal suntikan, bukan abjad.
     *
     * Expected di bawah ditulis dari jadwal imunisasi nasional, bukan dari
     * output: bulan 0 (HB-1), bulan 1 (BCG-1, polio-1), bulan 2 (DPT-1, PCV-1,
     * polio-2, rotavirus-1), dan seterusnya. Perhatikan bulan 2: urutan kodenya
     * DPT-HB-HIB, PCV, POLIO, ROTAVIRUS - itu abjad, dan itu pun benar, karena
     * `code` dipakai sebagai pemutus saat dua dosis menyasar bulan yang sama.
     * Yang menentukan urutan suntik adalah `target_age_months`.
     */
    #[Test]
    public function urutan_master_mengikuti_jadwal_suntikan_bukan_abjad(): void
    {
        $this->seedProgramNasional();

        $urutan = ImmunizationType::query()
            ->orderedForDosing()
            ->get()
            ->map(fn (ImmunizationType $tipe) => $tipe->code.'-'.$tipe->dose_number)
            ->all();

        $this->assertSame([
            // Bulan 0
            'HB-1',
            // Bulan 1
            'BCG-1', 'POLIO-1',
            // Bulan 2
            'DPT-HB-HIB-1', 'PCV-1', 'POLIO-2', 'ROTAVIRUS-1',
            // Bulan 3
            'DPT-HB-HIB-2', 'PCV-2', 'POLIO-3', 'ROTAVIRUS-2',
            // Bulan 4
            'DPT-HB-HIB-3', 'IPV-1', 'POLIO-4', 'ROTAVIRUS-3',
            // Bulan 9
            'IPV-2', 'MR-1',
            // Bulan 10
            'JE-1',
            // Bulan 12
            'PCV-3',
            // Bulan 18
            'DPT-HB-HIB-4', 'MR-2',
        ], $urutan);
    }

    /**
     * Urutan `target_age_months` harus tidak pernah turun.
     *
     * Ini pemeriksaan yang lebih lemah dari yang di atas tapi berguna sebagai
     * jaring pengaman: kalau ada developer yang menambahkan `orderBy` lain
     * tanpa sadar, urutan barisnya akan acak dan test eksak di atas akan gagal
     * dengan pesan yang membingungkan. Test ini gagal dengan pesan yang jelas.
     */
    #[Test]
    public function target_usia_tidak_pernah_berkurang_di_urutan(): void
    {
        $this->seedProgramNasional();

        $target = ImmunizationType::query()
            ->orderedForDosing()
            ->pluck('target_age_months')
            ->all();

        $urut = $target;
        sort($urut);

        $this->assertSame($urut, $target, 'urutan target usia harus sama dengan urutan yang sudah diurutkan');
    }

    /**
     * Dosis tanpa target usia harus di akhir, bukan di awal.
     *
     * Kolomnya nullable, jadi baris tanpa target itu mungkin terjadi - misalnya
     * ada master tambahan yang diimpor dari sumber lain dan targetnya belum
     * diisi. PostgreSQL sudah menempatkan NULL di akhir untuk `ORDER BY ... ASC`;
     * test ini mengunci perilaku itu supaya tidak diam-diam berubah kalau
     * default-nya diganti.
     */
    #[Test]
    public function dosis_tanpa_target_usia_ditaruh_di_akhir(): void
    {
        $this->seedProgramNasional();
        ImmunizationType::factory()->create(['code' => 'VAKSIN-UJI', 'dose_number' => 1, 'target_age_months' => null]);

        $kode = ImmunizationType::query()
            ->orderedForDosing()
            ->get()
            ->map(fn (ImmunizationType $tipe) => $tipe->code)
            ->all();

        $this->assertSame('VAKSIN-UJI', end($kode), 'dosis tanpa target harus baris terakhir');
    }

    /**
     * Dosis dengan target sama harus dapat urutan yang stabil.
     *
     * PostgreSQL tidak menjamin urutan baris yang `ORDER BY`-nya tidak
     * deterministik, jadi dua request ke endpoint yang sama bisa mengembalikan
     * urutan berbeda. Kader membandingkan daftar bulan lalu dengan bulan ini;
     * kalau urutan bisa bergeser, pengiraannya ikut kabur. Test ini memanggilnya
     * berulang kali untuk memastikan hasilnya tidak bergeser.
     */
    #[Test]
    public function urutan_dosis_dengan_target_sama_selalu_konsisten(): void
    {
        $this->seedProgramNasional();

        $pertama = ImmunizationType::query()->orderedForDosing()->pluck('code')->all();
        $kedua = ImmunizationType::query()->orderedForDosing()->pluck('code')->all();
        $ketiga = ImmunizationType::query()->orderedForDosing()->pluck('code')->all();

        $this->assertSame($pertama, $kedua);
        $this->assertSame($pertama, $ketiga);
    }

    /**
     * Endpoint `GET /immunization-types` harus memakai urutan yang sama.
     *
     * Ini yang dilihat kader: dropdown di form pencatatan suntikan. Kalau
     * endpointnya punya urutan sendiri yang berbeda, scope-nya benar tapi
     * hasilnya tetap tidak terpakai. Catatan: rutenya tidak memakai awalan
     * `/kader` seperti endpoint pencatatan, jadi tidak perlu kode kader.
     */
    #[Test]
    public function endpoint_jenis_vaksin_mengirim_master_dalam_urutan_suntikan(): void
    {
        $kader = User::factory()->kader()->create();
        $this->seedProgramNasional();

        $respons = $this->withToken($this->token($kader))->getJson('/api/immunization-types');

        $respons->assertOk();

        $data = $respons->json('data');
        $this->assertNotNull($data, 'respons harus punya wrapper data');

        $this->assertSame(
            ['HB-1', 'BCG-1', 'POLIO-1', 'DPT-HB-HIB-1', 'PCV-1', 'POLIO-2', 'ROTAVIRUS-1', 'DPT-HB-HIB-2', 'PCV-2', 'POLIO-3', 'ROTAVIRUS-2', 'DPT-HB-HIB-3', 'IPV-1', 'POLIO-4', 'ROTAVIRUS-3', 'IPV-2', 'MR-1', 'JE-1', 'PCV-3', 'DPT-HB-HIB-4', 'MR-2'],
            array_map(fn (array $tipe) => $tipe['code'].'-'.$tipe['dose_number'], $data)
        );
    }

    /**
     * Endpoint hanya mengirim dosis aktif.
     *
     * Dosis yang dinonaktifkan (mis. jadwal lama) tetap ada di database demi
     * catatan lama, tapi tidak boleh muncul di dropdown/checklist; kalau ikut
     * muncul, kader bisa mencatat suntikan ke dosis yang sudah tidak dipakai.
     */
    #[Test]
    public function endpoint_tidak_mengirim_dosis_nonaktif(): void
    {
        $kader = User::factory()->kader()->create();
        $this->seedProgramNasional();

        ImmunizationType::factory()->create([
            'code' => 'VAKSIN-LAMA',
            'dose_number' => 1,
            'target_age_months' => 2,
            'is_active' => false,
        ]);

        $data = $this->withToken($this->token($kader))
            ->getJson('/api/immunization-types')
            ->assertOk()
            ->json('data');

        $kode = array_map(fn (array $tipe) => $tipe['code'], $data);

        $this->assertNotContains('VAKSIN-LAMA', $kode);
    }

    private function token(User $user): string
    {
        return $user->createToken('uji')->plainTextToken;
    }
}
