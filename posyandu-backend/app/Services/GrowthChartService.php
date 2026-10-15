<?php

namespace App\Services;

use App\Models\Child;
use App\Models\Measurement;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;

/**
 * Deret waktu pertumbuhan satu anak untuk digambar sebagai grafik.
 *
 * Ini bentuk baca lain dari `measurements` yang sudah ada, ditambah pembacaan
 * tabel referensi `who_wfa_standards`, `who_hfa_standards`, dan
 * `who_bfa_standards`. Tidak ada tabel baru, tidak ada duplikasi data, jadi
 * grafik tidak mungkin menyimpang dari catatan aslinya.
 *
 * Bentuk keluaran dan batasannya dikunci di
 * `docs/RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md` bagian 7.2 dan 7.3, dan diperluas
 * di `docs/RANCANGAN_WHO_MULTIDIM.md` bagian 6 (aturan 13-22). Aturan agent:
 * `posyandu-backend/.ai/rules/kontrak-growth.md`. Kalau bentuk di sini terasa
 * perlu diubah, dokumennya yang diubah lebih dulu.
 *
 * Enam keputusan yang tidak boleh dibalik tanpa alasan tertulis:
 *
 *  1. **Dua query, tidak bertambah.** Satu query untuk titik penimbangan, satu
 *     untuk tiga pita WHO (`UNION ALL`). Keduanya tidak bergantung pada jumlah
 *     titik.
 *  2. **Tanpa penghitungan ulang.** `age_in_months`, `z_score_wfa`,
 *     `status_gizi`, `z_score_hfa`, `status_stunting`, `z_score_bfa`,
 *     `status_gizi_imt`, `z_score_wfh`, dan `status_wfh` dibaca apa adanya dari
 *     database, yang menghitungkannya sudah trigger PostgreSQL. Server dan
 *     mobile sama-sama tidak menghitung.
 *  3. **Pita dibaca, bukan dihitung dari data anak.** Ketiga pita diturunkan di
 *     SQL dari tabel acuan WHO. `z_score_*` anak sendiri tidak pernah diturunkan
 *     dari pita: nilainya tetap dibaca dari kolom yang diisi trigger.
 *  4. **Pita tiga metrik, bukan tiga query.** BB/U, TB/U, dan IMT/U dibaca
 *     dalam satu `UNION ALL`, lalu dipecah di PHP.
 *  5. **BB/TB tidak punya pita.** Sumbu acuan BB/TB adalah panjang badan, bukan
 *     umur, jadi `z_score_wfh` selalu dikirim sebagai nilai tanpa pita.
 *  6. **Tanpa pagination.** Endpoint ini sengaja tidak punya query string.
 *     Partial unique index membatasi satu baris per tanggal, jadi anak 0-60
 *     bulan paling banyak 61 titik.
 */
class GrowthChartService
{
    /**
     * Meta tiap metrik pita, urut normatif yang diuji.
     *
     * @var array<string, array{label: string, unit: string}>
     */
    private const META_PITA = [
        'weight_for_age' => ['label' => 'BB/U', 'unit' => 'kg'],
        'height_for_age' => ['label' => 'TB/U', 'unit' => 'cm'],
        'bmi_for_age' => ['label' => 'IMT/U', 'unit' => 'kg/m2'],
    ];

    /**
     * Grafik pertumbuhan satu anak, titik urut naik dari tanggal terlama.
     *
     * `who_reference` (tunggal, BB/U) dipertahankan apa adanya untuk klien lama
     * dan di-`slice` dari hasil query pita yang sama, sehingga tidak menambah
     * query.
     *
     * @return array<string, mixed>
     */
    public function chartFor(Child $child): array
    {
        $pita = $this->whoReferences($child);

        return [
            'child' => $this->childBlock($child),
            'series' => [
                'unit' => ['weight' => 'kg', 'height' => 'cm', 'bmi' => 'kg/m2'],
                // Selalu `"asc"`. Field ini ada supaya klien tidak perlu menebak
                // urutan dan supaya test bisa membuktikannya; grafik butuh sumbu x
                // dari lama ke baru, dan itu tanggung jawab server.
                'order' => 'asc',
                'points' => $this->points($child),
            ],
            // Pita dikirim walau `points` kosong: pita tidak bergantung pada
            // riwayat penimbangan, jadi layar bisa menggambarnya sebelum
            // kunjungan pertama.
            'who_reference' => $this->whoReferenceTunggal($pita, $child),
            'who_references' => $pita,
        ];
    }

