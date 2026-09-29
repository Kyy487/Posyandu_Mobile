<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\ImmunizationRecord;
use App\Models\ImmunizationType;
use App\Models\User;
use App\Services\ImmunizationChecklistService;
use App\Services\ImmunizationRecapService;
use Carbon\CarbonImmutable;
use Closure;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Menguji `GET /kader/immunizations/recap` (blokir 3, Opsi E).
 *
 * Seluruh test memakai bulan acuan tetap `2026-09` dengan tanggal acuan
 * `2026-09-30`. Angka yang diharapkan dihitung manual dari fixture di bawah,
 * supaya test ini benar-benar menguji aturan dan bukan hanya menguji dirinya
 * sendiri.
 *
 * Master dosis yang dipakai (lihat `masterDosis()`):
 *
 *   | code | target | batas terlambat (target + 2) |
 *   | :--- | -----: | ----------------------------: |
 *   | HB   |      0 |                             2 |
 *   | BCG  |      2 |                             4 |
 *   | MR   |      9 |                            11 |
 *
 * Usia anak pada 2026-09-30 (bulat ke bawah):
 *
 *   | anak  | lahir        | usia | HB | BCG | MR            |
 *   | :---- | :----------- | ---: | -- | --- | :------------ |
 *   | A     | 2025-10-15   |   11 |  2 |   2 |  1 terlambat |
 *   | B     | 2026-08-01   |    1 |  0 |   0 |  0 belum jatuh tempo |
 *   | C     | 2026-08-20   |    0 |  0 |   0 |  0 belum jatuh tempo |
 *   | D     | 2025-10-15   |   11 |    |     |  (ter-arsip)   |
 *   | E     | 2026-03-10   |    5 |  2 |   2 |  0 belum jatuh tempo |
 *   | F     | 2026-02-01   |    7 |  2 |   2 |  0 belum jatuh tempo |
 */
class ImmunizationRecapTest extends TestCase
{
    use RefreshDatabase;

    private const BULAN = '2026-09';

    private const ACUAN = '2026-09-30';

    // -----------------------------------------------------------------
    // 1. Akses endpoint
    // -----------------------------------------------------------------

    #[Test]
    public function ibu_tidak_boleh_membuka_rekap(): void
    {
        $ibu = User::factory()->ibu()->create();

        $this->withToken($this->token($ibu))
            ->getJson('/api/kader/immunizations/recap?month='.self::BULAN)
            ->assertForbidden();
    }

    /**
     * Rekap mengekspos data seluruh Posyandu, jadi Ibu harus tetap 403 walau
     * yang dia baca cuma anaknya sendiri lewat `GET /children/{id}/immunizations`.
     */
    #[Test]
    public function ibu_memiliki_endpoint_sendiri_untuk_anaknya(): void
    {
        $ibu = User::factory()->ibu()->create();
        $anak = Child::factory()->milik($ibu)->create();

        $this->masterDosis();

        $this->withToken($this->token($ibu))
            ->getJson("/api/children/{$anak->id}/immunizations")
            ->assertOk()
            ->assertJsonPath('success', true);
    }

    #[Test]
    public function tamu_tidak_boleh_membuka_rekap(): void
    {
        $this->getJson('/api/kader/immunizations/recap?month='.self::BULAN)
            ->assertUnauthorized();
    }

    #[Test]
    public function kader_boleh_membuka_rekap(): void
    {
        $kader = User::factory()->kader()->create();

        $this->masterDosis();

        $this->withToken($this->token($kader))
            ->getJson('/api/kader/immunizations/recap?month='.self::BULAN)
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.filter.month', self::BULAN)
            ->assertJsonPath('data.filter.reference_date', self::ACUAN);
    }

    // -----------------------------------------------------------------
    // 2. Validasi parameter bulan
    // -----------------------------------------------------------------

    #[Test]
    public function bulan_yang_tidak_ada_ditolak(): void
    {
        $kader = User::factory()->kader()->create();

        $this->withToken($this->token($kader))
            ->getJson('/api/kader/immunizations/recap?month=2026-13')
            ->assertStatus(422)
            ->assertJsonPath('success', false)
            ->assertJsonStructure(['success', 'message', 'errors' => ['month']]);
    }

