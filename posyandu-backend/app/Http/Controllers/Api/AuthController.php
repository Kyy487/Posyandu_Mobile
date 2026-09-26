<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Validator; // Wajib di-import

class AuthController extends Controller
{
    // Fungsi Pendaftaran Akun (Register)
    public function register(Request $request)
    {
        // 1. Gunakan Validator::make agar kita bisa mengontrol format JSON saat error
        $validator = Validator::make($request->all(), [
            'nik' => 'required|string|size:16|unique:users,nik',
            'name' => 'required|string|max:255',
            'password' => 'required|string|min:8', // Tambahkan 'confirmed' jika Flutter mengirim password_confirmation
            'role' => 'required|in:ibu,kader',
            'phone_number' => 'nullable|string|max:15',
        ]);

        // 2. Return error dengan format JSON Envelope yang ketat
        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validasi registrasi gagal.',
                'errors' => $validator->errors()
            ], 422);
        }

        $user = User::create([
            'nik' => $request->nik,
            'name' => $request->name,
            'password' => Hash::make($request->password),
            'role' => $request->role,
            'phone_number' => $request->phone_number,
        ]);

        $token = $user->createToken('posyandu-mobile-token')->plainTextToken;

        return response()->json([
            'success' => true,
            'message' => 'Registrasi berhasil',
            'data' => [
                'user' => $user,
                'token' => $token
            ]
        ], 201);
    }

    // Fungsi Masuk (Login)
    public function login(Request $request)
    {
        // 1. Validasi manual
        $validator = Validator::make($request->all(), [
            'nik' => 'required|string',
            'password' => 'required|string',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validasi login gagal.',
                'errors' => $validator->errors()
            ], 422);
        }

        $user = User::where('nik', $request->nik)->first();

        // 2. Cek kecocokan password & NIK dengan format JSON Envelope
        if (!$user || !Hash::check($request->password, $user->password)) {
            return response()->json([
                'success' => false,
                'message' => 'Kredensial yang diberikan tidak cocok dengan data kami.',
                'errors' => null
            ], 401); // 401 Unauthorized
        }

        // Hapus token lama agar tidak menumpuk (opsional, untuk keamanan)
        $user->tokens()->delete();

        // Buat token baru
        $token = $user->createToken('posyandu-mobile-token')->plainTextToken;

        return response()->json([
            'success' => true,
            'message' => 'Login berhasil',
            'data' => [
                'user' => $user,
                'token' => $token
            ]
        ], 200);
    }

    // Fungsi Keluar (Logout)
    public function logout(Request $request)
    {
        // Cabut (hapus) token yang sedang digunakan untuk request ini
        $request->user()->currentAccessToken()->delete();

        return response()->json([
            'success' => true,
            'message' => 'Berhasil logout.',
            'data' => null
        ], 200);
    }
}
