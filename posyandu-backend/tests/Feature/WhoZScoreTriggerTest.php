<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\Measurement;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Regresi trigger `calculate_measurement_who_zscore` setelah kolom
 * `status_wfh` ditambahkan.
 *
 * Migration `2026_10_15_052851_add_status_wfh_to_measurements_and_trigger.php`
 * mengganti isi function lewat `CREATE OR REPLACE FUNCTION`. Karena trigger
 * adalah satu-satunya tempat z-score dan status dihitung (aturan
 * `yang-jangan-diubah.md`), seluruh perilaku lama wajib dibuktikan tidak
 * bergeser - terutama `status_gizi` yang harus tetap BB/U, bukan komposit.
 *
 * Test di sini memakai PostgreSQL sungguhan: perilaku yang diuji tidak ada di
 * SQLite.
 */
class WhoZScoreTriggerTest extends TestCase
{
    use RefreshDatabase;

    /**
     * `status_wfh` hanya diisi ketika acuan BB/TB ketemu, yaitu umur < 24 bulan.
     *
     * Di umur >= 24 bulan tidak ada acuan panjang badan yang cocok, jadi nilai
     * dan statusnya harus `null` - bukan "Normal".
     */
    #[Test]
    public function status_wfh_terisi_di_bawah_24_bulan_dan_null_di_atasnya(): void
    {
        $bayi = Child::factory()->create(['date_of_birth' => '2024-06-01', 'gender' => 'L']);
        $besar = Child::factory()->create(['date_of_birth' => '2024-01-01', 'gender' => 'L']);

        // 12 bulan: acuan BB/TB ada.
        Measurement::factory()->untukAnak($bayi)->padaTanggal('2025-06-01')
            ->create(['weight_kg' => 9.6, 'height_cm' => 75.0]);

        // 30 bulan: di luar acuan BB/TB.
        Measurement::factory()->untukAnak($besar)->padaTanggal('2026-07-01')
            ->create(['weight_kg' => 13.0, 'height_cm' => 90.0]);

        $tersimpanBayi = Measurement::where('child_id', $bayi->id)->firstOrFail();
        $tersimpanBesar = Measurement::where('child_id', $besar->id)->firstOrFail();

        $this->assertNotNull($tersimpanBayi->z_score_wfh);
        $this->assertNotNull($tersimpanBayi->status_wfh);

        $this->assertNull($tersimpanBesar->z_score_wfh);
        $this->assertNull($tersimpanBesar->status_wfh);
    }

    /**
     * Kategori `status_wfh` mengikuti ambang z-score yang sama seperti indikator
     * lain: < -3 Gizi Buruk, < -2 Gizi Kurang, > 2 Risiko Gizi Lebih, sisanya
     * Normal.
     */
    #[Test]
    public function kategori_status_wfh_sesuai_ambang_z_score(): void
    {
        $anak = Child::factory()->create(['date_of_birth' => '2024-06-01', 'gender' => 'L']);

        // Berat dari sangat kurang sampai sangat lebih, tinggi tetap 75 cm.
        // Satu tanggal per baris: index unik `measurements_child_date_unique`
        // melarang dua penimbangan di hari yang sama, sedangkan umur tetap 12
        // bulan selama masih di bulan Juni 2025.
        foreach ([5.0, 8.0, 9.6, 13.0, 16.0] as $i => $berat) {
            Measurement::factory()->untukAnak($anak)->create([
                'measurement_date' => '2025-06-'.str_pad((string) ($i + 1), 2, '0', STR_PAD_LEFT),
                'weight_kg' => $berat,
                'height_cm' => 75.0,
            ]);
        }

        $semua = Measurement::where('child_id', $anak->id)->get();
        $this->assertCount(5, $semua);

        // Minimal satu 'Gizi Buruk', satu 'Risiko Gizi Lebih', dan satu
        // 'Normal', supaya test tidak lulus hanya karena semua baris kebetulan
        // sejenis.
        $statusTerkumpul = $semua->pluck('status_wfh')->unique()->values()->all();
        $this->assertContains('Normal', $statusTerkumpul);
        $this->assertNotEmpty(array_intersect(['Gizi Buruk', 'Gizi Kurang'], $statusTerkumpul));
        $this->assertContains('Risiko Gizi Lebih', $statusTerkumpul);

        foreach ($semua as $baris) {
            $z = (float) $baris->z_score_wfh;
            $harapan = match (true) {
                $z < -3 => 'Gizi Buruk',
                $z < -2 => 'Gizi Kurang',
                $z > 2 => 'Risiko Gizi Lebih',
                default => 'Normal',
            };

            $this->assertSame($harapan, $baris->status_wfh, "Status untuk z=$z salah.");
        }
    }

    /**
     * Regresi terpenting: `status_gizi` tetap BB/U, bukan komposit.
     *
     * Anak bisa pendek (stunting) tanpa kurang berat badan. Kalau `status_gizi`
     * kembali menjadi agregasi terburuk, anak ini akan berlabel "Stunting" di
     * kolom BB/U - persis bug yang dibatalkan
     * `2026_10_12_000000_restore_wfa_only_status_gizi_trigger.php`. Test ini
     * mengunci keputusan itu setelah trigger disentuh lagi.
     */
    #[Test]
    public function status_gizi_tetap_bb_u_bukan_komposit(): void
    {
        // Perempuan 27 bulan: berat 12,3 kg (di dalam pita BB/U), tinggi 70 cm
        // (jauh di bawah pita TB/U -> stunting).
        $anak = Child::factory()->create(['date_of_birth' => '2024-01-01', 'gender' => 'P']);

        Measurement::factory()->untukAnak($anak)->padaTanggal('2026-04-01')
            ->create(['weight_kg' => 12.3, 'height_cm' => 70.0]);

        $tersimpan = Measurement::where('child_id', $anak->id)->firstOrFail();

        $this->assertNotNull($tersimpan->z_score_wfa);
        $this->assertSame('Normal', $tersimpan->status_gizi, 'BB/U anak ini normal.');

        // Tinggi yang sama tetap menghasilkan status stunting di kolomnya
        // sendiri: dua indikator terpisah, tidak saling menimpa.
        $this->assertSame('Stunting', $tersimpan->status_stunting);
        $this->assertLessThan(-2, (float) $tersimpan->z_score_hfa);
    }

    /**
     * Menyentuh baris membuat trigger menghitung ulang dan mengosongkan status
     * yang tidak lagi berlaku.
     *
     * Kalau `status_wfh` lupa dikosongkan di awal function, memindahkan
     * penimbangan ke umur >= 24 bulan akan meninggalkan status lama - dan layar
     * akan menampilkan BB/TB untuk anak yang acuannya tidak ada.
     */
    #[Test]
    public function memindahkan_penimbangan_ke_umur_24_bulan_mengosongkan_status_wfh(): void
    {
        $anak = Child::factory()->create(['date_of_birth' => '2024-06-01', 'gender' => 'L']);

        $baris = Measurement::factory()->untukAnak($anak)->padaTanggal('2025-06-01')
            ->create(['weight_kg' => 9.6, 'height_cm' => 75.0]);

        $this->assertNotNull($baris->fresh()->status_wfh);

        // Pindahkan ke 30 bulan: 2026-12-01.
        $baris->update(['measurement_date' => '2026-12-01']);

        $this->assertNull($baris->fresh()->status_wfh);
        $this->assertNull($baris->fresh()->z_score_wfh);
    }
}
