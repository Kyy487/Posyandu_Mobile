<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\Measurement;
use App\Models\User;
use App\Services\GrowthChartService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Menguji `GET /children/{id}/growth` (Opsi D - Grafik Tumbuh Kembang).
 *
 * Nama test di sini bukan pilihan gaya: setiap aturan normatif di
 * `docs/arsip/RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md` bagian 7.3 dipetakan ke satu nama
 * test, dan pemetaan itu tidak boleh berubah diam-diam. Kalau nama di sini
 * diubah, tabel 7.3 yang harus ikut diperbarui.
 *
 * Test memakai PostgreSQL sungguhan, karena yang diuji justru perilaku yang
 * tidak ada di SQLite: partial unique index, soft delete, dan trigger z-score.
 */
class GrowthChartTest extends TestCase
{
    use RefreshDatabase;

    // =================================================================
    // Aturan 1-12 dari bagian 7.3
    // =================================================================

    /**
     * Aturan 1: `points` urut dari tanggal terlama ke terbaru.
     *
     * Urut naik, bukan menurun seperti timeline. Alasannya bukan selera: sumbu
     * x grafik dibaca dari kiri ke kanan, dan titik yang belum terjadi akan
     * menggambar garis melewati seluruh riwayat kalau urutannya dibalik.
     */
    #[Test]
    public function points_selalu_urut_dari_tanggal_terlama(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        // Sengaja tidak urut, supaya test ini tidak lulus hanya karena kebetulan
        // urut sama dengan urutan input.
        foreach (['2026-05-10', '2026-08-20', '2026-06-15'] as $tanggal) {
            Measurement::factory()->untukAnak($anak)->olehKader($kader)->padaTanggal($tanggal)->create();
        }

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $this->assertSame(
            ['2026-05-10', '2026-06-15', '2026-08-20'],
            array_column($respons->json('data.series.points'), 'date')
        );

        // `series.order` ada supaya klien tidak perlu menebak arah urut ini.
        $this->assertSame('asc', $respons->json('data.series.order'));
    }

    /**
     * Aturan 2: angka dari trigger dibaca, bukan dihitung ulang.
     *
     * `age_in_months`, `z_score_wfa`, dan `status_gizi` diisi trigger
     * PostgreSQL saat baris dicatat. Kalau service mengulang hitungannya dari
     * `date_of_birth`, hasilnya bisa meleset satu bulan dari yang tersimpan -
     * dan karena z-score bermula dari `age_in_months`, galatnya ikut terbawa ke
     * status gizi. Test ini membandingkan respons dengan baris yang benar-benar
     * ada di database, bukan dengan hitungan ulang.
     */
    #[Test]
    public function angka_trigger_dibaca_dari_database_tanpa_dihitung_ulang(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        Measurement::factory()->untukAnak($anak)->olehKader($kader)->padaTanggal('2026-07-01')->create();

        $tersimpan = Measurement::where('child_id', $anak->id)->firstOrFail();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $titik = $respons->json('data.series.points.0');

        // Angka desimal di-cast ke float di sisi server, tapi `json_encode`
        // menulis `56.0` sebagai `56`, jadi hasil decode JSON bisa bertipe int.
        // Perbandingan di sini memakai `assertEqualsWithDelta` supaya tipe JSON
        // tidak jadi bahan perdebatan sementara nilainya tetap harus sama
        // persis.
        $this->assertSame((int) $tersimpan->age_in_months, $titik['age_in_months']);
        $this->assertEqualsWithDelta(0.0, (float) $titik['z_score_wfa'] - (float) $tersimpan->z_score_wfa, 0.001);
        $this->assertSame($tersimpan->status_gizi, $titik['status_gizi']);
        $this->assertEqualsWithDelta(0.0, (float) $titik['weight_kg'] - (float) $tersimpan->weight_kg, 0.001);
        $this->assertEqualsWithDelta(0.0, (float) $titik['height_cm'] - (float) $tersimpan->height_cm, 0.001);

        // `child.age_in_months` harus umur pada penimbangan terakhir, bukan umur
        // hari ini. Menghitungnya dari `date_of_birth` akan menghasilkan angka
        // yang lebih besar setiap hari, dan itu definisi yang berbeda.
        $this->assertSame((int) $tersimpan->age_in_months, $respons->json('data.child.age_in_months'));
    }

