<?php

namespace App\Services;

use App\Models\Child;
use App\Models\Consent;
use App\Models\User;
use App\Repositories\Contracts\ChildRepositoryInterface;
use App\Repositories\Contracts\ParentRepositoryInterface;
use App\Support\NikHasher;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;

class ChildOnboardingService
{
    public function __construct(
        private readonly ChildRepositoryInterface $children,
        private readonly ParentRepositoryInterface $parents,
    ) {}

    /**
     * Simpan data anak dan selesaikan onboarding Ibu.
     *
     * @param  array<string, mixed>  $data
     */
    public function store(User $parent, array $data): Child
    {
        try {
            return DB::transaction(function () use ($parent, $data): Child {
                $nik = (string) $data['nik'];
                $nikHash = NikHasher::hash($nik);

                if ($this->children->existsByNikHash($nikHash)) {
                    throw ValidationException::withMessages([
                        'nik' => ['NIK anak sudah terdaftar.'],
                    ]);
                }

                // `birth_length` adalah nama kanonis. `birth_height` sekarang
                // kolom generated di database, jadi tidak boleh diisi manual.
                $birthLength = $data['birth_length'] ?? null;

                $child = $this->children->createForParent($parent, [
                    'nik' => $nik,
                    'nik_hash' => $nikHash,
                    'name' => $data['name'],
                    'place_of_birth' => $data['place_of_birth'] ?? $data['birth_place'] ?? null,
                    'birth_place' => $data['birth_place'] ?? $data['place_of_birth'] ?? null,
                    'date_of_birth' => $data['date_of_birth'],
                    'gender' => $data['gender'],
                    'birth_order' => $data['birth_order'] ?? null,
                    'birth_weight' => $data['birth_weight'] ?? null,
                    'birth_length' => $birthLength,
                    'birth_head_circumference' => $data['birth_head_circumference'] ?? null,
                    'birth_status' => $data['birth_status'] ?? null,
                    'buku_kia_id' => $data['buku_kia_id'] ?? null,
                ]);

                if (! empty($data['consent_type'])) {
                    Consent::query()->create([
                        'child_id' => $child->id,
                        'granted_by' => $parent->id,
                        'consent_type' => $data['consent_type'],
                        'granted_at' => now(),
                        'document_version' => $data['consent_document_version'],
                    ]);
                }

                $this->parents->markOnboardingCompleted($parent);

                return $child->load('mother:id,name');
            });
        } catch (QueryException $e) {
            if ((string) $e->getCode() === '23505') {
                throw ValidationException::withMessages([
                    'nik' => ['NIK anak sudah terdaftar.'],
                ]);
            }

            Log::error('Gagal menyimpan data anak: '.$e->getMessage(), [
                'parent_id' => $parent->id,
                'exception' => $e,
            ]);

            throw $e;
        }
    }
}
