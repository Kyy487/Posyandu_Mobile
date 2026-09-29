<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\ImmunizationRecord;
use App\Models\ImmunizationType;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Menguji `GET /kader/immunizations/recap?format=csv` (sisa Opsi E).
 *
 * Test ini sengaja membandingkan CSV dengan JSON, bukan hanya memeriksa isi CSV.
 * Export yang angkanya berbeda dari layar adalah kegagalan yang paling mahal di
 * fitur ini, karena angka laporan yang salah akan dipakai BIDAN untuk
 * memutuskan kunjungan. Test utamanya: CSV harus dibangun dari array yang sama
 * persis dengan yang dikirim ke JSON, dan angkanya harus identik.
 *
 * Master dosis yang dipakai (lihat `masterDosis()`):
 *
 *   | code | target | batas terlambat (target + 2) |
 *   | :--- | -----: | ----------------------------: |
 *   | BCG  |      2 |                             4 |
 *   | HB   |      0 |                             2 |
 *   | MR   |      9 |                            11 |
 *
 * `orderedForDosing()` mengurutkan berdasarkan `target_age_months`, jadi urutan
 * di file mengikuti urutan suntikan: HB (target 0), BCG (target 2), MR (target 9).
 * Dulu urutannya `code` saja, sehingga BCG muncul sebelum Hepatitis B; urutan
 * itu dikunci di sini supaya perubahannya jadi keputusan sadar, bukan efek
 * samping. Urutannya sendiri diuji di `ImmunizationTypeOrderTest`.
 *
 * Bulan acuan tetap `2026-09`, tanggal acuan `2026-09-30`.
 */
class ImmunizationRecapCsvTest extends TestCase
{
    use RefreshDatabase;

    private const BULAN = '2026-09';

    private const ACUAN = '2026-09-30';

    private const BOM = "\xEF\xBB\xBF";

    // -----------------------------------------------------------------
    // 1. Kontrak respons
    // -----------------------------------------------------------------

    #[Test]
    public function csv_mengirim_content_type_dan_nama_file_bulan(): void
    {
        $kader = User::factory()->kader()->create();
        $this->masterDosis();

        $respons = $this->withToken($this->token($kader))
            ->get('/api/kader/immunizations/recap?month='.self::BULAN.'&format=csv')
            ->assertOk();

        $this->assertSame('text/csv; charset=UTF-8', $respons->headers->get('Content-Type'));
        $this->assertSame(
            'attachment; filename="rekap-imunisasi-'.self::BULAN.'.csv"',
            $respons->headers->get('Content-Disposition')
        );
    }

    /**
     * Tanpa `format` responsnya tetap JSON yang persis sama seperti sebelumnya.
     *
     * Ini yang menjaga klien lama: aplikasi mobile yang sudah ada tidak
     * mengirim `format` sama sekali, jadi kontrak JSON tidak boleh bergeser
     * gara-gara fitur ini.
     */
    #[Test]
    public function tanpa_format_tetap_json_dan_tidak_berubah(): void
    {
        $kader = User::factory()->kader()->create();
        $tipe = $this->masterDosis();
        $this->anakTerlambat();

        $tanpa = $this->withToken($this->token($kader))
            ->getJson('/api/kader/immunizations/recap?month='.self::BULAN)
            ->assertOk()
            ->assertJsonPath('success', true);

        $eksplisit = $this->withToken($this->token($kader))
            ->getJson('/api/kader/immunizations/recap?month='.self::BULAN.'&format=json')
            ->assertOk()
            ->assertJsonPath('success', true);

        $this->assertSame($tanpa->json('data'), $eksplisit->json('data'));
    }

    #[Test]
    public function format_tidak_dikenal_ditolak_sebagai_422(): void
    {
        $kader = User::factory()->kader()->create();

        $this->withToken($this->token($kader))
            ->getJson('/api/kader/immunizations/recap?month='.self::BULAN.'&format=excel')
            ->assertStatus(422)
            ->assertJsonPath('success', false)
            ->assertJsonStructure(['success', 'message', 'errors' => ['format']]);
    }