    /** Aturan 3: baris yang dibatalkan tidak muncul di grafik. */
    #[Test]
    public function baris_yang_dibatalkan_tidak_muncul_di_grafik(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-07-01')->create();
        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-07-02')->dibatalkan()->create();
        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-07-03')->create();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $this->assertSame(
            ['2026-07-01', '2026-07-03'],
            array_column($respons->json('data.series.points'), 'date')
        );
    }

    /**
     * Aturan 4: anak tanpa penimbangan tetap 200 dengan `points: []`.
     *
     * Bukan 404. 404 di sini akan membuat layar Ibu menampilkan "anak tidak
     * ditemukan" untuk anak yang sebenarnya ada, padahal masalahnya cuma belum
     * pernah ditimbang - dan itu kondisi yang sangat sering terjadi.
     */
    #[Test]
    public function anak_tanpa_penimbangan_punya_points_kosong(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $this->assertSame([], $respons->json('data.series.points'));
        $this->assertSame($anak->id, $respons->json('data.child.id'));
        $this->assertNull($respons->json('data.child.age_in_months'));
    }

    /**
     * Aturan 5: di luar rentang WHO, `z_score_wfa` dan `status_gizi` tetap `null`.
     *
     * Trigger sengaja membiarkan keduanya kosong untuk anak di atas 60 bulan
     * daripada memaksa jadi "Normal" - lihat `2026_09_26_010000` langkah 5.
     * Yang diuji di sini adalah apakah keputusan itu diteruskan apa adanya:
     * nilai kosong tidak boleh diubah jadi 0, `"Normal"`, atau teks apa pun di
     * perjalanan ke klien.
     */
    #[Test]
    public function di_luar_rentang_who_z_score_tetap_null(): void
    {
        // Lahir 2019: diukur pada 2026 berarti 84 bulan, jauh di luar 0-60.
        $anak = Child::factory()->create(['date_of_birth' => '2019-01-01']);
        $kader = User::factory()->kader()->create();

        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-07-01')->create();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $titik = $respons->json('data.series.points.0');

        $this->assertNull($titik['z_score_wfa']);
        $this->assertNull($titik['status_gizi']);

        // Yang terisi harus tetap terisi: null bukan berarti data hilang.
        $this->assertNotNull($titik['weight_kg']);
        $this->assertNotNull($titik['age_in_months']);

        // Pita tetap dikirim, karena pita tidak bergantung pada riwayat.
        $this->assertNotEmpty($respons->json('data.who_reference.points'));
    }

    /**
     * Aturan 6: penimbangan tanpa kader tetap tampil.
     *
     * `kader_id` nullable dengan `ON DELETE SET NULL`. Kalau query memakai
     * `join` biasa ke `users`, riwayat anak yang kadernya sudah dihapus akan
     * hilang dari grafik - persis data yang paling tidak boleh hilang. Test ini
     * memakai `tanpaKader()` supaya baris tanpa kader tetap bisa dibaca tanpa
     * perlu akun kader sama sekali.
     */
    #[Test]
    public function penimbangan_tanpa_kader_tetap_tampil(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        Measurement::factory()
            ->untukAnak($anak)
            ->tanpaKader()
            ->padaTanggal('2026-08-15')
            ->create();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $this->assertCount(1, $respons->json('data.series.points'));
        $this->assertSame('2026-08-15', $respons->json('data.series.points.0.date'));
    }

    /**
     * Aturan 7: pita WHO hanya untuk berat badan.
     *
     * Database tidak punya tabel acuan TB/U, jadi `who_reference` tidak boleh
     * memuat pita tinggi badan. Tinggi badan tetap dikirim sebagai nilai mentah
     * di `points[].height_cm`, dan itu memang tidak punya pita.
     */
    #[Test]
    public function pita_who_hanya_untuk_berat_badan(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $this->assertSame('weight_for_age', $respons->json('data.who_reference.metric'));

        // Tidak boleh ada field pita tinggi badan di level apa pun.
        $this->assertNull($respons->json('data.who_reference.height_points'));
        $this->assertNull($respons->json('data.who_hfa_reference'));

        // Setiap titik pita hanya boleh punya empat field, semuanya satuan kg.
        foreach ($respons->json('data.who_reference.points') as $titik) {
            $this->assertSame(
                ['age_in_months', 'median_kg', 'lower_kg', 'upper_kg'],
                array_keys($titik)
            );
        }

        // Tinggi badan tetap ada sebagai nilai mentah di titik penimbangan.
        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-07-01')->create();
        $adaTitik = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");

        // `assertIsFloat` tidak bisa dipakai di sini: `json_encode` menulis
        // `88.0` sebagai `88`, jadi tinggi badan yang kebetulan bulat akan
        // terbaca integer dan test ini gagal acak. Yang diuji di sini adalah
        // angkanya terbaca, bukan tipe JSON-nya.
        $this->assertNotNull($adaTitik->json('data.series.points.0.height_cm'));
        $this->assertGreaterThan(
            0,
            (float) $adaTitik->json('data.series.points.0.height_cm')
        );
    }

    /** Aturan 8: pita mengikuti gender anak. */
    #[Test]
    public function pita_who_mengikuti_gender_anak(): void
    {
        $kader = User::factory()->kader()->create();

        $perempuan = $this->anak(['gender' => 'P']);
        $laki = $this->anak(['gender' => 'L']);

        $medP = $this->kader($kader)->getJson("/api/children/{$perempuan->id}/growth");
        $medL = $this->kader($kader)->getJson("/api/children/{$laki->id}/growth");

        $medP->assertOk();
        $medL->assertOk();

        $this->assertSame('P', $medP->json('data.who_reference.gender'));
        $this->assertSame('L', $medL->json('data.who_reference.gender'));
        $this->assertSame('P', $medP->json('data.child.gender'));
        $this->assertSame('L', $medL->json('data.child.gender'));

        // Titik pitanya harus benar-benar berbeda, bukan cuma label gender-nya.
        $this->assertNotSame(
            $medP->json('data.who_reference.points.30.median_kg'),
            $medL->json('data.who_reference.points.30.median_kg')
        );
    }

    /**
     * Aturan 9: pita dikirim walau `points` kosong.
     *
     * Pita tidak bergantung pada riwayat penimbangan, jadi layar bisa
     * menggambarnya sebelum kunjungan pertama. Kalau pita ikut hilang bersama
     * `points`, Ibu baru melihat kanvas kosong dan tidak tahu bahwa pita
     * hijau-kuning itu sebenarnya ada.
     */
    #[Test]
    public function pita_who_tetap_dikirim_saat_tanpa_penimbangan(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $this->assertSame([], $respons->json('data.series.points'));
        $this->assertCount(61, $respons->json('data.who_reference.points'));
        $this->assertSame(0, $respons->json('data.who_reference.age_range.from'));
        $this->assertSame(60, $respons->json('data.who_reference.age_range.to'));
    }

    /** Aturan 10: pita menutup 0 sampai 60 bulan, satu titik per umur. */
    #[Test]
    public function pita_who_menutup_rentang_0_sampai_60_bulan(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $umur = array_column($respons->json('data.who_reference.points'), 'age_in_months');

        $this->assertCount(61, $umur);
        $this->assertSame(range(0, 60), $umur);
        $this->assertSame(0, $respons->json('data.who_reference.age_range.from'));
        $this->assertSame(60, $respons->json('data.who_reference.age_range.to'));

        // Batas ±2 SD harus mengapit median: `lower_kg < median_kg < upper_kg`.
        foreach ($respons->json('data.who_reference.points') as $titik) {
            $median = $titik['median_kg'];
            $bawah = $titik['lower_kg'];
            $atas = $titik['upper_kg'];

            $this->assertLessThan($median, $bawah, 'Batas bawah harus di bawah median.');
            $this->assertLessThan($atas, $median, 'Batas atas harus di atas median.');
        }
    }

    /**
     * Aturan 11: seluruh riwayat dikembalikan, tanpa pagination.
     *
     * Endpoint ini sengaja tidak punya query string. Test ini mengirim
     * parameter yang *seharusnya* diabaikan, lalu membandingkan hasilnya dengan
     * respons tanpa parameter - kalau suatu saat ada pagination diam-diam, kedua
     * respons ini akan berbeda.
     */
    #[Test]
    public function seluruh_riwayat_dikembalikan_tanpa_paginasi(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        foreach (range(1, 12) as $bulan) {
            Measurement::factory()
                ->untukAnak($anak)
                ->padaTanggal('2026-'.str_pad((string) $bulan, 2, '0', STR_PAD_LEFT).'-01')
                ->create();
        }

        $tanpaParameter = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $tanpaParameter->assertOk();

        $denganParameter = $this->kader($kader)->getJson(
            "/api/children/{$anak->id}/growth?limit=2&before=2026-06-01&from=2026-01-01&to=2026-12-31"
        );
        $denganParameter->assertOk();

        $this->assertCount(12, $tanpaParameter->json('data.series.points'));
        $this->assertSame(
            $tanpaParameter->json('data.series.points'),
            $denganParameter->json('data.series.points')
        );

        // Tidak ada `meta`, karena tidak ada yang dipaginasi.
        $this->assertNull($tanpaParameter->json('data.meta'));
    }

    /**
     * Aturan 12: jumlah query tetap dua, tidak bergantung pada jumlah titik.
     *
     * Dua query: satu untuk titik penimbangan, satu untuk pita WHO. Yang diuji
     * adalah sifat "tidak bergantung", bukan angka mutlak - anak dengan 12
     * kunjungan harus membutuhkan jumlah query yang sama dengan anak yang punya
     * 1. Kalau ada refactor yang menambah satu query per titik, test ini gagal
     * bahkan kalau angka untuk kasus kecil masih terlihat benar.
     */
    #[Test]
    public function jumlah_query_tetap_dua(): void
    {
        $service = app(GrowthChartService::class);

        $anakSatu = $this->anakDenganRelasiSudahDimuat();
        Measurement::factory()->untukAnak($anakSatu)->padaTanggal('2026-02-01')->create();

        $anakBanyak = $this->anakDenganRelasiSudahDimuat();

        foreach (range(1, 12) as $bulan) {
            Measurement::factory()
                ->untukAnak($anakBanyak)
                ->padaTanggal('2026-'.str_pad((string) $bulan, 2, '0', STR_PAD_LEFT).'-01')
                ->create();
        }

        $jumlahSatu = $this->hitungQuery(fn () => $service->chartFor($anakSatu));
        $jumlahBanyak = $this->hitungQuery(fn () => $service->chartFor($anakBanyak));

        $this->assertSame(2, $jumlahSatu, 'Service harus memakai dua query: titik penimbangan dan pita WHO.');
        $this->assertSame(
            $jumlahSatu,
            $jumlahBanyak,
            'Jumlah query tidak boleh bergantung pada jumlah kunjungan.'
        );
    }

    // =================================================================
    // Otorisasi
    // =================================================================

    /** Ibu hanya boleh membuka grafik anaknya sendiri. */
    #[Test]
    public function ibu_membuka_anak_orang_ditolak(): void
    {
        $ibu = User::factory()->ibu()->create();
        $ibuLain = User::factory()->ibu()->create();
        $anakOrangLain = Child::factory()->milik($ibuLain)->create();

        $this->kader($ibu)
            ->getJson("/api/children/{$anakOrangLain->id}/growth")
            ->assertForbidden();
    }

    #[Test]
    public function ibu_membuka_anak_anaknya_sendiri_membalas_200(): void
    {
        $ibu = User::factory()->ibu()->create();
        $anak = Child::factory()->milik($ibu)->create(['date_of_birth' => '2024-01-01']);

        $respons = $this->kader($ibu)->getJson("/api/children/{$anak->id}/growth");

        $respons->assertOk();
        $this->assertSame($anak->id, $respons->json('data.child.id'));
    }

    #[Test]
    public function kader_bisa_membuka_grafik_anak_apa_saja(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01']);

        $this->kader($kader)->getJson("/api/children/{$anak->id}/growth")->assertOk();
    }

    /** `id` bukan UUID dibalas 404, bukan 500 dari error PostgreSQL. */
    #[Test]
    public function id_bukan_uuid_membalas_404(): void
    {
        $kader = User::factory()->kader()->create();

        $this->kader($kader)->getJson('/api/children/bukan-uuid/growth')->assertNotFound();
    }

    // =================================================================
    // Bentuk respons
    // =================================================================

    /**
     * Aturan 13: `data` berisi tepat empat kunci.
     *
     * Sebelumnya tiga (`child`, `series`, `who_reference`). Fitur
     * multidimensi menambah `who_references` - dan itu amendemen sadar, bukan
     * kebocoran: `who_reference` (tunggal, BB/U) sengaja dipertahankan supaya
     * klien lama tetap jalan. Test ini yang mengunci jumlah kunci, jadi
     * penambahan berikutnya harus lewat amendemen dokumen lagi.
     */
    #[Test]
    public function data_tepat_berisi_empat_kunci(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-07-01')->create();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $this->assertSame(
            ['child', 'series', 'who_reference', 'who_references'],
            array_keys($respons->json('data'))
        );

        // Envelope error juga tidak boleh bocor ke `data`.
        $this->assertSame(['success', 'message', 'data'], array_keys($respons->json()));

        $this->assertSame(
            ['unit', 'order', 'points'],
            array_keys($respons->json('data.series'))
        );
        // `bmi` ditambahkan aditif; `weight`/`height` tidak berubah.
        $this->assertSame(
            ['weight' => 'kg', 'height' => 'cm', 'bmi' => 'kg/m2'],
            $respons->json('data.series.unit')
        );
        $this->assertSame(
            ['id', 'name', 'nik', 'gender', 'date_of_birth', 'age_in_months', 'medical_flags'],
            array_keys($respons->json('data.child'))
        );
        $this->assertSame(
            ['metric', 'source', 'gender', 'age_range', 'points'],
            array_keys($respons->json('data.who_reference'))
        );
        $this->assertSame(
            ['metric', 'label', 'unit', 'x_axis', 'source', 'gender', 'age_range', 'points'],
            array_keys($respons->json('data.who_references.0'))
        );

        // Setiap titik penimbangan mendapat field multidimensi yang tetap
        // berbentuk sama, walau nilainya `null`.
        $this->assertSame(
            [
                'date', 'age_in_months', 'weight_kg', 'height_cm', 'head_circumference_cm',
                'bmi', 'z_score_wfa', 'status_gizi', 'z_score_hfa', 'status_stunting',
                'z_score_bfa', 'status_gizi_imt', 'z_score_wfh', 'status_wfh',
            ],
            array_keys($respons->json('data.series.points.0'))
        );
    }

    /**
     * Aturan 14: angka multidimensi dibaca apa adanya dari database.
     *
     * Sama seperti aturan 2 untuk BB/U: `z_score_hfa`/`status_stunting`,
     * `z_score_bfa`/`status_gizi_imt`, `z_score_wfh`/`status_wfh`, dan `bmi`
     * diisi trigger PostgreSQL saat baris dicatat. Test ini membandingkan
     * respons dengan baris yang benar-benar tersimpan, bukan hitungan ulang.
     * Anak sengaja berumur 17 bulan supaya BB/TB (< 24 bulan) ikut terisi.
     */
    #[Test]
    public function angka_multidimensi_dibaca_dari_database(): void
    {
        $anak = $this->anak(['gender' => 'P']);
        $kader = User::factory()->kader()->create();

        Measurement::factory()
            ->untukAnak($anak)
            ->padaTanggal('2025-06-01')
            ->create(['weight_kg' => 10.5, 'height_cm' => 79.0]);

        $tersimpan = Measurement::where('child_id', $anak->id)->firstOrFail();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $titik = $respons->json('data.series.points.0');

        $this->assertSame(17, $titik['age_in_months']);

        foreach (['z_score_hfa', 'z_score_bfa', 'z_score_wfh'] as $kolom) {
            $this->assertNotNull($tersimpan->{$kolom}, "Kolom $kolom seharusnya terisi.");
            $this->assertEqualsWithDelta(
                (float) $tersimpan->{$kolom},
                (float) $titik[$kolom],
                0.001,
                "Nilai $kolom tidak sama dengan baris database."
            );
        }

        $this->assertSame($tersimpan->status_stunting, $titik['status_stunting']);
        $this->assertSame($tersimpan->status_gizi_imt, $titik['status_gizi_imt']);
        $this->assertSame($tersimpan->status_wfh, $titik['status_wfh']);
    }

    /**
     * Aturan 15: `who_references` berisi tiga metrik dengan urutan normatif.
     *
     * BB/U, TB/U, IMT/U - bukan urutan alfabet dan bukan urutan tabel. Urutan
     * ini menentukan tombol mana yang muncul lebih dulu di layar, jadi ia
     * adalah kontrak, bukan detail penyajian.
     */
    #[Test]
    public function who_references_berisi_tiga_metrik_berurut(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $metrik = array_column($respons->json('data.who_references'), 'metric');
        $label = array_column($respons->json('data.who_references'), 'label');
        $unit = array_column($respons->json('data.who_references'), 'unit');

        $this->assertSame(['weight_for_age', 'height_for_age', 'bmi_for_age'], $metrik);
        $this->assertSame(['BB/U', 'TB/U', 'IMT/U'], $label);
        $this->assertSame(['kg', 'cm', 'kg/m2'], $unit);
    }

    /**
     * Aturan 16: pita TB/U dan IMT/U ikut gender anak dan cocok dengan tabel
     * acuan HFA/BFA untuk gender itu.
     *
     * Aturan 8 hanya membuktikan BB/U ikut gender. Test ini memperluasnya ke
     * dua pita baru, membandingkan tiap titik dengan hasil inverse LMS dari
     * `who_hfa_standards`/`who_bfa_standards` - konstanta yang sama yang dipakai
     * trigger, sehingga pita tidak mungkin memakai gender yang tertukar.
     */
    #[Test]
    public function pita_tbu_dan_imtu_mengikuti_gender_anak(): void
    {
        $kader = User::factory()->kader()->create();

        $medianPerGender = [];

        foreach (['P', 'L'] as $gender) {
            $anak = $this->anak(['gender' => $gender]);

            $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
            $respons->assertOk();

            $this->assertSame($gender, $respons->json('data.who_references.1.gender'));
            $this->assertSame($gender, $respons->json('data.who_references.2.gender'));

            // TB/U (indeks 1) dan IMT/U (indeks 2) dibandingkan dengan tabel
            // acuan untuk gender yang sama pada umur 24 bulan.
            foreach ([['who_hfa_standards', 1], ['who_bfa_standards', 2]] as [$tabel, $indeks]) {
                $acuan = DB::table($tabel)->where('gender', $gender)->where('age_in_months', 24)->first();
                $titik = collect($respons->json("data.who_references.$indeks.points"))->keyBy('age_in_months')->get(24);

                $this->assertEqualsWithDelta(
                    (float) $acuan->m,
                    (float) $titik['median'],
                    0.001,
                    "Median $tabel gender $gender umur 24 salah."
                );

                $bawah = (float) $acuan->m * (((float) $acuan->l) === 0.0
                    ? exp((float) $acuan->s * -2)
                    : ((1 + ((float) $acuan->l) * ((float) $acuan->s) * -2) ** (1.0 / ((float) $acuan->l))));

                $this->assertEqualsWithDelta(
                    $bawah,
                    (float) $titik['lower'],
                    0.001,
                    "Batas bawah $tabel gender $gender umur 24 salah."
                );
            }

            $medianPerGender[$gender] = $respons->json('data.who_references.1.points.24.median');
        }

        // Pita kedua gender harus benar-benar berbeda, bukan label gender saja.
        $this->assertNotSame($medianPerGender['P'], $medianPerGender['L']);
    }

    /**
     * Aturan 17: pita TB/U dan IMT/U dikirim walau `points` kosong dan menutup
     * 0-60 bulan (61 titik).
     *
     * Sama seperti aturan 9/10 untuk BB/U. Kalau pita baru hanya muncul
     * bersama data penimbangan, Ibu baru melihat kanvas kosong sebelum
     * kunjungan pertama - padahal pita WHO adalah acuan, bukan data anak.
     */
    #[Test]
    public function pita_tbu_dan_imtu_menutup_0_sampai_60_bulan(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $this->assertSame([], $respons->json('data.series.points'));

        foreach ([1 => 'height_for_age', 2 => 'bmi_for_age'] as $indeks => $metric) {
            $this->assertSame($metric, $respons->json("data.who_references.$indeks.metric"));

            $umur = array_column($respons->json("data.who_references.$indeks.points"), 'age_in_months');
            $this->assertCount(61, $umur, "Pita $metric harus punya 61 titik.");
            $this->assertSame(range(0, 60), $umur);
            $this->assertSame(0, $respons->json("data.who_references.$indeks.age_range.from"));
            $this->assertSame(60, $respons->json("data.who_references.$indeks.age_range.to"));

            foreach ($respons->json("data.who_references.$indeks.points") as $titik) {
                $this->assertLessThan($titik['median'], $titik['lower'], "Batas bawah $metric harus di bawah median.");
                $this->assertLessThan($titik['upper'], $titik['median'], "Batas atas $metric harus di atas median.");
            }
        }
    }

    /**
     * Aturan 18: `who_reference` (tunggal) konsisten dengan `who_references[0]`.
     *
     * WFA muncul di dua tempat dengan sengaja: yang tunggal mempertahankan
     * nama field lama (`median_kg` dst.) untuk kompatibilitas, yang jamak
     * memakai nama seragam (`median` dst.). Yang wajib sama adalah
     * `metric`/`source`/`gender`/`age_range` dan **nilai** tiap titiknya; kalau
     * keduanya pernah berasal dari angka berbeda, klien lama dan klien baru
     * akan menggambar pita yang berbeda dari tabel yang sama.
     */
    #[Test]
    public function who_reference_konsisten_dengan_who_references(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $tunggal = $respons->json('data.who_reference');
        $pertama = $respons->json('data.who_references.0');

        $this->assertSame($pertama['metric'], $tunggal['metric']);
        $this->assertSame($pertama['source'], $tunggal['source']);
        $this->assertSame($pertama['gender'], $tunggal['gender']);
        $this->assertSame($pertama['age_range'], $tunggal['age_range']);

        $this->assertCount(61, $tunggal['points']);

        foreach ($tunggal['points'] as $i => $titik) {
            $pasangan = $pertama['points'][$i];

            $this->assertSame($titik['age_in_months'], $pasangan['age_in_months']);
            $this->assertEqualsWithDelta((float) $titik['median_kg'], (float) $pasangan['median'], 0.0001);
            $this->assertEqualsWithDelta((float) $titik['lower_kg'], (float) $pasangan['lower'], 0.0001);
            $this->assertEqualsWithDelta((float) $titik['upper_kg'], (float) $pasangan['upper'], 0.0001);
        }
    }

    /**
     * Aturan 19: pita TB/U dan IMT/U konsisten dengan z-score yang dibaca
     * trigger.
     *
     * Pemeriksaan silang paling penting untuk dua indikator baru. Pita
     * dievaluasi service dari `(l, m, s)` di SQL; z-score dihitung trigger dari
     * `(l, m, s)` yang sama. Test ini mengevaluasi ulang **dari baris acuan
     * yang sama** lalu membandingkan keduanya: kalau service dan trigger pernah
     * memakai tabel atau rumus yang berbeda, kader akan melihat anak
     * berstatus "Stunting" dengan titik di dalam pita.
     */
    #[Test]
    public function pita_tbu_dan_imtu_konsisten_dengan_z_score_trigger(): void
    {
        $anak = $this->anak(['gender' => 'L']);
        $kader = User::factory()->kader()->create();

        // 2024-01-01 + 18 bulan -> 2025-07-01, tinggi 82 cm: di dalam rentang
        // HFA, dan masih < 24 bulan sehingga BB/TB juga terisi.
        Measurement::factory()
            ->untukAnak($anak)
            ->padaTanggal('2025-07-01')
            ->create(['weight_kg' => 11.0, 'height_cm' => 82.0]);

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $titik = $respons->json('data.series.points.0');
        $this->assertSame(18, $titik['age_in_months']);

        $kasus = [
            ['who_hfa_standards', 'height_cm', 1, 'z_score_hfa'],
            ['who_bfa_standards', 'bmi', 2, 'z_score_bfa'],
        ];

        foreach ($kasus as [$tabel, $fieldNilai, $indeks, $fieldZ]) {
            $acuan = DB::table($tabel)->where('gender', 'L')->where('age_in_months', 18)->first();
            $l = (float) $acuan->l;
            $m = (float) $acuan->m;
            $s = (float) $acuan->s;
            $nilai = (float) $titik[$fieldNilai];

            $z = $l === 0.0
                ? log($nilai / $m) / $s
                : ((($nilai / $m) ** $l) - 1) / ($l * $s);

            $this->assertEqualsWithDelta(
                $z,
                (float) $titik[$fieldZ],
                0.01,
                "z-score $tabel tidak cocok dengan nilai yang digambar."
            );

            $bawah = $l === 0.0 ? $m * exp($s * -2) : $m * ((1 + $l * $s * -2) ** (1.0 / $l));
            $atas = $l === 0.0 ? $m * exp($s * 2) : $m * ((1 + $l * $s * 2) ** (1.0 / $l));

            $pita = collect($respons->json("data.who_references.$indeks.points"))->keyBy('age_in_months')->get(18);

            $this->assertEqualsWithDelta($bawah, (float) $pita['lower'], 0.001, "Batas bawah $tabel salah.");
            $this->assertEqualsWithDelta($atas, (float) $pita['upper'], 0.001, "Batas atas $tabel salah.");
        }
    }

    /**
     * Aturan 20: `bmi` = berat / (tinggi/100)² dibulatkan dua desimal.
     *
     * IMT/U bersatuan kg/m², jadi titik anak harus sejajar dengan pita BFA.
     * BMI dihitung di SQL, bukan di Dart, supaya satu rumus hanya hidup di satu
     * tempat. Schema mewajibkan `weight_kg`/`height_cm`, jadi cabang `null`
     * hanya bisa terjadi saat tinggi nol - itu yang diuji di sini, bukan baris
     * tanpa tinggi yang memang tidak mungkin ada.
     */
    #[Test]
    public function bmi_dihitung_dari_berat_dan_tinggi(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        // 2024-01-01 + 27 bulan -> 2026-04-01.
        Measurement::factory()
            ->untukAnak($anak)
            ->padaTanggal('2026-04-01')
            ->create(['weight_kg' => 12.4, 'height_cm' => 88.0]);

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        // 12.4 / 0.88^2 = 16.0124... -> 16.01
        $this->assertEqualsWithDelta(16.01, (float) $respons->json('data.series.points.0.bmi'), 0.001);

        // Tinggi 0: guard `height_cm > 0` membuat `bmi` null, bukan error
        // pembagian dan bukan angka tak hingga.
        $anakNol = $this->anak(['date_of_birth' => '2024-01-01']);
        Measurement::factory()
            ->untukAnak($anakNol)
            ->padaTanggal('2026-04-01')
            ->create(['weight_kg' => 12.4, 'height_cm' => 0]);

        $responsNol = $this->kader($kader)->getJson("/api/children/{$anakNol->id}/growth");
        $responsNol->assertOk();

        $this->assertNull($responsNol->json('data.series.points.0.bmi'));
    }

    /**
     * Aturan 21: BB/TB tanpa pita.
     *
     * `z_score_wfh` dan `status_wfh` hanya bermakna untuk anak < 24 bulan
     * (acuan BB/TB diindeks panjang badan, bukan umur). Tidak ada entri
     * `who_references` bermetrik `weight_for_height`: menyatukannya dengan tiga
     * grafik bersumbu umur akan membuat satu kanvas punya dua arti sumbu x.
     */
    #[Test]
    public function bb_tb_tanpa_pita(): void
    {
        $kader = User::factory()->kader()->create();

        // < 24 bulan: 2024-06-01 + 12 bulan -> 2025-06-01.
        $bayi = $this->anak(['date_of_birth' => '2024-06-01']);
        Measurement::factory()
            ->untukAnak($bayi)
            ->padaTanggal('2025-06-01')
            ->create(['weight_kg' => 9.6, 'height_cm' => 75.0]);

        // >= 24 bulan: 2024-01-01 + 30 bulan -> 2026-07-01.
        $besar = $this->anak(['date_of_birth' => '2024-01-01']);
        Measurement::factory()
            ->untukAnak($besar)
            ->padaTanggal('2026-07-01')
            ->create(['weight_kg' => 13.0, 'height_cm' => 90.0]);

        $responsBayi = $this->kader($kader)->getJson("/api/children/{$bayi->id}/growth");
        $responsBesar = $this->kader($kader)->getJson("/api/children/{$besar->id}/growth");

        $responsBayi->assertOk();
        $responsBesar->assertOk();

        $titikBayi = $responsBayi->json('data.series.points.0');
        $this->assertNotNull($titikBayi['z_score_wfh'], 'BB/TB harus terisi untuk umur < 24 bulan.');
        $this->assertNotNull($titikBayi['status_wfh']);

        // Status BB/TB diklasifikasi trigger dengan ambang yang sama seperti
        // indicator lain; diuji di sini supaya kolom baru bukan sekadar terisi.
        $z = (float) $titikBayi['z_score_wfh'];
        $harapanStatus = match (true) {
            $z < -3 => 'Gizi Buruk',
            $z < -2 => 'Gizi Kurang',
            $z > 2 => 'Risiko Gizi Lebih',
            default => 'Normal',
        };
        $this->assertSame($harapanStatus, $titikBayi['status_wfh']);

        $this->assertNull(
            $responsBesar->json('data.series.points.0.z_score_wfh'),
            'BB/TB harus null untuk umur >= 24 bulan.'
        );
        $this->assertNull($responsBesar->json('data.series.points.0.status_wfh'));

        $metrik = array_column($responsBayi->json('data.who_references'), 'metric');
        $this->assertNotContains('weight_for_height', $metrik);
        $this->assertSame(['weight_for_age', 'height_for_age', 'bmi_for_age'], $metrik);
    }

    /** Tidak ada dua titik pada tanggal sama, dan mengurut ulang tidak mengubah apa pun. */
    #[Test]
    public function tidak_ada_dua_titik_pada_tanggal_sama(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        foreach (['2026-01-01', '2026-03-01', '2026-02-01', '2026-04-01'] as $tanggal) {
            Measurement::factory()->untukAnak($anak)->padaTanggal($tanggal)->create();
        }

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $tanggal = array_column($respons->json('data.series.points'), 'date');

        $this->assertSame(array_values(array_unique($tanggal)), $tanggal);
        $this->assertSame(['2026-01-01', '2026-02-01', '2026-03-01', '2026-04-01'], $tanggal);
    }

    /** `medical_flags` ikut terbaca apa adanya di blok `child`. */
    #[Test]
    public function medical_flags_terbaca_apa_adanya(): void
    {
        $anak = $this->anak(['medical_flags' => 'Asma, Alergi']);
        $kader = User::factory()->kader()->create();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $this->assertSame('Asma, Alergi', $respons->json('data.child.medical_flags'));
    }

    /**
     * `medical_flags` kosong harus tetap null, bukan string kosong.
     *
     * Ditambahkan karena `medical_flags` nullable: kalau lapisan serialisasi
     * mengubah `null` jadi `""`, mobile akan menampilkan chip "Tidak ada
     * catatan" yang berbeda dari kondisi anak yang memang tidak punya catatan.
     */
    #[Test]
    public function medical_flags_kosong_tetap_null(): void
    {
        $anak = $this->anak(['medical_flags' => null]);
        $kader = User::factory()->kader()->create();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $this->assertNull($respons->json('data.child.medical_flags'));
    }

    // =================================================================
    // Test tambahan di luar daftar 7.3
    // =================================================================

    /**
     * Anak di atas 60 bulan tetap dapat titik, dengan z-score kosong.
     *
     * Berbeda dari aturan 5 (`di_luar_rentang_who_z_score_tetap_null`) yang
     * memeriksa isi titiknya: test ini memeriksa bahwa titiknya tetap ada.
     *
     * Penyaringan titik berdasarkan rentang WHO akan terlihat benar di satu
     * kasus saja - anak yang di atas 60 bulan akan punya garis yang berhenti
     * mendadak, dan tidak ada yang bisa membedakannya dari "tidak pernah
     * ditimbang lagi". Grafik yang hilang lebih buruk daripada grafik tanpa
     * z-score, jadi yang diuji: titik ada, angkanya ada, dan hanya z-score
     * beserta statusnya yang kosong.
     */
    #[Test]
    public function anak_di_atas_60_bulan_tetap_mendapat_poin_dengan_z_score_null(): void
    {
        // Lahir 2019-01-01, ditimbang 2026-08-01: 7 tahun 7 bulan = 91 bulan.
        $anak = $this->anak(['date_of_birth' => '2019-01-01']);
        $kader = User::factory()->kader()->create();

        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-08-01')->create();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $titik = $respons->json('data.series.points');
        $this->assertCount(1, $titik, 'Anak di luar rentang WHO tetap harus punya titik.');

        // Yang kosong hanya z-score dan statusnya.
        $this->assertNull($titik[0]['z_score_wfa']);
        $this->assertNull($titik[0]['status_gizi']);

        // Umur dan ukuran tetap terbaca, dan umurnya memang di luar rentang.
        $this->assertSame(91, $titik[0]['age_in_months']);
        $this->assertSame(91, $respons->json('data.child.age_in_months'));
        $this->assertGreaterThan(0, (float) $titik[0]['weight_kg']);
        $this->assertGreaterThan(0, (float) $titik[0]['height_cm']);

        // Pita tetap dikirim, karena pita tidak bergantung pada riwayat.
        $this->assertCount(61, $respons->json('data.who_reference.points'));
    }

    /**
     * Cuma `L` dan `P` yang menghasilkan pita, dan pitanya sesuai tabel acuan.
     *
     * Aturan 8 (`pita_who_mengikuti_gender_anak`) hanya membuktikan bahwa dua
     * gender menghasilkan dua pita yang berbeda. Itu belum menyingkirkan
     * kemungkinan keduanya salah: pita "P" bisa saja berisi angka `L` yang
     * kebetulan tidak sama persis setelah pembulatan. Test ini membandingkan
     * setiap titik pita dengan baris `who_wfa_standards` untuk gender itu, satu
     * per satu.
     *
     * `children.gender` adalah enum `L`/`P` di database, jadi tidak ada gender
     * ketiga untuk diuji. Yang diuji justru bahwa kedua gender itu masing-masing
     * ketemu barisnya sendiri dan tidak tertukar.
     */
    #[Test]
    public function gender_anak_hanya_l_dan_p_menghasilkan_pita_yang_sesuai(): void
    {
        $kader = User::factory()->kader()->create();

        foreach (['P', 'L'] as $gender) {
            $anak = $this->anak(['gender' => $gender]);

            $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
            $respons->assertOk();

            $this->assertSame($gender, $respons->json('data.who_reference.gender'));

            $pita = collect($respons->json('data.who_reference.points'))
                ->keyBy('age_in_months');

            $harapan = DB::table('who_wfa_standards')
                ->where('gender', $gender)
                ->orderBy('age_in_months')
                ->get([
                    'age_in_months',
                    'median_kg',
                    DB::raw('median_kg - 2 * sd_kg as lower_kg'),
                    DB::raw('median_kg + 2 * sd_kg as upper_kg'),
                ])
                ->keyBy('age_in_months');

            $this->assertCount(61, $pita, "Pita gender $gender harus punya 61 titik.");

            foreach ($harapan as $umur => $baris) {
                $titik = $pita->get($umur);
                $this->assertNotNull($titik, "Pita gender $gender tidak punya umur $umur.");

                // Dilonggarkan ke 0,001 karena kolomnya `NUMERIC(6,3)` dan
                // konversi ke float di PHP bisa menyimpang di digit terakhir.
                // Yang diuji adalah pitanya pita gender lain, bukan ketelitian
                // pembulatan desimal ketiga.
                $this->assertEqualsWithDelta(
                    (float) $baris->median_kg,
                    (float) $titik['median_kg'],
                    0.001,
                    "Median gender $gender umur $umur salah."
                );
                $this->assertEqualsWithDelta(
                    (float) $baris->lower_kg,
                    (float) $titik['lower_kg'],
                    0.001,
                    "Batas bawah gender $gender umur $umur salah."
                );
                $this->assertEqualsWithDelta(
                    (float) $baris->upper_kg,
                    (float) $titik['upper_kg'],
                    0.001,
                    "Batas atas gender $gender umur $umur salah."
                );
            }
        }
    }

    /**
     * Pita dan z-score dari trigger tidak boleh pernah bertentangan.
     *
     * Ini pemeriksaan silang yang paling penting di seluruh endpoint.
     * `status_gizi` dihitung trigger dari `median_kg` dan `sd_kg`, sedangkan pita
     * dikirim dari tabel acuan yang sama. Kalau keduanya pernah memakai angka
     * yang berbeda, kader akan melihat anak berstatus "Gizi Kurang" dengan garis
     * yang berada **di dalam** area abu-abu. Dua tampilan itu masing-masing
     * terlihat benar dan salahnya tidak terdeteksi.
     *
     * Test ini membaca median dan sd **dari pita respons itu sendiri**
     * (`sd = (upper - lower) / 4`), lalu membandingkan hasilnya dengan z-score
     * yang dibaca dari baris database. Dengan begitu test tidak mengulang
     * rumus trigger, tapi memeriksa bahwa pita dan z-score benar-benar berasal
     * dari angka yang sama.
     */
    #[Test]
    public function garis_pita_konsisten_dengan_z_score_yang_dibaca_trigger(): void
    {
        // Lahir 2024-01-01, ditimbang 2026-04-01 s/d 2026-06-01: umur 27, 28,
        // dan 29 bulan. Gender dikunci ke `P` supaya median dan sd-nya pasti.
        $anak = $this->anak(['gender' => 'P']);
        $kader = User::factory()->kader()->create();

        // Untuk anak perempuan 27-29 bulan mediannya sekitar 12,1-12,5 kg dan
        // sd-nya 1,2-1,3 kg, jadi pita naik dari sekitar 9,7-10,1 kg sampai
        // 14,5-15,1 kg. Ketiga berat ini karena itu pasti jatuh di bawah pita,
        // di dalam pita, dan di atas pita.
        $kasus = [
            ['tanggal' => '2026-04-01', 'berat' => 9.0, 'status' => 'Gizi Kurang'],
            ['tanggal' => '2026-05-01', 'berat' => 12.3, 'status' => 'Normal'],
            ['tanggal' => '2026-06-01', 'berat' => 16.0, 'status' => 'Risiko Gizi Lebih'],
        ];

        foreach ($kasus as $satu) {
            Measurement::factory()
                ->untukAnak($anak)
                ->padaTanggal($satu['tanggal'])
                ->create(['weight_kg' => $satu['berat']]);
        }

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $pita = collect($respons->json('data.who_reference.points'))
            ->keyBy('age_in_months');
        $titik = collect($respons->json('data.series.points'))->keyBy('date');

        foreach ($kasus as $satu) {
            $titikIni = $titik->get($satu['tanggal']);
            $this->assertNotNull($titikIni, "Titik tanggal {$satu['tanggal']} hilang.");

            $acuan = $pita->get($titikIni['age_in_months']);
            $this->assertNotNull($acuan, "Pita untuk umur {$titikIni['age_in_months']} hilang.");

            $median = (float) $acuan['median_kg'];
            $bawah = (float) $acuan['lower_kg'];
            $atas = (float) $acuan['upper_kg'];
            $sd = ($atas - $bawah) / 4;
            $berat = (float) $titikIni['weight_kg'];

            $this->assertGreaterThan(0, $sd, 'Lebar pita tidak boleh nol.');

            // Trigger memakai `ROUND(..., 2)`, jadi selisih 0,01 masih diterima.
            $perhitungan = round(($berat - $median) / $sd, 2);

            $this->assertEqualsWithDelta(
                $perhitungan,
                (float) $titikIni['z_score_wfa'],
                0.01,
                "z-score tanggal {$satu['tanggal']} tidak cocok dengan pitanya."
            );

            $diDalamPita = $bawah <= $berat && $berat <= $atas;

            // Status dan posisi harus selalu sepakat. Ini yang dilihat kader:
            // anak berstatus "Normal" berarti titiknya berada di dalam pita.
            $this->assertSame(
                $satu['status'],
                $titikIni['status_gizi'],
                "Status gizi tanggal {$satu['tanggal']} tidak sesuai posisinya terhadap pita."
            );
            $this->assertSame(
                $satu['status'] === 'Normal',
                $diDalamPita,
                "Status '{$satu['status']}' tanggal {$satu['tanggal']} tidak cocok dengan "
                ."posisi titiknya terhadap pita $bawah - $atas kg."
            );
        }
    }

    /**
     * Umur di tiap titik sama dengan umur kalender yang dipakai trigger.
     *
     * Trigger menghitung `EXTRACT(YEAR FROM age(tanggal, lahir)) * 12 +
     * EXTRACT(MONTH FROM age(tanggal, lahir))`, jadi umurnya bulan lengkap
     * berdasarkan kalender. Hitungan ulang di server atau di klien terlihat
     * benar untuk sebagian besar tanggal dan meleset pada tanggal berulang
     * tahun - dan karena z-score berawal dari umur itu, satu bulan meleset
     * ikut menggeser status gizi.
     *
     * Tanggal lahir dan tanggal penimbangan sengaja dipilih **hari tanggal
     * sama**, semua tanggal 1, supaya hitungan kalender tidak punya ambiguitas
     * bulan pendek. Test dengan tanggal melintasi akhir bulan bisa hijau
     * karena kebetulan, bukan karena kodenya benar.
     */
    #[Test]
    public function titik_punya_umur_kalendar_yang_sama_dengan_trigger(): void
    {
        $anak = $this->anak(['date_of_birth' => '2024-01-01']);
        $kader = User::factory()->kader()->create();

        // 1, 6, 12, dan 30 bulan setelah lahir. Yang 12 bulan sengaja
        // melintasi pergantian tahun, jadi z-score-nya ikut teruji.
        foreach (['2024-02-01', '2024-07-01', '2025-01-01', '2026-07-01'] as $tanggal) {
            Measurement::factory()->untukAnak($anak)->padaTanggal($tanggal)->create();
        }

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $harapanUmur = [
            '2024-02-01' => 1,
            '2024-07-01' => 6,
            '2025-01-01' => 12,
            '2026-07-01' => 30,
        ];

        // Dibaca dari database, supaya test ini tidak bisa lulus kalau server dan
        // test sama-sama salah dengan cara yang sama persis.
        $tersimpan = Measurement::where('child_id', $anak->id)
            ->orderBy('measurement_date')
            ->get()
            ->keyBy(fn (Measurement $m): string => (string) $m->measurement_date);

        $this->assertCount(4, $respons->json('data.series.points'));

        foreach ($respons->json('data.series.points') as $titik) {
            $bulan = $harapanUmur[$titik['date']];

            $this->assertSame(
                $bulan,
                $titik['age_in_months'],
                "Umur pada tanggal {$titik['date']} seharusnya $bulan bulan."
            );

            $this->assertSame(
                (int) $tersimpan->get($titik['date'])->age_in_months,
                $titik['age_in_months']
            );
        }

        // Blok anak berisi umur penimbangan terakhir (30 bulan), bukan umur hari
        // ini. Menghitungnya ulang dari `date_of_birth` hari ini menghasilkan
        // angka yang lebih besar setiap hari, dan itu definisi yang berbeda.
        $this->assertSame(30, $respons->json('data.child.age_in_months'));
    }

    /**
     * Angka desimal dikirim sebagai angka, bukan teks.
     *
     * PostgreSQL mengirim `NUMERIC` sebagai string (`"12.40"`), termasuk hasil
     * `median_kg - 2 * sd_kg`. Kalau tidak dipaksa float di
     * `GrowthChartService::angka()`, Flutter membacanya sebagai `String` dan
     * `fl_chart` menggambar titik di posisi yang salah, atau tidak
     * menggambarnya sama sekali.
     *
     * Yang diperiksa adalah tipe JSON-nya, tapi lewat `is_int` atau
     * `is_float` dan nilai yang lebih besar dari nol, bukan `assertIsFloat`:
     * `json_encode` menulis `88.0` sebagai `88`, jadi `assertIsFloat` akan gagal
     * acak tergantung angka yang kebetulan keluar dari factory.
     */
    #[Test]
    public function nilai_desimal_dibaca_sebagai_angka_bukan_teks(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        Measurement::factory()
            ->untukAnak($anak)
            ->padaTanggal('2026-07-01')
            ->create(['weight_kg' => 12.4, 'height_cm' => 88.0]);

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/growth");
        $respons->assertOk();

        $titik = $respons->json('data.series.points.0');

        foreach (['weight_kg', 'height_cm', 'head_circumference_cm', 'z_score_wfa'] as $field) {
            $nilai = $titik[$field];

            $this->assertTrue(
                is_int($nilai) || is_float($nilai),
                "Angka titik $field dikirim sebagai ".get_debug_type($nilai).', bukan angka.'
            );
        }

        // `age_in_months` juga angka, tapi diuji sebagai integer supaya
        // penyimpangan tipe di kolom ini tidak lolos diam-diam.
        $this->assertIsInt($titik['age_in_months']);

        foreach (['median_kg', 'lower_kg', 'upper_kg'] as $field) {
            $nilai = $respons->json("data.who_reference.points.30.$field");

            $this->assertTrue(
                is_int($nilai) || is_float($nilai),
                "Angka pita $field dikirim sebagai ".get_debug_type($nilai).', bukan angka.'
            );
        }

        // Ketiga batas pita harus punya nilai positif. Pita yang mediannya 0
        // terlihat benar di layar sambil menarik seluruh sumbu y ke bawah.
        $this->assertGreaterThan(0, (float) $respons->json('data.who_reference.points.30.median_kg'));
        $this->assertGreaterThan(0, (float) $respons->json('data.who_reference.points.30.lower_kg'));
        $this->assertGreaterThan(0, (float) $respons->json('data.who_reference.points.30.upper_kg'));

        // Kebetulan: beratnya benar-benar desimal dan tidak berubah jadi
        // integer karena pembulatan, jadi test ini tidak bisa lulus kalau
        // semua angka diam-diam jadi bulat.
        $this->assertEqualsWithDelta(12.4, (float) $titik['weight_kg'], 0.001);
    }

    // =================================================================
    // Helper
    // =================================================================

    /**
     * Anak dengan tanggal lahir yang pasti.
     *
     * `ChildFactory` mengisi `date_of_birth` acak antara 5 tahun dan 1 bulan
     * lalu, sedangkan trigger menolak penimbangan yang lebih awal dari tanggal
     * lahir anak. Pasangkan anak acak dengan tanggal penimbangan hardcode dan
     * test ini gagal sekitar 1 dari 8 kali jalannya - bukan karena kodenya
     * salah, tapi karena hasilnya tidak bisa diprediksi. Tanggal lahir
     * ditetapkan di sini supaya kelulusannya tidak bergantung pada tanggal hari
     * ini.
     *
     * 2024-01-01 dipilih supaya penimbangan di 2026 berumur 12-31 bulan: masih
     * di dalam rentang WHO, jadi `z_score_wfa` dan `status_gizi` terisi dan
     * aturan 2 punya sesuatu untuk dibandingkan.
     *
     * @param  array<string, mixed>  $atribut
     */
    private function anak(array $atribut = []): Child
    {
        return Child::factory()->create(['date_of_birth' => '2024-01-01', ...$atribut]);
    }

    /**
     * Anak dengan `mother` dan `latestMeasurement` yang sudah dimuat.
     *
     * Dipakai test penghitung query: `ChildController` mengambil anak lewat
     * `findChildForUser()`, dan `Child` punya `$with = ['latestMeasurement']`,
     * jadi relasi sudah ada waktu service dipanggil. Kalau test memanggil
     * service dengan model yang relasinya belum dimuat, Eloquent menambah
     * query lazy-load dan angka yang diukur jadi tidak lagi soal grafik.
     */
    private function anakDenganRelasiSudahDimuat(): Child
    {
        return $this->anak()->load(['mother', 'latestMeasurement']);
    }

    /**
     * Login sebagai pengguna tertentu lewat Bearer token, sama seperti yang
     * dilakukan mobile.
     */
    private function kader(User $user): self
    {
        return $this->withHeader('Authorization', 'Bearer '.$user->createToken('uji')->plainTextToken);
    }

    /**
     * Jumlah query yang dijalankan di dalam `$callback`.
     *
     * Dipakai untuk menguji aturan "jumlah query tetap" tanpa mengikat test ini
     * ke angka absolut: kalau ada refactor internal, test ini tetap lulus selama
     * jumlahnya tidak bergantung pada data.
     */
    private function hitungQuery(callable $callback): int
    {
        DB::flushQueryLog();
        DB::enableQueryLog();
        $callback();
        $jumlah = count(DB::getQueryLog());
        DB::disableQueryLog();

        return $jumlah;
    }
}
