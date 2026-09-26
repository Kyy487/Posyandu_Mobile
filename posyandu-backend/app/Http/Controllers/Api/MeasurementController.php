<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Measurement;
use App\Models\Child;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class MeasurementController extends Controller
{
    /**
     * Memetakan pengecualian dari trigger PostgreSQL menjadi 422.
     *
     * Trigger memakai `RAISE EXCEPTION` (SQLSTATE P0001) untuk aturan bisnis,
     * misalnya tanggal penimbangan lebih awal dari tanggal lahir anak. Ini
     * kesalahan input pengguna, bukan kegagalan server.
     */
    private function isTriggerRuleViolation(\Throwable $e): bool
    {
        return $e instanceof \Illuminate\Database\QueryException
            && isset($e->errorInfo[0])
            && $e->errorInfo[0] === 'P0001';
    }

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

        } catch (ValidationException $e) {
            return response()->json([
                'success' => false,
                'message' => 'Validasi gagal. Periksa kembali angka yang diinputkan.',
                'errors' => $e->errors()
            ], 422);
        } catch (\Throwable $e) {
            // Aturan bisnis dari trigger (mis. tanggal ukur sebelum tanggal lahir)
            // adalah kesalahan input, bukan kegagalan server.
            if ($this->isTriggerRuleViolation($e)) {
                return response()->json([
                    'success' => false,
                    'message' => $this->cleanTriggerMessage($e->getMessage()),
                    'errors' => ['measurement_date' => [$this->cleanTriggerMessage($e->getMessage())]],
                ], 422);
            }

            // Pesan exception asli hanya masuk log, tidak dikirim ke client.
            Log::error('Gagal menyimpan penimbangan: ' . $e->getMessage(), [
                'user_id' => $request->user()?->id,
                'exception' => $e,
            ]);

            return response()->json([
                'success' => false,
                'message' => 'Terjadi kesalahan server. Silakan coba lagi.',
                'errors' => null
            ], 500);
        }
    }

    /**
     * Membersihkan pesan trigger agar tidak membocorkan detail internal
     * (nama tabel, SQL, baris PostgreSQL).
     */
    private function cleanTriggerMessage(string $raw): string
    {
        // Buang prefix driver: "ERROR:  <pesan> (Connection: pgsql, ... SQL: ...)"
        if (preg_match('/ERROR:\s*(.+?)(?:\s*\((?:Connection|SQL|Hint):|$)/s', $raw, $m)) {
            $message = trim($m[1]);
            // Ganti nama kolom/tabel internal dengan istilah yang dipahami pengguna.
            $message = str_replace(['date_of_birth', 'children'], ['tanggal lahir anak', 'data anak'], $message);
            return rtrim($message, '.') . '.';
        }

        return 'Data penimbangan tidak valid.';
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
                    'errors' => ['child_id' => ['Parameter child_id wajib diisi.']]
                ], 400);
            }

            // child_id kolomnya bertipe UUID; string sembarang akan membuat
            // PostgreSQL melempar error dan endpoint membalas 500.
            if (!Str::isUuid($childId)) {
                return response()->json([
                    'success' => false,
                    'message' => 'Parameter child_id tidak valid.',
                    'errors' => ['child_id' => ['child_id harus berupa UUID.']]
                ], 422);
            }

            if (!Child::where('id', $childId)->exists()) {
                return response()->json([
                    'success' => false,
                    'message' => 'Data balita tidak ditemukan.',
                    'errors' => null
                ], 404);
            }

            // Ambil data penimbangan diurutkan dari yang terbaru
            $measurements = Measurement::where('child_id', $childId)
                ->orderBy('measurement_date', 'desc')
                ->orderBy('created_at', 'desc')
                ->get();

            return response()->json([
                'success' => true,
                'message' => 'Berhasil mengambil riwayat penimbangan.',
                'data' => $measurements
            ], 200);

        } catch (\Throwable $e) {
            Log::error('Gagal mengambil riwayat penimbangan: ' . $e->getMessage(), [
                'exception' => $e,
            ]);

            return response()->json([
                'success' => false,
                'message' => 'Terjadi kesalahan server. Silakan coba lagi.',
                'errors' => null
            ], 500);
        }
    }

    // Fungsi untuk menghapus riwayat penimbangan
    public function destroy($id)
    {
        try {
            // id kolomnya bertipe UUID; validasi dulu agar URL rusak membalas 404.
            if (!is_string($id) || !Str::isUuid($id)) {
                return response()->json([
                    'success' => false,
                    'message' => 'Data penimbangan tidak ditemukan.',
                    'errors' => null
                ], 404);
            }

            $measurement = Measurement::find($id);

            if (!$measurement) {
                return response()->json([
                    'success' => false,
                    'message' => 'Data penimbangan tidak ditemukan.',
                    'errors' => null
                ], 404);
            }

            $measurement->delete();

            return response()->json([
                'success' => true,
                'message' => 'Riwayat penimbangan berhasil dihapus.',
                'data' => null
            ], 200);

        } catch (\Throwable $e) {
            Log::error('Gagal menghapus penimbangan: ' . $e->getMessage(), [
                'measurement_id' => $id,
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
