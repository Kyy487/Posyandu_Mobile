<?php

namespace App\Services;

use App\Models\Child;
use App\Models\User;
use App\Models\Visit;
use Carbon\CarbonImmutable;

/**
 * Kunjungan layanan (P0-1) — pembuatan, pembacaan, dan pembentukan respons.
 *
 * Controller hanya menangani validasi dan otorisasi; bentuk data ada di sini
 * agar bentuk yang sama dipakai daftar, detail, dan detail anak (lihat aturan
 * "Fat Model, Skinny Controller" di docs/AI_AGENT_RULES.md).
 *
 * Keputusan yang penting:
 *  1. Z-score dan `age_in_months` TIDAK dihitung ulang di sini. Nilainya dibaca
 *     apa adanya dari database - yang menghitungnya sudah trigger PostgreSQL.
 *  2. Kunjungan yang dibatalkan (soft delete) otomatis hilang dari daftar,
 *     karena global scope Eloquent.
 *  3. `kader_id` boleh `null` (akun kader dihapus). Penyajian selalu memeriksa
 *     null sebelum membaca `name`.
 */
class VisitService
{
    /**
     * Daftar kunjungan satu anak, terbaru lebih dulu.
     *
     * Setiap baris memuat jumlah penimbangan/imunisasi/keluhan pada kunjungan
     * itu, supaya klien tidak perlu menghitung ulang. Jumlahnya diambil lewat
     * `withCount` (satu query), bukan N+1.
     *
     * @return list<array<string, mixed>>
     */
    public function listForChild(Child $child): array
    {
        return Visit::query()
            ->where('child_id', $child->id)
            ->with('kader:id,name')
            ->withCount(['measurements', 'immunizationRecords', 'medicalNotes'])
            ->orderByDesc('visit_date')
            ->orderByDesc('created_at')
            ->get()
            ->map(fn (Visit $visit): array => $this->present($visit, withCounts: true))
            ->all();
    }

    /**
     * Membuat kunjungan baru untuk satu anak.
     *
     * `kader_id` diisi dari pengguna yang login (bukan dari klien), sama seperti
     * `MedicalNoteController@store`, supaya atribusi pencatat tidak bisa dipalsukan.
     *
     * @param  array<string, mixed>  $data  data yang sudah tervalidasi
     */
    public function create(Child $child, User $kader, array $data): Visit
    {
        return Visit::create([
            'child_id' => $child->id,
            'schedule_id' => $data['schedule_id'] ?? null,
            'visit_date' => $data['visit_date'],
            'visit_type' => $data['visit_type'],
            'kader_id' => $kader->id,
            'anamnesis' => $this->normalizeText($data['anamnesis'] ?? null),
            'catatan_kader' => $this->normalizeText($data['catatan_kader'] ?? null),
        ]);
    }

    /**
     * Perbarui kunjungan (partial update: hanya field yang dikirim).
     *
     * @param  array<string, mixed>  $data
     */
    public function update(Visit $visit, array $data): Visit
    {
        if (array_key_exists('anamnesis', $data)) {
            $data['anamnesis'] = $this->normalizeText($data['anamnesis']);
        }

        if (array_key_exists('catatan_kader', $data)) {
            $data['catatan_kader'] = $this->normalizeText($data['catatan_kader']);
        }

        $visit->fill($data)->save();

        return $visit;
    }

    /**
     * Detail satu kunjungan, lengkap dengan data yang terhubung.
     *
     * @return array<string, mixed>
     */
    public function detail(Visit $visit): array
    {
        $visit->load([
            'kader:id,name',
            'measurements' => fn ($q) => $q->orderBy('measurement_date'),
            'immunizationRecords.immunizationType',
            'medicalNotes',
            'referrals' => fn ($q) => $q->with('kader:id,name')->orderBy('referral_date'),
        ]);

        return $this->present($visit, withRecords: true);
    }