    #[Test]
    public function bulan_tanpa_garis_dash_ditolak(): void
    {
        $kader = User::factory()->kader()->create();

        $this->withToken($this->token($kader))
            ->getJson('/api/kader/immunizations/recap?month=202602')
            ->assertStatus(422);
    }

    /**
     * Tanpa `?month=` rekap memakai bulan berjalan.
     *
     * Nilai yang diharapkan dihitung ulang di sini, bukan ditulis literal, jadi
     * test ini tetap benar dijalankan di tanggal berapa pun.
     */
    #[Test]
    public function tanpa_parameter_bulan_rekap_memakai_bulan_berjalan(): void
    {
        $kader = User::factory()->kader()->create();

        $this->masterDosis();

        $bulanSekarang = CarbonImmutable::now()->format('Y-m');
        $akhirBulan = CarbonImmutable::createFromFormat('!Y-m', $bulanSekarang)->endOfMonth();

        $this->withToken($this->token($kader))
            ->getJson('/api/kader/immunizations/recap')
            ->assertOk()
            ->assertJsonPath('data.filter.month', $bulanSekarang)
            ->assertJsonPath('data.filter.reference_date', $akhirBulan->toDateString());
    }

    // -----------------------------------------------------------------
    // 3. `activity` - dosis yang benar-benar disuntik bulan itu
    // -----------------------------------------------------------------

    #[Test]
    public function aktivitas_hanya_menghitung_suntikan_pada_bulan_itu(): void
    {
        $kader = User::factory()->kader()->create();
        [$hb, $bcg, $mr] = $this->masterDosis();

        $anak = Child::factory()->create(['date_of_birth' => '2025-10-15']);

        // Tiga suntikan: dua di dalam bulan, satu sebelum, satu sesudah.
        ImmunizationRecord::factory()->untukAnak($anak)->untukDosis($hb)->padaTanggal('2026-09-03')->create();
        ImmunizationRecord::factory()->untukAnak($anak)->untukDosis($bcg)->padaTanggal('2026-09-30')->create();
        ImmunizationRecord::factory()->untukAnak($anak)->untukDosis($mr)->padaTanggal('2026-08-31')->create();

        // Anak kedua menyuntik dosis sama di bulan yang sama: `activity` harus
        // menghitung dosis, bukan anak.
        $anakLain = Child::factory()->create(['date_of_birth' => '2025-10-15']);
        ImmunizationRecord::factory()->untukAnak($anakLain)->untukDosis($hb)->padaTanggal('2026-09-20')->create();

        $data = $this->rekap($kader);

        $this->assertSame(3, $data['activity']['total_doses']);
        $this->assertSame(2, $data['activity']['total_children']);

        $this->assertSame(2, $this->countFor($data, 'HB'), 'HB disuntik 2x (satu anak saja)');
        $this->assertSame(1, $this->countFor($data, 'BCG'));
        $this->assertSame(0, $this->countFor($data, 'MR'), 'suntikan MR 31 Agustus bukan bagian September');
    }

    /**
     * Suntikan yang dibatalkan tidak boleh masuk aktivitas.
     *
     * `ImmunizationRecord` memakai soft delete, jadi yang meng-COVER ini adalah
     * global scope. Kalau scopenya hilang, stok vaksin akan overreacting pada
     * suntikan yang sudah dibatalin kader.
     */
    #[Test]
    public function suntikan_dibatalkan_tidak_masuk_aktivitas(): void
    {
        $kader = User::factory()->kader()->create();
        [$hb] = $this->masterDosis();

        $anak = Child::factory()->create(['date_of_birth' => '2025-10-15']);

        ImmunizationRecord::factory()->untukAnak($anak)->untukDosis($hb)->padaTanggal('2026-09-05')->create();
        ImmunizationRecord::factory()
            ->untukAnak($anak)
            ->untukDosis($hb)
            ->padaTanggal('2026-09-06')
            ->dibatalkan()
            ->create();

        $data = $this->rekap($kader);

        $this->assertSame(1, $data['activity']['total_doses']);
        $this->assertSame(1, $this->countFor($data, 'HB'));
    }

