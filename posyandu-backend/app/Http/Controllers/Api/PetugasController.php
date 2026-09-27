<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Support\Facades\Log;

/**
 * Daftar petugas posyandu.
 *
 * Endpoint ini terbuka untuk Ibu maupun Kader, jadi HANYA mengirim field yang
 * aman untuk dibagikan ke orang tua: `id`, `name`, `jabatan`, dan nomor HP.
 * `nik` sengaja tidak ikut, karena NIK adalah data pribadi yang tidak ada
 * urusannya diketahui orang tua yang bukan kerabat. `id` tetap dikirim karena
 * mobile memakainya untuk menyinkronkan penugasan lewat pivot agenda.
 *
 * Kolom yang dibaca di query (`select`) juga berfungsi sebagai pengaman kedua:
 * bila suatu saat model `User` menambah kolom sensitif baru, field itu tidak
 * akan bocor tanpa sengaja mengubah query ini.
 */
class PetugasController extends Controller
{
    public function index()
    {
        try {
            $petugas = User::query()
                ->where('role', 'kader')
                ->orderBy('name')
                // `id` dipakai mobile sebagai identifier saat menyinkronkan
                // daftar petugas di pivot agenda, jadi tetap dikirim. NIK tidak.
                ->get(['id', 'name', 'jabatan', 'phone_number']);

            return response()->json([
                'success' => true,
                'message' => 'Daftar petugas posyandu berhasil diambil.',
                'data' => $petugas,
            ], 200);

        } catch (\Throwable $e) {
            Log::error('Gagal mengambil daftar petugas: '.$e->getMessage(), [
                'exception' => $e,
            ]);

            return response()->json([
                'success' => false,
                'message' => 'Terjadi kesalahan server. Silakan coba lagi.',
                'errors' => null,
            ], 500);
        }
    }
}