    /**
     * `format=csv` tidak boleh melewati validasi bulan.
     *
     * Kalau tidak, request dengan bulan salah akan membalas CSV berisi header
     * tapi tanpa pesan error, dan kader menyimpan berkas itu tanpa tahu ada yang
     * salah.
     */
    #[Test]
    public function csv_dengan_bulan_salah_tetap_422_json(): void
    {
        $kader = User::factory()->kader()->create();

        $respons = $this->withToken($this->token($kader))
            ->get('/api/kader/immunizations/recap?month=2026-13&format=csv')
            ->assertStatus(422);

        $this->assertStringContainsString('"errors"', $respons->getContent());
        $this->assertStringNotContainsString('AKTIVITAS SUNTIKAN', $respons->getContent());
    }

    #[Test]
    public function ibu_tidak_boleh_mengekspor_csv(): void
    {
        $ibu = User::factory()->ibu()->create();

        $this->withToken($this->token($ibu))
            ->get('/api/kader/immunizations/recap?month='.self::BULAN.'&format=csv')
            ->assertForbidden();
    }

    #[Test]
    public function tamu_tidak_boleh_mengekspor_csv(): void
    {
        $this->get('/api/kader/immunizations/recap?month='.self::BULAN.'&format=csv')
            ->assertUnauthorized();
    }

    // -----------------------------------------------------------------
    // 2. Isi file
    // -----------------------------------------------------------------

    /**
     * Guard utama: angka di CSV harus sama persis dengan angka di JSON.
     *
     * Kedua request memakai `month` yang sama, jadi `filter` juga harus sama.
     * Setiap angka yang muncul di kepala, aktivitas, dan kelengkapan CSV
     * dicocokkan dengan nilai JSON-nya, dan jumlah baris anak terlambat di file
     * dicocokkan dengan `overdue_children` di JSON.
     */
    #[Test]
    public function angka_csv_identik_dengan_json(): void
    {
        $kader = User::factory()->kader()->create();
        $tipe = $this->masterDosis();
        $lengkap = $this->anakLengkap($tipe);
        $terlambat = $this->anakTerlambat();

        // Hanya dua suntikan pada bulan yang direkap. `anakLengkap()` sudah
        // punya record HB dan BCG, tapi keduanya tanggalnya Maret dan April, jadi
        // tidak masuk hitungan September.
        ImmunizationRecord::factory()->untukAnak($lengkap)->untukDosis($tipe['MR'])->padaTanggal('2026-09-03')->create();
        ImmunizationRecord::factory()->untukAnak($terlambat)->untukDosis($tipe['HB'])->padaTanggal('2026-09-20')->create();

        $json = $this->withToken($this->token($kader))
            ->getJson('/api/kader/immunizations/recap?month='.self::BULAN)
            ->assertOk()
            ->json('data');

        $csv = $this->csv($kader);

        $this->assertSame(self::BULAN, $json['filter']['month']);
        $this->assertStringContainsString('Bulan: '.self::BULAN, $csv);
        $this->assertStringContainsString('Dihitung sampai: '.self::ACUAN, $csv);

        $activity = $json['activity'];
        $this->assertStringContainsString("TOTAL,,,{$activity['total_doses']}", $csv);
        $this->assertStringContainsString('Anak yang disuntik bulan ini,'.$activity['total_children'], $csv);

        $coverage = $json['coverage'];
        $this->assertStringContainsString('Total anak,'.$coverage['total_children'], $csv);
        $this->assertStringContainsString('Imunisasi lengkap,'.$coverage['complete'], $csv);
        $this->assertStringContainsString('Imunisasi belum lengkap,'.$coverage['incomplete'], $csv);
        $this->assertStringContainsString('Ada dosis terlambat,'.$coverage['overdue'], $csv);
        $this->assertStringContainsString('Tidak dihitung (arsip / pindah),'.$coverage['excluded_archived'], $csv);

        $this->assertCount(
            count($coverage['overdue_children']),
            $this->barisAnakTerlambat($csv),
            'jumlah baris anak terlambat di CSV harus sama dengan overdue_children di JSON'
        );
    }

