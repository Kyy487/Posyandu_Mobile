<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Child;
use App\Models\ImmunizationRecord;
use App\Models\Measurement;
use App\Models\Visit;
use App\Services\SatusehatFhirService;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Log;

/**
 * Endpoint FHIR R4 — jembatan menuju integrasi SATUSEHAT.
 *
 * Endpoint ini mengembalikan data lokal dalam format FHIR R4 sehingga bisa
 * langsung dikirim ke SATUSEHAT. Selama kredensial belum diisi, data hanya
 * bisa dibaca (belum dikirim). Lihat `SatusehatFhirService` untuk mapper
 * dan log pengiriman.
 */
class FhirController extends Controller
{
    public function __construct(
        private readonly SatusehatFhirService $satusehat,
    ) {}

    public function show(string $resourceType, string $id): JsonResponse
    {
        $match = match ($resourceType) {
            'Patient' => fn () => Child::query()->find($id),
            'Encounter' => fn () => Visit::query()->find($id),
            'Observation' => fn () => Measurement::query()->find($id),
            'Immunization' => fn () => ImmunizationRecord::query()->find($id),
            default => null,
        };

        if (! $match) {
            return response()->json([
                'success' => false,
                'message' => 'Resource type tidak didukung.',
                'errors' => ['resourceType' => ['Tipe resource tidak dikenal.']],
            ], 422);
        }

        $model = $match();

        if (! $model) {
            return response()->json([
                'success' => false,
                'message' => 'Data tidak ditemukan.',
                'errors' => null,
            ], 404);
        }

        $resource = match ($resourceType) {
            'Patient' => $this->satusehat->formatPatient($model),
            'Encounter' => $this->satusehat->formatEncounter($model),
            'Observation' => $this->satusehat->formatObservation($model),
            'Immunization' => $this->satusehat->formatImmunization($model),
        };

        return response()->json($resource, 200);
    }

    /**
     * Kirim resource ke SATUSEHAT (atau log saja bila kredensial belum diisi).
     */
    public function send(string $resourceType, string $id): JsonResponse
    {
        $model = match ($resourceType) {
            'Patient' => Child::query()->find($id),
            'Encounter' => Visit::query()->find($id),
            'Observation' => Measurement::query()->find($id),
            'Immunization' => ImmunizationRecord::query()->find($id),
            default => null,
        };

        if (! $model) {
            return response()->json([
                'success' => false,
                'message' => 'Data tidak ditemukan.',
                'errors' => null,
            ], 404);
        }

        $payload = match ($resourceType) {
            'Patient' => $this->satusehat->formatPatient($model),
            'Encounter' => $this->satusehat->formatEncounter($model),
            'Observation' => $this->satusehat->formatObservation($model),
            'Immunization' => $this->satusehat->formatImmunization($model),
        };

        $hasil = $this->satusehat->sendToSatusehat($resourceType, $payload);

        if (! $hasil['sent']) {
            Log::channel('satusehat')->info('Kirim FHIR belum aktif: '.$hasil['reason']);

            return response()->json([
                'success' => true,
                'message' => 'Data FHIR siap dikirim. Kredensial SATUSEHAT belum diisi — payload hanya dicatat.',
                'data' => $payload,
            ], 200);
        }

        return response()->json([
            'success' => true,
            'message' => 'Data terkirim ke SATUSEHAT.',
            'data' => $hasil,
        ], 200);
    }
}