    /**
     * Titik penimbangan satu anak, urut naik.
     *
     * `leftJoin` ke `users` dipakai agar penimbangan tanpa kader tetap ikut
     * terbaca. `kader_id` bisa `null` karena `ON DELETE SET NULL`, jadi `join`
     * biasa akan diam-diam menghilangkan riwayat anak yang kadernya sudah
     * dihapus - persis data yang paling tidak boleh hilang.
     *
     * BMI dihitung di SQL dengan rumus antropometri sederhana (bukan z-score,
     * bukan median WHO), supaya satu rumus hanya hidup di satu tempat. Kolom
     * z-score/status multidimensi dibaca apa adanya dari trigger.
     *
     * Soft delete terfilter oleh global scope Eloquent, jadi `deleted_at IS NULL`
     * tidak ditulis manual di sini.
     *
     * @return list<array<string, mixed>>
     */
    private function points(Child $child): array
    {
        return Measurement::query()
            ->leftJoin('users as kader', 'kader.id', '=', 'measurements.kader_id')
            ->where('measurements.child_id', $child->id)
            ->orderBy('measurements.measurement_date')
            ->orderBy('measurements.id')
            ->select([
                'measurements.measurement_date',
                'measurements.age_in_months',
                'measurements.weight_kg',
                'measurements.height_cm',
                'measurements.head_circumference_cm',
                DB::raw('CASE WHEN measurements.height_cm IS NOT NULL AND measurements.height_cm > 0 '
                    .'THEN round(measurements.weight_kg / power(measurements.height_cm / 100.0, 2), 2) '
                    .'ELSE NULL END AS bmi'),
                'measurements.z_score_wfa',
                'measurements.status_gizi',
                'measurements.z_score_hfa',
                'measurements.status_stunting',
                'measurements.z_score_bfa',
                'measurements.status_gizi_imt',
                'measurements.z_score_wfh',
                'measurements.status_wfh',
            ])
            ->get()
            ->map(fn (Measurement $m): array => [
                'date' => $this->tanggal($m->measurement_date),
                // Dibaca apa adanya. Menghitungnya ulang dari `date_of_birth` di
                // sini akan menyimpang dari trigger, karena trigger menghitungnya
                // saat baris dicatat, bukan saat baris dibaca.
                'age_in_months' => $m->age_in_months === null ? null : (int) $m->age_in_months,
                'weight_kg' => $this->angka($m->weight_kg),
                'height_cm' => $this->angka($m->height_cm),
                'head_circumference_cm' => $this->angka($m->head_circumference_cm),
                'bmi' => $this->angka($m->bmi),
                // Semua boleh `null` untuk anak di luar rentang WHO atau di luar
                // rentang indikatornya. Itu berbeda dari "gizi baik", jadi tidak
                // boleh diisi 0 atau teks.
                'z_score_wfa' => $this->angka($m->z_score_wfa),
                'status_gizi' => $m->status_gizi,
                'z_score_hfa' => $this->angka($m->z_score_hfa),
                'status_stunting' => $m->status_stunting,
                'z_score_bfa' => $this->angka($m->z_score_bfa),
                'status_gizi_imt' => $m->status_gizi_imt,
                'z_score_wfh' => $this->angka($m->z_score_wfh),
                'status_wfh' => $m->status_wfh,
            ])
            ->all();
    }

    /**
     * Tiga pita acuan WHO (BB/U, TB/U, IMT/U) dalam satu query `UNION ALL`.
     *
     * BB/U memakai `median_kg`/`sd_kg`. TB/U dan IMT/U menyimpan `(l, m, s)`,
     * jadi batas pitanya dievaluasi di SQL dengan rumus inverse LMS WHO:
     *
     *   z = -2 / 0 / +2  ->  CASE WHEN l = 0 THEN m * exp(s * z)
     *                             ELSE m * power(1 + l * s * z, 1.0 / l) END
     *
     * Ini bukan menghitung ulang z-score anak: ini mengevaluasi konstanta
     * referensi di tiga nilai z tetap, seperti `median_kg - 2 * sd_kg` yang
     * sudah diterima untuk BB/U. `NULLIF(l, 0)` mencegah pembagian nol walau
     * cabang CASE-nya tidak dipakai.
     *
     * Urut keluaran **normatif**: BB/U, TB/U, IMT/U. `metric_order` hanya alat
     * bantu urut dan tidak dikirim.
     *
     * @return list<array<string, mixed>>
     */
    private function whoReferences(Child $child): array
    {
        $lms = static function (string $z): string {
            return "CASE WHEN l = 0 THEN m * exp(s * {$z}) "
                ."ELSE m * power(1 + l * s * {$z}, 1.0 / NULLIF(l, 0)) END";
        };

        $baris = DB::table('who_wfa_standards')
            ->where('gender', $child->gender)
            ->selectRaw("0 as metric_order, 'weight_for_age' as metric, age_in_months, "
                .'median_kg as median, median_kg - 2 * sd_kg as "lower", median_kg + 2 * sd_kg as "upper"')
            ->unionAll(
                DB::table('who_hfa_standards')
                    ->where('gender', $child->gender)
                    ->selectRaw("1 as metric_order, 'height_for_age' as metric, age_in_months, "
                        .'m as median, '.$lms('-2').' as "lower", '.$lms('2').' as "upper"')
            )
            ->unionAll(
                DB::table('who_bfa_standards')
                    ->where('gender', $child->gender)
                    ->selectRaw("2 as metric_order, 'bmi_for_age' as metric, age_in_months, "
                        .'m as median, '.$lms('-2').' as "lower", '.$lms('2').' as "upper"')
            )
            ->orderBy('metric_order')
            ->orderBy('age_in_months')
            ->get();

        $perMetrik = array_fill_keys(array_keys(self::META_PITA), []);

        foreach ($baris as $b) {
            if (! array_key_exists($b->metric, $perMetrik)) {
                continue;
            }

            $perMetrik[$b->metric][] = [
                'age_in_months' => (int) $b->age_in_months,
                'median' => $this->angka($b->median),
                'lower' => $this->angka($b->lower),
                'upper' => $this->angka($b->upper),
            ];
        }

        $hasil = [];

        foreach (self::META_PITA as $metric => $meta) {
            $titik = $perMetrik[$metric];
            // Gender di luar L/P menghasilkan pita kosong, dan itu jawaban yang
            // benar: tidak ada acuan WHO untuk data itu. Rentang umurnya null,
            // tapi entrinya tetap ada supaya layar bisa menjelaskan alasannya.
            $pertama = $titik[0]['age_in_months'] ?? null;
            $terakhir = $titik === [] ? null : $titik[count($titik) - 1]['age_in_months'];

            $hasil[] = [
                'metric' => $metric,
                'label' => $meta['label'],
                'unit' => $meta['unit'],
                'x_axis' => 'age_in_months',
                'source' => 'WHO Child Growth Standards 2006',
                'gender' => $child->gender,
                'age_range' => ['from' => $pertama, 'to' => $terakhir],
                'points' => $titik,
            ];
        }

        return $hasil;
    }

