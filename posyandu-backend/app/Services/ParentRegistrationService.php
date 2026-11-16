<?php

namespace App\Services;

use App\Models\User;
use App\Repositories\Contracts\ParentRepositoryInterface;
use App\Support\NikHasher;
use Illuminate\Database\QueryException;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;

class ParentRegistrationService
{
    /**
     * Field profil yang boleh diisi dari request. `role`, `password`,
     * `verification_file`, dan field kader sengaja tidak termasuk karena
     * ditangani terpisah.
     */
    private const PROFILE_FIELDS = [
        'no_kk',
        'name',
        'phone_number',
        'place_of_birth',
        'date_of_birth',
        'gender',
        'blood_type',
        'address',
        'rt_rw',
        'education',
        'occupation',
    ];

    public function __construct(
        private readonly ParentRepositoryInterface $parents,
        private readonly VerificationDocumentService $documents,
    ) {}

    /**
     * Daftarkan akun Ibu baru.
     *
     * @param  array<string, mixed>  $data
     * @return array{user: User, token: string}
     */
    public function registerParent(
        array $data,
        ?UploadedFile $document = null,
        string $documentType = 'other',
    ): array {
        try {
            return DB::transaction(function () use ($data, $document, $documentType): array {
                $nik = (string) $data['nik'];
                $nikHash = NikHasher::hash($nik);

                if ($this->parents->findByNikHash($nikHash) !== null) {
                    throw ValidationException::withMessages([
                        'nik' => ['NIK sudah terdaftar. Silakan login atau hubungi Kader Posyandu.'],
                    ]);
                }

                $user = $this->parents->create([
                    ...$this->profileAttributes($data),
                    'nik' => $nik,
                    'nik_hash' => $nikHash,
                    'password' => Hash::make((string) $data['password']),
                    'role' => 'ibu',
                    'status' => 'pending',
                    'onboarding_status' => 'need_child_data',
                ]);

                if ($document !== null) {
                    $this->documents->store($document, $user->id, $documentType);
                }

                // Token tetap diterbitkan walau status masih pending. Tanpa
                // token, klien tidak bisa memanggil /registration/status dan
                // /registration/complete setelah mendaftar (bug alur lama).
                $token = $user->createToken('posyandu-mobile-token')->plainTextToken;

                return [
                    'user' => $user->load('verifications'),
                    'token' => $token,
                ];
            });
        } catch (QueryException $e) {
            $this->rethrowDuplicateNik($e);
        }
    }

    /**
     * Lengkapi/perbaiki data pendaftaran Ibu.
     *
     * Akun `pending` maupun `rejected` boleh memakai endpoint ini. Akun yang
     * ditolak dikembalikan ke status pending agar bisa ditinjau ulang kader
     * (alur "Perbaiki & Kirim Ulang" pada mobile sebelumnya tidak berfungsi
     * karena controller menolak status rejected).
     *
     * @param  array<string, mixed>  $data
     */
    public function completeProfile(
        User $user,
        array $data,
        ?UploadedFile $document = null,
        string $documentType = 'other',
    ): User {
        try {
            return DB::transaction(function () use ($user, $data, $document, $documentType): User {
                $attributes = $this->profileAttributes($data);

                if (array_key_exists('nik', $data) && $data['nik'] !== null) {
                    $nik = (string) $data['nik'];
                    $nikHash = NikHasher::hash($nik);

                    $other = $this->parents->findByNikHash($nikHash);

                    if ($other !== null && $other->id !== $user->id) {
                        throw ValidationException::withMessages([
                            'nik' => ['NIK sudah terdaftar pada akun lain.'],
                        ]);
                    }

                    $attributes['nik'] = $nik;
                    $attributes['nik_hash'] = $nikHash;
                }

                if ($user->status === 'rejected') {
                    $attributes['status'] = 'pending';
                    $attributes['rejection_reason'] = null;
                    $attributes['approved_by'] = null;
                    $attributes['approved_at'] = null;
                    $attributes['verified_at'] = null;
                }

                $user = $this->parents->update($user, $attributes);

                if ($document !== null) {
                    $this->documents->store($document, $user->id, $documentType);
                }

                return $user->load('verifications');
            });
        } catch (QueryException $e) {
            $this->rethrowDuplicateNik($e);
        }
    }

    /**
     * @param  array<string, mixed>  $data
     * @return array<string, mixed>
     */
    private function profileAttributes(array $data): array
    {
        $attributes = [];

        foreach (self::PROFILE_FIELDS as $field) {
            if (array_key_exists($field, $data)) {
                $attributes[$field] = $data[$field];
            }
        }

        return $attributes;
    }

    /**
     * @throws ValidationException
     */
    private function rethrowDuplicateNik(QueryException $e): never
    {
        // 23505 = unique_violation PostgreSQL. Bisa terjadi bila dua request
        // mendaftar NIK yang sama hampir bersamaan (race condition), karena
        // pengecekan aplikasi tidak berada di dalam lock.
        if ((string) $e->getCode() === '23505') {
            throw ValidationException::withMessages([
                'nik' => ['NIK sudah terdaftar. Silakan login atau hubungi Kader Posyandu.'],
            ]);
        }

        Log::error('Gagal menyimpan data pendaftaran Ibu: '.$e->getMessage(), ['exception' => $e]);

        throw $e;
    }
}
