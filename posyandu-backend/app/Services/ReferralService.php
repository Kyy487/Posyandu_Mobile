<?php

namespace App\Services;

use App\Models\Child;
use App\Models\Referral;
use App\Models\User;
use Carbon\CarbonImmutable;

/**
 * Rujukan anak ke fasilitas kesehatan (lihat docs/RANCANGAN_RUJUKAN.md).
 *
 * Controller hanya menangani validasi dan otorisasi; bentuk data ada di sini
 * supaya bentuk yang sama dipakai daftar, detail, dan detail kunjungan.
 *
 * Keputusan yang penting:
 *  1. `kader_id` diisi dari pengguna yang login, bukan dari klien, supaya
 *     atribusi pencatat tidak bisa dipalsukan - sama seperti `VisitService`.
 *  2. Rujukan yang dibatalkan (soft delete) otomatis hilang dari daftar, karena
 *     global scope Eloquent.
 *  3. `kader_id` boleh `null` (akun kader dihapus). Penyajian selalu memeriksa
 *     null sebelum membaca `name`.
 */
class ReferralService
{
    /**
     * Daftar rujukan satu anak, terbaru lebih dulu.
     *
     * @return list<array<string, mixed>>
     */
    public function listForChild(Child $child): array
    {
        return Referral::query()
            ->where('child_id', $child->id)
            ->with('kader:id,name')
            ->orderByDesc('referral_date')
            ->orderByDesc('created_at')
            ->get()
            ->map(fn (Referral $referral): array => $this->present($referral))
            ->all();
    }

    /**
     * Membuat rujukan baru untuk satu anak.
     *
     * @param  array<string, mixed>  $data  data yang sudah tervalidasi
     */
    public function create(Child $child, User $kader, array $data): Referral
    {
        return Referral::create([
            'visit_id' => $data['visit_id'],
            'child_id' => $child->id,
            'referral_date' => $data['referral_date'],
            'referral_type' => $data['referral_type'],
            'reason' => $this->normalizeText($data['reason']),
            'facility_name' => $this->normalizeText($data['facility_name']),
            'status' => $data['status'] ?? Referral::STATUS_DIBUAT,
            'kader_id' => $kader->id,
        ]);
    }

    /**
     * Perbarui rujukan (partial update: hanya field yang dikirim).
     *
     * `child_id` dan `visit_id` tidak bisa dipindah: rujukan yang salah anak
     * atau salah kunjungan dibatalkan lalu dibuat ulang.
     *
     * @param  array<string, mixed>  $data
     */
    public function update(Referral $referral, array $data): Referral
    {
        foreach (['reason', 'facility_name'] as $kolom) {
            if (array_key_exists($kolom, $data)) {
                $data[$kolom] = $this->normalizeText($data[$kolom]);
            }
        }

        $referral->fill($data)->save();

        return $referral;
    }

    /**
     * Bentuk satu rujukan untuk respons API.
     *
     * Field baru boleh ditambah; mengganti nama atau tipe field lama akan
     * merusak klien yang sudah berjalan.
     *
     * @return array<string, mixed>
     */
    public function present(Referral $referral): array
    {
        return [
            'id' => $referral->id,
            'child_id' => $referral->child_id,
            'visit_id' => $referral->visit_id,
            'referral_date' => CarbonImmutable::parse((string) $referral->referral_date)->toDateString(),
            'referral_type' => $referral->referral_type,
            'reason' => $referral->reason,
            'facility_name' => $referral->facility_name,
            'status' => $referral->status,
            'kader_id' => $referral->kader_id,
            'kader' => $referral->kader === null ? null : [
                'id' => $referral->kader->id,
                'name' => $referral->kader->name,
            ],
            'created_at' => $referral->created_at?->toIso8601String(),
            'updated_at' => $referral->updated_at?->toIso8601String(),
        ];
    }

    /**
     * `null` tetap `null`; teks kosong/spasi jadi `null`. Konsisten dengan
     * `VisitService::normalizeText`.
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
