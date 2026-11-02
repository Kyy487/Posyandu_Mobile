<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Models\UserVerification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    /**
     * Pendaftaran Akun (Register)
     *
     * Aturan #2/#3: role TIDAK PERNAH diambil dari input pengguna. Server yang
     * memutuskan.
     *
     * - Tanpa `kader_code`  -> akun `ibu` (kategori utama masyarakat) dengan status pending (perlu persetujuan kader)
     * - Dengan `kader_code` yang cocok -> akun `kader` (langsung aktif)
     * - `KADER_REGISTRATION_CODE` kosong di .env -> pendaftaran kader dimatikan (403).
     */
    public function register(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'nik' => ['required', 'string', 'size:16', Rule::unique('users', 'nik')],
            'name' => ['required', 'string', 'max:255'],
            'password' => ['required', 'string', 'min:8', 'confirmed'],
            'phone_number' => ['required', 'string', 'max:16', 'regex:/^[0-9+\-\s]+$/'],

            // Data profil untuk ibu
            'place_of_birth' => ['required', 'string', 'max:100'],
            'date_of_birth' => ['required', 'date'],
            'gender' => ['required', Rule::in(['L', 'P'])],
            'address' => ['required', 'string'],

            // `role` tetap diterima (opsional) sebagai PERMINTAAN, bukan perintah.
            'role' => ['nullable', 'string', Rule::in(['kader'])],
            'kader_code' => ['nullable', 'string', 'max:100'],

            // Bukti verifikasi untuk calon ibu
            'verification_file' => ['required', 'file', 'mimes:jpg,jpeg,png,pdf', 'max:5120'],
            'verification_type' => ['required', Rule::in(['self_photo', 'kk', 'other'])],
        ]);

        if ($validator->fails()) {
            return $this->validationFailed($validator->errors()->toArray());
        }

        try {
            $role = $this->resolveRegistrationRole($request);

            if ($role === null) {
                return response()->json([
                    'success' => false,
                    'message' => 'Pendaftaran akun kader ditolak.',
                    'errors' => $this->kaderCodeErrors($request),
                ], 403);
            }

            $userData = [
                'nik' => $request->nik,
                'nik_hash' => hash('sha256', $request->nik),
                'name' => $request->name,
                'password' => Hash::make($request->password),
                'role' => $role,
                'phone_number' => $request->phone_number,
                'place_of_birth' => $request->place_of_birth,
                'date_of_birth' => $request->date_of_birth,
                'gender' => $request->gender,
                'address' => $request->address,
            ];

            if ($role === 'ibu') {
                $userData['status'] = 'pending';
            } else {
                $userData['status'] = 'active';
                $userData['verified_at'] = now();
            }

            $user = User::create($userData);

            // Upload bukti verifikasi jika ada (untuk ibu)
            if ($role === 'ibu') {
                if ($request->hasFile('verification_file')) {
                    $file = $request->file('verification_file');
                    $path = $file->store('verifications', 'public');
                    UserVerification::create([
                        'user_id' => $user->id,
                        'type' => $request->input('verification_type') ?: 'other',
                        'file_path' => $path,
                        'file_name' => $file->getClientOriginalName(),
                        'mime_type' => $file->getMimeType(),
                        'uploaded_at' => now(),
                    ]);
                }
            }

            if ($role === 'ibu') {
                return response()->json([
                    'success' => true,
                    'message' => 'Pendaftaran berhasil. Akun Anda menunggu persetujuan dari Kader Posyandu.',
                    'data' => [
                        'user' => $user->makeHidden(['nik', 'nik_hash', 'password']),
                        'status' => $user->status,
                    ],
                ], 201);
            }

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
     * Menentukan role baru dari server.
     *
     * @return string|null 'ibu' | 'kader', atau null bila permintaan kader ditolak.
     */
    private function resolveRegistrationRole(Request $request): ?string
    {
        // Default dan satu-satunya role yang boleh didaftarkan sendiri.
        if ($request->input('role') !== 'kader') {
            return 'ibu';
        }

        $expected = config('posyandu.kader_registration_code');

        // Kode belum diisi di .env -> pendaftaran kader sengaja dimatikan.
        if (! is_string($expected) || $expected === '') {
            return null;
        }

        $given = (string) ($request->input('kader_code') ?? '');

        // hash_equals mencegah perbandingan bocor waktu (timing attack).
        return hash_equals($expected, $given) ? 'kader' : null;
    }

    /**
     * Pesan error yang tepat untuk EACH kode kader ditolak.
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
     * Memeriksa NIK + password.
     */
    public function login(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            // `size:16` ikut dipakai supaya konsisten dengan register. Tanpa ini
            // Format NIK harus sama seperti saat pendaftaran.
            // NIK ngawur ditolak di sini, bukan di query database.
            'nik' => ['required', 'string', 'size:16'],
            'password' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return $this->validationFailed($validator->errors()->toArray());
        }

        try {
            $user = User::where('nik_hash', hash('sha256', $request->nik))->first();

            if (! $user || ! Hash::check($request->password, $user->password)) {
                // Satu pesan untuk "tidak ada" dan "salah password" supaya
                // NIK terdaftar atau tidak tidak bisa ditebak.
                return response()->json([
                    'success' => false,
                    'message' => 'Kredensial yang diberikan tidak cocok dengan data kami.',
                    'errors' => null,
                ], 401);
            }

            if ($user->role === 'ibu') {
                if ($user->status === 'rejected') {
                    $msg = 'Pendaftaran Anda ditolak.';
                    if ($user->rejection_reason) {
                        $msg .= ' Alasan: '.$user->rejection_reason;
                    }
                    return response()->json([
                        'success' => false,
                        'message' => $msg,
                        'errors' => null,
                    ], 403);
                }
                if (isset($user->status) && $user->status === 'pending') {
                    return response()->json([
                        'success' => false,
                        'message' => 'Akun Anda masih menunggu persetujuan dari Kader Posyandu.',
                        'errors' => null,
                    ], 403);
                }
            }

            // Hapus token lama agar tidak menumpuk.
            $user->tokens()->delete();

            $token = $user->createToken('posyandu-mobile-token')->plainTextToken;

            return response()->json([
                'success' => true,
                'message' => 'Login berhasil',
                'data' => [
                    'user' => $user,
                    'token' => $token,
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
     * Keluar (Logout) — mencabut token yang sedang dipakai.
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
