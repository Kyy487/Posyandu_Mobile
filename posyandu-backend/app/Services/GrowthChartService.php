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
 * tabel referensi `who_wfa_standards`. Tidak ada tabel baru, tidak ada duplikasi
 * data, jadi grafik tidak mungkin menyimpang dari catatan aslinya.
 *
 * Bentuk keluaran dan batasannya dikunci di
 * `docs/RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md` bagian 7.2 dan 7.3 (aturan agent:
 * `posyandu-backend/.ai/rules/kontrak-growth.md`). Kalau bentuk di sini terasa
 * perlu diubah, dokumennya yang diubah lebih dulu.
 *
 * Lima keputusan yang tidak boleh dibalik tanpa alasan tertulis:
 *
 *  1. **Dua query, tidak bertambah.** Satu query untuk titik penimbangan, satu
 *     untuk pita WHO. Keduanya tidak bergantung pada jumlah titik.
 *  2. **Tanpa penghitungan ulang.** `age_in_months`, `z_score_wfa`, dan
 *     `status_gizi` dibaca apa adanya dari database, yang menghitungkannya
 *     sudah trigger PostgreSQL. Server dan mobile sama-sama tidak menghitung.
 *  3. **Pita dibaca, bukan dihitung dari data anak.** `lower_kg` dan `upper_kg`
 *     diturunkan dari `median_kg` dan `sd_kg` di SQL, karena itu konstanta
 *     referensi WHO. `z_score_wfa` anak sendiri tidak pernah diturunkan dari
 *     pita: nilainya tetap dibaca dari kolom yang diisi trigger.
 *  4. **Pita hanya untuk BB/U.** Database tidak punya acuan TB/U, jadi
 *     `who_reference` tidak memuat pita tinggi badan. `height_cm` tetap
 *     dikirim sebagai nilai mentah - itu keputusan, bukan kekurangan.
 *  5. **Tanpa pagination.** Endpoint ini sengaja tidak punya query string.
 *     Partial unique index membatasi satu baris per tanggal, jadi anak 0-60
 *     bulan paling banyak 61 titik.
 */
class GrowthChartService
{
    /**
     * Grafik pertumbuhan satu anak, titik urut naik dari tanggal terlama.
     *
     * @return array{
     *     child: array<string, mixed>,
     *     series: array{unit: array{weight: string, height: string}, order: string, points: list<array<string, mixed>>},
     *     who_reference: array{metric: string, source: string, gender: string|null, age_range: array{from: int|null, to: int|null}, points: list<array<string, mixed>>}
     * }
     */
    public function chartFor(Child $child): array
    {
        return [
            'child' => $this->childBlock($child),
            'series' => [
                'unit' => ['weight' => 'kg', 'height' => 'cm'],
                // Selalu `"asc"`. Field ini ada supaya klien tidak perlu menebak
                // urutan dan supaya test bisa membuktikannya; grafik butuh sumbu x
                // dari lama ke baru, dan itu tanggung jawab server.
                'order' => 'asc',
                'points' => $this->points($child),
            ],
            // Pita dikirim walau `points` kosong: pita tidak bergantung pada
            // riwayat penimbangan, jadi layar bisa menggambarnya sebelum
            // kunjungan pertama.
            'who_reference' => $this->whoReference($child),
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
            ->get([
                'measurements.measurement_date',
                'measurements.age_in_months',
                'measurements.weight_kg',
                'measurements.height_cm',
                'measurements.head_circumference_cm',
                'measurements.z_score_wfa',
                'measurements.status_gizi',
            ])
            ->map(fn (Measurement $m): array => [
                'date' => $this->tanggal($m->measurement_date),
                // Dibaca apa adanya. Menghitungnya ulang dari `date_of_birth` di
                // sini akan menyimpang dari trigger, karena trigger menghitungnya
                // saat baris dicatat, bukan saat baris dibaca.
                'age_in_months' => $m->age_in_months === null ? null : (int) $m->age_in_months,
                'weight_kg' => $this->angka($m->weight_kg),
                'height_cm' => $this->angka($m->height_cm),
                'head_circumference_cm' => $this->angka($m->head_circumference_cm),
                // Keduanya boleh `null` untuk anak di luar rentang WHO. Itu
                // berbeda dari "gizi baik", jadi tidak boleh diisi 0 atau teks.
                'z_score_wfa' => $this->angka($m->z_score_wfa),
                'status_gizi' => $m->status_gizi,
            ])
            ->all();
    }

    /**
     * Pita acuan WHO BB/U: median dan batas -/+2 SD per umur, mengikuti gender anak.
     *
     * Penurunan `lower_kg` dan `upper_kg` dilakukan di SQL, bukan di PHP,
     * karena `who_wfa_standards` adalah tabel konstanta referensi - bukan data
     * anak. Melewatkan nilai mentahnya ke klien memaksa Flutter menghitung
     * sendiri batas pita, dan dua tempat menghitung berarti dua jawaban.
     *
     * Batas rentang umur dibaca dari baris yang benar-benar ada, bukan ditulis
     * konstanta di sini, supaya tabel acuan yang berubah tidak diam-diam membuat
     * pita meleset dari usia anak.
     *
     * Satu query untuk seluruh rentang umur. Tidak ada query per umur, dan
     * jumlah query tidak bergantung pada jumlah titik.
     *
     * @return array{metric: string, source: string, gender: string|null, age_range: array{from: int|null, to: int|null}, points: list<array<string, mixed>>}
     */
    private function whoReference(Child $child): array
    {
        $baris = DB::table('who_wfa_standards')
            ->where('gender', $child->gender)
            ->orderBy('age_in_months')
            ->get([
                'age_in_months',
                'median_kg',
                'sd_kg',
                DB::raw('median_kg - 2 * sd_kg as lower_kg'),
                DB::raw('median_kg + 2 * sd_kg as upper_kg'),
            ]);

        $points = $baris->map(fn (object $b): array => [
            'age_in_months' => (int) $b->age_in_months,
            'median_kg' => $this->angka($b->median_kg),
            'lower_kg' => $this->angka($b->lower_kg),
            'upper_kg' => $this->angka($b->upper_kg),
        ])->values()->all();

        // Gender di luar `L`/`P` menghasilkan pita kosong, dan itu jawaban
        // yang benar: tidak ada acuan WHO untuk data itu. `gender` tetap
        // dikembalikan apa adanya supaya layar bisa menjelaskan kenapa pitanya
        // kosong, alih-alih diam-diam tidak menggambar apa pun.
        $pertama = $points[0] ?? null;
        $terakhir = $points === [] ? null : $points[count($points) - 1];

        return [
            'metric' => 'weight_for_age',
            'source' => 'WHO Child Growth Standards 2006',
            'gender' => $child->gender,
            'age_range' => [
                'from' => $pertama === null ? null : (int) $pertama['age_in_months'],
                'to' => $terakhir === null ? null : (int) $terakhir['age_in_months'],
            ],
            'points' => $points,
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