    /**
     * Baris dengan jumlah nol tetap ditulis.
     *
     * Layar mobile menyembunyikan baris nol di balik toggle, tapi berkasnya tidak
     * boleh: BIDAN yang mengarsipkan laporan tidak punya toggle, dan "tidak ada
     * suntikan" vs "tidak sempat dicatat" harus bisa dibedakan dari berkasnya
     * sendiri.
     */
    #[Test]
    public function baris_dengan_jumlah_nol_tetap_ada(): void
    {
        $kader = User::factory()->kader()->create();
        $this->masterDosis();

        $csv = $this->csv($kader);

        $this->assertStringContainsString('BCG,1,BCG,0', $csv);
        $this->assertStringContainsString('HB,1,Hepatitis B,0', $csv);
        $this->assertStringContainsString('MR,1,Campak Rubella,0', $csv);
    }

    /**
     * Hanya suntikan bulan itu yang dihitung; suntikan batas bulan sebelumnya
     * tidak boleh ikut masuk.
     */
    #[Test]
    public function hanya_suntikan_bulan_yang_direkap_yang_dihitung(): void
    {
        $kader = User::factory()->kader()->create();
        $tipe = $this->masterDosis();

        // Dua anak berbeda, karena satu anak tidak boleh punya dua record untuk
        // dosis yang sama (unique constraint `immunization_child_type_unique`).
        $dalam = $this->anakLengkap($tipe);
        $sebelum = $this->anakLengkap($tipe);

        ImmunizationRecord::factory()->untukAnak($dalam)->untukDosis($tipe['MR'])->padaTanggal('2026-09-05')->create();
        ImmunizationRecord::factory()->untukAnak($sebelum)->untukDosis($tipe['MR'])->padaTanggal('2026-08-31')->create();

        $csv = $this->csv($kader);

        $this->assertStringContainsString('MR,1,Campak Rubella,1', $csv);
        $this->assertStringContainsString('TOTAL,,,1', $csv);
        $this->assertStringContainsString('Anak yang disuntik bulan ini,1', $csv);
    }

    /**
     * Suntikan yang sudah dibatalkan tidak boleh masuk hitungan.
     *
     * Sama seperti di JSON: barisnya tidak dihapus fisik, jadi export yang
     * mengabaikan soft delete akan melaporkan stok vaksin yang tidak pernah
     * dipakai.
     */
    #[Test]
    public function suntikan_yang_dibatalkan_tidak_dihitung(): void
    {
        $kader = User::factory()->kader()->create();
        $tipe = $this->masterDosis();
        $anak = $this->anakLengkap($tipe);

        // Pakai MR: `anakLengkap()` sudah punya record HB dan BCG, dan satu anak
        // tidak boleh punya dua record untuk dosis yang sama.
        $record = ImmunizationRecord::factory()
            ->untukAnak($anak)
            ->untukDosis($tipe['MR'])
            ->padaTanggal('2026-09-05')
            ->create();

        $this->assertStringContainsString('MR,1,Campak Rubella,1', $this->csv($kader));

        $record->delete();

        $csv = $this->csv($kader);
        $this->assertStringContainsString('MR,1,Campak Rubella,0', $csv);
        $this->assertStringContainsString('TOTAL,,,0', $csv);
    }

    /**
     * Daftar anak terlambat: satu baris per anak, dengan dosis digabung.
     *
     * Kader sedang memilih siapa yang dikunjungi berikutnya, jadi satu anak
     * dengan beberapa dosis telat harus tetap jadi satu baris. Kalau satu baris
     * per dosis, nama anak akan muncul berulang dan daftar kunjungan berantakan.
     *
     * Angka "Terlambat (bulan)" diambil dari `sisa_bulan` paling negatif, yaitu
     * `batas - usia` yang paling kecil. Untuk anak lahir 2025-10-15 pada
     * 2026-09-30 usianya 11 bulan: HB batas 2 (sisa -9), BCG batas 4 (sisa -7),
     * MR batas 11 (sisa 0). Yang paling lama telat adalah HB dengan -9.
     */
    #[Test]
    public function daftar_anak_terlambat_satu_baris_per_anak(): void
    {
        $kader = User::factory()->kader()->create();
        $this->masterDosis();
        $this->anakTerlambat();

        $baris = $this->barisAnakTerlambat($this->csv($kader));

        $this->assertCount(1, $baris, 'satu anak telat harus jadi satu baris');
        $this->assertSame('1', $baris[0][0], 'ada nomor urut');
        $this->assertSame('Anak Telat', $baris[0][1]);
        $this->assertSame('2025-10-15', $baris[0][2]);
        $this->assertSame('11', $baris[0][3], 'usia dihitung pada akhir bulan');
        $this->assertSame('3', $baris[0][4], 'HB, BCG, dan MR semuanya sudah jatuh tempo');
        $this->assertSame(
            'Hepatitis B; BCG; Campak Rubella',
            $baris[0][5],
            'nama dosis digabung dalam satu sel dengan pemisah titik koma, urutannya dari server'
        );
        $this->assertSame('-9', $baris[0][6], 'paling lama terlambat = sisa_bulan paling negatif');
    }

