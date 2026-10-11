<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Child;
use App\Models\Visit;
use App\Services\VisitService;
use Illuminate\Database\QueryException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Kunjungan layanan anak (P0-1).
 *
 * Endpoint yang tersedia di sini:
 *  - `POST   /visits`        buat kunjungan (Kader)
 *  - `GET    /visits/{id}`   detail kunjungan (pemilik anak / Kader)
 *  - `PATCH  /visits/{id}`   koreksi kunjungan (Kader)
 *
 * Daftar kunjungan satu anak (`GET /children/{id}/visits`) tinggal di
 * `ChildController@visits`, sama seperti `timeline` dan `growth`. Alasannya:
 * otorisasi "Ibu hanya anaknya sendiri" sudah ada di
 * `ChildController::findChildForUser()`, dan menyalinnya ke sini akan
 * menghasilkan dua versi aturan yang pasti kelak berbeda
 * (lihat `.ai/rules/kontrak-timeline.md`).
 *
 * Kunjungan dibuat EKSPLISIT lewat `POST`, bukan otomatis saat data pertama
 * dicatat. `GET` tetap idempoten (docs/RANCANGAN_VISIT.md bagian 5).
 */
class VisitController extends Controller
{
    /**
     * Membuat kunjungan baru.
     *
     * Kader yang login otomatis menjadi pemegang kunjungan; klien tidak
     * mengirim `kader_id`.
     */
    public function store(Request $request, VisitService $visits)
    {
        $user = $request->user();

        try {
            $validated = $request->validate([
                'child_id' => ['required', 'uuid', Rule::exists('children', 'id')],
                'schedule_id' => ['nullable', 'uuid', Rule::exists('posyandu_schedules', 'id')],
                'visit_date' => ['required', 'date_format:Y-m-d', 'before_or_equal:today'],
                'visit_type' => ['required', 'string', Rule::in(Visit::VISIT_TYPES)],
                'anamnesis' => ['nullable', 'string', 'max:2000'],
                'catatan_kader' => ['nullable', 'string', 'max:2000'],
            ]);

            $child = Child::find($validated['child_id']);

            if (! $child) {
                return $this->childNotFound();
            }

            $visit = $visits->create($child, $user, $validated);

            return response()->json([
                'success' => true,
                'message' => 'Kunjungan berhasil dibuat.',
                'data' => $visits->present($visit->fresh()->load('kader:id,name')),
            ], 201);

        } catch (ValidationException $e) {
            return $this->validationError($e);
        } catch (QueryException $e) {
            // 23514 = check_violation: `visit_type` yang lolos validasi PHP tapi
            // ditolak CHECK constraint database.
            if ($e->getCode() === '23514') {
                return response()->json([
                    'success' => false,
                    'message' => 'Tipe kunjungan tidak valid.',
                    'errors' => ['visit_type' => ['Tipe kunjungan tidak dikenal.']],
                ], 422);
            }

            Log::error('Gagal membuat kunjungan: '.$e->getMessage(), [
                'user_id' => $user->id,
                'exception' => $e,
            ]);

            return $this->serverError();
        } catch (\Throwable $e) {
            Log::error('Gagal membuat kunjungan: '.$e->getMessage(), [
                'user_id' => $user->id,
                'exception' => $e,
            ]);

            return $this->serverError();
        }
    }

    /**
     * Detail satu kunjungan, termasuk penimbangan, imunisasi, dan keluhan yang
     * terhubung.
     *
     * Ibu hanya boleh membuka kunjungan anaknya sendiri; Kader boleh semua.
     */
    public function show(Request $request, string $id, VisitService $visits)
    {
        $visit = $this->findVisit($id);

        if (! $visit instanceof Visit) {
            return $visit;
        }

        $akses = $this->assertCanView($visit, $request->user());

        if ($akses !== null) {
            return $akses;
        }

        return response()->json([
            'success' => true,
            'message' => 'Detail kunjungan berhasil diambil.',
            'data' => $visits->detail($visit),
        ], 200);
    }

