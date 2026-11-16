<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Child;
use App\Models\Consent;
use App\Models\Measurement;
use App\Models\User;
use App\Services\ChildTimelineService;
use App\Services\GrowthChartService;
use App\Services\ReferralService;
use App\Services\VisitService;
use App\Support\NikHasher;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
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
        //
        // `latestMeasurement` otomatis ikut termuat karena `$with` pada model
        // Child, sehingga `latest_z_score` dan `nutritional_status` tersedia
        // tanpa query tambahan per anak.
        $query = Child::with('mother:id,name,nik');

        // Ibu hanya melihat anaknya sendiri. Kader melihat seluruh data.
        if ($user->role === 'ibu') {
            $query->ownedBy($user->id);
        }

        $children = $query->orderBy('name')->get();

        return response()->json([
            'success' => true,
            'message' => 'Data balita berhasil diambil.',
            'data' => $children,
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
                // NIK dicek lewat hash, bukan kolom terenkripsi. Lihat child
                // NIK uniqueness di StoreChildRequest.
                'nik' => ['nullable', 'string', 'size:16', $this->uniqueChildNikRule()],
                'name' => 'required|string|max:255',
                'place_of_birth' => 'required_without:birth_place|string|max:100',
                'birth_place' => 'required_without:place_of_birth|string|max:100',
                // `date_format:Y-m-d` WAJIB dipakai, bukan `date` saja.
                'date_of_birth' => 'required|date_format:Y-m-d|before_or_equal:today',
                'gender' => 'required|in:L,P',
                'birth_order' => 'nullable|integer|min:1|max:20',
                'birth_weight' => 'nullable|numeric|min:0',
                'birth_height' => 'nullable|numeric|min:0',
                'birth_length' => 'nullable|numeric|min:0',
                'birth_head_circumference' => 'nullable|numeric|min:0',
                'birth_status' => 'nullable|in:normal,premature',
                'buku_kia_id' => 'nullable|string|max:50',
                'user_id' => [
                    $isKader ? 'required_without:ibu_nik' : 'nullable',
                    'exists:users,id',
                ],
                'ibu_nik' => [
                    $isKader ? 'required_without:user_id' : 'nullable',
                    'string',
                    'size:16',
                ],
                'consent_type' => 'required|in:data_processing,data_sharing,research',
                'consent_document_version' => 'required|string|max:20',
            ]);

            // --- Tentukan ibu pemilik anak -------------------------------
            [$mother, $error] = $this->resolveMother($user, $validated, true);
            if ($error) {
                return $error;
            }

            if ($mother && $mother->role === 'ibu' && isset($mother->status) && $mother->status !== 'active') {
                return response()->json([
                    'success' => false,
                    'message' => 'Akun Ibu belum disetujui oleh Kader Posyandu. Tidak dapat menambahkan data anak.',
                    'errors' => null,
                ], 403);
            }

            // --- Simpan (UUID dibuat otomatis oleh trait HasUuids) -------
            $nik = $validated['nik'] ?? null;

            $childData = [
                'user_id' => $mother->id,
                'nik' => $nik,
                'nik_hash' => $nik ? NikHasher::hash($nik) : null,
                'name' => $validated['name'],
                'date_of_birth' => $validated['date_of_birth'],
                'gender' => $validated['gender'],
                'birth_order' => $validated['birth_order'] ?? null,
                'birth_weight' => $validated['birth_weight'] ?? null,
                'birth_length' => $validated['birth_length'] ?? $validated['birth_height'] ?? null,
                'birth_head_circumference' => $validated['birth_head_circumference'] ?? null,
                'birth_status' => $validated['birth_status'] ?? null,
                'buku_kia_id' => $validated['buku_kia_id'] ?? null,
            ];

            if (array_key_exists('place_of_birth', $validated)) {
                $childData['place_of_birth'] = $validated['place_of_birth'];
            }
            if (array_key_exists('birth_place', $validated)) {
                $childData['birth_place'] = $validated['birth_place'];
                if (! array_key_exists('place_of_birth', $childData)) {
                    $childData['place_of_birth'] = $validated['birth_place'];
                }
            }

            $child = Child::create($childData);

            if ($mother && $mother->role === 'ibu' && $mother->needsChildData()) {
                $mother->update(['onboarding_status' => 'completed']);
            }

            Consent::create([
                'child_id' => $child->id,
                'granted_by' => $mother->id,
                'consent_type' => $validated['consent_type'],
                'granted_at' => now(),
                'document_version' => $validated['consent_document_version'],
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
            Log::error('Gagal menambah data balita: '.$e->getMessage(), [
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
        if (! isset($errors['nik'])) {
            return $errors;
        }

        $nik = request()->input('nik');
        if (empty($nik)) {
            return $errors;
        }

        $archived = Child::withTrashed()
            ->where('nik_hash', NikHasher::hash($nik))
            ->whereNotNull('deleted_at')
            ->first();

        if ($archived) {
            $errors['nik'] = ["NIK sudah dipakai oleh anak yang datanya sudah dihapus ({$archived->name}). "
                .'Pulihkan data tersebut atau gunakan NIK lain.'];
        }

        return $errors;
    }

    /**
     * NIK disimpan terenkripsi sehingga `unique:children,nik` tidak bisa
     * dipakai. Keunikan dicek lewat `nik_hash` (HMAC-SHA256 deterministik).
     */
    private function uniqueChildNikRule(?string $ignoreId = null): \Closure
    {
        return function (string $attribute, mixed $value, \Closure $fail) use ($ignoreId): void {
            $query = Child::withTrashed()->where('nik_hash', NikHasher::hash((string) $value));

            if ($ignoreId !== null) {
                $query->whereKeyNot($ignoreId);
            }

            if ($query->exists()) {
                $fail('NIK sudah dipakai oleh data anak lain.');
            }
        };
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

        $hasId = ! empty($validated['user_id']);
        $hasNik = ! empty($validated['ibu_nik']);

        if (! $hasId && ! $hasNik) {
            if (! $required) {
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
            $byNik = User::where('nik_hash', NikHasher::hash($validated['ibu_nik']))->first();

            if (! $byNik) {
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

        if (! $mother) {
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
            if (! $child instanceof Child) {
                return $child;
            }

            $validated = $request->validate([
                'nik' => [
                    'sometimes', 'nullable', 'string', 'size:16',
                    // NIK anak unik, tapi abaikan dirinya sendiri saat update.
                    $this->uniqueChildNikRule($child->id),
                ],
                'name' => ['sometimes', 'required', 'string', 'max:255'],
                'place_of_birth' => ['sometimes', 'string', 'max:100'],
                'birth_place' => ['sometimes', 'string', 'max:100'],
                // Sama seperti `store`: date_format mencegah 500 dari
                // PostgreSQL, before_or_equal mencegah tanggal lahir di masa depan.
                'date_of_birth' => [
                    'sometimes', 'required',
                    'date_format:Y-m-d', 'before_or_equal:today',
                ],
                'gender' => ['sometimes', 'required', 'in:L,P'],
                'birth_order' => ['sometimes', 'nullable', 'integer', 'min:1', 'max:20'],
                'birth_weight' => ['sometimes', 'nullable', 'numeric', 'min:0'],
                'birth_height' => ['sometimes', 'nullable', 'numeric', 'min:0'],
                'birth_length' => ['sometimes', 'nullable', 'numeric', 'min:0'],
                'birth_head_circumference' => ['sometimes', 'nullable', 'numeric', 'min:0'],
                'birth_status' => ['sometimes', 'nullable', 'in:normal,premature'],
                'buku_kia_id' => ['sometimes', 'nullable', 'string', 'max:50'],
                // Batas 500 karakter divalidasi di sini, bukan lewat CHECK
                // constraint, supaya kesalahan ketik jadi 422 yang bisa dibaca
                // kader. Isinya teks bebas satu penanda per baris dan sengaja
                // TIDAK diparsing - lihat `docs/arsip/RANCANGAN_BUKU_MEDIS.md` bagian 5.1.
                'medical_flags' => ['sometimes', 'nullable', 'string', 'max:500'],
                'user_id' => ['sometimes', 'exists:users,id'],
                'ibu_nik' => ['sometimes', 'string', 'size:16'],
            ]);

            // Hanya Kader yang boleh menulis kondisi khusus. Ibu tetap boleh
            // MEMBACA penanda anaknya sendiri (`docs/arsip/RANCANGAN_BUKU_MEDIS.md` 12).
            //
            // Penolakan di sini, bukan diam-diam diabaikan: `validate()` di atas
            // sudah menerima `medical_flags` untuk semua role, jadi tanpa
            // pemeriksaan ini Ibu akan mendapat 200 padahal nilainya tidak
            // pernah tersimpan - dan itu lebih buruk daripada error, karena
            // kader mengira penandanya sudah tercatat.
            if ($request->has('medical_flags') && $user->role !== 'kader') {
                return response()->json([
                    'success' => false,
                    'message' => 'Akses ditolak. Hanya Kader yang dapat menulis kondisi khusus anak.',
                    'errors' => ['medical_flags' => ['Hanya Kader yang dapat mengubah kondisi khusus anak.']],
                ], 403);
            }

            if (array_key_exists('birth_place', $validated) && ! array_key_exists('place_of_birth', $validated)) {
                $validated['place_of_birth'] = $validated['birth_place'];
            }

            // `birth_length` adalah nama kanonis; `birth_height` diterima
            // sebagai alias input dari klien lama, tetapi tidak pernah ditulis
            // karena kolom itu generated dari `birth_length`.
            $birthLengthProvided = array_key_exists('birth_length', $request->all())
                || array_key_exists('birth_height', $request->all());

            if ($birthLengthProvided) {
                $validated['birth_length'] = $validated['birth_length'] ?? $validated['birth_height'] ?? null;
                unset($validated['birth_height']);
            }

            // Buang key yang tidak berubah agar tidak menimpa nilai lama.
            foreach (['nik', 'birth_order', 'birth_weight', 'birth_height', 'birth_length', 'birth_head_circumference', 'birth_status', 'buku_kia_id'] as $optional) {
                if ($optional === 'birth_length' && $birthLengthProvided) {
                    continue;
                }

                if (array_key_exists($optional, $validated) && $validated[$optional] === null
                    && ! array_key_exists($optional, $request->all())) {
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
            Log::error('Gagal memperbarui data balita: '.$e->getMessage(), [
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

            if (! is_string($id) || ! Str::isUuid($id)) {
                return response()->json([
                    'success' => false,
                    'message' => 'Data balita tidak ditemukan.',
                    'errors' => null,
                ], 404);
            }

            $child = Child::find($id);

            if (! $child) {
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
            Log::error('Gagal menghapus data balita: '.$e->getMessage(), [
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
     * @return Child|\Illuminate\Http\Response Model bila boleh diakses, atau response error.
     */
    private function findChildForUser($id, User $user, string $action = 'mengubah')
    {
        $notFound = response()->json([
            'success' => false,
            'message' => 'Data balita tidak ditemukan.',
            'errors' => null,
        ], 404);

        if (! is_string($id) || ! Str::isUuid($id)) {
            return $notFound;
        }

        $child = Child::find($id);

        if (! $child) {
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

    /**
     * Riwayat medis satu anak, dikelompokkan per tanggal kunjungan.
     *
     * Bookkeeping-nya ada di `ChildTimelineService`; method ini hanya
     * memvalidasi parameter, memastikan akses, lalu mengembalikan bentuk
     * envelope baku.
     *
     * `before` TIDAK memakai `before_or_equal:today`. Riwayat harus tetap bisa
     * dibaca setelah tanggal lewat - yang tidak boleh hanyalah tanggal yang
     * tidak pernah ada seperti `2026-13-45`, dan itu sudah tertangkap
     * `date_format`. Batas waktu tambahan hanya menyembunyikan riwayat, bukan
     * melindungi apa pun.
     */
    public function timeline(Request $request, $id, ChildTimelineService $timeline)
    {
        $user = $request->user();

        try {
            // `findChildForUser` yang dipakai, bukan pemeriksaan sendiri: Ibu
            // hanya boleh timeline anaknya sendiri, dan aturan 404-untuk-id-bukan-UUID
            // di sana sudah benar.
            $child = $this->findChildForUser($id, $user, 'melihat');

            if (! $child instanceof Child) {
                return $child;
            }

            $validated = $request->validate([
                // Menghitung TANGGAL, bukan jumlah baris. Satu tanggal dengan
                // tiga suntikan tetap satu entri.
                'limit' => ['sometimes', 'integer', 'min:1', 'max:200'],
                'before' => ['sometimes', 'nullable', 'date_format:Y-m-d'],
            ]);

            $limit = (int) ($validated['limit'] ?? 50);
            $before = $validated['before'] ?? null;

            return response()->json([
                'success' => true,
                'message' => 'Riwayat medis anak berhasil diambil.',
                'data' => $timeline->timelineFor($child, $limit, $before),
            ], 200);

        } catch (ValidationException $e) {
            return response()->json([
                'success' => false,
                'message' => 'Validasi gagal.',
                'errors' => $e->errors(),
            ], 422);
        } catch (\Throwable $e) {
            Log::error('Gagal mengambil timeline anak: '.$e->getMessage(), [
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
     * Deret waktu pertumbuhan satu anak untuk digambar sebagai grafik.
     *
     * Bookkeeping-nya ada di `GrowthChartService`; method ini hanya memastikan
     * akses lalu mengembalikan bentuk envelope baku.
     *
     * Endpoint ini sengaja tidak punya query string: tidak ada `limit`,
     * `before`, `from`, maupun `to`. Partial unique index
     * `measurements_child_date_unique` membatasi satu baris penimbangan per
     * tanggal, jadi anak 0-60 bulan paling banyak 61 titik. Menambah
     * pagination justru berisiko memotong grafik di tengah, dan grafik yang
     * terpotong adalah grafik yang salah.
     */
    public function growth(Request $request, $id, GrowthChartService $growth)
    {
        $user = $request->user();

        try {
            // `findChildForUser` yang dipakai, bukan pemeriksaan sendiri: Ibu
            // hanya boleh grafik anaknya sendiri, dan aturan 404-untuk-id-bukan-UUID
            // di sana sudah benar.
            $child = $this->findChildForUser($id, $user, 'melihat');

            if (! $child instanceof Child) {
                return $child;
            }

            return response()->json([
                'success' => true,
                'message' => 'Data pertumbuhan anak berhasil diambil.',
                'data' => $growth->chartFor($child),
            ], 200);

        } catch (\Throwable $e) {
            Log::error('Gagal mengambil data pertumbuhan anak: '.$e->getMessage(), [
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
     * Daftar kunjungan satu anak (P0-1), terbaru lebih dulu.
     *
     * Didaftarkan di group `RoleCheck:ibu,kader` yang sama dengan `timeline`
     * dan `growth`, supaya aturan aksesnya persis sama: Ibu hanya anaknya
     * sendiri, Kader semua. Otorisasi memakai `findChildForUser()` yang sudah
     * ada, bukan salinan baru.
     *
     * Bentuk keluaran ada di `VisitService::listForChild()`; controller hanya
     * memasang envelope baku.
     */
    public function visits(Request $request, $id, VisitService $visits)
    {
        $user = $request->user();

        try {
            $child = $this->findChildForUser($id, $user, 'melihat');

            if (! $child instanceof Child) {
                return $child;
            }

            return response()->json([
                'success' => true,
                'message' => 'Daftar kunjungan anak berhasil diambil.',
                'data' => [
                    'child' => [
                        'id' => $child->id,
                        'name' => $child->name,
                    ],
                    'visits' => $visits->listForChild($child),
                ],
            ], 200);

        } catch (\Throwable $e) {
            Log::error('Gagal mengambil daftar kunjungan anak: '.$e->getMessage(), [
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
     * Daftar rujukan satu anak, terbaru lebih dulu.
     *
     * Didaftarkan di group `RoleCheck:ibu,kader` yang sama dengan `timeline`,
     * `growth`, dan `visits`, supaya aturan aksesnya persis sama: Ibu hanya
     * anaknya sendiri, Kader semua. Otorisasi memakai `findChildForUser()` yang
     * sudah ada, bukan salinan baru.
     *
     * Bentuk keluaran ada di `ReferralService::listForChild()`; controller hanya
     * memasang envelope baku.
     */
    public function referrals(Request $request, $id, ReferralService $referrals)
    {
        $user = $request->user();

        try {
            $child = $this->findChildForUser($id, $user, 'melihat');

            if (! $child instanceof Child) {
                return $child;
            }

            return response()->json([
                'success' => true,
                'message' => 'Daftar rujukan anak berhasil diambil.',
                'data' => [
                    'child' => [
                        'id' => $child->id,
                        'name' => $child->name,
                    ],
                    'referrals' => $referrals->listForChild($child),
                ],
            ], 200);

        } catch (\Throwable $e) {
            Log::error('Gagal mengambil daftar rujukan anak: '.$e->getMessage(), [
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

    // Melihat detail satu anak
    public function show(Request $request, $id)
    {
        $child = $this->findChildForUser($id, $request->user(), 'melihat');

        if (! $child instanceof Child) {
            return $child;
        }

        return response()->json([
            'success' => true,
            'message' => 'Detail balita berhasil diambil.',
            'data' => $child->load('mother:id,name,nik'),
        ], 200);
    }

    public function indexKader(Request $request)
    {
        try {
            // Relasi `mother` agar nama ibu ikut terkirim (dibaca mobile di
            // child.dart). `latestMeasurement` ikut termuat otomatis dari
            // `$with` pada model Child.
            //
            // Paginasi/filter bisa ditambahkan nanti tanpa mengubah bentuk respons.
            $children = Child::with('mother:id,name,nik')
                ->orderBy('name')
                ->orderBy('id')
                ->paginate($this->perPage($request));

            // Format baku JSON Envelope wajib
            return response()->json([
                'success' => true,
                'message' => 'Berhasil mengambil daftar anak',
                'data' => $children->items(),
                'meta' => $this->paginationMeta($children),
            ], 200);

        } catch (\Throwable $e) {
            Log::error('Gagal mengambil daftar anak: '.$e->getMessage(), [
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
