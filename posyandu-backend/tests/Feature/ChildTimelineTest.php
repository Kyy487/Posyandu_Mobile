<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\ImmunizationRecord;
use App\Models\ImmunizationType;
use App\Models\Measurement;
use App\Models\MedicalNote;
use App\Models\User;
use App\Services\ChildTimelineService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Menguji `GET /children/{id}/timeline` (Opsi B - Buku Medis Digital).
 *
 * Nama test di sini bukan pilihan gaya: setiap aturan di
 * `docs/RANCANGAN_BUKU_MEDIS.md` bagian 7.3 dipetakan ke satu nama test, dan
 * pemetaan itu tidak boleh berubah diam-diam. Kalau aturan ditambah, testnya
 * ditambah dengan nama yang sama di tabel itu. Kalau nama di sini diubah,
 * tabel 7.3 yang harus ikut diperbarui.
 *
 * Test memakai PostgreSQL sungguhan, karena yang diuji justru perilaku yang
 * tidak ada di SQLite: partial unique index, soft delete, dan trigger z-score.
 */
class ChildTimelineTest extends TestCase
{
    use RefreshDatabase;

    // =================================================================
    // Aturan 1-7 dari bagian 7.3
    // =================================================================

    /** Aturan 1: `entries` selalu urut dari yang terbaru. */
    #[Test]
    public function entries_selalu_urut_dari_tanggal_terbaru(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        // Sengaja dibuat tidak berurutan, supaya test ini tidak lulus hanya
        // karena kebetulan urut sama dengan urutan input.
        foreach (['2026-05-10', '2026-08-20', '2026-06-15'] as $tanggal) {
            Measurement::factory()->untukAnak($anak)->olehKader($kader)->padaTanggal($tanggal)->create();
        }

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/timeline");
        $respons->assertOk();

        $tanggal = array_column($respons->json('data.entries'), 'date');

        $this->assertSame(['2026-08-20', '2026-06-15', '2026-05-10'], $tanggal);
    }

    /** Aturan 2: baris yang dibatalkan tidak muncul di timeline. */
    #[Test]
    public function baris_yang_dibatalkan_tidak_muncul_di_timeline(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();
        $dosis = ImmunizationType::factory()->create();

        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-07-01')->create();
        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-07-02')->dibatalkan()->create();
        ImmunizationRecord::factory()
            ->untukAnak($anak)->untukDosis($dosis)->padaTanggal('2026-07-03')->create();
        ImmunizationRecord::factory()
            ->untukAnak($anak)->padaTanggal('2026-07-04')->dibatalkan()->create();
        MedicalNote::factory()->untukAnak($anak)->demam()->create(['note_date' => '2026-07-05']);

        // Keluhan yang dibatalkan, bukan dibuat dengan `deleted_at` manual.
        // `delete()` mengisi timestamp-nya sendiri; selain itu CHECK
        // `medical_notes_isi_check` menolak baris kosong, jadi notes yang
        // dibuat tanpa keluhan dan tanpa catatan harus tetap lewat `demam()`.
        MedicalNote::factory()->untukAnak($anak)->demam()->create(['note_date' => '2026-07-06'])->delete();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/timeline");
        $respons->assertOk();

        $tanggal = array_column($respons->json('data.entries'), 'date');

        // 02, 04, dan 06 dibatalkan - harus hilang dari daftar tanggal DAN dari
        // isi. Kalau tanggalnya masih ada padahal isinya disembunyikan, `limit`
        // akan tetap terpotong oleh tanggal yang tidak berisi apa pun.
        $this->assertSame(['2026-07-05', '2026-07-03', '2026-07-01'], $tanggal);
    }

    /**
     * Aturan 3: keluhan tetap tampil walau penimbangannya dibatalkan.
     *
     * `medical_notes.measurement_id` sengaja tidak jadi `null` saat
     * penimbangan di-soft delete (lihat `MeasurementRecapTest`). Konsekuensinya
     * di sini: timeline tidak boleh menyembunyikan keluhan hanya karena
     * `measurement` di entri itu `null` - keluhan itu tetap bagian dari
     * kunjungan yang sah.
     */
    #[Test]
    public function keluhan_tetap_muncul_walau_penimbangan_tertaut_dibatalkan(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        $penimbangan = Measurement::factory()
            ->untukAnak($anak)
            ->olehKader($kader)
            ->padaTanggal('2026-08-01')
            ->create();

        MedicalNote::factory()
            ->untukAnak($anak)
            ->olehKader($kader)
            ->demam()
            ->create(['measurement_id' => $penimbangan->id, 'note_date' => '2026-08-01']);

        $penimbangan->delete();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/timeline");
        $respons->assertOk();

        $entri = collect($respons->json('data.entries'))->firstWhere('date', '2026-08-01');

        $this->assertNotNull($entri, 'Entri tanggal 2026-08-01 harus tetap ada walaupun penimbangannya dibatalkan.');
        $this->assertNull($entri['measurement']);
        $this->assertTrue($entri['medical_note']['demam']);
        $this->assertSame(MedicalNote::TINDAK_LANJUT_RUJUK, $entri['medical_note']['tindak_lanjut']);
    }