    /**
     * Semua master dosis dikembalikan, termasuk yang nol.
     *
     * Kader perlu melihat "tidak ada yang disuntik bulan ini" untuk satu jenis
     * vaksin. Kalau baris nol disembunyikan, "tidak ada suntikan" dan "tidak
     * sempat dicatat" tampil sama saja.
     */
    #[Test]
    public function aktivitas_menampilkan_seluruh_master_termasuk_yang_nol(): void
    {
        $kader = User::factory()->kader()->create();
        $this->masterDosis();

        $data = $this->rekap($kader);

        $this->assertCount(3, $data['activity']['by_type']);

        $totalDariBaris = array_sum(array_column($data['activity']['by_type'], 'count'));
        $this->assertSame($data['activity']['total_doses'], $totalDariBaris);
    }

    // -----------------------------------------------------------------
    // 4. `coverage` - kelengkapan di akhir bulan
    // -----------------------------------------------------------------

    #[Test]
    public function coverage_menghitung_kelengkapan_di_akhir_bulan(): void
    {
        $kader = User::factory()->kader()->create();
        [$hb] = $this->masterDosis();

        // A: 11 bulan, belum apa-apa -> 3 dosis terlambat.
        Child::factory()->create(['name' => 'Anak A', 'date_of_birth' => '2025-10-15']);

        // B: 1 bulan, HB sudah disuntik -> semua dosis jatuh tempo sudah
        //    terpenuhi, jadi `complete`.
        $b = Child::factory()->create(['name' => 'Anak B', 'date_of_birth' => '2026-08-01']);
        ImmunizationRecord::factory()->untukAnak($b)->untukDosis($hb)->padaTanggal('2026-08-05')->create();

        // C: 0 bulan, belum disuntik -> `incomplete` tapi BELUM terlambat.
        //    Dosis yang belum jatuh tempo tidak boleh dihitung sebagai kekurangan.
        Child::factory()->create(['name' => 'Anak C', 'date_of_birth' => '2026-08-20']);

        $coverage = $this->rekap($kader)['coverage'];

        $this->assertSame(3, $coverage['total_children']);
        $this->assertSame(1, $coverage['complete']);
        $this->assertSame(2, $coverage['incomplete']);
        $this->assertSame(1, $coverage['overdue']);
    }

    #[Test]
    public function anak_ter_arsip_dikecualikan_tapi_jumlahnya_dilaporkan(): void
    {
        $kader = User::factory()->kader()->create();
        $this->masterDosis();

        Child::factory()->create(['name' => 'Anak A', 'date_of_birth' => '2025-10-15']);
        $pindah = Child::factory()->create(['name' => 'Anak Pindah', 'date_of_birth' => '2025-10-15']);
        $pindah->delete();

        $coverage = $this->rekap($kader)['coverage'];

        $this->assertSame(1, $coverage['total_children'], 'anak ter-arsip tidak dihitung');
        $this->assertSame(1, $coverage['excluded_archived'], 'tapi jumlahnya dilaporkan');
        $this->assertSame(1, $coverage['overdue'], 'anak terlambat yang dihitung hanya anak aktif');

        $namaTerlambat = array_column($coverage['overdue_children'], 'name');
        $this->assertSame(['Anak A'], $namaTerlambat);
    }

