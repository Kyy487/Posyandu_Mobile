<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    /**
     * Pendaftaran Akun (Register)
     *
     * Aturan #2/#3: role TIDAK PERNAH diambil dari input pengguna. Server yang
     * memutuskan. Tanpa ini, siapa pun bisa mendaftar sebagai `kader` dan
     * langsung mendapat akses ke seluruh data anak.
     *
     * - Tanpa `kader_code`  -> akun `ibu` (kategori utama masyarakat).
     * - Dengan `kader_code` yang cocok -> akun `kader`.
     * - `KADER_REGISTRATION_CODE` kosong di .env -> pendaftaran kader dimatikan (403).
     */
    public function register(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'nik' => ['required', 'string', 'size:16', Rule::unique('users', 'nik')],
            'name' => ['required', 'string', 'max:255'],
            'password' => ['required', 'string', 'min:8', 'confirmed'],
            'phone_number' => ['nullable', 'string', 'max:15'],

            // `role` tetap diterima (opsional) sebagai PERMINTAAN, bukan perintah.
            // Kalau ada, ia hanya boleh bernilai 'kader' — nilai tetap dihitung
            // ulang oleh server di bawah ini.
            'role' => ['nullable', 'string', Rule::in(['kader'])],
            'kader_code' => ['nullable', 'string', 'max:100'],
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

            $user = User::create([
                'nik' => $request->nik,
                'name' => $request->name,
                'password' => Hash::make($request->password),
                'role' => $role,
                'phone_number' => $request->phone_number,
            ]);

            $token = $user->createToken('posyandu-mobile-token')->plainTextToken;

            return response()->json([
                'success' => true,
                'message' => $role === 'kader'
                    ? 'Registrasi kader berhasil.'
                    : 'Registrasi berhasil.',
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
            $user = User::where('nik', $request->nik)->first();

            if (! $user || ! Hash::check($request->password, $user->password)) {
                // Satu pesan untuk "tidak ada" dan "salah password" supaya
                // NIK terdaftar atau tidak tidak bisa ditebak.
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