    /**
     * Aturan 4: tidak ada penghitungan ulang di server.
     *
     * Z-score, `age_in_months`, dan `status_gizi` dihitung trigger PostgreSQL.
     * Test ini membandingkan nilai respons dengan nilai yang benar-benar ada di
     * database, jadi server yang diam-diam menghitung ulang dengan rumus sendiri
     * akan gagal di sini.
     */
    #[Test]
    public function nilai_z_score_dibaca_dari_database_tanpa_dihitung_ulang(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        $penimbangan = Measurement::factory()
            ->untukAnak($anak)
            ->olehKader($kader)
            ->padaTanggal('2026-08-10')
            ->create();

        // Nilai yang dibaca harus persis yang trigger tulis. Kalau service
        // menghitung ulang, angka yang cocok hanya kebetulan pada satu baris.
        $tersimpan = DB::table('measurements')
            ->where('id', $penimbangan->id)
            ->first(['z_score_wfa', 'status_gizi', 'age_in_months']);

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/timeline");
        $respons->assertOk();

        $entri = $respons->json('data.entries.0.measurement');

        // `assertEqualsWithDelta`, bukan `assertSame`: service memang mengirim
        // float, tapi `json_encode` menulis `56.0` sebagai `56`, jadi hasil
        // `json_decode` bisa bertipe integer. Perbandingan tipe membuat test ini
        // gagal acak - hanya kalau z-score kebetulan bulat, yang bergantung
        // pada angka acak dari factory. Nilainya tetap harus sama persis.
        $this->assertEqualsWithDelta(0.0, (float) $entri['z_score_wfa'] - (float) $tersimpan->z_score_wfa, 0.001);
        $this->assertSame($tersimpan->status_gizi, $entri['status_gizi']);
        $this->assertSame((int) $tersimpan->age_in_months, $respons->json('data.child.age_in_months'));
    }

    /**
     * Aturan 5: satu tanggal = satu entri.
     *
     * Dua suntikan pada tanggal yang sama itu sah (dosis berbeda), dan keduanya
     * masuk ke array `immunizations` yang sama - bukan jadi dua entri.
     */
    #[Test]
    public function dua_suntikan_tanggal_sama_masih_satu_entri(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        $pertama = ImmunizationType::factory()->create(['code' => 'HB-0']);
        $kedua = ImmunizationType::factory()->create(['code' => 'BCG']);

        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-08-20')->create();
        ImmunizationRecord::factory()->untukAnak($anak)->untukDosis($pertama)->padaTanggal('2026-08-20')->create();
        ImmunizationRecord::factory()->untukAnak($anak)->untukDosis($kedua)->padaTanggal('2026-08-20')->create();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/timeline");
        $respons->assertOk();

        $entri = $respons->json('data.entries');

        $this->assertCount(1, $entri);
        $this->assertSame('2026-08-20', $entri[0]['date']);
        $this->assertCount(2, $entri[0]['immunizations']);
        // Penimbangan dan suntikan tanggal sama tetap satu entri.
        $this->assertNotNull($entri[0]['measurement']);

        $kode = array_column($entri[0]['immunizations'], 'type');
        sort($kode);
        $this->assertSame(['BCG', 'HB-0'], $kode);
    }

    /** Aturan 6: anak tanpa data tetap 200 dengan `entries` kosong. */
    #[Test]
    public function anak_tanpa_data_punya_entries_kosong(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/timeline");

        $respons->assertOk();
        $this->assertTrue($respons->json('success'));
        $this->assertSame([], $respons->json('data.entries'));
        $this->assertFalse($respons->json('data.meta.has_more'));
        $this->assertNull($respons->json('data.meta.next_before'));
        $this->assertSame($anak->id, $respons->json('data.child.id'));
    }

