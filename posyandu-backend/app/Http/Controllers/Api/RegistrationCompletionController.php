<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\CompleteRegistrationRequest;
use App\Http\Requests\Child\StoreChildRequest;
use App\Models\User;
use App\Services\ChildOnboardingService;
use App\Services\ParentRegistrationService;
use App\Support\NikHasher;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class RegistrationCompletionController extends Controller
{
    public function __construct(
        private readonly ParentRegistrationService $registrations,
        private readonly ChildOnboardingService $onboarding,
    ) {}

    /**
     * Status pendaftaran (bisa diakses via token atau NIK).
     */
    public function show(Request $request): JsonResponse
    {
        $user = $this->resolveUser($request);

        if ($user === null) {
            return response()->json([
                'success' => false,
                'message' => 'Status pendaftaran tidak ditemukan.',
                'errors' => null,
            ], 404);
        }

        $user->load('verifications');

        return response()->json([
            'success' => true,
            'message' => 'Status pendaftaran berhasil diambil.',
            'data' => $user,
        ]);
    }

    /**
     * Lengkapi atau perbaiki data pendaftaran Ibu.
     */
    public function update(CompleteRegistrationRequest $request): JsonResponse
    {
        $user = $this->resolveUser($request);

        if ($user === null) {
            return response()->json([
                'success' => false,
                'message' => 'Status pendaftaran tidak ditemukan.',
                'errors' => null,
            ], 404);
        }

        if ($user->role !== 'ibu') {
            return response()->json([
                'success' => false,
                'message' => 'Hanya akun Ibu yang dapat melengkapi data pendaftaran.',
                'errors' => null,
            ], 403);
        }

        if (! in_array($user->status, ['pending', 'rejected'], true)) {
            return response()->json([
                'success' => false,
                'message' => 'Data pendaftaran hanya dapat diubah saat status menunggu atau ditolak.',
                'errors' => null,
            ], 403);
        }

        $user = $this->registrations->completeProfile(
            $user,
            $request->validated(),
            $request->file('verification_file'),
            (string) $request->input('verification_type', 'other'),
        );

        return response()->json([
            'success' => true,
            'message' => 'Data pendaftaran berhasil dilengkapi dan menunggu persetujuan kader.',
            'data' => $user,
        ]);
    }

    /**
     * Onboarding data anak setelah akun Ibu disetujui Kader.
     *
     * Endpoint ini adalah satu-satunya jalur yang diizinkan selama
     * `onboarding_status = need_child_data`.
     */
    public function storeChild(StoreChildRequest $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        if ($user->role !== 'ibu') {
            return response()->json([
                'success' => false,
                'message' => 'Hanya akun Ibu yang dapat melengkapi data anak.',
                'errors' => null,
            ], 403);
        }

        $child = $this->onboarding->store($user, $request->validated());

        return response()->json([
            'success' => true,
            'message' => 'Data anak berhasil disimpan. Onboarding selesai.',
            'data' => [
                'child' => $child,
                'user' => $user->fresh()->load('verifications'),
            ],
        ], 201);
    }

    private function resolveUser(Request $request): ?User
    {
        if ($request->user() !== null) {
            return $request->user();
        }

        $nik = (string) $request->input('nik');
        if ($nik === '') {
            return null;
        }

        return User::query()
            ->where('nik_hash', NikHasher::hash($nik))
            ->whereIn('status', ['pending', 'rejected'])
            ->first();
    }
}
