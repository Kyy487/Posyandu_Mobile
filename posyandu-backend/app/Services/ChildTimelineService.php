<?php

namespace App\Services;

use App\Models\Child;
use App\Models\ImmunizationRecord;
use App\Models\Measurement;
use App\Models\MedicalNote;
use Carbon\CarbonImmutable;
use Illuminate\Database\Query\Builder as QueryBuilder;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Riwayat medis satu anak dalam satu layar, dikelompokkan per tanggal kunjungan.
 *
 * Ini gabungan tiga tabel yang sudah ada - `measurements`,
 * `immunization_records`, `medical_notes` - bukan tabel baru. Tidak ada data yang
 * diduplikasi, jadi timeline tidak mungkin menyimpang dari catatan aslinya.
 *
 * Bentuk keluaran dan batasannya dikunci di `docs/RANCANGAN_BUKU_MEDIS.md` bagian
 * 7.2 dan 7.3 (aturan agent: `posyandu-backend/.ai/rules/kontrak-timeline.md`).
 * Kalau bentuk di sini terasa perlu diubah, dokumennya yang diubah lebih dulu.
 *
 * Tiga keputusan yang tidak boleh dibalik tanpa alasan tertulis:
 *
 *  1. **Empat query, tidak bertambah.** Satu query mengambil daftar tanggal lewat
 *     `UNION` atas tiga kolom tanggal, lalu tiga query mengisi isi rentang
 *     tanggal itu. Alternatifnya - mengambil `limit` baris per tabel lalu
 *     digabung - menghasilkan timeline yang terpotong di tengah satu
 *     kunjungan, dan jumlah query-nya ikut tumbuh.
 *  2. **Tanpa penghitungan ulang.** Z-score, `age_in_months`, dan `status_gizi`
 *     dibaca apa adanya dari database, yang menghitungkannya sudah trigger
 *     PostgreSQL. Server dan mobile sama-sama tidak menghitung; kalau angka di
 *     sini terasa salah, perbaikannya di trigger atau di data, bukan di sini.
 *  3. **Baris yang dibatalkan tidak tampil.** Ketiga tabel punya `deleted_at`.
 *     Dua query di bawah memakai Eloquent (soft delete terfilter otomatis), satu
 *     query tanggal memakai query builder mentah - di situ `deleted_at IS NULL`
 *     ditulis sendiri, karena global scope tidak berlaku untuk query mentah.
 */
class ChildTimelineService
{
    /**
     * Timeline satu anak, terbaru lebih dulu.
     *
     * @param  int  $limit  jumlah TANGGAL yang dikembalikan, bukan jumlah baris
     * @param  string|null  $before  cursor `Y-m-d`; hanya tanggal sebelum ini yang diambil
     * @return array{
     *     child: array<string, mixed>,
     *     entries: list<array<string, mixed>>,
     *     meta: array{has_more: bool, next_before: string|null}
     * }
     */
    public function timelineFor(Child $child, int $limit = 50, ?string $before = null): array
    {
        // Satu tanggal ekstra diambil untuk membedakan "halaman terakhir" dari
        // "halaman penuh". Tanpa itu, `has_more` hanya bisa ditebak.
        $tanggal = $this->datesWindow($child, $before)->limit($limit + 1)->pluck('tanggal');

        $hasMore = $tanggal->count() > $limit;
        $tanggal = $tanggal->take($limit)->values();

        if ($tanggal->isEmpty()) {
            // `entries` kosong adalah jawaban yang benar untuk anak yang belum
            // pernah ditimbang, disuntik, atau punya keluhan - bukan 404.
            return [
                'child' => $this->childBlock($child),
                'entries' => [],
                'meta' => ['has_more' => false, 'next_before' => null],
            ];
        }

        // Isi ketiga tabel diambil untuk rentang tanggal halaman ini saja.
        // `min` dan `max` hampir selalu sama kalau satu tanggal per kunjungan,
        // tapi `before` dan `limit` membuat keduanya tidak selalu begitu.
        $dari = (string) $tanggal->last();
        $sampai = (string) $tanggal->first();

        $measurements = $this->measurementsIn($child, $dari, $sampai);
        $immunizations = $this->immunizationsIn($child, $dari, $sampai);
        $notes = $this->notesIn($child, $dari, $sampai);

        $entries = $tanggal->map(function (string $tgl) use ($measurements, $immunizations, $notes): array {
            return [
                'date' => $tgl,
                // Tiga kunci ini boleh `null`. Tanggal yang punya keluhan tapi
                // tanpa penimbangan tetap muncul sebagai entri - itu kunjungan
                // yang sah, bukan data yang tidak lengkap.
                'measurement' => $measurements->get($tgl),
                'immunizations' => $immunizations->get($tgl, []),
                'medical_note' => $notes->get($tgl),
            ];
        })->all();

        return [
            'child' => $this->childBlock($child),
            'entries' => $entries,
            'meta' => [
                'has_more' => $hasMore,
                // `null` di halaman terakhir, bukan string kosong: bentuknya
                // harus sama di semua halaman supaya klien tidak perlu
                // mengecek dua tipe nilai.
                'next_before' => $hasMore ? (string) $tanggal->last() : null,
            ],
        ];
    }

