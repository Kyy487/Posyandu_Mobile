<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\Measurement;
use App\Models\MedicalNote;
use App\Models\User;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Menguji perbaikan dari migration `2026_09_27_020000_prepare_measurements_for_recap`.
 *
 * Semua test di sini memakai PostgreSQL sungguhan, karena yang diuji justru
 * perilaku yang hanya ada di PostgreSQL: partial unique index, `ON DELETE SET
 * NULL`, dan soft delete.
 */
class MeasurementRecapTest extends TestCase
{
    use RefreshDatabase;

    // -----------------------------------------------------------------
    // 1. Menghapus akun kader tidak boleh menghapus riwayat penimbangan
    // -----------------------------------------------------------------

    #[Test]
    public function menghapus_akun_kader_tidak_menghapus_riwayat_penimbangan(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();

        // Tiga tanggal berbeda, satu anak. Index `measurements_child_date_unique`
        // melarang dua baris untuk anak yang sama pada tanggal yang sama, jadi
        // fixture ini harus menyedarinya - kalau tidak, test ini diam-diam
        // menguji constraint yang salah.
        foreach (['2026-08-20', '2026-09-01', '2026-09-10'] as $tanggal) {
            Measurement::factory()
                ->untukAnak($anak)
                ->olehKader($kader)
                ->padaTanggal($tanggal)
                ->create();
        }

        $this->assertSame(3, Measurement::withTrashed()->count());

        $kader->forceDelete();

        // Riwayat harus utuh; hanya kadernya yang hilang.
        $this->assertSame(3, Measurement::withTrashed()->count());
        $this->assertSame(3, Measurement::whereNull('kader_id')->count());
    }

    #[Test]
    public function relasi_kader_boleh_null_tanpa_melempar_error(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();

        $penimbangan = Measurement::factory()
            ->untukAnak($anak)
            ->olehKader($kader)
            ->padaTanggal('2026-09-01')
            ->create();

        $kader->forceDelete();

        $penimbangan->refresh();

        $this->assertNull($penimbangan->kader);
    }

    // -----------------------------------------------------------------
    // 2. Soft delete
    // -----------------------------------------------------------------

    #[Test]
    public function pembatalan_penimbangan_tidak_menghapus_baris_secara_fisik(): void
    {
        $anak = $this->anak();

        $penimbangan = Measurement::factory()
            ->untukAnak($anak)
            ->padaTanggal('2026-09-01')
            ->create();

        $penimbangan->delete();

        $this->assertSoftDeleted($penimbangan);
        $this->assertNull(Measurement::find($penimbangan->id));
        $this->assertNotNull(Measurement::withTrashed()->find($penimbangan->id));
    }

    #[Test]
    public function baris_dibatalkan_tidak_masuk_hitungan_rekap(): void
    {
        $anak = $this->anak();

        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-09-01')->create();
        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-09-15')->create();
        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-09-20')->dibatalkan()->create();

        $this->assertSame(2, Measurement::forMonth('2026-09')->count());
        $this->assertSame(3, Measurement::withTrashed()->forMonth('2026-09')->count());
    }

    // -----------------------------------------------------------------
    // 3. Partial unique index (child_id, measurement_date)
    // -----------------------------------------------------------------

    #[Test]
    public function satu_anak_tidak_boleh_ditimbang_dua_kali_pada_tanggal_sama(): void
    {
        $anak = $this->anak();

        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-09-01')->create();

        $this->expectException(UniqueConstraintViolationException::class);

        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-09-01')->create();
    }

    #[Test]
    public function anak_berbeda_tetap_boleh_ditimbang_pada_tanggal_sama(): void
    {
        $tanggal = '2026-09-01';

        Measurement::factory()->untukAnak($this->anak())->padaTanggal($tanggal)->create();
        Measurement::factory()->untukAnak($this->anak())->padaTanggal($tanggal)->create();

        $this->assertSame(2, Measurement::where('measurement_date', $tanggal)->count());
    }

    #[Test]
    public function penimbangan_ulang_boleh_setelah_yang_lama_dibatalkan(): void
    {
        $anak = $this->anak();
        $tanggal = '2026-09-01';

        $lama = Measurement::factory()->untukAnak($anak)->padaTanggal($tanggal)->create();
        $lama->delete();

        $baru = Measurement::factory()->untukAnak($anak)->padaTanggal($tanggal)->create();

        $this->assertNotSame($lama->id, $baru->id);
        $this->assertNotNull($baru->fresh());
    }

