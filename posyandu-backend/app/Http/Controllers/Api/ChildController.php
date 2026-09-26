<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Child;
use App\Models\Measurement;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
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
            [$mother, $error] = $this->resolveMother($user, $validated, true);
            if ($error) {
                return $error;
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
                'errors' => $this->explainNikConflict($e->errors()),
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

    /**
     * Mengubah pesan "nik sudah dipakai" menjadi lebih informatif bila bentrok
     * disebabkan anak yang sebelumnya sudah di-soft delete.
     */
    private function explainNikConflict(array $errors): array
    {
        if (!isset($errors['nik'])) {
            return $errors;
        }

        $nik = request()->input('nik');
        if (empty($nik)) {
            return $errors;
        }

        $archived = Child::withTrashed()->where('nik', $nik)->whereNotNull('deleted_at')->first();

        if ($archived) {
            $errors['nik'] = ["NIK sudah dipakai oleh anak yang datanya sudah dihapus ({$archived->name}). "
                . 'Pulihkan data tersebut atau gunakan NIK lain.'];
        }

        return $errors;
    }

    /**
     * Menentukan ibu pemilik anak dari `ibu_nik` / `user_id`.
     *
     * @param  bool  $required  true = ibu wajib ditentukan (tambah data),
     *                          false = opsional (ubah data; ibu tidak diubah
     *                          bila identifier tidak dikirim).
     * @return array{0: ?User, 1: ?Response}
     */
    private function resolveMother(User $user, array $validated, bool $required): array
    {
        // Ibu selalu memakai dirinya sendiri dan tidak pernah bisa menunjuk ibu lain.
        if ($user->role !== 'kader') {
            return [$user, null];
        }

        $hasId = !empty($validated['user_id']);
        $hasNik = !empty($validated['ibu_nik']);

        if (!$hasId && !$hasNik) {
            if (!$required) {
                return [null, null]; // tidak ada perubahan ibu
            }

            return [null, response()->json([
                'success' => false,
                'message' => 'Ibu pemilik anak tidak ditemukan.',
                'errors' => ['user_id' => ['Data ibu wajib diisi.']],
            ], 404)];
        }

        $byId = $hasId ? User::find($validated['user_id']) : null;
        $byNik = null;

        if ($hasNik) {
            $byNik = User::where('nik', $validated['ibu_nik'])->first();

            if (!$byNik) {
                return [null, response()->json([
                    'success' => false,
                    'message' => 'NIK Ibu tidak ditemukan di sistem. Pastikan akun Ibu sudah terdaftar.',
                    'errors' => ['ibu_nik' => ['NIK Ibu belum terdaftar.']],
                ], 404)];
            }
        }

        // Dua-duanya dikirim harus menunjuk user yang sama.
        if ($byId && $byNik && $byId->id !== $byNik->id) {
            return [null, response()->json([
                'success' => false,
                'message' => 'user_id dan ibu_nik harus menunjuk Ibu yang sama.',
                'errors' => ['user_id' => ['user_id dan ibu_nik tidak sesuai.']],
            ], 422)];
        }

        $mother = $byNik ?? $byId;

        if (!$mother) {
            return [null, response()->json([
                'success' => false,
                'message' => 'Ibu pemilik anak tidak ditemukan.',
                'errors' => ['user_id' => ['Data ibu wajib diisi.']],
            ], 404)];
        }

        if ($mother->role !== 'ibu') {
            return [null, response()->json([
                'success' => false,
                'message' => 'Data anak hanya dapat ditambahkan pada akun dengan role ibu.',
                'errors' => ['user_id' => ['User yang dipilih bukan role ibu.']],
            ], 422)];
        }

        return [$mother, null];
    }

    /**
     * Memperbarui data balita.
     *
     * Berperilaku sebagai partial update: hanya field yang dikirim yang diubah,
     * sehingga aman dipanggil via `PUT` maupun `PATCH`.
     *
     * Bila `date_of_birth` atau `gender` berubah, z-score measurement anak
     * ikut dihitung ulang karena umur & acuan WHO ikut berubah.
     */
    public function update(Request $request, $id)
    {
        $user = $request->user();

        try {
            $child = $this->findChildForUser($id, $user);

            // findChildForUser() mengembalikan response error (404/403) bila
            // tidak ditemukan atau tidak berhak diakses.
            if (!$child instanceof Child) {
                return $child;
            }

            $validated = $request->validate([
                'nik' => [
                    'sometimes', 'nullable', 'string', 'size:16',
                    // NIK anak unik, tapi abaikan dirinya sendiri saat update.
                    Rule::unique('children', 'nik')->ignore($child->id),
                ],
                'name' => ['sometimes', 'required', 'string', 'max:255'],
                'date_of_birth' => ['sometimes', 'required', 'date'],
                'gender' => ['sometimes', 'required', 'in:L,P'],
                'birth_weight' => ['sometimes', 'nullable', 'numeric', 'min:0'],
                'birth_height' => ['sometimes', 'nullable', 'numeric', 'min:0'],
                'user_id' => ['sometimes', 'exists:users,id'],
                'ibu_nik' => ['sometimes', 'string', 'size:16'],
            ]);

            // Buang key yang tidak berubah agar tidak menimpa nilai lama.
            foreach (['nik', 'birth_weight', 'birth_height'] as $optional) {
                if (array_key_exists($optional, $validated) && $validated[$optional] === null
                    && !array_key_exists($optional, $request->all())) {
                    unset($validated[$optional]);
                }
            }

            if ($validated === []) {
                return response()->json([
                    'success' => false,
                    'message' => 'Tidak ada data yang diperbarui.',
                    'errors' => ['body' => ['Kirim minimal satu field untuk diperbarui.']],
                ], 422);
            }

            // Perpindahan induk hanya boleh dilakukan Kader.
            [$mother, $error] = $this->resolveMother($user, $validated, false);
            if ($error) {
                return $error;
            }
            if ($mother) {
                $validated['user_id'] = $mother->id;
            }

            // Z-score lama jadi tidak valid bila umur/gender berubah.
            $zScoreAffected = array_key_exists('date_of_birth', $validated)
                || array_key_exists('gender', $validated);

            $child->fill($validated)->save();

            $recalculated = 0;
            if ($zScoreAffected) {
                // Menyentuh baris memicu trigger BEFORE UPDATE sehingga
                // age_in_months, z_score_wfa, dan status_gizi dihitung ulang.
                $recalculated = Measurement::where('child_id', $child->id)
                    ->update(['updated_at' => now()]);
            }

            $message = 'Data balita berhasil diperbarui.';
            if ($recalculated > 0) {
                $message .= " Z-score {$recalculated} data penimbangan dihitung ulang.";
            }

            return response()->json([
                'success' => true,
                'message' => $message,
                'data' => $child->fresh()->load('mother:id,name,nik'),
            ], 200);

        } catch (ValidationException $e) {
            return response()->json([
                'success' => false,
                'message' => 'Validasi gagal.',
                'errors' => $this->explainNikConflict($e->errors()),
            ], 422);
        } catch (\Throwable $e) {
            Log::error('Gagal memperbarui data balita: ' . $e->getMessage(), [
                'user_id' => $user->id,
                'child_id' => $id,
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
     * Menghapus data balita (soft delete).
     *
     * Hanya Kader yang boleh menghapus. Data anak, measurement, dan imunisasi
     * tetap tersimpan di database dengan `children.deleted_at` terisi, sehingga
     * tidak ada riwayat kesehatan yang hilang. Bisa dipulihkan dengan
     * `Child::withTrashed()->find($id)->restore()`.
     */
    public function destroy(Request $request, $id)
    {
        $user = $request->user();

        try {
            // Hanya Kader yang berwenang; dicek sebelum query agar error 403
            // tidak bocor keberadaan data anak.
            if ($user->role !== 'kader') {
                return response()->json([
                    'success' => false,
                    'message' => 'Akses ditolak. Hanya Kader yang dapat menghapus data anak.',
                    'errors' => null,
                ], 403);
            }

            if (!is_string($id) || !Str::isUuid($id)) {
                return response()->json([
                    'success' => false,
                    'message' => 'Data balita tidak ditemukan.',
                    'errors' => null,
                ], 404);
            }

            $child = Child::find($id);

            if (!$child) {
                return response()->json([
                    'success' => false,
                    'message' => 'Data balita tidak ditemukan.',
                    'errors' => null,
                ], 404);
            }

            // Hitung dulu agar jumlah ini bisa dikembalikan ke client.
            $measurementCount = $child->measurements()->count();
            $immunizationCount = $child->immunizationRecords()->count();

            $child->delete();

            return response()->json([
                'success' => true,
                'message' => 'Data balita berhasil dihapus. Riwayat penimbangan dan imunisasi tetap disimpan.',
                'data' => [
                    'id' => $child->id,
                    'archived_measurements' => $measurementCount,
                    'archived_immunizations' => $immunizationCount,
                ],
            ], 200);

        } catch (\Throwable $e) {
            Log::error('Gagal menghapus data balita: ' . $e->getMessage(), [
                'user_id' => $user->id,
                'child_id' => $id,
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
     * Mencari anak sekaligus memeriksa otorisasi.
     *
     * Kolom `id` bertipe UUID, sehingga id yang bukan UUID harus ditolak lebih
     * dulu — jika tidak, PostgreSQL melempar error dan endpoint membalas 500.
     *
     * @return Child|\Illuminate\Http\Response  Model bila boleh diakses, atau response error.
     */
    private function findChildForUser($id, User $user, string $action = 'mengubah')
    {
        $notFound = response()->json([
            'success' => false,
            'message' => 'Data balita tidak ditemukan.',
            'errors' => null,
        ], 404);

        if (!is_string($id) || !Str::isUuid($id)) {
            return $notFound;
        }

        $child = Child::find($id);

        if (!$child) {
            return $notFound;
        }

        // Kader boleh akses semua anak; Ibu hanya anaknya sendiri.
        if ($user->role !== 'kader' && $child->user_id !== $user->id) {
            return response()->json([
                'success' => false,
                'message' => "Akses ditolak. Anda tidak berhak {$action} data anak ini.",
                'errors' => null,
            ], 403);
        }

        return $child;
    }

    // Melihat detail satu anak
    public function show(Request $request, $id)
    {
        $child = $this->findChildForUser($id, $request->user(), 'melihat');

        if (!$child instanceof Child) {
            return $child;
        }

        return response()->json([
            'success' => true,
            'message' => 'Detail balita berhasil diambil.',
            'data' => $child->load('mother:id,name,nik')
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