    /**
     * Suntikan yang tercatat SETELAH bulan yang direkap tidak boleh masuk
     * perhitungan coverage.
     *
     * Ini yang membuat laporan lama bisa dipakai sebagai arsip: rekap
     * September yang dibuat di November harus menghasilkan angka yang sama
     * dengan rekap September yang dibuat di Oktober.
     */
    #[Test]
    public function suntikan_setelah_akhir_bulan_tidak_mengubah_laporan_historis(): void
    {
        $kader = User::factory()->kader()->create();
        [$hb, $bcg, $mr] = $this->masterDosis();

        $anak = Child::factory()->create(['date_of_birth' => '2025-10-15']);

        $sebelum = $this->rekap($kader)['coverage'];

        // `overdue` menghitung ANAK, bukan dosis. Satu anak ini punya tiga
        // dosis yang lewat.
        $this->assertSame(1, $sebelum['overdue']);
        $this->assertSame(3, count($sebelum['overdue_children'][0]['overdue_doses']));

        // Ketiga dosis dicatat 5 Oktober. September sudah lewat, jadi laporan
        // September tidak boleh ikut berubah.
        foreach ([$hb, $bcg, $mr] as $tipe) {
            ImmunizationRecord::factory()->untukAnak($anak)->untukDosis($tipe)->padaTanggal('2026-10-05')->create();
        }

        $sesudah = $this->rekap($kader)['coverage'];

        $this->assertEquals($sebelum, $sesudah, 'seluruh coverage September harus sama persis');

        // Rekap Oktober memang harus melihat suntikan itu.
        $oktober = $this->rekap($kader, '2026-10')['coverage'];
        $this->assertSame(0, $oktober['overdue']);
        $this->assertSame(1, $oktober['complete']);
    }

    /**
     * Suntikan tepat pada tanggal acuan (akhir bulan) tetap dihitung.
     */
    #[Test]
    public function suntikan_pada_tanggal_akhir_bulan_masih_dihitung(): void
    {
        $kader = User::factory()->kader()->create();
        [$hb, $bcg, $mr] = $this->masterDosis();

        $anak = Child::factory()->create(['date_of_birth' => '2025-10-15']);

        // 30 September adalah tanggal acuan, dan batasnya inklusif: suntikan
        // terakhir hari itu sah dihitung.
        foreach ([$hb, $bcg, $mr] as $tipe) {
            ImmunizationRecord::factory()->untukAnak($anak)->untukDosis($tipe)->padaTanggal('2026-09-30')->create();
        }

        $coverage = $this->rekap($kader)['coverage'];

        $this->assertSame(0, $coverage['overdue'], 'suntikan tepat di tanggal acuan ikut dihitung');
        $this->assertSame(1, $coverage['complete']);
    }

    #[Test]
    public function dosis_belum_jatuh_tempo_tidak_dihitung_sebagai_kurang(): void
    {
        $kader = User::factory()->kader()->create();
        $this->masterDosis();

        // Bayi 0 bulan: hanya HB (target 0) yang jatuh tempo. BCG (target 2)
        // dan MR (target 9) belum, jadi tidak boleh dihitung sebagai kurang.
        $anak = Child::factory()->create(['date_of_birth' => '2026-08-20']);

        $coverage = $this->rekap($kader)['coverage'];

        $this->assertSame(0, $coverage['overdue']);
        $this->assertSame(1, $coverage['incomplete']);
        $this->assertSame(0, $coverage['complete']);
    }

    // -----------------------------------------------------------------
    // 5. Urutan anak terlambat
    // -----------------------------------------------------------------

    /**
     * Urutan yang dipakai kader untuk memutuskan siapa dikunjungi dulu:
     * paling banyak dosis terlambat, lalu paling lama terlambat.
     */
    #[Test]
    public function anak_terlambat_diurutkan_paling_banyak_dosis_dulu(): void
    {
        $kader = User::factory()->kader()->create();
        $this->masterDosis();

        // A: 3 dosis terlambat (sisa paling negatif -9)
        Child::factory()->create(['name' => 'A', 'date_of_birth' => '2025-10-15']);

        // F: 2 dosis terlambat, sisa -5 (lebih lama telat dari E)
        Child::factory()->create(['name' => 'F', 'date_of_birth' => '2026-02-01']);

        // E: 2 dosis terlambat, sisa -3
        Child::factory()->create(['name' => 'E', 'date_of_birth' => '2026-03-10']);

        $coverage = $this->rekap($kader)['coverage'];

        $this->assertSame(3, $coverage['overdue']);
        $this->assertSame(
            ['A', 'F', 'E'],
            array_column($coverage['overdue_children'], 'name'),
            'A (3 dosis) dulu, lalu F dan E (2 dosis) diurutkan dari yang paling terlambat'
        );

        $pertama = $coverage['overdue_children'][0];
        $this->assertSame(3, count($pertama['overdue_doses']));
        $this->assertSame(11, $pertama['age_in_months']);
        $this->assertSame('2025-10-15', $pertama['date_of_birth']);
    }