    /**
     * Pita BB/U tunggal (bentuk lama) yang di-`slice` dari `who_references`.
     *
     * Klien lama membaca `median_kg`/`lower_kg`/`upper_kg`, jadi nama field-nya
     * dipertahankan persis. Nilainya sama dengan entri `weight_for_age` di
     * `who_references`, hanya nama kunci titiknya yang dipetakan. Tidak ada
     * query tambahan di sini.
     *
     * @param  list<array<string, mixed>>  $pita
     * @return array{metric: string, source: string, gender: string|null, age_range: array{from: int|null, to: int|null}, points: list<array<string, mixed>>}
     */
    private function whoReferenceTunggal(array $pita, Child $child): array
    {
        $wfa = $pita[0];

        return [
            'metric' => 'weight_for_age',
            'source' => $wfa['source'],
            'gender' => $child->gender,
            'age_range' => $wfa['age_range'],
            'points' => array_map(fn (array $t): array => [
                'age_in_months' => $t['age_in_months'],
                'median_kg' => $t['median'],
                'lower_kg' => $t['lower'],
                'upper_kg' => $t['upper'],
            ], $wfa['points']),
        ];
    }

    /**
     * Blok identitas anak di kepala respons.
     *
     * `age_in_months` dibaca dari penimbangan terakhir, yang dihitung trigger
     * `trg_measurements_who_zscore`. Anak yang belum pernah ditimbang tidak
     * punya baris itu, jadi nilainya `null` - bukan hasil hitungan ulang di PHP.
     * Definisi ini sama dengan `ChildTimelineService::childBlock()`, supaya dua
     * layar tidak berbeda makna "umur".
     *
     * @return array<string, mixed>
     */
    private function childBlock(Child $child): array
    {
        $anak = $child->loadMissing('mother:id,name,nik');
        $terakhir = $anak->latestMeasurement;

        return [
            'id' => $anak->id,
            'name' => $anak->name,
            'nik' => $anak->nik,
            'gender' => $anak->gender,
            'date_of_birth' => $this->tanggal($anak->date_of_birth),
            'age_in_months' => $terakhir === null || $terakhir->age_in_months === null
                ? null
                : (int) $terakhir->age_in_months,
            // Teks mentah apa adanya, sama seperti di `GET /children/{id}` dan
            // timeline. Tidak diparsing: kode dan Kader harus melihat nilai yang
            // sama persis.
            'medical_flags' => $anak->medical_flags,
        ];
    }

    /**
     * Tanggal dari database selalu `Y-m-d`, tapi kolomnya lewat beberapa jalur
     * (cast Eloquent, attribute model) yang bisa berbeda tipe. Satu tempat
     * untuk membentuknya supaya isi `points[].date` dijamin konsisten.
     */
    private function tanggal(mixed $nilai): string
    {
        return CarbonImmutable::parse((string) $nilai)->toDateString();
    }

    /**
     * Angka desimal dari PostgreSQL datang sebagai string (`"12.40"`), termasuk
     * hasil `median_kg - 2 * sd_kg` yang juga bertipe decimal. Flutter
     * membacanya sebagai teks kalau dibiarkan begitu, dan `LineChart` butuh
     * num, jadi dikembalikan sebagai float di sini.
     */
    private function angka(mixed $nilai): ?float
    {
        return $nilai === null ? null : (float) $nilai;
    }
}