    /**
     * Koreksi satu kunjungan (partial update).
     *
     * Hanya Kader (dijaga middleware role di route). `child_id` sengaja tidak
     * bisa dipindah: kunjungan yang salah anak dibatalkan lalu dibuat ulang.
     */
    public function update(Request $request, string $id, VisitService $visits)
    {
        $visit = $this->findVisit($id);

        if (! $visit instanceof Visit) {
            return $visit;
        }

        try {
            $validated = $request->validate([
                'schedule_id' => ['sometimes', 'nullable', 'uuid', Rule::exists('posyandu_schedules', 'id')],
                'visit_date' => ['sometimes', 'required', 'date_format:Y-m-d', 'before_or_equal:today'],
                'visit_type' => ['sometimes', 'required', 'string', Rule::in(Visit::VISIT_TYPES)],
                'anamnesis' => ['sometimes', 'nullable', 'string', 'max:2000'],
                'catatan_kader' => ['sometimes', 'nullable', 'string', 'max:2000'],
            ]);

            if ($validated === []) {
                return response()->json([
                    'success' => false,
                    'message' => 'Tidak ada data yang diperbarui.',
                    'errors' => ['body' => ['Kirim minimal satu field untuk diperbarui.']],
                ], 422);
            }

            $visit = $visits->update($visit, $validated);

            return response()->json([
                'success' => true,
                'message' => 'Kunjungan berhasil diperbarui.',
                'data' => $visits->present($visit->fresh()->load('kader:id,name')),
            ], 200);

        } catch (ValidationException $e) {
            return $this->validationError($e);
        } catch (QueryException $e) {
            if ($e->getCode() === '23514') {
                return response()->json([
                    'success' => false,
                    'message' => 'Tipe kunjungan tidak valid.',
                    'errors' => ['visit_type' => ['Tipe kunjungan tidak dikenal.']],
                ], 422);
            }

            Log::error('Gagal memperbarui kunjungan: '.$e->getMessage(), [
                'visit_id' => $id,
                'exception' => $e,
            ]);

            return $this->serverError();
        } catch (\Throwable $e) {
            Log::error('Gagal memperbarui kunjungan: '.$e->getMessage(), [
                'visit_id' => $id,
                'exception' => $e,
            ]);

            return $this->serverError();
        }
    }

    // -----------------------------------------------------------------
    // Helper
    // -----------------------------------------------------------------

    /**
     * Mencari satu kunjungan.
     *
     * Kolom `id` bertipe UUID, jadi id yang bukan UUID ditolak lebih dulu -
     * jika tidak, PostgreSQL melempar error dan endpoint membalas 500.
     *
     * @return Visit|JsonResponse
     */
    private function findVisit(string $id)
    {
        if (! Str::isUuid($id)) {
            return $this->visitNotFound();
        }

        $visit = Visit::with('child:id,user_id,name')->find($id);

        if (! $visit) {
            return $this->visitNotFound();
        }

        return $visit;
    }

    /**
     * Memastikan pengguna berhak membaca kunjungan ini.
     *
     * Kader boleh semua; Ibu hanya kunjungan anaknya sendiri.
     *
     * @return JsonResponse|null
     */
    private function assertCanView(Visit $visit, $user)
    {
        if ($user->role === 'kader') {
            return null;
        }

        if ($visit->child !== null && $visit->child->user_id === $user->id) {
            return null;
        }

        return response()->json([
            'success' => false,
            'message' => 'Akses ditolak. Anda tidak berhak melihat kunjungan ini.',
            'errors' => null,
        ], 403);
    }

    private function childNotFound()
    {
        return response()->json([
            'success' => false,
            'message' => 'Data balita tidak ditemukan.',
            'errors' => null,
        ], 404);
    }

    private function visitNotFound()
    {
        return response()->json([
            'success' => false,
            'message' => 'Kunjungan tidak ditemukan.',
            'errors' => null,
        ], 404);
    }

    private function validationError(ValidationException $e)
    {
        return response()->json([
            'success' => false,
            'message' => 'Validasi gagal.',
            'errors' => $e->errors(),
        ], 422);
    }

    private function serverError()
    {
        return response()->json([
            'success' => false,
            'message' => 'Terjadi kesalahan server. Silakan coba lagi.',
            'errors' => null,
        ], 500);
    }
}