    /**
     * `overdue_doses` harus menyebut dosis yang lewat, lengkap dengan sisa
     * bulannya.
     *
     * Urutan barisnya mengikuti `orderedForDosing()` (kode lalu nomor dosis),
     * bukan urutan kronologis - jadi yang diuji di sini adalah isi tiap baris,
     * bukan posisinya.
     */
    #[Test]
    public function daftar_anak_terlambat_menyertakan_dosis_yang_lewat(): void
    {
        $kader = User::factory()->kader()->create();
        $this->masterDosis();

        $this->anakLengkap();

        $coverage = $this->rekap($kader)['coverage'];
        $anak = $coverage['overdue_children'][0];

        $this->assertCount(3, $anak['overdue_doses']);

        $sisaPerKode = [];
        foreach ($anak['overdue_doses'] as $dosis) {
            $sisaPerKode[$dosis['code']] = $dosis['sisa_bulan'];
        }

        // Usia 11 bulan pada 2026-09-30. Batas terlambat = target + 2.
        $this->assertEquals(
            ['HB' => -9, 'BCG' => -7, 'MR' => 0],
            $sisaPerKode,
            'HB paling telat, lalu BCG, lalu MR yang tepat di batas'
        );
    }

    // -----------------------------------------------------------------
    // 6. Tidak ada N+1
    // -----------------------------------------------------------------

    /**
     * Jumlah query rekap harus tetap, bukan ikut bertambah dengan jumlah anak.
     *
     * Rekap mengevaluasi status di PHP dari data yang sudah dimuat, jadi
     * menambah anak tidak boleh menambah query. Kalau suatu saat service-nya
     * berubah jadi looping `checklistFor()` per anak, test ini langsung gagal.
     *
     * Token dibuat SEKALI di awal test. Sanctum menyimpan hasil resolusi token
     * di cache statis, jadi kalau token baru dibuat di dalam pengukuran, request
     * kedua akan melewati 3 query autentikasi dan angkanya jadi kelihatan
     * turun - bukan karena rekap lebih hemat, tapi karena autentikasinya cheaper.
     */
    #[Test]
    public function jumlah_query_tidak_ikut_bertambah_dengan_jumlah_anak(): void
    {
        $kader = User::factory()->kader()->create();
        $token = $this->token($kader);
        $this->masterDosis();

        for ($i = 0; $i < 3; $i++) {
            $this->anakLengkap();
        }

        // Pemanasan: mengisi cache token Sanctum supaya 3 query autentikasi
        // tidak ikut terukur.
        $this->withToken($token)->getJson('/api/kader/immunizations/recap?month='.self::BULAN);

        $sedikit = $this->hitungQuery(fn () => $this->withToken($token)
            ->getJson('/api/kader/immunizations/recap?month='.self::BULAN));

        for ($i = 0; $i < 28; $i++) {
            $this->anakLengkap();
        }

        $banyak = $this->hitungQuery(fn () => $this->withToken($token)
            ->getJson('/api/kader/immunizations/recap?month='.self::BULAN));

        $this->assertSame(
            $sedikit,
            $banyak,
            "Query rekap naik dari {$sedikit} ke {$banyak} saat anak bertambah 3 -> 31 (N+1)"
        );
    }

    // -----------------------------------------------------------------
    // 7. Satu sumber kebenaran dengan checklist
    // -----------------------------------------------------------------