    /**
     * Bentuk satu kunjungan untuk respons API.
     *
     * Field baru boleh ditambah; mengganti nama atau tipe field lama akan
     * merusak klien yang sudah berjalan (docs/AI_AGENT_RULES.md bagian 8).
     *
     * @return array<string, mixed>
     */
    public function present(Visit $visit, bool $withCounts = false, bool $withRecords = false): array
    {
        $data = [
            'id' => $visit->id,
            'child_id' => $visit->child_id,
            'schedule_id' => $visit->schedule_id,
            'visit_date' => CarbonImmutable::parse((string) $visit->visit_date)->toDateString(),
            'visit_type' => $visit->visit_type,
            'kader_id' => $visit->kader_id,
            'kader' => $visit->kader === null ? null : [
                'id' => $visit->kader->id,
                'name' => $visit->kader->name,
            ],
            'anamnesis' => $visit->anamnesis,
            'catatan_kader' => $visit->catatan_kader,
            'created_at' => $visit->created_at?->toIso8601String(),
            'updated_at' => $visit->updated_at?->toIso8601String(),
        ];

        if ($withCounts) {
            $data['jumlah_pengukuran'] = (int) ($visit->measurements_count ?? 0);
            $data['jumlah_imunisasi'] = (int) ($visit->immunization_records_count ?? 0);
            $data['jumlah_keluhan'] = (int) ($visit->medical_notes_count ?? 0);
        }

        if ($withRecords) {
            $data['pengukuran'] = $visit->measurements
                ->map(fn ($m): array => [
                    'id' => $m->id,
                    'measurement_date' => CarbonImmutable::parse((string) $m->measurement_date)->toDateString(),
                    'weight_kg' => $m->weight_kg === null ? null : (float) $m->weight_kg,
                    'height_cm' => $m->height_cm === null ? null : (float) $m->height_cm,
                    'head_circumference_cm' => $m->head_circumference_cm === null ? null : (float) $m->head_circumference_cm,
                    'age_in_months' => $m->age_in_months === null ? null : (int) $m->age_in_months,
                    'z_score_wfa' => $m->z_score_wfa === null ? null : (float) $m->z_score_wfa,
                    'status_gizi' => $m->status_gizi,
                ])
                ->values()
                ->all();

            $data['imunisasi'] = $visit->immunizationRecords
                ->map(fn ($r): array => [
                    'id' => $r->id,
                    'immunization_type_id' => $r->immunization_type_id,
                    'type' => $r->immunizationType?->code,
                    'date_given' => CarbonImmutable::parse((string) $r->date_given)->toDateString(),
                    'batch_number' => $r->batch_number,
                    'notes' => $r->notes,
                ])
                ->values()
                ->all();

            $data['catatan_keluhan'] = $visit->medicalNotes
                ->map(fn ($n): array => [
                    'id' => $n->id,
                    'note_date' => CarbonImmutable::parse((string) $n->note_date)->toDateString(),
                    'demam' => (bool) $n->demam,
                    'rewel' => (bool) $n->rewel,
                    'diare' => (bool) $n->diare,
                    'catatan' => $n->catatan,
                    'tindak_lanjut' => $n->tindak_lanjut,
                    'ringkasan' => $n->ringkasan,
                ])
                ->values()
                ->all();

            // Rujukan yang tercatat pada kunjungan ini (aditif; kunci baru,
            // tidak menggantikan yang lama).
            $data['rujukan'] = $visit->referrals
                ->map(fn ($r): array => [
                    'id' => $r->id,
                    'referral_date' => CarbonImmutable::parse((string) $r->referral_date)->toDateString(),
                    'referral_type' => $r->referral_type,
                    'reason' => $r->reason,
                    'facility_name' => $r->facility_name,
                    'status' => $r->status,
                    'kader_id' => $r->kader_id,
                    'kader' => $r->kader === null ? null : [
                        'id' => $r->kader->id,
                        'name' => $r->kader->name,
                    ],
                ])
                ->values()
                ->all();
        }

        return $data;
    }

    /**
     * `null` tetap `null`; teks kosong/spasi jadi `null`. Konsisten dengan
     * `MedicalNoteController::normalizeCatatan`.
     */
    private function normalizeText(?string $text): ?string
    {
        if ($text === null) {
            return null;
        }

        $bersih = trim($text);

        return $bersih === '' ? null : $bersih;
    }
}