    /**
     * Daftar tanggal kunjungan, sudah terpotong `before` dan `limit`.
     *
     * `UNION` (bukan `UNION ALL`) dipakai supaya tanggal yang sama dari tiga
     * tabel muncul satu kali. Tanpa itu, satu tanggal yang punya penimbangan
     * dan suntikan akan memakan dua slot `limit` dan menggeser batas halaman.
     *
     * `before` diterapkan di lapisan luar, bukan di tiap cabang, supaya
     * syaratnya hanya ditulis sekali.
     */
    private function datesWindow(Child $child, ?string $before): QueryBuilder
    {
        return DB::query()
            ->fromSub($this->unionOfDates($child), 'kunjungan')
            ->when($before, fn (QueryBuilder $q, string $tgl) => $q->where('kunjungan.tanggal', '<', $tgl))
            ->orderByDesc('kunjungan.tanggal');
    }

    /**
     * Gabungan tiga kolom tanggal untuk satu anak.
     *
     * Ditulis dengan query builder mentah, bukan Eloquent, supaya tiga kolom
     * dengan nama berbeda bisa disatukan. Konsekuensinya, filter soft delete
     * TIDAK otomatis: `deleted_at IS NULL` ditulis eksplisit di tiap cabang.
     * Kalau salah satu lupa, baris yang sudah dibatalkan kader akan muncul
     * lagi sebagai tanggal kunjungan.
     */
    private function unionOfDates(Child $child): QueryBuilder
    {
        $tanggalPenimbangan = DB::query()
            ->select('measurement_date as tanggal')
            ->from('measurements')
            ->where('child_id', $child->id)
            ->whereNull('deleted_at');

        $tanggalSuntikan = DB::query()
            ->select('date_given as tanggal')
            ->from('immunization_records')
            ->where('child_id', $child->id)
            ->whereNull('deleted_at');

        $tanggalKeluhan = DB::query()
            ->select('note_date as tanggal')
            ->from('medical_notes')
            ->where('child_id', $child->id)
            ->whereNull('deleted_at');

        return $tanggalPenimbangan
            ->union($tanggalSuntikan)
            ->union($tanggalKeluhan);
    }

    /**
     * Penimbangan dalam rentang tanggal, dikelompokkan per tanggal.
     *
     * `leftJoin` ke `users` dipakai agar penimbangan tanpa kader tetap ikut
     * terbaca. `kader_id` bisa `null` karena `ON DELETE SET NULL`, jadi `join`
     * biasa akan diam-diam menghilangkan riwayat anak yang kadernya sudah
     * dihapus - dan itu justru data yang paling tidak boleh hilang.
     *
     * @return Collection<string, array<string, mixed>>
     */
    private function measurementsIn(Child $child, string $dari, string $sampai): Collection
    {
        return Measurement::query()
            ->leftJoin('users as kader', 'kader.id', '=', 'measurements.kader_id')
            ->where('measurements.child_id', $child->id)
            ->whereBetween('measurements.measurement_date', [$dari, $sampai])
            ->orderBy('measurements.measurement_date')
            ->get([
                'measurements.id',
                'measurements.measurement_date',
                'measurements.weight_kg',
                'measurements.height_cm',
                'measurements.head_circumference_cm',
                'measurements.z_score_wfa',
                'measurements.status_gizi',
                'kader.id as kader_id',
                'kader.name as kader_name',
            ])
            ->mapWithKeys(fn (Measurement $m): array => [
                $this->tanggal($m->measurement_date) => [
                    'weight_kg' => $this->angka($m->weight_kg),
                    'height_cm' => $this->angka($m->height_cm),
                    'head_circumference_cm' => $this->angka($m->head_circumference_cm),
                    'z_score_wfa' => $this->angka($m->z_score_wfa),
                    'status_gizi' => $m->status_gizi,
                    'kader' => $m->kader_id === null ? null : [
                        'id' => $m->kader_id,
                        'name' => $m->kader_name,
                    ],
                ],
            ]);
    }

