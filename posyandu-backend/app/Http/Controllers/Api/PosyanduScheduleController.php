<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\PosyanduSchedule;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Arr;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Agenda kegiatan posyandu.
 *
 * Endpoint yang tersedia:
 *  - `GET    /schedules`                  daftar agenda (Ibu & Kader, read-only)
 *  - `POST   /kader/schedules`            buat agenda (Kader)
 *  - `PATCH  /kader/schedules/{id}`       ubah status/petugas (Kader)
 *  - `DELETE /kader/schedules/{id}`       hapus agenda (Kader)
 *
 * Ibu hanya membaca; seluruh penulisan dibatasi Kader lewat route middleware
 * `RoleCheck:kader`. Daftar petugas yang ditugaskan ke agenda dikirim sebagai
 * array UUID pada field `petugas_ids`, disimpan lewat pivot
 * `posyandu_schedule_petugas` (FK cascadeOnDelete, unik per pasangan).
 */
class PosyanduScheduleController extends Controller
{
    /** Daftar agenda, opsional difilter per tanggal atau rentang tanggal. */
    public function index(Request $request)
    {
        try {
            $query = PosyanduSchedule::query()
                ->with(['petugas:id,name,jabatan', 'creator:id,name'])
                ->orderBy('scheduled_date')
                ->orderBy('start_time');

            // Filter opsional. `date` untuk satu hari, `from`/`to` untuk rentang.
            if ($date = $request->query('date')) {
                $query->onDate($date);
            } elseif ($request->filled('from') && $request->filled('to')) {
                $query->betweenDates($request->query('from'), $request->query('to'));
            }

            $schedules = $query->get();

            return response()->json([
                'success' => true,
                'message' => 'Daftar jadwal posyandu berhasil diambil.',
                'data' => $schedules->map(fn (PosyanduSchedule $s) => $this->present($s))->all(),
            ], 200);

        } catch (\Throwable $e) {
            Log::error('Gagal mengambil jadwal posyandu: ' . $e->getMessage(), [
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
     * Membuat agenda baru.
     *
     * Validasi `petugas_ids` memakai `Rule::exists` supaya UUID yang tidak
     * dikenal ditolak sebagai 422, bukan jadi 500 dari PostgreSQL. Field ini
     * opsional - agenda boleh dibuat sebelum petugas ditugaskan.
     */
    public function store(Request $request)
    {
        $user = $request->user();

        try {
            $validated = $request->validate([
                'title' => 'required|string|max:255',
                'description' => 'nullable|string|max:1000',
                'scheduled_date' => 'required|date_format:Y-m-d',
                'start_time' => 'nullable|date_format:H:i',
                'end_time' => 'nullable|date_format:H:i|after_or_equal:start_time',
                'location' => 'nullable|string|max:160',
                'status' => ['nullable', Rule::in(PosyanduSchedule::STATUSES)],
                'notes' => 'nullable|string|max:1000',
                'petugas_ids' => 'nullable|array|max:20',
                'petugas_ids.*' => ['uuid', Rule::exists('users', 'id')],
            ]);

            // Validasi role kader dipisah dari rules karena memerlukan query.
            // `Rule::exists` di dalam `store` cukup untuk memastikan UUID-nya
            // dikenal; yang belum dijamin adalah role-nya `kader`, jadi dicek
            // di sini agar pesannya jelas.
            $petugasIds = $this->validatePetugasAreKader($validated['petugas_ids'] ?? []);
            if ($petugasIds === null) {
                return response()->json([
                    'success' => false,
                    'message' => 'Validasi gagal.',
                    'errors' => ['petugas_ids' => ['Hanya akun dengan role kader yang bisa ditugaskan.']],
                ], 422);
            }

            $schedule = DB::transaction(function () use ($validated, $petugasIds, $user) {
                $schedule = PosyanduSchedule::create([
                    'title' => $validated['title'],
                    'description' => $validated['description'] ?? null,
                    'scheduled_date' => $validated['scheduled_date'],
                    'start_time' => $validated['start_time'] ?? null,
                    'end_time' => $validated['end_time'] ?? null,
                    'location' => $validated['location'] ?? config('posyandu.posyandu_name'),
                    'status' => $validated['status'] ?? PosyanduSchedule::STATUS_TERJADWAL,
                    'notes' => $validated['notes'] ?? null,
                    'created_by' => $user->id,
                ]);

                // Sync petugas bila dikirim. `sync` aman dipanggil dengan array
                // kosong (mengosongkan penugasan) maupun tanpa argumen.
                if (!empty($petugasIds)) {
                    $schedule->petugas()->sync($petugasIds);
                }

                return $schedule;
            });

            $schedule->load(['petugas:id,name,jabatan', 'creator:id,name']);

            return response()->json([
                'success' => true,
                'message' => 'Agenda posyandu berhasil dibuat.',
                'data' => $this->present($schedule),
            ], 201);

        } catch (ValidationException $e) {
            return response()->json([
                'success' => false,
                'message' => 'Validasi gagal.',
                'errors' => $e->errors(),
            ], 422);
        } catch (\Throwable $e) {
            Log::error('Gagal membuat jadwal posyandu: ' . $e->getMessage(), [
                'user_id' => $user->id,
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
     * Memperbarui agenda (partial update).
     *
     * Hanya field yang dikirim yang berubah, jadi aman dipanggil via PATCH.
     * `status` divalidasi terhadap `PosyanduSchedule::STATUSES` yang cerminannya
     * CHECK constraint database, supaya ketik salah ketahuan sebagai 422.
     */
    public function update(Request $request, string $id)
    {
        $user = $request->user();

        $schedule = $this->findSchedule($id);

        if (!$schedule instanceof PosyanduSchedule) {
            return $schedule;
        }

        try {
            $validated = $request->validate([
                'title' => 'sometimes|required|string|max:255',
                'description' => 'sometimes|nullable|string|max:1000',
                'scheduled_date' => 'sometimes|required|date_format:Y-m-d',
                'start_time' => 'sometimes|nullable|date_format:H:i',
                'end_time' => 'sometimes|nullable|date_format:H:i',
                'status' => ['sometimes', 'required', Rule::in(PosyanduSchedule::STATUSES)],
                'notes' => 'sometimes|nullable|string|max:1000',
                'location' => 'sometimes|nullable|string|max:160',
                'petugas_ids' => 'sometimes|nullable|array|max:20',
                'petugas_ids.*' => ['uuid', Rule::exists('users', 'id')],
            ]);

            if ($validated === []) {
                return response()->json([
                    'success' => false,
                    'message' => 'Tidak ada data yang diperbarui.',
                    'errors' => ['body' => ['Kirim minimal satu field untuk diperbarui.']],
                ], 422);
            }

            if (array_key_exists('petugas_ids', $validated)) {
                $valid = $this->validatePetugasAreKader($validated['petugas_ids'] ?? []);

                if ($valid === null) {
                    return response()->json([
                        'success' => false,
                        'message' => 'Validasi gagal.',
                        'errors' => ['petugas_ids' => ['Hanya akun dengan role kader yang bisa ditugaskan.']],
                    ], 422);
                }

                $validated['petugas_ids'] = $valid;
            }

            $schedule = DB::transaction(function () use ($schedule, $validated) {
                // `petugas_ids` sengaja TIDAK ikut di-`fill` ke sini: ia kolom
                // pivot, bukan kolom tabel. Field lain boleh di-fill langsung.
                $schedule->fill(Arr::only($validated, [
                    'title', 'description', 'scheduled_date',
                    'start_time', 'end_time', 'status', 'notes', 'location',
                ]))->save();

                // `sync` (bukan syncWithoutDetaching) menggantikan seluruh
                // penugasan, jadi klien boleh mengirim daftar lengkap -
                // termasuk array kosong untuk mengosongkan penugasan.
                if (array_key_exists('petugas_ids', $validated)) {
                    $schedule->petugas()->sync($validated['petugas_ids'] ?? []);
                }

                return $schedule;
            });

            $schedule->load(['petugas:id,name,jabatan', 'creator:id,name']);

            return response()->json([
                'success' => true,
                'message' => 'Agenda posyandu berhasil diperbarui.',
                'data' => $this->present($schedule),
            ], 200);

        } catch (ValidationException $e) {
            return response()->json([
                'success' => false,
                'message' => 'Validasi gagal.',
                'errors' => $e->errors(),
            ], 422);
        } catch (\Throwable $e) {
            Log::error('Gagal memperbarui jadwal posyandu: ' . $e->getMessage(), [
                'user_id' => $user->id,
                'schedule_id' => $id,
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
     * Menghapus agenda beserta penugasan petugasnya.
     *
     * Baris pivot otomatis ikut terhapus lewat FK `ON DELETE CASCADE`, jadi
     * tidak ada sisa data yatim.
     */
    public function destroy(Request $request, string $id)
    {
        $user = $request->user();

        $schedule = $this->findSchedule($id);

        if (!$schedule instanceof PosyanduSchedule) {
            return $schedule;
        }

        try {
            $schedule->delete();

            return response()->json([
                'success' => true,
                'message' => 'Agenda posyandu berhasil dihapus.',
                'data' => ['id' => $id],
            ], 200);

        } catch (\Throwable $e) {
            Log::error('Gagal menghapus jadwal posyandu: ' . $e->getMessage(), [
                'user_id' => $user->id,
                'schedule_id' => $id,
                'exception' => $e,
            ]);

            return response()->json([
                'success' => false,
                'message' => 'Terjadi kesalahan server. Silakan coba lagi.',
                'errors' => null,
            ], 500);
        }
    }

    // -----------------------------------------------------------------
    // Helper
    // -----------------------------------------------------------------

    /**
     * Memastikan semua UUID pada `petugas_ids` benar-benar akun Kader.
     *
     * Satu query: ambil semua user dengan role `kader` dari UUID yang dikirim,
     * lalu bandingkan jumlahnya. Kalau ada UUID yang tidak masuk, return null
     * supaya caller membalas 422.
     *
     * @param  array<int, string>  $ids
     * @return array<int, string>|null  daftar UUID(unique, valid) atau null bila tidak valid
     */
    private function validatePetugasAreKader(array $ids): ?array
    {
        $ids = array_values(array_unique($ids));

        if ($ids === []) {
            return [];
        }

        $valid = User::where('role', 'kader')
            ->whereIn('id', $ids)
            ->pluck('id')
            ->all();

        // Jumlah UUID unik yang benar-benar role kader harus sama dengan
        // jumlah yang diminta. Kalau kurang, ada UUID yang bukan kader.
        if (count($valid) !== count($ids)) {
            return null;
        }

        return array_values($valid);
    }

    /**
     * Mencari agenda berdasarkan UUID, membalas 404 bila tidak ada.
     *
     * @return PosyanduSchedule|\Illuminate\Http\Response
     */
    private function findSchedule(string $id)
    {
        $notFound = response()->json([
            'success' => false,
            'message' => 'Agenda posyandu tidak ditemukan.',
            'errors' => null,
        ], 404);

        if (!Str::isUuid($id)) {
            return $notFound;
        }

        $schedule = PosyanduSchedule::find($id);

        if (!$schedule) {
            return $notFound;
        }

        return $schedule;
    }

    /**
     * Bentuk agenda untuk respons API.
     *
     * `location_name` memakai accessor model yang jatuh ke nama posyandu dari
     * config bila `location` kosong, sehingga mobile tidak perlu logika
     * fallback sendiri.
     */
    private function present(PosyanduSchedule $schedule): array
    {
        return [
            'id' => $schedule->id,
            'title' => $schedule->title,
            'description' => $schedule->description,
            'scheduled_date' => $schedule->scheduled_date?->format('Y-m-d'),
            'start_time' => $schedule->start_time?->format('H:i'),
            'end_time' => $schedule->end_time?->format('H:i'),
            'location' => $schedule->location,
            'location_name' => $schedule->location_name,
            'status' => $schedule->status,
            'notes' => $schedule->notes,
            'created_by' => $schedule->created_by,
            'creator_name' => $schedule->creator?->name,
            'petugas_ids' => $schedule->petugas->pluck('id')->all(),
            'petugas' => $schedule->petugas->map(fn (User $p) => [
                'id' => $p->id,
                'name' => $p->name,
                'jabatan' => $p->jabatan,
            ])->all(),
            'created_at' => $schedule->created_at?->toIso8601String(),
            'updated_at' => $schedule->updated_at?->toIso8601String(),
        ];
    }
}
