<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Child;
use App\Models\Measurement;
use App\Models\MedicalNote;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Database\QueryException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Catatan keluhan anak yang dicatat kader.
 *
 * Endpoint yang tersedia:
 *  - `GET    /children/{child}/medical-notes`        daftar (Ibu & Kader)
 *  - `POST   /kader/children/{child}/medical-notes` catat (Kader)
 *  - `PATCH  /kader/medical-notes/{note}`           koreksi (Kader)
 *  - `DELETE /kader/medical-notes/{note}`           batalkan (Kader)
 *
 * Catatan desain penting:
 *  - Endpoint daftar memakai SATU path untuk Ibu dan Kader, sama seperti
 *    `GET /children/{id}/immunizations`. Membuat dua path terpisah hanya
 *    akan menggandakan kode tanpa menambah manfaat apa pun, karena beda
 *    peran sudah ditangani middleware `RoleCheck` dan pemeriksaan
 *    kepemilikan di `findAccessibleChild`.
 *  - Keluhan disimpan sebagai kolom boolean terpisah (`demam`, `rewel`,
 *    `diare`), bukan JSON. Alasannya ada di migration
 *    `2026_09_27_010000_create_medical_notes_table.php`.
 *  - Ibu hanya membaca. Penulisan hanya lewat prefix `/kader/`, yang
 *    dijaga middleware `RoleCheck:kader` di `routes/api.php`.
 *  - Pembatalan memakai soft delete, bukan hapus fisik: entri yang salah
 *    input dibatalkan, bukan dihapus, supaya riwayat kesehatan bisa diaudit.
 *
 * Catatan tipe return: helper di bawah memakai `Illuminate\Http\JsonResponse`,
 * BUKAN `Illuminate\Http\Response`. `response()->json()` mengembalikan
 * JsonResponse, yang mewarisi JsonResponse dari Symfony dan TIDAK mewarisi
 * `Illuminate\Http\Response`. Menulis `: ?Response` untuk method yang
 * mengembalikan `response()->json()` akan memicu TypeError saat method itu
 * dipanggil, dan karena pemanggilnya berada di dalam blok `try` untuk
 * penanganan error, hasilnya 500 - bukan 422 yang diharapkan.
 *
 * @see MedicalNote
 */
class MedicalNoteController extends Controller
{
    /**
     * Daftar catatan keluhan satu anak.
     *
     * Default-nya bulan berjalan, karena hampir semua permintaan dari
     * lapangan menanyakan "bulan ini" atau "bulan lalu", bukan seluruh riwayat.
     * Kirim `?all=1` untuk mengambil semua catatan tanpa batas tanggal.
     *
     * Ibu hanya boleh melihat anaknya sendiri; Kader boleh melihat semua anak.
     */
    public function index(Request $request, string $childId)
    {
        $user = $request->user();

        $child = $this->findAccessibleChild($childId, $user, 'melihat');

        if (! $child instanceof Child) {
            return $child;
        }

        try {
            $validated = $request->validate([
                'month' => ['nullable', 'date_format:Y-m'],
                'all' => ['nullable', 'boolean'],
            ]);
        } catch (ValidationException $e) {
            return response()->json([
                'success' => false,
                'message' => 'Validasi gagal.',
                'errors' => $e->errors(),
            ], 422);
        }

        $semua = filter_var($request->query('all', false), FILTER_VALIDATE_BOOL);
        $bulan = $validated['month'] ?? CarbonImmutable::now()->format('Y-m');

        $query = MedicalNote::query()
            ->where('child_id', $child->id)
            ->with('kader:id,name')
            ->orderByDesc('note_date')
            ->orderByDesc('created_at');

        $query = $semua
            ? $query
            : $query->forMonth($bulan);

        $notes = $query->get();

        return response()->json([
            'success' => true,
            'message' => 'Daftar catatan keluhan berhasil diambil.',
            'data' => [
                'child' => [
                    'id' => $child->id,
                    'name' => $child->name,
                ],
                'filter' => [
                    'month' => $semua ? null : $bulan,
                    'all' => $semua,
                ],
                'summary' => $this->summarize($notes),
                'notes' => $notes->map(fn (MedicalNote $note) => $this->presentNote($note))->all(),
            ],
        ], 200);
    }