    /**
     * Rekap dan checklist harus menilai anak yang sama dengan hasil yang sama.
     *
     * Ini yang membuat `ImmunizationChecklistService::evaluate()` wajib jadi
     * satu-satunya tempat aturan status. Kalau ada dua salinan aturan, angka
     * untuk kasus yang sama akan berbeda antara layar anak dan layar rekap -
     * dan tidak ada yang bisa tahu mana yang benar.
     */
    #[Test]
    public function rekap_dan_checklist_memberi_hasil_yang_sama(): void
    {
        $kader = User::factory()->kader()->create();
        [$hb] = $this->masterDosis();

        $anak = Child::factory()->create(['date_of_birth' => '2025-10-15']);
        ImmunizationRecord::factory()->untukAnak($anak)->untukDosis($hb)->padaTanggal('2025-10-16')->create();

        $checklist = app(ImmunizationChecklistService::class);
        $acuan = CarbonImmutable::parse(self::ACUAN);

        $dariChecklist = $checklist->checklistFor($anak, $acuan);
        $terlambatChecklist = array_values(array_filter(
            $dariChecklist,
            fn (array $item): bool => $item['status'] === ImmunizationType::STATUS_OVERDUE
        ));

        $rekap = app(ImmunizationRecapService::class)->recapForMonth(
            CarbonImmutable::createFromFormat('!Y-m', self::BULAN)
        );

        $dariRekap = $rekap['coverage']['overdue_children'][0]['overdue_doses'];

        $this->assertSame(
            array_column($terlambatChecklist, 'code'),
            array_column($dariRekap, 'code'),
            'dosis terlambat harus sama antara checklist anak dan rekap'
        );
        $this->assertSame(
            array_column($terlambatChecklist, 'sisa_bulan'),
            array_column($dariRekap, 'sisa_bulan'),
            'sisa bulan harus sama antara checklist anak dan rekap'
        );

        // HB sudah disuntik, jadi tidak boleh muncul sebagai terlambat.
        $this->assertNotContains('HB', array_column($dariRekap, 'code'));
        $this->assertCount(2, $dariRekap, 'BCG dan MR yang masih terlambat');
    }

    /**
     * Dosis yang sudah disuntik tidak punya `sisa_bulan`.
     *
     * `sisa_bulan` adalah countdown menuju status terlambat. Untuk dosis yang
     * sudah `sudah`, angka yang tersisa selalu menyesatkan: anak 11 bulan yang
     * suntik MR tepat waktu akan tampil "terlambat 0 bulan" kalau angkanya
     * ikut dikirim, padahal dosisnya justru sudah diberikan.
     */
    #[Test]
    public function dosis_yang_sudah_disuntik_tidak_punya_sisa_bulan(): void
    {
        $kader = User::factory()->kader()->create();
        [$hb] = $this->masterDosis();

        $anak = Child::factory()->create(['date_of_birth' => '2025-10-15']);
        ImmunizationRecord::factory()->untukAnak($anak)->untukDosis($hb)->padaTanggal('2025-10-16')->create();

        $respons = $this->withToken($this->token($kader))
            ->getJson("/api/children/{$anak->id}/immunizations")
            ->assertOk();

        $perKode = collect($respons->json('data.checklist'))->keyBy('code');

        $this->assertSame('sudah', $perKode['HB']['status']);
        $this->assertNull($perKode['HB']['sisa_bulan'], 'dosis sudah disuntik tidak punya countdown');

        $this->assertSame('terlambat', $perKode['MR']['status']);
        $this->assertSame(0, $perKode['MR']['sisa_bulan'], 'tepat di batas terlambat -> 0, bukan null');
    }