    /**
     * Aturan 7: `limit` menghitung TANGGAL, bukan jumlah baris.
     *
     * Ini aturan yang paling mudah dilanggar dan paling diam-diam: kalau
     * service mengambil `limit` baris per tabel lalu menggabungkannya, satu
     * tanggal dengan tiga suntikan memakan tiga slot dan timeline terpotong di
     * tengah satu kunjungan.
     */
    #[Test]
    public function limit_menghitung_tanggal_bukan_baris(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        // Lima baris pada tiga tanggal. Kalau `limit` dihitung dari baris,
        // `limit=2` akan mengembalikan paling banyak dua entri dan salah
        // potong tanggal yang puntahnya di tengah satu kunjungan.
        $tigaDosis = ImmunizationType::factory()->count(3)->create();

        foreach ($tigaDosis as $satu) {
            ImmunizationRecord::factory()
                ->untukAnak($anak)
                ->untukDosis($satu)
                ->padaTanggal('2026-08-30')
                ->create();
        }

        ImmunizationRecord::factory()
            ->untukAnak($anak)
            ->untukDosis(ImmunizationType::factory()->create())
            ->padaTanggal('2026-08-29')
            ->create();

        ImmunizationRecord::factory()
            ->untukAnak($anak)
            ->untukDosis(ImmunizationType::factory()->create())
            ->padaTanggal('2026-08-28')
            ->create();

        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-08-30')->create();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/timeline?limit=2");
        $respons->assertOk();

        $entri = $respons->json('data.entries');

        $this->assertCount(2, $entri);
        $this->assertSame('2026-08-30', $entri[0]['date']);
        $this->assertCount(3, $entri[0]['immunizations']);
        $this->assertSame('2026-08-29', $entri[1]['date']);
        $this->assertTrue($respons->json('data.meta.has_more'));
    }

    // =================================================================
    // Otorisasi
    // =================================================================

    /** Ibu hanya boleh membuka timeline anaknya sendiri. */
    #[Test]
    public function ibu_membuka_anak_orang_ditolak(): void
    {
        $ibu = User::factory()->ibu()->create();
        $ibuLain = User::factory()->ibu()->create();
        $anakOrangLain = Child::factory()->milik($ibuLain)->create();

        $this->kader($ibu)
            ->getJson("/api/children/{$anakOrangLain->id}/timeline")
            ->assertForbidden();
    }

    #[Test]
    public function ibu_membuka_anak_anaknya_sendiri_membalas_200(): void
    {
        $ibu = User::factory()->ibu()->create();
        $anak = Child::factory()->milik($ibu)->create(['date_of_birth' => '2024-01-01']);

        $respons = $this->kader($ibu)->getJson("/api/children/{$anak->id}/timeline");

        $respons->assertOk();
        $this->assertSame($anak->id, $respons->json('data.child.id'));
    }

    /** `id` bukan UUID dibalas 404, bukan 500 dari error PostgreSQL. */
    #[Test]
    public function id_bukan_uuid_membalas_404(): void
    {
        $kader = User::factory()->kader()->create();

        $this->kader($kader)->getJson('/api/children/bukan-uuid/timeline')->assertNotFound();
    }

    #[Test]
    public function parameter_tidak_valid_membalas_422(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        $this->kader($kader)->getJson("/api/children/{$anak->id}/timeline?limit=0")->assertStatus(422);
        $this->kader($kader)->getJson("/api/children/{$anak->id}/timeline?limit=201")->assertStatus(422);
        $this->kader($kader)->getJson("/api/children/{$anak->id}/timeline?limit=abc")->assertStatus(422);
        // Tanggal yang tidak pernah ada. Tidak perlu `before_or_equal:today`:
        // riwayat lama harus tetap bisa dibaca.
        $this->kader($kader)->getJson("/api/children/{$anak->id}/timeline?before=2026-13-45")->assertStatus(422);
        $this->kader($kader)->getJson("/api/children/{$anak->id}/timeline?before=15-09-2026")->assertStatus(422);
    }

    // =================================================================
    // Cursor
    // =================================================================

