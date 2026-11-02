<?php

namespace App\Services;

use App\Models\Child;
use App\Models\ImmunizationRecord;
use App\Models\Measurement;
use App\Models\Visit;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Adapter untuk integrasi SATUSEHAT FHIR R4.
 *
 * Dua peran:
 *  1. Mapper — mengubah model lokal menjadi array FHIR R4 yang siap dikirim.
 *  2. Kirim — meneruskan payload ke endpoint SATUSEHAT.
 *
 * Selama kredensial SATUSEHAT belum diisi di .env, `sendToSatusehat()` hanya
 * mencatat payload ke `storage/logs/satusehat.log`. Begitu `SATUSEHAT_CLIENT_ID`
 * dan `SATUSEHAT_CLIENT_SECRET` diisi, method yang sama yang benar-benar
 * menembak API — tidak ada kode lain yang perlu diubah.
 */
class SatusehatFhirService
{
    /**
     * Kirim resource FHIR ke SATUSEHAT.
     *
     * Bila kredensial belum diisi, payload hanya dicatat ke log. Ini membuktikan
     * sistem sudah memproduksi data FHIR-compliant yang siap tembak.
     *
     * @param  array<string, mixed>  $payload
     */
    public function sendToSatusehat(string $resourceType, array $payload): array
    {
        $clientId = config('services.satusehat.client_id');
        $clientSecret = config('services.satusehat.client_secret');

        if (empty($clientId) || empty($clientSecret)) {
            Log::channel('satusehat')->info('SATUSEHAT_FHIR_PAYLOAD', [
                'resourceType' => $resourceType,
                'payload' => $payload,
            ]);

            return [
                'sent' => false,
                'reason' => 'Kredensial SATUSEHAT belum diisi di .env.',
                'resourceType' => $resourceType,
            ];
        }

        $token = $this->accessToken();

        $response = Http::withToken($token)
            ->acceptJson()
            ->post(
                config('services.satusehat.base_url').'/'.$resourceType,
                $payload,
            );

        return [
            'sent' => true,
            'status' => $response->status(),
            'body' => $response->json(),
        ];
    }

    /**
     * Ambil access token OAuth2 dari SATUSEHAT.
     */
    private function accessToken(): string
    {
        $response = Http::asForm()->post(
            config('services.satusehat.auth_url'),
            [
                'grant_type' => 'client_credentials',
                'client_id' => config('services.satusehat.client_id'),
                'client_secret' => config('services.satusehat.client_secret'),
            ],
        );

        return $response->json('access_token', '');
    }

    /**
     * @return array<string, mixed>
     */
    public function formatPatient(Child $child): array
    {
        return [
            'resourceType' => 'Patient',
            'identifier' => $child->nik ? [
                [
                    'system' => 'http://sys-ids.kemkes.go.id/pasien',
                    'use' => 'official',
                    'value' => $child->nik,
                ],
            ] : [],
            'active' => true,
            'name' => [
                ['use' => 'official', 'text' => $child->name],
            ],
            'gender' => match ($child->gender) {
                'L' => 'male',
                'P' => 'female',
                default => 'unknown',
            },
            'birthDate' => $child->date_of_birth ? Carbon::parse($child->date_of_birth)->toDateString() : null,
        ];
    }

    /**
     * @return array<string, mixed>
     */
    public function formatEncounter(Visit $visit): array
    {
        return [
            'resourceType' => 'Encounter',
            'identifier' => [
                [
                    'system' => 'http://sys-ids.kemkes.go.id/encounter/'.config('services.satusehat.org_id'),
                    'use' => 'official',
                    'value' => (string) $visit->id,
                ],
            ],
            'status' => 'finished',
            'class' => [
                'system' => 'http://terminology.hl7.org/CodeSystem/v3-ActCode',
                'code' => 'AMB',
                'display' => 'ambulatory',
            ],
            'subject' => [
                'reference' => 'Patient/'.optional($visit->child)->nik,
                'display' => optional($visit->child)->name,
            ],
            'period' => [
                'start' => optional($visit->visit_date)->toDateTimeString(),
            ],
        ];
    }

    /**
     * @return array<string, mixed>
     */
    public function formatObservation(Measurement $measurement): array
    {
        return [
            'resourceType' => 'Observation',
            'status' => 'final',
            'code' => [
                'coding' => [
                    [
                        'system' => 'http://loinc.org',
                        'code' => '8302-2',
                        'display' => 'Body height',
                    ],
                ],
            ],
            'subject' => [
                'reference' => 'Patient/'.optional($measurement->child)->nik,
            ],
            'encounter' => [
                'reference' => 'Encounter/'.optional($measurement->visit)->id,
            ],
            'effectiveDateTime' => optional($measurement->measurement_date)->toDateTimeString(),
            'valueQuantity' => [
                'value' => $measurement->height_cm,
                'unit' => 'cm',
                'system' => 'http://unitsofmeasure.org',
                'code' => 'cm',
            ],
        ];
    }

    /**
     * @return array<string, mixed>
     */
    public function formatImmunization(ImmunizationRecord $record): array
    {
        $type = $record->immunizationType;

        return [
            'resourceType' => 'Immunization',
            'identifier' => [
                [
                    'system' => 'http://sys-ids.kemkes.go.id/immunization/'.config('services.satusehat.org_id'),
                    'use' => 'official',
                    'value' => (string) $record->id,
                ],
            ],
            'status' => 'completed',
            'vaccineCode' => [
                'coding' => [
                    [
                        'system' => 'http://hl7.org/fhir/sid/cvx',
                        'code' => $type?->code,
                        'display' => $type?->name,
                    ],
                ],
            ],
            'patient' => [
                'reference' => 'Patient/'.optional($record->child)->nik,
                'display' => optional($record->child)->name,
            ],
            'encounter' => [
                'reference' => 'Encounter/'.optional($record->visit)->id,
            ],
            'occurrenceDateTime' => optional($record->date_given)->toDateTimeString(),
            'lotNumber' => $record->batch_number,
            'primarySource' => true,
        ];
    }
}
