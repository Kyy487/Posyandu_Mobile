<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Child;
use App\Models\ImmunizationRecord;
use App\Models\ImmunizationType;
use App\Models\User;
use App\Services\ImmunizationChecklistService;
use Carbon\CarbonImmutable;
use Illuminate\Database\QueryException;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Pencatatan imunisasi anak.
 *
 * Endpoint yang tersedia:
 *  - `GET    /children/{child}/immunizations`        checklist (Ibu & Kader)
 *  - `GET    /immunization-types`                   master dosis (Ibu & Kader)
 *  - `POST   /kader/children/{child}/immunizations` catat suntikan (Kader)
 *  - `PATCH  /kader/immunizations/{record}`        koreksi suntikan (Kader)
 *  - `DELETE /kader/immunizations/{record}`        batalkan suntikan (Kader)
 *
 * Catatan desain penting:
 *  - Status `sudah`/`belum`/`terlambat` DI HITUNG di PHP
 *    (`ImmunizationChecklistService`), tidak disimpan di database.
 *  - Koreksi field biasa memakai PATCH. Dose tidak bisa dipindah lewat PATCH,
 *    jadi kasus "salah pilih dosis" ditangani DELETE (soft delete).
 *  - `assertDoseOrder` menjaga agar tanggal suntikan tidak lebih tua dari
 *    dosis sebelumnya pada vaksin yang sama.
 */
class ImmunizationController extends Controller
{
    public function __construct(private readonly ImmunizationChecklistService $checklist) {}

    /**
     * Checklist imunisasi untuk satu anak.
     *
     * Ibu hanya boleh melihat anaknya sendiri; Kader boleh melihat semua anak.
     */
    public function show(Request $request, string $childId)
    {
        $user = $request->user();

        $child = $this->findAccessibleChild($childId, $user, 'melihat');

        if (! $child instanceof Child) {
            return $child;
        }

        $checklist = $this->checklist->checklistFor($child);

        return response()->json([
            'success' => true,
            'message' => 'Checklist imunisasi berhasil diambil.',
            'data' => [
                'child' => [
                    'id' => $child->id,
                    'name' => $child->name,
                    // `Child` tidak punya cast date, jadi nilainya masih string
                    // dari PDO. `CarbonImmutable::parse` aman untuk keduanya
                    // (string maupun instance Carbon) tanpa harus mengubah
                    // serialisasi `Child` yang sudah dipakai dashboard Ibu.
                    'date_of_birth' => CarbonImmutable::parse($child->date_of_birth)->format('Y-m-d'),
                    'gender' => $child->gender,
                ],
                // Ringkasan supaya Flutter tidak perlu menghitung sendiri.
                'summary' => $this->summarize($checklist),
                'checklist' => $checklist,
            ],
        ], 200);
    }

    /**
     * Master seluruh dosis imunisasi yang tersedia.
     *
     * Endpoint terpisah dari checklist karena layar Kader butuh daftar lengkap
     * (untuk form pencatatan) walau anak yang dipilih belum punya catatan apa pun.
     */
    public function types()
    {
        $types = ImmunizationType::query()
            ->orderedForDosing()
            ->get(['id', 'code', 'name', 'dose_number', 'target_age_months', 'interval_months', 'notes']);

        return response()->json([
            'success' => true,
            'message' => 'Daftar jenis imunisasi berhasil diambil.',
            'data' => $types,
        ], 200);
    }