    // -----------------------------------------------------------------
    // 4. Scope untuk rekap
    // -----------------------------------------------------------------

    #[Test]
    public function scope_bulan_membatasi_hasil_ke_bulan_yang_diminta(): void
    {
        $anak = $this->anak();

        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-08-31')->create();
        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-09-01')->create();
        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-09-30')->create();
        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-10-01')->create();

        // `measurement_date` sengaja tidak di-cast menjadi objek Carbon di
        // jadi nilainya masih string `Y-m-d`. Test ini membandingkan apa yang
        // benar-benar dikembalikan database.
        $hasil = Measurement::forMonth('2026-09')->orderBy('measurement_date')
            ->pluck('measurement_date')->map(fn ($t) => (string) $t)->all();

        $this->assertSame(['2026-09-01', '2026-09-30'], $hasil);
    }

    #[Test]
    public function scope_bulan_menangani_bulan_dengan_29_hari(): void
    {
        $anak = $this->anak();

        // 2026 bukan tahun kabisat, jadi Februari punya 28 hari. Kalau batas
        // akhir dihitung dengan pola `$month.'-31'`, PostgreSQL melempar
        // "date/time field value out of range".
        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-02-28')->create();
        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-03-01')->create();

        $this->assertSame(1, Measurement::forMonth('2026-02')->count());
    }

    #[Test]
    public function scope_rentang_tanggal_inklusif_di_kedua_ujung(): void
    {
        $anak = $this->anak();

        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-08-30')->create();
        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-08-31')->create();
        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-09-01')->create();

        $hasil = Measurement::betweenDates('2026-08-31', '2026-09-01')->count();

        $this->assertSame(2, $hasil);
    }

    // -----------------------------------------------------------------
    // 5. Dampak ke `medical_notes` - PERUBAHAN KONTRAK
    // -----------------------------------------------------------------

    /**
     * `medical_notes.measurement_id` TIDAK lagi jadi null setelah penimbangan
     * dibatalkan.
     *
     * Sebelumnya `delete()` menghapus baris secara fisik, jadi FK
     * `ON DELETE SET NULL` menyala dan tautannya terlepas. Sekarang
     * `measurements` memakai soft delete: barisnya tetap ada, FK tidak pernah
     * menyala, dan catatan masih menunjuk penimbangan yang dibatalkan.
     *
     * Ini yang diinginkan: "keluhan ini dicatat saat penimbangan 18 Sep, yang lalu
     * dibatalkan" lebih berguna untuk audit daripada tautan yang hilang. Yang
     * tetap dijamin adalah isi catatan itu sendiri tidak ikut terhapus.
     *
     * FK `ON DELETE SET NULL` sengaja dipertahankan karena masih berlaku untuk
     * penghapusan fisik (forceDelete).
     */
    #[Test]
    public function membatalkan_penimbangan_menahan_keluhan_tetap_utuh(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();

        $penimbangan = Measurement::factory()
            ->untukAnak($anak)
            ->olehKader($kader)
            ->padaTanggal('2026-09-18')
            ->create();

        $keluhan = MedicalNote::factory()
            ->untukAnak($anak)
            ->olehKader($kader)
            ->demam()
            ->create(['measurement_id' => $penimbangan->id, 'note_date' => '2026-09-18']);

        $penimbangan->delete();

        // Baris penimbangan masih ada, hanya ditandai batal.
        $this->assertSoftDeleted($penimbangan);
        $this->assertSame(1, Measurement::withTrashed()->whereKey($penimbangan->id)->count());

        // Keluhan tetap utuh, termasuk kolom boolean-nya.
        $keluhan->refresh();
        $this->assertNotNull($keluhan);
        $this->assertTrue($keluhan->demam);
        $this->assertFalse($keluhan->diare);
        $this->assertSame(MedicalNote::TINDAK_LANJUT_RUJUK, $keluhan->tindak_lanjut);

        // Tautan tetap menunjuk penimbangan yang sudah dibatalkan.
        $this->assertSame($penimbangan->id, $keluhan->measurement_id);
        $this->assertSame(1, MedicalNote::whereKey($keluhan->id)->count());
    }

