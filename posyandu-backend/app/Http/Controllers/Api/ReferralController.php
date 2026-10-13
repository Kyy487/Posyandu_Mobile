<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Child;
use App\Models\Referral;
use App\Models\Visit;
use App\Services\ReferralService;
use Illuminate\Database\QueryException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Rujukan anak ke fasilitas kesehatan (lihat docs/RANCANGAN_RUJUKAN.md).
 *
 * Endpoint yang tersedia di sini:
 *  - `POST   /referrals`        buat rujukan (Kader)
 *  - `GET    /referrals/{id}`   detail rujukan (pemilik anak / Kader)
 *  - `PATCH  /referrals/{id}`   koreksi rujukan / ubah status (Kader)
 *  - `DELETE /referrals/{id}`   batalkan rujukan (Kader, soft delete)
 *
 * Daftar rujukan satu anak (`GET /children/{id}/referrals`) tinggal di
 * `ChildController@referrals`, sama seperti `timeline`, `growth`, dan `visits`.
 * Alasannya: otorisasi "Ibu hanya anaknya sendiri" sudah ada di
 * `ChildController::findChildForUser()`, dan menyalinnya ke sini akan
 * menghasilkan dua versi aturan yang pasti kelak berbeda.
 *
 * `visit_id` WAJIB dan harus milik anak yang sama dengan `child_id`; rujukan
 * selalu bagian dari satu kunjungan (PERANCANGAN_PERKUATAN.md bagian 1.3).
 */
class ReferralController extends Controller
{
    /**
     * Membuat rujukan baru.
     *
     * Kader yang login otomatis menjadi pencatat; klien tidak mengirim
     * `kader_id`.
     */
    public function store(Request $request, ReferralService $referrals)
    {
        $user = $request->user();

        try {
            $validated = $request->validate([
                'child_id' => ['required', 'uuid', Rule::exists('children', 'id')],
                'visit_id' => ['required', 'uuid', Rule::exists('visits', 'id')],
                'referral_date' => ['required', 'date_format:Y-m-d', 'before_or_equal:today'],
                'referral_type' => ['required', 'string', Rule::in(Referral::REFERRAL_TYPES)],
                'reason' => ['required', 'string', 'max:2000'],
                'facility_name' => ['required', 'string', 'max:255'],
                'status' => ['nullable', 'string', Rule::in(Referral::STATUSES)],
            ]);

            $child = Child::find($validated['child_id']);

            if (! $child) {
                return $this->childNotFound();
            }

            // `visit_id` harus milik anak yang sama. `Visit::findForChild()`
            // mengembalikan null untuk kunjungan yang tidak ada, sudah
            // dibatalkan, atau milik anak lain.
            if (Visit::findForChild($validated['visit_id'], $child->id) === null) {
                return response()->json([
                    'success' => false,
                    'message' => 'Validasi gagal.',
                    'errors' => ['visit_id' => ['Kunjungan tidak ditemukan untuk anak ini.']],
                ], 422);
            }

            $referral = $referrals->create($child, $user, $validated);

            return response()->json([
                'success' => true,
                'message' => 'Rujukan berhasil dibuat.',
                'data' => $referrals->present($referral->fresh()->load('kader:id,name')),
            ], 201);

        } catch (ValidationException $e) {
            return $this->validationError($e);
        } catch (QueryException $e) {
            // 23514 = check_violation: nilainya lolos validasi PHP tapi ditolak
            // CHECK constraint database.
            if ($e->getCode() === '23514') {
                return response()->json([
                    'success' => false,
                    'message' => 'Tipe atau status rujukan tidak valid.',
                    'errors' => null,
                ], 422);
            }

            Log::error('Gagal membuat rujukan: '.$e->getMessage(), [
                'user_id' => $user->id,
                'exception' => $e,
            ]);

            return $this->serverError();
        } catch (\Throwable $e) {
            Log::error('Gagal membuat rujukan: '.$e->getMessage(), [
                'user_id' => $user->id,
                'exception' => $e,
            ]);

            return $this->serverError();
        }
    }

    /**
     * Detail satu rujukan.
     *
     * Ibu hanya boleh membuka rujukan anaknya sendiri; Kader boleh semua.
     */
    public function show(Request $request, string $id, ReferralService $referrals)
    {
        $referral = $this->findReferral($id);

        if (! $referral instanceof Referral) {
            return $referral;
        }

        $akses = $this->assertCanView($referral, $request->user());

        if ($akses !== null) {
            return $akses;
        }

        return response()->json([
            'success' => true,
            'message' => 'Detail rujukan berhasil diambil.',
            'data' => $referrals->present($referral->load('kader:id,name')),
        ], 200);
    }