    /**
     * Bulan tanpa anak terlambat: tabel tetap harus punya bentuk yang sama.
     *
     * Kalau header tanpa baris data, pembaca file tidak bisa membedakan
     * "memang tidak ada yang telat" dari "ekspornya gagal di tengah jalan".
     */
    #[Test]
    public function tanpa_anak_terlambat_tetap_ada_baris_penanda(): void
    {
        $kader = User::factory()->kader()->create();
        $tipe = $this->masterDosis();
        $this->anakLengkap($tipe);

        $baris = $this->barisAnakTerlambat($this->csv($kader));

        $this->assertCount(1, $baris);
        $this->assertSame('(tidak ada anak dengan dosis terlambat)', $baris[0][1]);
        $this->assertSame('', $baris[0][6], 'kolom terlambat dikosongkan, bukan diisi 0');
    }

    /**
     * Anak yang ter-archive tidak masuk hitungan dan tidak masuk daftar
     * kunjungan, tapi jumlahnya harus tertulis.
     *
     * Kalau hanya jumlahnya yang muncul tanpa ada_child, total anak di laporan
     * terlihat lebih kecil tanpa ada penjelasan sama sekali.
     */
    #[Test]
    public function anak_ter_arsip_dihitung_tanpa_masuk_daftar_kunjungan(): void
    {
        $kader = User::factory()->kader()->create();
        $tipe = $this->masterDosis();
        $this->anakLengkap($tipe);
        $this->anakTerlambat();

        $arsip = $this->anakTerlambat();
        $arsip->update(['name' => 'Anak Pindah']);
        $arsip->delete();

        $csv = $this->csv($kader);

        $this->assertStringContainsString('Tidak dihitung (arsip / pindah),1', $csv);
        $this->assertStringNotContainsString('Anak Pindah', $csv, 'arsip tidak boleh muncul di mana pun di file');

        $baris = $this->barisAnakTerlambat($csv);
        $this->assertCount(1, $baris);
        $this->assertSame('Anak Telat', $baris[0][1], 'arsip tidak boleh masuk daftar kunjungan');
    }

    // -----------------------------------------------------------------
    // 3. Ketahanan file
    // -----------------------------------------------------------------

    /**
     * BOM UTF-8 wajib ada di depan file.
     *
     * Tanpa BOM, Excel di Windows memaksa file ke ANSI dan nama anak beraksen
     * berubah jadi karakter aneh tepat saat BIDAN membacanya. Tidak ada test lain
     * yang menangkap ini, karena isi file-nya sendiri tetap UTF-8 yang benar -
     * yang rusak baru terjadi di aplikasi yang membukanya.
     */
    #[Test]
    public function file_dimulai_dengan_bom_utf8(): void
    {
        $kader = User::factory()->kader()->create();
        $this->masterDosis();

        $this->assertStringStartsWith(self::BOM, $this->konten($kader));
    }

    /**
     * Pemisah baris `CRLF`, file ditutup dengan baris baru, dan tidak ada baris
     * kosong ganda.
     *
     * `CRLF` supaya tabel tidak berantakan di Excel Windows. Baris baru di akhir
     * file supaya berkas yang ditambahkan ke arsip tidak menyatu dengan baris
     * terakhir berkas sebelumnya.
     */
    #[Test]
    public function pemisah_baris_crlf_dan_tanpa_baris_kosong_ganda(): void
    {
        $kader = User::factory()->kader()->create();
        $tipe = $this->masterDosis();
        $this->anakLengkap($tipe);

        $csv = $this->csv($kader);

        $this->assertStringContainsString("\r\n", $csv);
        $this->assertStringEndsWith("\r\n", $csv);
        $this->assertStringNotContainsString("\n\n", $csv, 'tidak boleh ada baris kosong ganda');
    }

