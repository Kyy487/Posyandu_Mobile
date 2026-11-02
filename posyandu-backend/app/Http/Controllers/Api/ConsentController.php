<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Child;
use App\Models\Consent;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

class ConsentController extends Controller
{
    /**
     * Tipe consent yang diakui (UU PDP No. 27/2022).
     */
    private const CONSENT_TYPES = ['data_processing', 'data_sharing', 'research'];

    /**
     * Menampilkan consent aktif untuk satu anak.
     *
     * Ibu hanya boleh melihat anaknya sendiri; Kader boleh melihat semua anak,
     * sama seperti `GET /children/{id}/medical-notes`.
     */
    public function show(Request $request, string $childId): JsonResponse
    {
        $user = $request->user();

        $child = $this->findAccessibleChild($childId, $user, 'melihat', allowKader: true);

        if (! $child instanceof Child) {
            return $child;
        }

        $consents = $child->consents()
            ->whereNull('revoked_at')
            ->orderBy('consent_type')
            ->get();

        return response()->json([
            'success' => true,
            'message' => 'Data consent berhasil diambil.',
            'data' => $consents
                ->map(fn (Consent $consent) => $this->presentConsent($consent))
                ->all(),
        ], 200);
    }

    /**
     * Memberikan (atau memberikan ulang) consent untuk satu anak.
     *
     * Hanya Ibu/wali pemilik anak yang boleh memberikan consent; Kader ditolak
     * agar persetujuan tetap berasal dari pihak yang berhak.
     */
    public function store(Request $request, string $childId): JsonResponse
    {
        $user = $request->user();

        $child = $this->findAccessibleChild($childId, $user, 'memberikan persetujuan untuk', allowKader: false);

        if (! $child instanceof Child) {
            return $child;
        }

        $validator = Validator::make($request->all(), [
            'consent_type' => ['required', 'string', Rule::in(self::CONSENT_TYPES)],
            'document_version' => ['required', 'string', 'max:20'],
            'notes' => ['nullable', 'string', 'max:500'],
        ]);

        if ($validator->fails()) {
            return $this->validationFailed($validator->errors()->toArray());
        }

        $consentType = $request->string('consent_type')->toString();
        $documentVersion = $request->string('document_version')->toString();
        $notes = $request->input('notes');

        try {
            $existing = $child->consents()
                ->where('consent_type', $consentType)
                ->first();

            if ($existing && $existing->revoked_at === null) {
                return response()->json([
                    'success' => false,
                    'message' => 'Consent untuk tipe ini sudah pernah diberikan.',
                    'errors' => null,
                ], 409);
            }

            $attributes = [
                'granted_by' => $user->id,
                'granted_at' => now(),
                'revoked_at' => null,
                'document_version' => $documentVersion,
                'notes' => $notes,
            ];

            if ($existing) {
                $existing->update($attributes);
                $consent = $existing->refresh();
                $status = 200;
                $message = 'Consent berhasil diberikan ulang.';
            } else {
                $consent = Consent::create($attributes + [
                    'child_id' => $child->id,
                    'consent_type' => $consentType,
                ]);
                $status = 201;
                $message = 'Consent berhasil dicatat.';
            }

            return response()->json([
                'success' => true,
                'message' => $message,
                'data' => $this->presentConsent($consent),
            ], $status);
        } catch (\Throwable $e) {
            Log::error('Gagal mencatat consent: '.$e->getMessage(), [
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
     * Mencabut consent yang sudah diberikan.
     *
     * Pencabutan mengisi `revoked_at` (bukan menghapus baris) supaya jejak
     * persetujuan tetap tersimpan. Hanya Ibu/wali pemilik anak yang boleh.
     */
    public function destroy(Request $request, string $childId): JsonResponse
    {
        $user = $request->user();

        $child = $this->findAccessibleChild($childId, $user, 'mencabut persetujuan untuk', allowKader: false);

        if (! $child instanceof Child) {
            return $child;
        }

        $validator = Validator::make($request->all(), [
            'consent_type' => ['required', 'string', Rule::in(self::CONSENT_TYPES)],
        ]);

        if ($validator->fails()) {
            return $this->validationFailed($validator->errors()->toArray());
        }

        $consentType = $request->string('consent_type')->toString();

        try {
            $consent = $child->consents()
                ->where('consent_type', $consentType)
                ->whereNull('revoked_at')
                ->first();

            if (! $consent) {
                return response()->json([
                    'success' => false,
                    'message' => 'Consent aktif tidak ditemukan.',
                    'errors' => null,
                ], 404);
            }

            $consent->update(['revoked_at' => now()]);

            return response()->json([
                'success' => true,
                'message' => 'Consent berhasil dicabut.',
                'data' => $this->presentConsent($consent->refresh()),
            ], 200);
        } catch (\Throwable $e) {
            Log::error('Gagal mencabut consent: '.$e->getMessage(), [
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
     * Mencari anak yang boleh diakses pengguna.
     *
     * Ibu hanya boleh mengakses anaknya sendiri; Kader boleh semua anak bila
     * `$allowKader` benar. Mengembalikan `Child` atau `JsonResponse` (404/403).
     */
    private function findAccessibleChild(string $childId, User $user, string $action, bool $allowKader = true)
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

        $isOwner = $child->user_id === $user->id;
        $isAllowedKader = $allowKader && $user->role === 'kader';

        if (! $isOwner && ! $isAllowedKader) {
            return response()->json([
                'success' => false,
                'message' => "Akses ditolak. Anda tidak berhak {$action} data anak ini.",
                'errors' => null,
            ], 403);
        }

        return $child;
    }

    /**
     * Bentuk satu consent untuk respons API.
     *
     * @return array<string, mixed>
     */
    private function presentConsent(Consent $consent): array
    {
        return [
            'id' => $consent->id,
            'child_id' => $consent->child_id,
            'granted_by' => $consent->granted_by,
            'consent_type' => $consent->consent_type,
            'granted_at' => $consent->granted_at?->toIso8601String(),
            'revoked_at' => $consent->revoked_at?->toIso8601String(),
            'document_version' => $consent->document_version,
            'notes' => $consent->notes,
            'created_at' => $consent->created_at?->toIso8601String(),
            'updated_at' => $consent->updated_at?->toIso8601String(),
        ];
    }

    /**
     * @param  array<string, array<int, string>>  $errors
     */
    private function validationFailed(array $errors): JsonResponse
    {
        return response()->json([
            'success' => false,
            'message' => 'Validasi gagal.',
            'errors' => $errors,
        ], 422);
    }
}
