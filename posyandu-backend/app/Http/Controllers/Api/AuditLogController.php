<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

/**
 * Daftar riwayat audit (siapa mengubah apa dan kapan).
 *
 * Hanya Kader yang boleh membaca riwayat ini karena isinya bisa mengungkap
 * jadwal kerja orang lain, siapa yang mencatat apa, dan - untuk entitas anak -
 * data klinis. Ibu tidak boleh.
 */
class AuditLogController extends Controller
{
    /**
     * @return JsonResponse
     */
    public function index(Request $request)
    {
        try {
            $validated = $request->validate([
                'auditable_type' => ['nullable', 'string', 'max:255'],
                'auditable_id' => ['nullable', 'uuid'],
                'event' => ['nullable', 'string', 'in:created,updated,deleted,restored'],
            ]);

            // `with` sekaligus untuk menghindari N+1: nama pelaku dipakai di
            // hampir setiap baris yang dilihat kader. `select` memastikan field
            // sensitif tidak ikut terkirim walau model User berubah.
            $riwayat = AuditLog::query()
                ->with('actor:id,name')
                ->when($validated['auditable_type'] ?? null, fn ($q, $type) => $q->where('auditable_type', $type))
                ->when($validated['auditable_id'] ?? null, fn ($q, $id) => $q->where('auditable_id', $id))
                ->when($validated['event'] ?? null, fn ($q, $event) => $q->where('event', $event))
                ->orderByDesc('created_at')
                ->orderByDesc('id')
                ->get();

            return response()->json([
                'success' => true,
                'message' => 'Riwayat audit berhasil diambil.',
                'data' => $riwayat->map(fn (AuditLog $log) => [
                    'id' => $log->id,
                    'auditable_type' => $log->auditable_type,
                    'auditable_id' => $log->auditable_id,
                    'event' => $log->event,
                    'actor' => $log->actor,
                    'old_values' => $log->old_values,
                    'new_values' => $log->new_values,
                    'ip_address' => $log->ip_address,
                    'created_at' => $log->created_at?->toISOString(),
                ]),
            ], 200);

        } catch (\Throwable $e) {
            Log::error('Gagal mengambil riwayat audit: '.$e->getMessage(), [
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