    /**
     * Nama anak yang memuat koma dan tanda kutip tidak boleh merusak baris.
     *
     * Koma di dalam sel harus diapit tanda kutip (RFC 4180), dan tanda kutip di
     * dalam sel harus jadi dua tanda kutip. Kalau ini salah, file yang dibuka
     * Excel akan menggeser semua kolom setelahnya - dan karena nama anak ada di
     * kolom kedua, satu nama dengan koma saja sudah cukup untuk membuat kolom
     * "Tanggal Lahir" berisi isi yang salah.
     */
    #[Test]
    public function nama_anak_dengan_koma_dan_tanda_kutip_tetap_satu_kolom(): void
    {
        $kader = User::factory()->kader()->create();
        $this->masterDosis();

        $this->anakTerlambat()->update(['name' => 'Budi, "Si Otong"']);

        $baris = $this->barisAnakTerlambat($this->csv($kader));

        $this->assertCount(1, $baris);
        $this->assertSame('Budi, "Si Otong"', $baris[0][1]);
        $this->assertSame('2025-10-15', $baris[0][2], 'kolom setelah nama tidak bergeser');
        $this->assertCount(7, $baris[0]);
    }

    /**
     * Nama anak yang diawali `=` tidak boleh dieksekusi Excel sebagai formula.
     *
     * Nama anak adalah input kader, dan tanpa awakean tanda kutip tunggal,
     * formula di dalam nama akan dijalankan begitu BIDAN membuka file-nya.
     * Sel di-parse, bukan dicek dengan `assertStringContainsString`, supaya test
     * ini tahu persis apa yang ditulis exporter di dalam sel.
     */
    #[Test]
    public function nama_anak_berpola_formula_ditandai_sebagai_teks(): void
    {
        $kader = User::factory()->kader()->create();
        $this->masterDosis();

        $this->anakTerlambat()->update(['name' => '=1+1']);

        $baris = $this->barisAnakTerlambat($this->csv($kader));

        $this->assertCount(1, $baris);
        $this->assertSame(
            "'=1+1",
            $baris[0][1],
            'awalan tanda kutip tunggal membuat Excel membacanya sebagai teks, bukan formula'
        );
    }

    /**
     * Baris baru di dalam nama diratakan jadi spasi.
     *
     * `children.name` hanya divalidasi `string|max:255`, jadi newline
     * diperbolehkan. Satu sel ber-newline membuat file gagal dibaca pembaca yang
     * memecah per baris, dan kader sering menyalin isi laporan ke chat.
     */
    #[Test]
    public function baris_baru_di_nama_anak_diratakan(): void
    {
        $kader = User::factory()->kader()->create();
        $this->masterDosis();

        $this->anakTerlambat()->update(['name' => "Budi\nSantoso"]);

        $baris = $this->barisAnakTerlambat($this->csv($kader));

        $this->assertCount(1, $baris);
        $this->assertSame('Budi Santoso', $baris[0][1]);
    }

    /**
     * Bulan tanpa aktivitas apa pun tetap menghasilkan CSV yang utuh, bukan
     * file kosong dan bukan 404. Kader rutin membuka bulan lama untuk melihat
     * apakah ada yang kelewatan dicatat.
     */
    #[Test]
    public function bulan_kosong_tetap_menghasilkan_csv_yang_utuh(): void
    {
        $kader = User::factory()->kader()->create();
        $this->masterDosis();

        $csv = $this->csv($kader, '2019-01');

        $this->assertStringContainsString('Bulan: 2019-01', $csv);
        $this->assertStringContainsString('Dihitung sampai: 2019-01-31', $csv);
        $this->assertStringContainsString('AKTIVITAS SUNTIKAN', $csv);
        $this->assertStringContainsString('KELENGKAPAAN IMUNISASI (pada akhir bulan)', $csv);
        $this->assertStringContainsString('DAFTAR ANAK TERLAMBAT', $csv);
        $this->assertStringContainsString('TOTAL,,,0', $csv);
    }

    // -----------------------------------------------------------------
    // Helper
    // -----------------------------------------------------------------

