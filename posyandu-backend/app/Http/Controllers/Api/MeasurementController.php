<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Measurement;
use App\Models\Child;
use Illuminate\Http\Request;

class MeasurementController extends Controller
{
    // Fungsi untuk Kader menginput data penimbangan baru
    public function store(Request $request)
    {
        try {
            // 1. Validasi Input
            $validated = $request->validate([
                'child_id' => 'required|uuid|exists:children,id',
                'measurement_date' => 'required|date|before_or_equal:today',
                'weight_kg' => 'required|numeric|min:0.5|max:50',
                'height_cm' => 'required|numeric|min:20|max:150',
                'head_circumference_cm' => 'nullable|numeric|min:20|max:60',
            ]);

            // Pastikan anak yang dituju memang ada
            $child = Child::findOrFail($validated['child_id']);

            // 2. Simpan Data Penimbangan
            // Kader yang sedang login otomatis menjadi pencatat
            $measurement = Measurement::create([
                'child_id' => $child->id,
                'kader_id' => $request->user()->id,
                'measurement_date' => $validated['measurement_date'],
                'weight_kg' => $validated['weight_kg'],
                'height_cm' => $validated['height_cm'],
                'head_circumference_cm' => $validated['head_circumference_cm'] ?? null,
                // Catatan: age_in_months, z_score_wfa, dan status_gizi tidak diisi dari sini.
                // Sesuai Aturan, kolom-kolom ini akan diisi otomatis oleh Database Trigger PostgreSQL!
            ]);

            // 2b. Muat ulang dari database agar age_in_months, z_score_wfa, dan status_gizi
            //     yang dihitung oleh trigger ikut terbawa pada response API.
            $measurement->refresh();

            // 3. Return sukses dengan JSON Envelope
            return response()->json([
                'success' => true,
                'message' => 'Data penimbangan (e-KMS) berhasil dicatat.',
                'data' => $measurement
            ], 201);

        } catch (\Illuminate\Validation\ValidationException $e) {
            return response()->json([
                'success' => false,
                'message' => 'Validasi gagal. Periksa kembali angka yang diinputkan.',
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
    // Fungsi untuk mengambil riwayat penimbangan berdasarkan anak
    public function index(Request $request)
    {
        try {
            $childId = $request->query('child_id');

            if (!$childId) {
                return response()->json([
                    'success' => false,
                    'message' => 'Parameter child_id diperlukan.',
                    'data' => []
                ], 400);
            }

            // Ambil data penimbangan diurutkan dari yang terbaru
            $measurements = Measurement::where('child_id', $childId)
                ->orderBy('measurement_date', 'desc')
                ->get();

            return response()->json([
                'success' => true,
                'message' => 'Berhasil mengambil riwayat penimbangan.',
                'data' => $measurements
            ], 200);

        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Terjadi kesalahan server: ' . $e->getMessage(),
                'data' => []
            ], 500);
        }
    }
    // Fungsi untuk menghapus riwayat penimbangan
    public function destroy($id)
    {
        try {
            $measurement = Measurement::find($id);

            if (!$measurement) {
                return response()->json([
                    'success' => false,
                    'message' => 'Data penimbangan tidak ditemukan.'
                ], 404);
            }

            $measurement->delete();

            return response()->json([
                'success' => true,
                'message' => 'Riwayat penimbangan berhasil dihapus.'
            ], 200);

        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Gagal menghapus data: ' . $e->getMessage()
            ], 500);
        }
    }
}