    /**
     * Rekap punya bentuk respons yang stabil.
     *
     * Field yang hilang di sini tidak akan menggagalkan request, tapi akan
     * menggagalkan parser Flutter dengan error yang jauh lebih membingungkan.
     */
    #[Test]
    public function bentuk_respons_lengkap_dan_konsisten(): void
    {
        $kader = User::factory()->kader()->create();
        $this->masterDosis();
        $this->anakLengkap();

        $respons = $this->withToken($this->token($kader))
            ->getJson('/api/kader/immunizations/recap?month='.self::BULAN)
            ->assertOk();

        $respons->assertJsonStructure([
            'success',
            'message',
            'data' => [
                'filter' => ['month', 'reference_date'],
                'activity' => [
                    'total_doses',
                    'total_children',
                    'by_type' => [['immunization_type_id', 'code', 'name', 'label', 'dose_number', 'count']],
                ],
                'coverage' => [
                    'total_children',
                    'complete',
                    'incomplete',
                    'overdue',
                    'excluded_archived',
                    'overdue_children' => [[
                        'child_id',
                        'name',
                        'date_of_birth',
                        'age_in_months',
                        'overdue_doses' => [[
                            'immunization_type_id',
                            'code',
                            'name',
                            'label',
                            'dose_number',
                            'target_age_months',
                            'sisa_bulan',
                        ]],
                    ]],
                ],
            ],
        ]);

        // `complete` + `incomplete` harus selalu sama dengan total. Kalau tidak,
        // ada anak yang tidak masuk kategori mana pun dan angkaBIDAN salah.
        $coverage = $respons->json('data.coverage');
        $this->assertSame(
            $coverage['total_children'],
            $coverage['complete'] + $coverage['incomplete']
        );
        $this->assertSame($coverage['overdue'], count($coverage['overdue_children']));
    }

    // -----------------------------------------------------------------
    // Helper
    // -----------------------------------------------------------------

    /**
     * Master 3 dosis dengan target usia yang terhingga.
     *
     * Angka target menentukan seluruh ekspektasi di test ini, jadi master dibuat
     * eksplisit - bukan `seeder`, yang isinya bisa berubah sewaktu-waktu tanpa
     * test ini gagal.
     *
     * @return array{0: ImmunizationType, 1: ImmunizationType, 2: ImmunizationType}
     */
    private function masterDosis(): array
    {
        return [
            ImmunizationType::factory()->dosisPertama('Hepatitis B', 'HB')
                ->create(['target_age_months' => 0, 'interval_months' => null]),
            ImmunizationType::factory()->dosisPertama('BCG', 'BCG')
                ->create(['target_age_months' => 2, 'interval_months' => null]),
            ImmunizationType::factory()->dosisPertama('Campak Rubella', 'MR')
                ->create(['target_age_months' => 9, 'interval_months' => 9]),
        ];
    }

    /**
     * Satu anak yang pasti terlambat: lahir 2025-10-15, tidak ada suntikan.
     * Pada 2026-09-30 usianya 11 bulan, jadi HB, BCG, dan MR semuanya lewat
     * batas toleransi.
     */
    private function anakLengkap(): Child
    {
        return Child::factory()->create(['date_of_birth' => '2025-10-15']);
    }

    private function token(User $user): string
    {
        return $user->createToken('uji')->plainTextToken;
    }

    /**
     * @return array<string, mixed>
     */
    private function rekap(User $kader, string $bulan = self::BULAN): array
    {
        return $this->withToken($this->token($kader))
            ->getJson("/api/kader/immunizations/recap?month={$bulan}")
            ->assertOk()
            ->json('data');
    }

    /** Jumlah suntikan satu jenis vaksin di bagian `activity`. */
    private function countFor(array $data, string $code): int
    {
        foreach ($data['activity']['by_type'] as $tipe) {
            if ($tipe['code'] === $code) {
                return $tipe['count'];
            }
        }

        $this->fail("Jenis vaksin {$code} tidak ada di activity.by_type");
    }

    /**
     * Jumlah query yang dijalankan selama satu callback.
     *
     * `refreshApplication` tidak ikut dihitung karena yang diukur hanya
     * permintaan HTTP-nya, termasuk query autentikasi Sanctum yang selalu sama.
     */
    private function hitungQuery(Closure $callback): int
    {
        DB::flushQueryLog();
        DB::enableQueryLog();

        try {
            $callback();
        } finally {
            $n = count(DB::getQueryLog());
            DB::disableQueryLog();

            return $n;
        }
    }
}