    #[Test]
    public function cursor_before_melanjutkan_dari_tanggal_terakhir(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        foreach (['2026-09-20', '2026-09-10', '2026-09-05', '2026-08-28'] as $tanggal) {
            Measurement::factory()->untukAnak($anak)->padaTanggal($tanggal)->create();
        }

        $pertama = $this->kader($kader)->getJson("/api/children/{$anak->id}/timeline?limit=2");
        $pertama->assertOk();

        $this->assertSame(['2026-09-20', '2026-09-10'], array_column($pertama->json('data.entries'), 'date'));
        $this->assertTrue($pertama->json('data.meta.has_more'));
        $this->assertSame('2026-09-10', $pertama->json('data.meta.next_before'));

        $kedua = $this->kader($kader)->getJson(
            "/api/children/{$anak->id}/timeline?limit=2&before=".($pertama->json('data.meta.next_before'))
        );
        $kedua->assertOk();

        $this->assertSame(['2026-09-05', '2026-08-28'], array_column($kedua->json('data.entries'), 'date'));
        $this->assertFalse($kedua->json('data.meta.has_more'));
        // `null` di halaman terakhir, bukan string kosong.
        $this->assertNull($kedua->json('data.meta.next_before'));
    }

    /**
     * Riwayat yang sudah lewat tidak boleh menghilang.
     *
     * Nama test ini sengaja menyebut "tidak boleh", karena temptation-nya nyata:
     * `before_or_equal:today` kelihatan seperti paginasi biasa, padahal ia
     * membuat seluruh riwayat lama tidak bisa diunduh begitu tanggalnya lewat.
     */
    #[Test]
    public function riwayat_lama_tetap_bisa_dibaca(): void
    {
        $kader = User::factory()->kader()->create();

        // Tanggal lahir 2018 supaya tanggal penimbangan 2019 memang sah -
        // trigger z-score menolak penimbangan yang lebih awal dari tanggal
        // lahir anak, dan penurunan itu akan jadi 500, bukan membuktikan apa pun.
        $anak = Child::factory()->create(['date_of_birth' => '2018-06-01']);

        Measurement::factory()->untukAnak($anak)->padaTanggal('2019-03-15')->create();

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/timeline");

        $respons->assertOk();
        $this->assertSame('2019-03-15', $respons->json('data.entries.0.date'));
    }

    // =================================================================
    // `medical_flags`
    // =================================================================

    #[Test]
    public function kader_bisa_menulis_medical_flags(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        $this->kader($kader)->patchJson("/api/children/{$anak->id}", [
            'medical_flags' => "alergi: penisilin\nasma",
        ])->assertOk();

        $this->assertSame("alergi: penisilin\nasma", $anak->fresh()->medical_flags);
    }

    /**
     * Ibu tidak boleh menulis, dan penolakannya harus terlihat.
     *
     * Menghapus field `medical_flags` dari respons akan lebih murah, tapi itu
     * menghasilkan 200 palsu: kader mengira penandanya sudah tercatat padahal
     * tidak. Lebih baik 403 yang terbaca.
     */
    #[Test]
    public function ibu_tidak_bisa_menulis_medical_flags(): void
    {
        $ibu = User::factory()->ibu()->create();
        $anak = Child::factory()->milik($ibu)->create(['date_of_birth' => '2024-01-01']);

        $respons = $this->kader($ibu)->patchJson("/api/children/{$anak->id}", [
            'medical_flags' => 'alergi: penisilin',
        ]);

        $respons->assertForbidden();
        $this->assertArrayHasKey('medical_flags', $respons->json('errors'));
        $this->assertNull($anak->fresh()->medical_flags);
    }

    /**
     * `medical_flags` yang dikirim `null` harus MENGHAPUS penanda, bukan
     * diabaikan.
     *
     * Ini berbeda dari `medical_flags` yang tidak dikirim sama sekali, dan
     * perbedaan itulah yang dipakai form edit Kader: mengosongkan kolom harus
     * bisa menghapus penanda yang salah ketik. Mobile dulu memakai spread
     * null-aware (`?medicalFlags`) yang membuat key-nya hilang begitu nilainya
     * `null`, sehingga penghapusan tidak pernah sampai ke server sama sekali.
     *
     * Perilaku ini berasal dari `ChildController::update` yang membuang key
     * nullable yang bernilai `null` **hanya** bila key itu tidak ada di
     * request. Test ini mengunci kedua sisi aturan itu.
     */
    #[Test]
    public function medical_flags_null_menghapus_penanda(): void
    {
        $anak = Child::factory()->create([
            'date_of_birth' => '2024-01-01',
            'medical_flags' => 'alergi: penisilin',
        ]);
        $kader = User::factory()->kader()->create();

        $this->kader($kader)->patchJson("/api/children/{$anak->id}", [
            'medical_flags' => null,
        ])->assertOk();

        $this->assertNull($anak->fresh()->medical_flags);
    }

