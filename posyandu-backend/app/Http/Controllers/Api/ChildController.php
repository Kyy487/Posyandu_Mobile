<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Child;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Support\Facades\Validator;

class ChildController extends Controller
{
    // Mengambil daftar balita
    public function index(Request $request)
    {
        $user = $request->user();

        // Jika Ibu, hanya ambil anaknya sendiri. Jika Kader, ambil semua anak beserta data ibunya.
        if ($user->role === 'ibu') {
            $children = Child::where('user_id', $user->id)->get();
        } else {
            $children = Child::with('mother:id,name,nik')->get();
        }

        return response()->json([
            'success' => true,
            'message' => 'Data balita berhasil diambil.',
            'data' => $children
        ], 200);
    }

    // Menambahkan data balita baru
    public function store(Request $request)
    {
        $user = $request->user();

        $validator = Validator::make($request->all(), [
            'nik' => 'nullable|string|size:16|unique:children,nik',
            'name' => 'required|string|max:255',
            'date_of_birth' => 'required|date',
            'gender' => 'required|in:L,P',
            'birth_weight' => 'nullable|numeric|min:0',
            'birth_height' => 'nullable|numeric|min:0',
            // Kader wajib mengirim user_id (Ibu), sedangkan Ibu otomatis memakai ID-nya sendiri
            'user_id' => $user->role === 'kader' ? 'required|exists:users,id' : 'nullable'
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validasi gagal.',
                'errors' => $validator->errors()
            ], 422);
        }

        // Tentukan siapa ibu dari anak ini
        $motherId = $user->role === 'ibu' ? $user->id : $request->user_id;

        $child = Child::create([
            'user_id' => $motherId,
            'nik' => $request->nik,
            'name' => $request->name,
            'date_of_birth' => $request->date_of_birth,
            'gender' => $request->gender,
            'birth_weight' => $request->birth_weight,
            'birth_height' => $request->birth_height,
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Data balita berhasil ditambahkan.',
            'data' => $child
        ], 201);
    }

    // Melihat detail satu anak
    public function show($id)
    {
        $child = Child::with('mother:id,name')->find($id);

        if (!$child) {
            return response()->json([
                'success' => false,
                'message' => 'Data balita tidak ditemukan.',
                'errors' => null
            ], 404);
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
            // Mengambil semua data anak (bisa dimodifikasi dengan paginasi/filter nanti)
            $children = Child::all();

            // Format baku JSON Envelope wajib
            return response()->json([
                'success' => true,
                'message' => 'Berhasil mengambil daftar anak',
                'data' => $children
            ], 200);

        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Terjadi kesalahan server: ' . $e->getMessage(),
                'errors' => null
            ], 500);
        }
    }
public function storeKader(Request $request)
    {
        try {
            // 1. Validasi Input
            $validated = $request->validate([
                'nik' => 'required|string|size:16|unique:children,nik',
                'name' => 'required|string|max:255',
                'date_of_birth' => 'required|date',
                'gender' => 'required|in:L,P',
                'birth_weight' => 'required|numeric',
                'birth_height' => 'required|numeric',
                'ibu_nik' => 'required|string|size:16'
            ]);

            // 2. CARI DATA IBU BERDASARKAN NIK
            // Kita cari user yang memiliki NIK sesuai inputan 'ibu_nik'
            $ibu = \App\Models\User::where('nik', $validated['ibu_nik'])->first();

            // Jika NIK Ibu belum terdaftar di sistem, tolak penyimpanan
            if (!$ibu) {
                return response()->json([
                    'success' => false,
                    'message' => 'NIK Ibu tidak ditemukan di sistem. Pastikan akun Ibu sudah terdaftar.',
                    'errors' => ['ibu_nik' => ['NIK Ibu belum terdaftar.']]
                ], 404);
            }

            // 3. Simpan ke Database
            $child = new Child();
            $child->id = (string) \Illuminate\Support\Str::uuid();

            // MASUKKAN UUID IBU KE KOLOM user_id
            $child->user_id = $ibu->id;

            $child->nik = $validated['nik'];
            $child->name = $validated['name'];
            $child->date_of_birth = $validated['date_of_birth'];
            $child->gender = $validated['gender'];
            $child->birth_weight = $validated['birth_weight'];
            $child->birth_height = $validated['birth_height'];
            $child->save();

            // 4. Return respons JSON Envelope
            return response()->json([
                'success' => true,
                'message' => 'Data anak berhasil ditambahkan.',
                'data' => $child
            ], 201);

        } catch (\Illuminate\Validation\ValidationException $e) {
            return response()->json([
                'success' => false,
                'message' => 'Data tidak valid. Periksa kembali isian Anda.',
                'errors' => $e->errors()
            ], 422);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Terjadi kesalahan server: ' . $e->getMessage(),
                'errors' => null
            ], 500);
        }
    }
}
