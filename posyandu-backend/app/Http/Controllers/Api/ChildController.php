<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Child;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;

class ChildController extends Controller
{
    // Mengambil daftar balita
    public function index(Request $request)
    {
        $user = $request->user();

        // Relasi `mother` dimuat untuk Ibu maupun Kader. Mobile membaca
        // `mother.name` (dan NIK) di child.dart; tanpa ini dashboard Ibu
        // menampilkan "-" untuk nama ibu.
        $query = Child::with('mother:id,name,nik');

        // Ibu hanya melihat anaknya sendiri. Kader melihat seluruh data.
        if ($user->role === 'ibu') {
            $query->where('user_id', $user->id);
        }

        $children = $query->get();

        return response()->json([
            'success' => true,
            'message' => 'Data balita berhasil diambil.',
            'data' => $children
        ], 200);
    }

    /**
     * Menambahkan data balita baru.
     *
     * Kontrak tunggal untuk Ibu maupun Kader:
     * - Ibu  : anak otomatis milik Ibu yang login, tidak perlu menyebut ibu.
     * - Kader: wajib menyebut ibu lewat `ibu_nik` (NIK, sesuai KK) atau
     *          `user_id` (UUID). Keduanya boleh dikirim, asal menunjuk
     *          user yang sama.
     */
    public function store(Request $request)
    {
        $user = $request->user();
        $isKader = $user->role === 'kader';

        try {
            $validated = $request->validate([
                'nik' => 'nullable|string|size:16|unique:children,nik',
                'name' => 'required|string|max:255',
                'date_of_birth' => 'required|date',
                'gender' => 'required|in:L,P',
                'birth_weight' => 'nullable|numeric|min:0',
                'birth_height' => 'nullable|numeric|min:0',
                'user_id' => [
                    $isKader ? 'required_without:ibu_nik' : 'nullable',
                    'exists:users,id',
                ],
                'ibu_nik' => [
                    $isKader ? 'required_without:user_id' : 'nullable',
                    'string',
                    'size:16',
                ],
            ]);

            // --- Tentukan ibu pemilik anak -------------------------------
            if (!$isKader) {
                // Ibu tidak pernah bisa menunjuk ibu lain.
                $mother = $user;
            } else {
                $byId = !empty($validated['user_id'])
                    ? User::find($validated['user_id'])
                    : null;

                $byNik = null;
                if (!empty($validated['ibu_nik'])) {
                    $byNik = User::where('nik', $validated['ibu_nik'])->first();

                    if (!$byNik) {
                        return response()->json([
                            'success' => false,
                            'message' => 'NIK Ibu tidak ditemukan di sistem. Pastikan akun Ibu sudah terdaftar.',
                            'errors' => ['ibu_nik' => ['NIK Ibu belum terdaftar.']],
                        ], 404);
                    }
                }

                // Dua-duanya dikirim harus menunjuk user yang sama.
                if ($byId && $byNik && $byId->id !== $byNik->id) {
                    return response()->json([
                        'success' => false,
                        'message' => 'user_id dan ibu_nik harus menunjuk Ibu yang sama.',
                        'errors' => ['user_id' => ['user_id dan ibu_nik tidak sesuai.']],
                    ], 422);
                }

                $mother = $byNik ?? $byId;
            }

            if (!$mother) {
                return response()->json([
                    'success' => false,
                    'message' => 'Ibu pemilik anak tidak ditemukan.',
                    'errors' => ['user_id' => ['Data ibu wajib diisi.']],
                ], 404);
            }

            if ($mother->role !== 'ibu') {
                return response()->json([
                    'success' => false,
                    'message' => 'Data anak hanya dapat ditambahkan pada akun dengan role ibu.',
                    'errors' => ['user_id' => ['User yang dipilih bukan role ibu.']],
                ], 422);
            }

            // --- Simpan (UUID dibuat otomatis oleh trait HasUuids) -------
            $child = Child::create([
                'user_id' => $mother->id,
                'nik' => $validated['nik'] ?? null,
                'name' => $validated['name'],
                'date_of_birth' => $validated['date_of_birth'],
                'gender' => $validated['gender'],
                'birth_weight' => $validated['birth_weight'] ?? null,
                'birth_height' => $validated['birth_height'] ?? null,
            ]);

            return response()->json([
                'success' => true,
                'message' => 'Data balita berhasil ditambahkan.',
                'data' => $child->load('mother:id,name,nik'),
            ], 201);

        } catch (ValidationException $e) {
            return response()->json([
                'success' => false,
                'message' => 'Validasi gagal.',
                'errors' => $e->errors(),
            ], 422);
        } catch (\Throwable $e) {
            // Pesan exception asli hanya masuk log, tidak dikirim ke client.
            Log::error('Gagal menambah data balita: ' . $e->getMessage(), [
                'user_id' => $user->id,
                'role' => $user->role,
                'exception' => $e,
            ]);

            return response()->json([
                'success' => false,
                'message' => 'Terjadi kesalahan server. Silakan coba lagi.',
                'errors' => null,
            ], 500);
        }
    }

    // Melihat detail satu anak
    public function show(Request $request, $id)
    {
        $child = Child::with('mother:id,name,nik')->find($id);

        if (!$child) {
            return response()->json([
                'success' => false,
                'message' => 'Data balita tidak ditemukan.',
                'errors' => null
            ], 404);
        }

        // Otorisasi: Kader boleh melihat semua anak, Ibu hanya boleh melihat anaknya sendiri.
        if ($request->user()->role !== 'kader' && $child->user_id !== $request->user()->id) {
            return response()->json([
                'success' => false,
                'message' => 'Akses ditolak. Anda tidak berhak melihat data anak ini.',
                'errors' => null
            ], 403);
        }

        return response()->json([
            'success' => true,
            'message' => 'Detail balita berhasil diambil.',
            'data' => $child
        ], 200);
    }
    public function indexKader()
    {
        try {
            // Memuat relasi mother agar nama ibu ikut terkirim (dibaca mobile di child.dart).
            // Paginasi/filter bisa ditambahkan nanti tanpa mengubah bentuk respons.
            $children = Child::with('mother:id,name,nik')->get();

            // Format baku JSON Envelope wajib
            return response()->json([
                'success' => true,
                'message' => 'Berhasil mengambil daftar anak',
                'data' => $children
            ], 200);

        } catch (\Throwable $e) {
            Log::error('Gagal mengambil daftar anak: ' . $e->getMessage(), [
                'exception' => $e,
            ]);

            return response()->json([
                'success' => false,
                'message' => 'Terjadi kesalahan server. Silakan coba lagi.',
                'errors' => null
            ], 500);
        }
    }
}