    /**
     * @return array{BCG: ImmunizationType, HB: ImmunizationType, MR: ImmunizationType}
     */
    private function masterDosis(): array
    {
        return [
            'BCG' => ImmunizationType::factory()->dosisPertama('BCG', 'BCG')
                ->create(['target_age_months' => 2, 'interval_months' => null]),
            'HB' => ImmunizationType::factory()->dosisPertama('Hepatitis B', 'HB')
                ->create(['target_age_months' => 0, 'interval_months' => null]),
            'MR' => ImmunizationType::factory()->dosisPertama('Campak Rubella', 'MR')
                ->create(['target_age_months' => 9, 'interval_months' => 9]),
        ];
    }

    /**
     * Anak yang imunisasinya benar-benar lengkap: lahir 2026-02-01, sudah dapat
     * HB dan BCG, dan usia 7 bulan pada 2026-09-30 berarti MR belum jatuh tempo.
     *
     * Tanpa record suntikan, anak ini justru AKAN terlambat - makanya helper ini
     * membuat record-nya, bukan cuma baris anaknya.
     *
     * @param  array{BCG: ImmunizationType, HB: ImmunizationType, MR: ImmunizationType}  $tipe
     */
    private function anakLengkap(array $tipe): Child
    {
        $anak = Child::factory()->create(['date_of_birth' => '2026-02-01', 'name' => 'Anak Lengkap']);

        ImmunizationRecord::factory()->untukAnak($anak)->untukDosis($tipe['HB'])->padaTanggal('2026-03-01')->create();
        ImmunizationRecord::factory()->untukAnak($anak)->untukDosis($tipe['BCG'])->padaTanggal('2026-04-01')->create();

        return $anak;
    }

    /**
     * Anak yang pasti terlambat: lahir 2025-10-15 tanpa suntikan apa pun.
     *
     * Pada 2026-09-30 usianya 11 bulan, jadi HB (target 0), BCG (target 2), dan
     * MR (target 9) semuanya sudah jatuh tempo dan sudah lewat batas toleransi.
     */
    private function anakTerlambat(): Child
    {
        return Child::factory()->create(['date_of_birth' => '2025-10-15', 'name' => 'Anak Telat']);
    }

    private function token(User $user): string
    {
        return $user->createToken('uji')->plainTextToken;
    }

    /** Unduh CSV dan kembalikan isinya sebagai string, dengan BOM dibuang. */
    private function csv(User $kader, string $bulan = self::BULAN): string
    {
        $konten = $this->konten($kader, $bulan);

        $this->assertStringStartsWith(self::BOM, $konten);

        return substr($konten, strlen(self::BOM));
    }

    /** Isi respons mentah, BOM dan apa pun yang lain tidak disentuh. */
    private function konten(User $kader, string $bulan = self::BULAN): string
    {
        return $this->withToken($this->token($kader))
            ->get("/api/kader/immunizations/recap?month={$bulan}&format=csv")
            ->assertOk()
            ->getContent();
    }

    /**
     * Baris-baris tabel "Daftar Anak Terlambat", sudah di-parse jadi sel.
     *
     * Dipakai `str_getcsv` per baris, bukan `explode(',')`, karena nama anak
     * boleh memuat koma di dalam tanda kutip. Parser ini cukup untuk file ini
     * karena `teks()` sudah meratakan semua baris baru di dalam sel.
     *
     * @return list<list<string>>
     */
    private function barisAnakTerlambat(string $csv): array
    {
        $semua = explode("\r\n", $csv);
        $mulai = null;

        foreach ($semua as $i => $baris) {
            if (str_starts_with($baris, 'No,Nama,Tanggal Lahir')) {
                $mulai = $i + 1;

                break;
            }
        }

        if ($mulai === null) {
            $this->fail('Header "No,Nama,Tanggal Lahir" tidak ada di CSV');
        }

        $hasil = [];

        for ($i = $mulai; $i < count($semua); $i++) {
            if ($semua[$i] === '') {
                break;
            }

            $sel = str_getcsv($semua[$i]);

            // Jumlah kolom dikunci 7: kalau exporter salah menghitung kolom, test
            // ini harus gagal, bukan diam-diam menerima baris yang geser.
            $this->assertCount(7, $sel, "baris anak tidak punya 7 kolom: {$semua[$i]}");

            $hasil[] = $sel;
        }

        return $hasil;
    }
}