    #[Test]
    public function penghapusan_fisik_penimbangan_melepaskan_tautan_keluhan(): void
    {
        $kader = User::factory()->kader()->create();
        $anak = $this->anak();

        $penimbangan = Measurement::factory()
            ->untukAnak($anak)
            ->olehKader($kader)
            ->padaTanggal('2026-09-18')
            ->create();

        $keluhan = MedicalNote::factory()
            ->untukAnak($anak)
            ->demam()
            ->create(['measurement_id' => $penimbangan->id, 'note_date' => '2026-09-18']);

        // forceDelete benar-benar menghapus baris, jadi FK harus menyala dan
        // melepas tautannya. Keluhannya sendiri tetap ada.
        $penimbangan->forceDelete();

        $this->assertNull($keluhan->fresh()->measurement_id);
        $this->assertTrue($keluhan->fresh()->demam);
    }

    /**
     * Catatan yang menunjuk penimbangan batal TETAP bisa diedit.
     *
     * Ini yang perlu dijaga. `MedicalNoteController` memvalidasi
     * `measurement_id` dengan `Rule::exists('measurements', 'id')`, yang
     * memakai query builder sehingga TIDAK melihat soft delete. Kalau aturan
     * itu diubah jadi stricter tanpa diperhatikan aturan `sometimes`, catatan
     * lama akan terkunci hanya karena penimbangannya dibatalkan - padahal
     * membetulkan tanggal atau menambah tindak lanjut adalah hal yang paling
     * sering dilakukan kader.
     */
    #[Test]
    public function catatan_yang_tautannya_dibatalkan_tetap_bisa_diedit(): void
    {
        $kader = User::factory()->kader()->create(['role' => 'kader']);
        $anak = $this->anak();

        $penimbangan = Measurement::factory()
            ->untukAnak($anak)
            ->olehKader($kader)
            ->padaTanggal('2026-09-18')
            ->create();

        $keluhan = MedicalNote::factory()
            ->untukAnak($anak)
            ->demam()
            ->create(['measurement_id' => $penimbangan->id, 'note_date' => '2026-09-18']);

        $penimbangan->delete();

        $token = $kader->createToken('uji')->plainTextToken;

        $respons = $this->withHeader('Authorization', 'Bearer '.$token)
            ->patchJson("/api/kader/medical-notes/{$keluhan->id}", [
                'tindak_lanjut' => MedicalNote::TINDAK_LANJUT_SEDANG,
            ]);

        $respons->assertOk();

        // Tautan tidak ikut berubah, dan isi catatan bisa disempitkan.
        $keluhan->refresh();
        $this->assertSame($penimbangan->id, $keluhan->measurement_id);
        $this->assertSame(MedicalNote::TINDAK_LANJUT_SEDANG, $keluhan->tindak_lanjut);
    }

    // -----------------------------------------------------------------
    // 6. Factory/user bawaan
    // -----------------------------------------------------------------

    #[Test]
    public function factory_user_bisa_dibuat_tanpa_kolom_email(): void
    {
        // Factory bawaan Laravel mengisi `email`, yang tidak ada di tabel
        // `users`. Test ini gagal kalau ada yang memunculkan kembali kolom itu.
        $kader = User::factory()->kader()->create();
        $ibu = User::factory()->ibu()->create();

        $this->assertSame('kader', $kader->role);
        $this->assertSame('ibu', $ibu->role);
        $this->assertDatabaseHas('users', ['nik' => $kader->nik, 'role' => 'kader']);
    }

    // -----------------------------------------------------------------
    // Helper
    // -----------------------------------------------------------------

    /**
     * Anak dengan tanggal lahir yang pasti.
     *
     * `ChildFactory` mengisi `date_of_birth` secara acak antara 5 tahun dan 1
     * bulan lalu, sedangkan trigger `calculate_measurement_who_zscore()`
     * menolak penimbangan yang lebih awal dari tanggal lahir anak. Pasangkan
     * anak acak dengan tanggal pengimbangan hardcode Februari 2026 dan test
     * ini gagal sekitar 1 dari 8 kali jalannya - bukan karena kodenya salah,
     * tapi karena hasilnya tidak bisa diprediksi. Tanggal lahir ditetapkan di
     * sini supaya kelulusannya tidak bergantung pada tanggal hari ini.
     */
    private function anak(): Child
    {
        return Child::factory()->create(['date_of_birth' => '2024-01-01']);
    }
}
