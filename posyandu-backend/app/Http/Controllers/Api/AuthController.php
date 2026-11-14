<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\RegisterParentRequest;
use App\Models\User;
use App\Services\ParentRegistrationService;
use App\Support\NikHasher;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    /**
     * Pendaftaran Akun (Register)
     *
     * Aturan #2/#3: role TIDAK PERNAH diambil dari input pengguna. Server yang
     * memutuskan.
     *
     * - Tanpa `kader_code`  -> akun `ibu`, status pending, onboarding
     *   `need_child_data`, dan token diterbitkan agar klien bisa langsung
     *   melengkapi data.
     * - Dengan `kader_code` yang cocok -> akun `kader` (langsung aktif)
     * - `KADER_REGISTRATION_CODE` kosong di .env -> pendaftaran kader dimatikan (403).
     */
    public function register(
        RegisterParentRequest $request,
        ParentRegistrationService $service,
    ): JsonResponse {
        try {
            $role = $this->resolveRegistrationRole($request);

            if ($role === null) {
                return response()->json([
                    'success' => false,
                    'message' => 'Pendaftaran akun kader ditolak.',
                    'errors' => $this->kaderCodeErrors($request),
                ], 403);
            }

            if ($role === 'ibu') {
                $result = $service->registerParent(
                    $request->validated(),
                    $request->file('verification_file'),
                    (string) $request->input('verification_type', 'other'),
                );

                return response()->json([
                    'success' => true,
                    'message' => 'Pendaftaran berhasil. Akun Anda menunggu persetujuan dari Kader Posyandu.',
                    'data' => [
                        'user' => $result['user'],
                        'status' => $result['user']->status,
                        'token' => $result['token'],
                    ],
                ], 201);
            }

            $user = User::query()->create([
                ...$this->profileAttributes($request->validated()),
                'nik' => $request->validated('nik'),
                'nik_hash' => NikHasher::hash((string) $request->validated('nik')),
                'name' => $request->validated('name'),
                'password' => Hash::make((string) $request->validated('password')),
                'role' => 'kader',
                'status' => 'active',
                'onboarding_status' => 'completed',
                'verified_at' => now(),
            ]);

            $token = $user->createToken('posyandu-mobile-token')->plainTextToken;

            return response()->json([
                'success' => true,
                'message' => 'Registrasi kader berhasil.',
                'data' => [
                    'user' => $user,
                    'token' => $token,
                ],
            ], 201);

        } catch (ValidationException $e) {
            return $this->validationFailed($e->errors());
        } catch (\Throwable $e) {
            // Aturan #10: pesan asli hanya ke log, tidak pernah ke klien.
            Log::error('Gagal mendaftar akun: '.$e->getMessage(), [
                'nik' => $request->input('nik'),
                'exception' => $e,
            ]);

            return response()->json([
                'success' => false,
                'message' => 'Terjadi kesalahan server. Silakan coba lagi.',
                'errors' => null,
            ], 500);
        }
    }

    /**
     * Memeriksa NIK + password.
     *
     * Ibu yang masih pending / ditolak tetap mendapat token agar bisa
     * melengkapi atau memperbaiki pendaftaran. Pembatasan akses dilakukan
     * middleware `CheckKaderVerification`, bukan dengan menolak login -
     * tanpa token, endpoint perbaikan data tidak bisa dipakai.
     */
    public function login(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'nik' => ['required', 'string', 'size:16'],
            'password' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return $this->validationFailed($validator->errors()->toArray());
        }

        try {
            $user = User::query()
                ->where('nik_hash', NikHasher::hash((string) $request->nik))
                ->first();

            if (! $user || ! Hash::check((string) $request->password, $user->password)) {
                return response()->json([
                    'success' => false,
                    'message' => 'Kredensial yang diberikan tidak cocok dengan data kami.',
                    'errors' => null,
                ], 401);
            }

            // Hapus token lama agar tidak menumpuk.
            $user->tokens()->delete();

            $token = $user->createToken('posyandu-mobile-token')->plainTextToken;

            return response()->json([
                'success' => true,
                'message' => $this->loginMessage($user),
                'data' => [
                    'user' => $user,
                    'token' => $token,
                    'status' => $user->status,
                    'next_action' => $user->next_action,
                ],
            ], 200);

        } catch (\Throwable $e) {
            Log::error('Gagal login: '.$e->getMessage(), [
                'nik' => $request->nik,
                'exception' => $e,
            ]);

            return response()->json([
                'success' => false,
                'message' => 'Terjadi kesalahan server. Silakan coba lagi.',
                'errors' => null,
            ], 500);
        }
    }

    /**
     * Keluar (Logout) - mencabut token yang sedang dipakai.
     */
    public function logout(Request $request): JsonResponse
    {
        try {
            $request->user()->currentAccessToken()?->delete();

            return response()->json([
                'success' => true,
                'message' => 'Berhasil logout.',
                'data' => null,
            ], 200);
        } catch (\Throwable $e) {
            Log::error('Gagal logout: '.$e->getMessage(), ['exception' => $e]);

            return response()->json([
                'success' => false,
                'message' => 'Terjadi kesalahan server. Silakan coba lagi.',
                'errors' => null,
            ], 500);
        }
    }

    private function loginMessage(User $user): string
    {
        if ($user->role !== 'ibu') {
            return 'Login berhasil';
        }

        return match ($user->verification_status) {
            'pending' => 'Akun Anda sedang menunggu verifikasi oleh Kader Posyandu.',
            'rejected' => $user->rejection_reason
                ? 'Pendaftaran Anda ditolak. Alasan: '.$user->rejection_reason
                : 'Pendaftaran Anda ditolak.',
            'approved' => $user->needsChildData()
                ? 'Login berhasil. Lengkapi data anak Anda terlebih dahulu.'
                : 'Login berhasil',
            default => 'Login berhasil',
        };
    }

    /**
     * Menentukan role baru dari server.
     *
     * @return string|null 'ibu' | 'kader', atau null bila permintaan kader ditolak.
     */
    private function resolveRegistrationRole(Request $request): ?string
    {
        if ($request->input('role') !== 'kader') {
            return 'ibu';
        }

        $expected = config('posyandu.kader_registration_code');

        if (! is_string($expected) || $expected === '') {
            return null;
        }

        $given = (string) ($request->input('kader_code') ?? '');

        return hash_equals($expected, $given) ? 'kader' : null;
    }

    /**
     * Pesan error yang tepat untuk setiap kode kader ditolak.
     */
    private function kaderCodeErrors(Request $request): array
    {
        $expected = config('posyandu.kader_registration_code');

        if (! is_string($expected) || $expected === '') {
            return [
                'kader_code' => [
                    'Pendaftaran akun kader sedang dinonaktifkan. '
                    .'Akun kader dibuat oleh petugas posyandu, hubungi koordinator.',
                ],
            ];
        }

        if ((string) ($request->input('kader_code') ?? '') === '') {
            return ['kader_code' => ['Kode pendaftaran kader wajib diisi.']];
        }

        return ['kader_code' => ['Kode pendaftaran kader tidak cocok.']];
    }

    /**
     * @param  array<string, mixed>  $data
     * @return array<string, mixed>
     */
    private function profileAttributes(array $data): array
    {
        $attributes = [];

        foreach ([
            'no_kk', 'phone_number', 'place_of_birth', 'date_of_birth', 'gender',
            'blood_type', 'address', 'rt_rw', 'education', 'occupation',
        ] as $field) {
            if (array_key_exists($field, $data)) {
                $attributes[$field] = $data[$field];
            }
        }

        return $attributes;
    }

    /**
     * Membungkus validation errors dalam JSON Envelope (Aturan #8).
     */
    private function validationFailed(array $errors): JsonResponse
    {
        return response()->json([
            'success' => false,
            'message' => 'Validasi gagal.',
            'errors' => $errors,
        ], 422);
    }
}