    /**
     * Koreksi satu rujukan (partial update).
     *
     * Hanya Kader (dijaga middleware role di route). `child_id` dan `visit_id`
     * sengaja tidak bisa dipindah: rujukan yang salah anak/kunjungan dibatalkan
     * lalu dibuat ulang.
     */
    public function update(Request $request, string $id, ReferralService $referrals)
    {
        $referral = $this->findReferral($id);

        if (! $referral instanceof Referral) {
            return $referral;
        }

        try {
            $validated = $request->validate([
                'referral_date' => ['sometimes', 'required', 'date_format:Y-m-d', 'before_or_equal:today'],
                'referral_type' => ['sometimes', 'required', 'string', Rule::in(Referral::REFERRAL_TYPES)],
                'reason' => ['sometimes', 'required', 'string', 'max:2000'],
                'facility_name' => ['sometimes', 'required', 'string', 'max:255'],
                'status' => ['sometimes', 'required', 'string', Rule::in(Referral::STATUSES)],
            ]);

            if ($validated === []) {
                return response()->json([
                    'success' => false,
                    'message' => 'Tidak ada data yang diperbarui.',
                    'errors' => ['body' => ['Kirim minimal satu field untuk diperbarui.']],
                ], 422);
            }

            $referral = $referrals->update($referral, $validated);

            return response()->json([
                'success' => true,
                'message' => 'Rujukan berhasil diperbarui.',
                'data' => $referrals->present($referral->fresh()->load('kader:id,name')),
            ], 200);

        } catch (ValidationException $e) {
            return $this->validationError($e);
        } catch (QueryException $e) {
            if ($e->getCode() === '23514') {
                return response()->json([
                    'success' => false,
                    'message' => 'Tipe atau status rujukan tidak valid.',
                    'errors' => null,
                ], 422);
            }

            Log::error('Gagal memperbarui rujukan: '.$e->getMessage(), [
                'referral_id' => $id,
                'exception' => $e,
            ]);

            return $this->serverError();
        } catch (\Throwable $e) {
            Log::error('Gagal memperbarui rujukan: '.$e->getMessage(), [
                'referral_id' => $id,
                'exception' => $e,
            ]);

            return $this->serverError();
        }
    }

    /**
     * Batalkan rujukan (soft delete).
     *
     * Hanya Kader (dijaga middleware role di route). Rujukan yang salah input
     * dibatalkan, bukan dihapus, supaya tindak lanjutnya tetap bisa diaudit.
     */
    public function destroy(string $id, ReferralService $referrals)
    {
        $referral = $this->findReferral($id);

        if (! $referral instanceof Referral) {
            return $referral;
        }

        try {
            $referral->delete();

            return response()->json([
                'success' => true,
                'message' => 'Rujukan berhasil dibatalkan.',
                'data' => ['id' => $referral->id],
            ], 200);

        } catch (\Throwable $e) {
            Log::error('Gagal membatalkan rujukan: '.$e->getMessage(), [
                'referral_id' => $id,
                'exception' => $e,
            ]);

            return $this->serverError();
        }
    }

    // -----------------------------------------------------------------
    // Helper
    // -----------------------------------------------------------------

    /**
     * Mencari satu rujukan.
     *
     * Kolom `id` bertipe UUID, jadi id yang bukan UUID ditolak lebih dulu -
     * jika tidak, PostgreSQL melempar error dan endpoint membalas 500.
     *
     * @return Referral|JsonResponse
     */
    private function findReferral(string $id)
    {
        if (! Str::isUuid($id)) {
            return $this->referralNotFound();
        }

        $referral = Referral::with('child:id,user_id,name')->find($id);

        if (! $referral) {
            return $this->referralNotFound();
        }

        return $referral;
    }

    /**
     * Memastikan pengguna berhak membaca rujukan ini.
     *
     * Kader boleh semua; Ibu hanya rujukan anaknya sendiri.
     *
     * @return JsonResponse|null
     */
    private function assertCanView(Referral $referral, $user)
    {
        if ($user->role === 'kader') {
            return null;
        }

        if ($referral->child !== null && $referral->child->user_id === $user->id) {
            return null;
        }

        return response()->json([
            'success' => false,
            'message' => 'Akses ditolak. Anda tidak berhak melihat rujukan ini.',
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

    private function referralNotFound()
    {
        return response()->json([
            'success' => false,
            'message' => 'Rujukan tidak ditemukan.',
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