    /**
     * `birth_weight` dan `birth_height` punya aturan null yang sama.
     *
     *'incorrect input harus bisa dihapus|Totalỹi| jadi dikoreksi jadi kosong,
     * bukan terkunci selamanya karena mobile tidak pernah bisa mengirim null.
     */
    #[Test]
    public function berat_dan_panjang_lahir_null_mengosongkan_nilai(): void
    {
        $anak = Child::factory()->create([
            'date_of_birth' => '2024-01-01',
            'birth_weight' => 3.2,
            'birth_height' => 49,
        ]);
        $kader = User::factory()->kader()->create();

        $this->kader($kader)->patchJson("/api/children/{$anak->id}", [
            'birth_weight' => null,
            'birth_height' => null,
        ])->assertOk();

        $anak->refresh();
        $this->assertNull($anak->birth_weight);
        $this->assertNull($anak->birth_height);
    }

    /**
     * Field yang tidak dikirim harus utuh - ini pembeda dari kasus di atas.
     *
     * Tanpa test ini, loop yang membuang key null di `ChildController::update`
     * bisa "diperbaiki" dengan menghapus seluruh isset nullable, dan setiap
     * PATCH parsial akan diam-diam mengosongkan data yang tidak boleh disentuh.
     */
    #[Test]
    public function field_yang_tidak_dikirim_tidak_berubah(): void
    {
        $anak = Child::factory()->create([
            'date_of_birth' => '2024-01-01',
            'birth_weight' => 3.2,
            'medical_flags' => 'alergi: penisilin',
        ]);
        $kader = User::factory()->kader()->create();

        // Hanya nama yang dikirim.
        $this->kader($kader)->patchJson("/api/children/{$anak->id}", [
            'name' => 'Nama Baru',
        ])->assertOk();

        $anak->refresh();
        $this->assertSame('Nama Baru', $anak->name);
        $this->assertEquals(3.2, (float) $anak->birth_weight);
        $this->assertSame('alergi: penisilin', $anak->medical_flags);
    }

    #[Test]
    public function medical_flags_terbaca_apa_adanya(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create([
            'date_of_birth' => '2024-01-01',
            'medical_flags' => "alergi: penisilin\nasma\nriwayat: premature",
        ]);

        $timeline = $this->kader($kader)->getJson("/api/children/{$anak->id}/timeline");
        $timeline->assertOk();

        // Tidak ada normalisasi: Kader dan Ibu harus melihat nilai yang sama
        // persis seperti yang ditulis.
        $this->assertSame(
            "alergi: penisilin\nasma\nriwayat: premature",
            $timeline->json('data.child.medical_flags')
        );
    }

    #[Test]
    public function medical_flags_kosong_dibaca_sebagai_null(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01', 'medical_flags' => null]);

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/timeline");

        $respons->assertOk();
        $this->assertNull($respons->json('data.child.medical_flags'));

        // Penanda juga ikut terbaca di `GET /children/{id}` karena controller
        // itu men-serialize model secara langsung - lihat bagian 7.4.
        $this->kader($kader)->getJson("/api/children/{$anak->id}")
            ->assertOk()
            ->assertJsonPath('data.medical_flags', null);
    }

    #[Test]
    public function medical_flags_lebih_dari_500_karakter_menolak_422(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();

        $this->kader($kader)->patchJson("/api/children/{$anak->id}", [
            'medical_flags' => str_repeat('a', 501),
        ])->assertStatus(422);
    }

    // =================================================================
    // Bentuk respons
    // =================================================================

    /**
     * Kunci `data` tepat tiga, dan `entries` punya empat kunci per entri.
     *
     * Ini contractual: klien Flutter mengambil `data.entries` dan
     * `data.child` berdasarkan nama, dan menambah/menghapus kunci di sini akan
     * merusak layar yang sudah jadi.
     */
    #[Test]
    public function data_tepat_berisi_tiga_kunci(): void
    {
        $anak = $this->anak();
        $kader = User::factory()->kader()->create();
        Measurement::factory()->untukAnak($anak)->olehKader($kader)->padaTanggal('2026-08-01')->create();

        $data = $this->kader($kader)->getJson("/api/children/{$anak->id}/timeline")->json('data');

        $this->assertSame(['child', 'entries', 'meta'], array_keys($data));

        $entri = $data['entries'][0];
        $this->assertSame(['date', 'measurement', 'immunizations', 'medical_note'], array_keys($entri));

        $this->assertSame(['has_more', 'next_before'], array_keys($data['meta']));
    }