    /**
     * Suntikan dalam rentang tanggal, dikelompokkan per tanggal.
     *
     * `immunization_types` di-join supaya kode dosis ikut terbaca tanpa query
     * tambahan. Bentuk keluarannya persis `{type, date_given}` sesuai bagian 7.2;
     * rincian dosis lengkap (label, batch, catatan) tetap dibaca dari
     * `GET /children/{id}/immunizations`, bukan diduplikasi di sini.
     *
     * @return Collection<string, list<array<string, mixed>>>
     */
    private function immunizationsIn(Child $child, string $dari, string $sampai): Collection
    {
        return ImmunizationRecord::query()
            ->join('immunization_types', 'immunization_types.id', '=', 'immunization_records.immunization_type_id')
            ->where('immunization_records.child_id', $child->id)
            ->whereBetween('immunization_records.date_given', [$dari, $sampai])
            // Satu tanggal boleh punya beberapa suntikan, jadi urutannya harus
            // deterministik. Tanpa `id`, dua suntikan pada tanggal yang sama
            // bisa tertukar posisinya antar request.
            ->orderBy('immunization_records.date_given')
            ->orderBy('immunization_records.id')
            ->get([
                'immunization_records.id',
                'immunization_records.date_given',
                'immunization_types.code as type',
            ])
            ->groupBy(fn (ImmunizationRecord $r): string => $this->tanggal($r->date_given))
            ->map(fn ($rows): array => $rows
                ->map(fn (ImmunizationRecord $r): array => [
                    'type' => $r->type,
                    'date_given' => $this->tanggal($r->date_given),
                ])
                ->values()
                ->all());
    }

    /**
     * Keluhan dalam rentang tanggal, dikelompokkan per tanggal.
     *
     * Satu anak punya paling banyak satu catatan keluhan per tanggal, dijamin
     * partial unique index `medical_notes_child_date_unique`. Jadi di sini tidak
     * perlu array, cukup ambil yang pertama.
     *
     * @return Collection<string, array<string, mixed>>
     */
    private function notesIn(Child $child, string $dari, string $sampai): Collection
    {
        return MedicalNote::query()
            ->where('child_id', $child->id)
            ->whereBetween('note_date', [$dari, $sampai])
            ->orderBy('note_date')
            ->get()
            ->mapWithKeys(fn (MedicalNote $n): array => [
                $this->tanggal($n->note_date) => [
                    // Cast `boolean` di model dipakai di sini: tanpa itu
                    // PostgreSQL mengirim `true`/`false` yang dibaca Flutter
                    // sebagai string, dan checkbox di UI tidak tercentang
                    // padahal isinya benar.
                    'demam' => (bool) $n->demam,
                    'rewel' => (bool) $n->rewel,
                    'diare' => (bool) $n->diare,
                    'catatan' => $n->catatan,
                    'tindak_lanjut' => $n->tindak_lanjut,
                ],
            ]);
    }

    /**
     * Blok identitas anak di kepala respons.
     *
     * `age_in_months` dibaca dari penimbangan terakhir, yang dihitung trigger
     * `trg_measurements_who_zscore`. Anak yang belum pernah ditimbang tidak
     * punya baris itu, jadi nilainya `null` - bukan hasil hitungan ulang di
     * PHP, karena hitungan kedua di server pasti akan menyimpang dari trigger
     * begitu aturan usianya berubah.
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
            'date_of_birth' => $this->tanggal($anak->date_of_birth),
            'age_in_months' => $terakhir === null ? null : (int) $terakhir->age_in_months,
            'gender' => $anak->gender,
            'mother' => $anak->mother === null ? null : [
                'name' => $anak->mother->name,
                'nik' => $anak->mother->nik,
            ],
            // Teks mentah apa adanya. Tidak diparsing, tidak dinormalisasi:
            // kode dan Kader harus melihat nilai yang sama persis.
            'medical_flags' => $anak->medical_flags,
            'latest_measurement' => $terakhir === null ? null : [
                'weight_kg' => $this->angka($terakhir->weight_kg),
                'status_gizi' => $terakhir->status_gizi,
            ],
        ];
    }

    /**
     * Tanggal dari database selalu `Y-m-d`, tapi kolomnya lewat beberapa jalur
     * (raw query, cast Eloquent, attribute model) yang bisa berbeda tipe.
     * Satu tempat untuk membentuknya supaya isi `entries[].date` dan kunci
     * pengelompokan dijamin identik.
     */
    private function tanggal(mixed $nilai): string
    {
        return CarbonImmutable::parse((string) $nilai)->toDateString();
    }

    /**
     * Angka desimal dari PostgreSQL datang sebagai string (`"12.40"`). Flutter
     * membacanya sebagai teks kalau dibiarkan begitu, jadi dikembalikan sebagai
     * float di sini - sama seperti `Child::getLatestZScoreAttribute()`.
     */
    private function angka(mixed $nilai): ?float
    {
        return $nilai === null ? null : (float) $nilai;
    }
}