    /**
     * Mencatat keluhan baru untuk satu anak.
     *
     * Kader yang login otomatis menjadi pencatat (`kader_id`), jadi klien tidak
     * perlu mengirim field itu.
     *
     * Satu anak hanya boleh punya satu catatan per hari (unique constraint
     * `medical_notes_child_date_unique`). Kader yang salah mengetik tanggal
     * seharusnya mengoreksi catatan yang sudah ada lewat PATCH, bukan mencatat
     * ulang - karena itu kasus duplikat dibalas 422 dengan arahan yang jelas.
     */
    public function store(Request $request, string $childId)
    {
        $user = $request->user();

        $child = $this->findAccessibleChild($childId, $user, 'mencatat keluhan');

        if (! $child instanceof Child) {
            return $child;
        }

        try {
            $validated = $request->validate([
                'measurement_id' => ['nullable', 'uuid', Rule::exists('measurements', 'id')],
                'note_date' => ['required', 'date_format:Y-m-d', 'before_or_equal:today'],
                'demam' => ['nullable', 'boolean'],
                'rewel' => ['nullable', 'boolean'],
                'diare' => ['nullable', 'boolean'],
                'catatan' => ['nullable', 'string', 'max:1000'],
                'tindak_lanjut' => ['nullable', 'string', Rule::in(MedicalNote::TINDAK_LANJUTS)],
            ]);

            // Penimbangan yang dilampirkan harus milik anak yang sama. Dicek di
            // sini supaya pesannya jelas; tanpa cek ini, catatan anak ini bisa
            // sengaja ditempelkan ke penimbangan anak lain tanpa error.
            $measurementError = $this->assertMeasurementBelongsToChild($validated['measurement_id'] ?? null, $child);

            if ($measurementError !== null) {
                return $measurementError;
            }

            $isiError = $this->assertHasContent($validated);

            if ($isiError !== null) {
                return $isiError;
            }

            $sudahAda = MedicalNote::where('child_id', $child->id)
                ->where('note_date', $validated['note_date'])
                ->exists();

            if ($sudahAda) {
                return response()->json([
                    'success' => false,
                    'message' => 'Catatan keluhan tanggal tersebut sudah ada.',
                    'errors' => [
                        'note_date' => [
                            'Sudah ada catatan untuk tanggal ini. Koreksi catatan yang lama lewat PATCH, jangan catat ulang.',
                        ],
                    ],
                ], 422);
            }

            $note = MedicalNote::create([
                'child_id' => $child->id,
                'measurement_id' => $validated['measurement_id'] ?? null,
                'kader_id' => $user->id,
                'note_date' => $validated['note_date'],
                'demam' => $validated['demam'] ?? false,
                'rewel' => $validated['rewel'] ?? false,
                'diare' => $validated['diare'] ?? false,
                'catatan' => $this->normalizeCatatan($validated['catatan'] ?? null),
                'tindak_lanjut' => $validated['tindak_lanjut'] ?? null,
            ]);

            return response()->json([
                'success' => true,
                'message' => 'Catatan keluhan berhasil dicatat.',
                'data' => $this->presentNote($note->fresh()->load('kader:id,name')),
            ], 201);

        } catch (ValidationException $e) {
            return response()->json([
                'success' => false,
                'message' => 'Validasi gagal.',
                'errors' => $e->errors(),
            ], 422);
        } catch (QueryException $e) {
            // 23505 = unique_violation: dua kader menyimpan tanggal yang sama
            //         hampir bersamaan, sehingga pengecekan di atas lolos.
            // 23514 = check_violation: record kosong yang lolos cek PHP.
            if ($e->getCode() === '23505') {
                return response()->json([
                    'success' => false,
                    'message' => 'Catatan keluhan tanggal tersebut sudah ada.',
                    'errors' => [
                        'note_date' => ['Sudah ada catatan untuk tanggal ini. Koreksi lewat PATCH.'],
                    ],
                ], 422);
            }

            if ($e->getCode() === '23514') {
                return $this->emptyContentError();
            }

            Log::error('Gagal menyimpan catatan keluhan: '.$e->getMessage(), [
                'user_id' => $user->id,
                'child_id' => $child->id,
                'exception' => $e,
            ]);

            return response()->json([
                'success' => false,
                'message' => 'Terjadi kesalahan server. Silakan coba lagi.',
                'errors' => null,
            ], 500);
        } catch (\Throwable $e) {
            Log::error('Gagal menyimpan catatan keluhan: '.$e->getMessage(), [
                'user_id' => $user->id,
                'child_id' => $child->id,
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
     * Koreksi satu catatan keluhan.
     *
     * Partial update: hanya field yang dikirim yang berubah.
     *
     * Tanggal (`note_date`) SENGAJA bisa diubah lewat endpoint ini, berbeda
     * dari `PATCH /kader/immunizations/{record}` yang mengunci tanggal. Alasannya
     * unik: pada catatan keluhan, tanggal adalah tanggal Pencatatan -
     * kesalahan tanggal di sini adalah typo murni (salah pilih hari di
     * kalender), bukan pilihan yang perlu dibatalkan dan diulang. Mengunci
     * tanggal hanya akan memaksa kader mencatat ulang.
     *
     * Tetap ada satu penjaga: PATCH ke tanggal yang sudah dipakai anak itu
     * (dan bukan catatan ini sendiri) ditolak, karena bertabrakan dengan unique
     * constraint.
     */
    public function update(Request $request, string $noteId)
    {
        $user = $request->user();

        $note = $this->findNote($noteId);

        if (! $note instanceof MedicalNote) {
            return $note;
        }

        try {
            $validated = $request->validate([
                'measurement_id' => ['sometimes', 'nullable', 'uuid', Rule::exists('measurements', 'id')],
                'note_date' => ['sometimes', 'required', 'date_format:Y-m-d', 'before_or_equal:today'],
                'demam' => ['sometimes', 'nullable', 'boolean'],
                'rewel' => ['sometimes', 'nullable', 'boolean'],
                'diare' => ['sometimes', 'nullable', 'boolean'],
                'catatan' => ['sometimes', 'nullable', 'string', 'max:1000'],
                'tindak_lanjut' => ['sometimes', 'nullable', 'string', Rule::in(MedicalNote::TINDAK_LANJUTS)],
            ]);

            if ($validated === []) {
                return response()->json([
                    'success' => false,
                    'message' => 'Tidak ada data yang diperbarui.',
                    'errors' => ['body' => ['Kirim minimal satu field untuk diperbarui.']],
                ], 422);
            }

            if (array_key_exists('measurement_id', $validated)) {
                $measurementError = $this->assertMeasurementBelongsToChild(
                    $validated['measurement_id'],
                    $note->child,
                );

                if ($measurementError !== null) {
                    return $measurementError;
                }
            }

            // Validasi isi dijalankan terhadap hasil GABUNGAN nilai lama dan baru,
            // bukan hanya field yang dikirim. Kalau tidak, PATCH `{demam:false}`
            // ke catatan yang tadinya `{demam:true, catatan:null}` akan lolos
            // validasi lalu ditolak database dengan 500.
            if (array_key_exists('note_date', $validated)) {
                $bentrok = MedicalNote::where('child_id', $note->child_id)
                    ->where('note_date', $validated['note_date'])
                    ->where('id', '!=', $note->id)
                    ->exists();

                if ($bentrok) {
                    return response()->json([
                        'success' => false,
                        'message' => 'Sudah ada catatan lain pada tanggal tersebut.',
                        'errors' => [
                            'note_date' => ['Tanggal ini sudah dipakai catatan lain untuk anak yang sama.'],
                        ],
                    ], 422);
                }
            }

            $isiError = $this->assertHasContent([
                'demam' => $validated['demam'] ?? $note->demam,
                'rewel' => $validated['rewel'] ?? $note->rewel,
                'diare' => $validated['diare'] ?? $note->diare,
                'catatan' => array_key_exists('catatan', $validated) ? $validated['catatan'] : $note->catatan,
            ]);

            if ($isiError !== null) {
                return $isiError;
            }

            if (array_key_exists('catatan', $validated)) {
                $validated['catatan'] = $this->normalizeCatatan($validated['catatan']);
            }

            $note->fill($validated)->save();

            return response()->json([
                'success' => true,
                'message' => 'Catatan keluhan berhasil diperbarui.',
                'data' => $this->presentNote($note->fresh()->load('kader:id,name')),
            ], 200);

        } catch (ValidationException $e) {
            return response()->json([
                'success' => false,
                'message' => 'Validasi gagal.',
                'errors' => $e->errors(),
            ], 422);
        } catch (QueryException $e) {
            if ($e->getCode() === '23505') {
                return response()->json([
                    'success' => false,
                    'message' => 'Sudah ada catatan lain pada tanggal tersebut.',
                    'errors' => [
                        'note_date' => ['Tanggal ini sudah dipakai catatan lain untuk anak yang sama.'],
                    ],
                ], 422);
            }

            if ($e->getCode() === '23514') {
                return $this->emptyContentError();
            }

            Log::error('Gagal memperbarui catatan keluhan: '.$e->getMessage(), [
                'user_id' => $user->id,
                'note_id' => $noteId,
                'exception' => $e,
            ]);

            return response()->json([
                'success' => false,
                'message' => 'Terjadi kesalahan server. Silakan coba lagi.',
                'errors' => null,
            ], 500);
        } catch (\Throwable $e) {
            Log::error('Gagal memperbarui catatan keluhan: '.$e->getMessage(), [
                'user_id' => $user->id,
                'note_id' => $noteId,
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
     * Membatalkan satu catatan keluhan (soft delete).
     *
     * Baris tidak dihapus fisik, hanya ditandai `deleted_at`, jadi riwayat
     * kesehatan anak tetap bisa diaudit. Setelah dibatalkan, tanggal yang sama
     * boleh dicatat ulang karena unique constraint-nya partial.
     */
    public function destroy(string $noteId)
    {
        $note = $this->findNote($noteId);

        if (! $note instanceof MedicalNote) {
            return $note;
        }

        $note->delete();

        return response()->json([
            'success' => true,
            'message' => 'Catatan keluhan berhasil dibatalkan.',
            'data' => ['id' => $note->id],
        ], 200);
    }

    // -----------------------------------------------------------------
    // Helper
    // -----------------------------------------------------------------

    /**
     * Memastikan ada isi yang berarti.
     *
     * Setara CHECK constraint `medical_notes_isi_check` di database, tapi
     * ditulis di PHP supaya kesalahannya muncul sebagai 422 yang bisa dibaca
     * kader, bukan 500 dari PostgreSQL. Kolom yang error dikembalikan sebagai
     * `errors` supaya Flutter bisa menyorot input yang salah.
     *
     * @param  array<string, mixed>  $data
     * @return JsonResponse|null null bila isi cukup
     */
    private function assertHasContent(array $data): ?JsonResponse
    {
        $adaKeluhan = (bool) ($data['demam'] ?? false)
            || (bool) ($data['rewel'] ?? false)
            || (bool) ($data['diare'] ?? false);

        $catatan = $data['catatan'] ?? null;
        $adaCatatan = is_string($catatan) && trim($catatan) !== '';

        if ($adaKeluhan || $adaCatatan) {
            return null;
        }

        return response()->json([
            'success' => false,
            'message' => 'Catatan keluhan masih kosong.',
            'errors' => [
                'demam' => ['Centang minimal satu keluhan, atau isi catatan.'],
            ],
        ], 422);
    }

    /** Bentuk respons 422 untuk catatan yang tidak berisi informasi apa pun. */
    private function emptyContentError(): JsonResponse
    {
        return response()->json([
            'success' => false,
            'message' => 'Catatan keluhan masih kosong.',
            'errors' => [
                'demam' => ['Centang minimal satu keluhan, atau isi catatan.'],
            ],
        ], 422);
    }

    /**
     * Memastikan penimbangan yang dilampirkan milik anak yang sama.
     *
     * Tanpa pemeriksaan ini, kader bisa menempelkan penimbangan anak lain ke
     * catatan anak ini tanpa error sama sekali - UUID-nya valid, relasinya
     * ada, hanya saja menunjuk ke anak yang berbeda.
     *
     * @return JsonResponse|null null bila tidak ada masalah
     */
    private function assertMeasurementBelongsToChild(?string $measurementId, ?Child $child): ?JsonResponse
    {
        if ($measurementId === null) {
            return null;
        }

        $measurement = Measurement::find($measurementId);

        // `Rule::exists` sudah lebih dulu menyaring id yang tidak dikenal,
        // jadi di sini yang mungkin adalah id milik anak lain.
        if ($measurement && $child && $measurement->child_id !== $child->id) {
            return response()->json([
                'success' => false,
                'message' => 'Penimbangan tidak sesuai.',
                'errors' => [
                    'measurement_id' => ['Penimbangan ini bukan milik anak tersebut.'],
                ],
            ], 422);
        }

        return null;
    }

    /**
     * Membersihkan `catatan`: `null` jadi `null`, spasi excess dibuang, dan
     * teks kosong jadi `null`.
     *
     * Ini penting karena CHECK constraint menolak `catatan` yang isinya
     * hanya spasi (`btrim(catatan) <> ''`). Tanpa normalisasi ini, kader yang
     * mengosongkan field lalu mengetuk spasi akan mendapat 500.
     */
    private function normalizeCatatan(?string $catatan): ?string
    {
        if ($catatan === null) {
            return null;
        }

        $bersih = trim($catatan);

        return $bersih === '' ? null : $bersih;
    }

    /**
     * Mencari anak sekaligus memeriksa otorisasi.
     *
     * Kolom `id` bertipe UUID, sehingga id yang bukan UUID ditolak lebih dulu -
     * jika tidak, PostgreSQL melempar error dan endpoint membalas 500.
     *
     * @return Child|JsonResponse
     */
    private function findAccessibleChild(string $childId, User $user, string $action)
    {
        $notFound = response()->json([
            'success' => false,
            'message' => 'Data balita tidak ditemukan.',
            'errors' => null,
        ], 404);

        if (! Str::isUuid($childId)) {
            return $notFound;
        }

        $child = Child::find($childId);

        if (! $child) {
            return $notFound;
        }

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
     * Mencari satu catatan keluhan.
     *
     * Route sudah dijaga middleware `kader`, jadi di sini tidak ada
     * pemeriksaan kepemilikan.
     *
     * @return MedicalNote|JsonResponse
     */
    private function findNote(string $noteId)
    {
        $notFound = response()->json([
            'success' => false,
            'message' => 'Catatan keluhan tidak ditemukan.',
            'errors' => null,
        ], 404);

        if (! Str::isUuid($noteId)) {
            return $notFound;
        }

        $note = MedicalNote::find($noteId);

        if (! $note) {
            return $notFound;
        }

        return $note;
    }

    /**
     * Bentuk satu catatan untuk respons API.
     *
     * `demam`/`rewel`/`diare` dikirim sebagai boolean sejati karena sudah di-cast
     * di model, jadi checkbox di Flutter langsung mengikuti. `keluhan` dan
     * `ringkasan` sengaja ikut dikirim supaya Kader dan Ibu menampilkan teks
     * yang sama dari sumber yang sama.
     */
    private function presentNote(MedicalNote $note): array
    {
        return [
            'id' => $note->id,
            'child_id' => $note->child_id,
            'measurement_id' => $note->measurement_id,
            'kader_id' => $note->kader_id,
            'kader' => $note->kader ? [
                'id' => $note->kader->id,
                'name' => $note->kader->name,
            ] : null,
            'note_date' => $note->note_date?->format('Y-m-d'),
            'demam' => (bool) $note->demam,
            'rewel' => (bool) $note->rewel,
            'diare' => (bool) $note->diare,
            'keluhan' => $note->keluhan_list,
            'catatan' => $note->catatan,
            'tindak_lanjut' => $note->tindak_lanjut,
            'ringkasan' => $note->ringkasan,
            'created_at' => $note->created_at?->toIso8601String(),
            'updated_at' => $note->updated_at?->toIso8601String(),
        ];
    }

    /**
     * Ringkasan jumlah untuk ditampilkan di header daftar.
     *
     * Mobile tidak perlu menghitung ulang dari daftar catatan, dan Ibu tetap
     * melihat angka yang sama dengan yang dilihat kader.
     */
    private function summarize(Collection $notes): array
    {
        return [
            'total' => $notes->count(),
            'demam' => $notes->where('demam', true)->count(),
            'rewel' => $notes->where('rewel', true)->count(),
            'diare' => $notes->where('diare', true)->count(),
            'perlu_rujuk' => $notes->where('tindak_lanjut', MedicalNote::TINDAK_LANJUT_RUJUK)->count(),
        ];
    }
}