    /**
     * Jumlah query tetap: satu untuk daftar tanggal, tiga untuk isi jendela.
     *
     * Yang diperiksa BUKAN jumlah query seluruh request, tapi query yang
     * dijalankan service-nya. Alasannya, komponen lain (autentikasi, pengambilan
     * anak) memang memiliki query sendiri dan tidak berkaitan dengan timeline;
     * menghitung semuanya membuat test ini rapuh tanpa menambah perlindungan.
     *
     * Yang penting: jumlahnya tidak bergantung pada jumlah tanggal. Anak dengan
     * 10 kunjungan harus membutuhkan jumlah query yang sama dengan anak yang
     * punya 1.
     */
    #[Test]
    public function jumlah_query_tetap_walaupun_tanggal_banyak(): void
    {
        $service = app(ChildTimelineService::class);

        $anakSatu = $this->anakDenganRelasiSudahDimuat();
        Measurement::factory()->untukAnak($anakSatu)->padaTanggal('2026-02-01')->create();

        $anakBanyak = $this->anakDenganRelasiSudahDimuat();

        foreach (range(1, 10) as $hari) {
            Measurement::factory()
                ->untukAnak($anakBanyak)
                ->padaTanggal('2026-01-'.str_pad((string) $hari, 2, '0', STR_PAD_LEFT))
                ->create();
        }

        $jumlahSatu = $this->hitungQuery(fn () => $service->timelineFor($anakSatu, 50));
        $jumlahBanyak = $this->hitungQuery(fn () => $service->timelineFor($anakBanyak, 50));

        $this->assertSame(4, $jumlahSatu, 'Service harus memakai empat query: daftar tanggal, lalu tiga isi.');
        $this->assertSame(
            $jumlahSatu,
            $jumlahBanyak,
            'Jumlah query tidak boleh bergantung pada jumlah tanggal kunjungan.'
        );
    }

    /**
     * Penimbangan tanpa kader tetap tampil.
     *
     * `kader_id` bisa `null` karena `ON DELETE SET NULL`. Kalau service memakai
     * `join` biasa ke `users`, riwayat anak yang kadernya sudah dihapus akan
     * hilang dari timeline - persis data yang paling tidak boleh hilang.
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

        $respons = $this->kader($kader)->getJson("/api/children/{$anak->id}/timeline");

        $respons->assertOk();
        $this->assertNotNull($respons->json('data.entries.0.measurement'));
        $this->assertNull($respons->json('data.entries.0.measurement.kader'));
    }

    // -----------------------------------------------------------------
    // Helper
    // -----------------------------------------------------------------

    /**
     * Anak dengan tanggal lahir yang pasti.
     *
     * `ChildFactory` mengisi `date_of_birth` acak antara 5 tahun dan 1 bulan
     * lalu, sedangkan trigger z-score menolak penimbangan yang lebih awal dari
     * tanggal lahir anak. Pasangkan anak acak dengan tanggal penimbangan
     * hardcode dan test ini gagal sekitar 1 dari 8 kali jalannya - bukan karena
     * kodenya salah, tapi karena hasilnya tidak bisa diprediksi. Tanggal lahir
     * ditetapkan di sini supaya kelulusannya tidak bergantung pada tanggal hari
     * ini.
     */
    private function anak(): Child
    {
        return Child::factory()->create(['date_of_birth' => '2024-01-01']);
    }

    /**
     * Anak dengan `mother` dan `latestMeasurement` yang sudah dimuat.
     *
     * Dipakai test penghitung query: `ChildController` mengambil anak lewat
     * `findChildForUser()`, dan `Child` punya `$with = ['latestMeasurement']`,
     * jadi relasi sudah ada waktu service dipanggil. Kalau test memanggil
     * service dengan model yang relasinya belum dimuat, Eloquent akan menambah
     * query lazy-load dan angka yang diukur jadi tidak lagi soal timeline.
     */
    private function anakDenganRelasiSudahDimuat(): Child
    {
        return Child::factory()
            ->create(['date_of_birth' => '2024-01-01'])
            ->load(['mother', 'latestMeasurement']);
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
     * ke angka absolut: kalau ada refactor internal yang menambah satu query
     * untuk dua anak, test ini masih lulus selama jumlahnya tidak bergantung pada
     * data.
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