    /**
     * Mencatat suntikan baru untuk satu anak.
     *
     * Kader yang login otomatis menjadi pencatat (`kader_id`), jadi klien tidak
     * perlu mengirim field itu.
     */
    public function store(Request $request, string $childId)
    {
        $user = $request->user();

        $child = $this->findAccessibleChild($childId, $user, 'mencatat imunisasi');

        if (! $child instanceof Child) {
            return $child;
        }

        try {
            $validated = $request->validate([
                'immunization_type_id' => [
                    'required',
                    'uuid',
                    // Dipakai `Rule::exists` supaya dosis yang tidak dikenal
                    // ditolak sebagai 422, bukan jadi 500 dari PostgreSQL.
                    Rule::exists('immunization_types', 'id'),
                ],
                'date_given' => 'required|date_format:Y-m-d|before_or_equal:today',
                'batch_number' => 'nullable|string|max:60',
                'notes' => 'nullable|string|max:1000',
            ]);

            // Dosis yang sama tidak boleh dicatat dua kali untuk satu anak.
            // Dicek di sini agar pesannya ramah; unique constraint di database
            // tetap jadi penjaga terakhir bila ada dua kader yang mengetik
            // bersamaan.
            $already = ImmunizationRecord::where('child_id', $child->id)
                ->where('immunization_type_id', $validated['immunization_type_id'])
                ->exists();

            if ($already) {
                return response()->json([
                    'success' => false,
                    'message' => 'Imunisasi ini sudah tercatat untuk anak tersebut.',
                    'errors' => [
                        'immunization_type_id' => [
                            'Dosis ini sudah pernah dicatat. Koreksi tanggalnya lewat PATCH, jangan catat ulang.',
                        ],
                    ],
                ], 422);
            }

            // Tanggal harus masuk akal terhadap dosis tetangga: tidak boleh lebih
            // tua dari dosis sebelumnya, tidak boleh lebih baru dari dosis
            // berikutnya.
            $type = ImmunizationType::find($validated['immunization_type_id']);
            $orderError = $this->assertDoseOrder($child, $type, $validated['date_given']);

            if ($orderError !== null) {
                return $orderError;
            }

            $record = ImmunizationRecord::create([
                'child_id' => $child->id,
                'kader_id' => $user->id,
                'immunization_type_id' => $validated['immunization_type_id'],
                'date_given' => $validated['date_given'],
                'batch_number' => $validated['batch_number'] ?? null,
                'notes' => $validated['notes'] ?? null,
            ]);

            return response()->json([
                'success' => true,
                'message' => 'Data imunisasi berhasil dicatat.',
                'data' => $this->presentRecord($record->load('immunizationType')),
            ], 201);

        } catch (ValidationException $e) {
            return response()->json([
                'success' => false,
                'message' => 'Validasi gagal.',
                'errors' => $e->errors(),
            ], 422);
        } catch (QueryException $e) {
            // 23505 = unique_violation. Terjadi bila dua kader menyimpan
            // dosis yang sama pada anak yang sama hampir bersamaan.
            if ($e->getCode() === '23505') {
                return response()->json([
                    'success' => false,
                    'message' => 'Imunisasi ini sudah tercatat untuk anak tersebut.',
                    'errors' => [
                        'immunization_type_id' => ['Dosis ini sudah pernah dicatat untuk anak tersebut.'],
                    ],
                ], 422);
            }

            Log::error('Gagal menyimpan imunisasi: '.$e->getMessage(), [
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
            Log::error('Gagal menyimpan imunisasi: '.$e->getMessage(), [
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
     * Koreksi satu catatan suntikan.
     *
     * Partial update: hanya field yang dikirim yang berubah. Dosis
     * (`immunization_type_id`) SENGAJA tidak bisa diganti lewat endpoint ini -
     * memindahkan dosis berarti membatalkan satu dosis dan mencatat yang lain,
     * yang merupakan dua operasi berbeda di lapangan.
     */
    public function update(Request $request, string $recordId)
    {
        $user = $request->user();

        $record = $this->findRecord($recordId);

        if (! $record instanceof ImmunizationRecord) {
            return $record;
        }

        try {
            $validated = $request->validate([
                'date_given' => 'sometimes|required|date_format:Y-m-d|before_or_equal:today',
                'batch_number' => 'sometimes|nullable|string|max:60',
                'notes' => 'sometimes|nullable|string|max:1000',
            ]);

            if ($validated === []) {
                return response()->json([
                    'success' => false,
                    'message' => 'Tidak ada data yang diperbarui.',
                    'errors' => ['body' => ['Kirim minimal satu field untuk diperbarui.']],
                ], 422);
            }

            // PATCH tanggal harus tetap menjaga urutan dosis. Kalau tidak
            // diperiksa di sini, validasi `store` bisa dilewati: catat dosis 1
            // dan 2 dengan urutan benar, lalu ubah tanggal dosis 1 ke belakang.
            $orderError = $this->assertDoseOrder(
                $record->child,
                $record->immunizationType,
                $validated['date_given'] ?? $record->date_given->format('Y-m-d'),
                $record->id,
            );

            if ($orderError !== null) {
                return $orderError;
            }

            $record->fill($validated)->save();

            return response()->json([
                'success' => true,
                'message' => 'Data imunisasi berhasil diperbarui.',
                'data' => $this->presentRecord($record->fresh()->load('immunizationType')),
            ], 200);

        } catch (ValidationException $e) {
            return response()->json([
                'success' => false,
                'message' => 'Validasi gagal.',
                'errors' => $e->errors(),
            ], 422);
        } catch (\Throwable $e) {
            Log::error('Gagal memperbarui imunisasi: '.$e->getMessage(), [
                'user_id' => $user->id,
                'record_id' => $recordId,
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
     * Membatalkan satu catatan suntikan (soft delete).
     *
     * Endpoint ini menutup kasus yang tidak bisa ditangani PATCH: kader salah
     * memilih dosis. `PATCH` sengaja tidak bisa memindahkan
     * `immunization_type_id`, jadi tanpa endpoint ini salah pilihan itu permanen.
     *
     * Baris tidak dihapus fisik, hanya ditandai `deleted_at`, jadi riwayat
     * kesehatan anak tetap bisa diaudit. Setelah dibatalkan, dosis yang sama
     * boleh dicatat ulang karena unique constraint-nya partial.
     */
    public function destroy(string $recordId)
    {
        $record = $this->findRecord($recordId);

        if (! $record instanceof ImmunizationRecord) {
            return $record;
        }

        $record->delete();

        return response()->json([
            'success' => true,
            'message' => 'Catatan imunisasi berhasil dibatalkan.',
            'data' => ['id' => $record->id],
        ], 200);
    }

    // -----------------------------------------------------------------
    // Helper
    // -----------------------------------------------------------------

    /**
     * Memastikan tanggal suntikan masuk akal terhadap dosis tetangganya.
     *
     * Aturan: dosis N tidak boleh lebih tua dari dosis N-1 pada vaksin yang
     * sama, dan tidak boleh lebih baru dari dosis N+1.
     *
     * Hanya dosis tetangga yang SUDAH tercatat yang dibandingkan. Dosis yang
     * belum ada record-nya tidak menghalangi: anak bisa saja datang dengan
     * dosis 2 tanpa dose 1 di sistem ini, misalnya karena dosis 1 diberikan di
     * fasilitas lain. Menolak kasus seperti itu akan menghambat pekerjaan
     * lapangan tanpa benefit.
     *
     * @return Response|null null bila tidak ada pelanggaran
     */
    private function assertDoseOrder(
        ?Child $child,
        ?ImmunizationType $type,
        string $dateGiven,
        ?string $ignoreRecordId = null,
    ) {
        if (! $child || ! $type) {
            return null;
        }

        // `label` sengaja tidak ikut: itu accessor (`getLabelAttribute`),
        // bukan kolom di database. Meminta kolom yang tidak ada akan
        // PostgreSQL melempar 42703 dan jadi 500.
        $tetangga = ImmunizationType::where('code', $type->code)
            ->whereIn('dose_number', [(int) $type->dose_number - 1, (int) $type->dose_number + 1])
            ->get(['id', 'code', 'name', 'dose_number']);

        if ($tetangga->isEmpty()) {
            return null;
        }

        $records = ImmunizationRecord::where('child_id', $child->id)
            ->whereIn('immunization_type_id', $tetangga->pluck('id'))
            ->when($ignoreRecordId !== null, fn ($q) => $q->where('id', '!=', $ignoreRecordId))
            ->get(['immunization_type_id', 'date_given']);

        foreach ($records as $record) {
            $tetanggaType = $tetangga->firstWhere('id', $record->immunization_type_id);
            $sebelum = (int) $tetanggaType->dose_number < (int) $type->dose_number;
            $tanggalTetangga = $record->date_given->format('Y-m-d');

            // Tanggal suntikan tidak boleh mendahului dosis sebelumnya.
            if ($sebelum && $tanggalTetangga > $dateGiven) {
                return $this->doseOrderError(
                    "Tanggal suntikan tidak boleh lebih awal dari {$tetanggaType->label} "
                    ."yang tercatat pada {$tanggalTetangga}."
                );
            }

            // Maupun mendahului dosis berikutnya.
            if (! $sebelum && $tanggalTetangga < $dateGiven) {
                return $this->doseOrderError(
                    "Tanggal suntikan tidak boleh lebih baru dari {$tetanggaType->label} "
                    ."yang tercatat pada {$tanggalTetangga}."
                );
            }
        }

        return null;
    }

    /** Bentuk respons 422 untuk pelanggaran urutan dosis. */
    private function doseOrderError(string $reason)
    {
        return response()->json([
            'success' => false,
            'message' => 'Validasi gagal.',
            'errors' => ['date_given' => [$reason]],
        ], 422);
    }

    /**
     * Mencari anak sekaligus memeriksa otorisasi.
     *
     * Kolom `id` bertipe UUID, sehingga id yang bukan UUID ditolak lebih dulu -
     * jika tidak, PostgreSQL melempar error dan endpoint membalas 500.
     *
     * @return Child|Response
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
     * Mencari satu record imunisasi.
     *
     * Route sudah dijaga middleware `kader`, jadi di sini tidak ada OwnershipException.
     *
     * @return ImmunizationRecord|Response
     */
    private function findRecord(string $recordId)
    {
        $notFound = response()->json([
            'success' => false,
            'message' => 'Data imunisasi tidak ditemukan.',
            'errors' => null,
        ], 404);

        if (! Str::isUuid($recordId)) {
            return $notFound;
        }

        $record = ImmunizationRecord::with('immunizationType')->find($recordId);

        if (! $record) {
            return $notFound;
        }

        return $record;
    }

    /**
     * Bentuk record untuk respons API: tanggal sudah `Y-m-d`, dan nama dosis
     * ikut dikirim supaya mobile tidak perlu lookup terpisah.
     */
    private function presentRecord(ImmunizationRecord $record): array
    {
        $type = $record->immunizationType;

        return [
            'id' => $record->id,
            'child_id' => $record->child_id,
            'kader_id' => $record->kader_id,
            'immunization_type_id' => $record->immunization_type_id,
            'date_given' => $record->date_given?->format('Y-m-d'),
            'batch_number' => $record->batch_number,
            'notes' => $record->notes,
            'immunization_type' => $type ? [
                'id' => $type->id,
                'code' => $type->code,
                'name' => $type->name,
                'dose_number' => (int) $type->dose_number,
                'label' => $type->label,
            ] : null,
            'created_at' => $record->created_at?->toIso8601String(),
            'updated_at' => $record->updated_at?->toIso8601String(),
        ];
    }

    /**
     * Ringkasan jumlah status untuk ditampilkan di header checklist.
     */
    private function summarize(array $checklist): array
    {
        $summary = [
            ImmunizationType::STATUS_DONE => 0,
            ImmunizationType::STATUS_PENDING => 0,
            ImmunizationType::STATUS_OVERDUE => 0,
            'total' => count($checklist),
        ];

        foreach ($checklist as $item) {
            $summary[$item['status']]++;
        }

        return $summary;
    }
}
