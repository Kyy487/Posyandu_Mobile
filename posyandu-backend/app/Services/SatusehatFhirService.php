<?php

namespace App\Services;

use App\Models\Child;
use App\Models\ImmunizationRecord;
use App\Models\Measurement;
use App\Models\Visit;
use App\Support\FhirDateTime;
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
        $payload = [
            'resourceType' => 'Patient',
            'identifier' => $child->nik ? [
                [
                    'system' => 'https://fhir.kemkes.go.id/id/nik',
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
            'birthDate' => $child->date_of_birth
                ? Carbon::parse($child->date_of_birth)->toDateString()
                : null,
        ];

        if ($child->ihs_number !== null && $child->ihs_number !== '') {
            $payload['id'] = $child->ihs_number;
        }

        return $payload;
    }

    /**
     * @return array<string, mixed>
     */
    public function formatEncounter(Visit $visit): array
    {
        $patientReference = $this->patientReference($visit->child);
        $organizationId = (string) config('services.satusehat.org_id');

        $payload = [
            'resourceType' => 'Encounter',
            'identifier' => [
                [
                    'system' => 'http://sys-ids.kemkes.go.id/encounter/'.$organizationId,
                    'use' => 'official',
                    'value' => (string) $visit->id,
                ],
            ],
            'status' => $visit->visit_ended_at ? 'finished' : 'in-progress',
            'class' => [
                'system' => 'http://terminology.hl7.org/CodeSystem/v3-ActCode',
                'code' => 'AMB',
                'display' => 'ambulatory',
            ],
            'subject' => [
                'reference' => $patientReference,
                'display' => $visit->child?->name,
            ],
            'period' => [
                'start' => FhirDateTime::fromDateTime($visit->visit_started_at)
                    ?? FhirDateTime::fromDate($visit->visit_date?->toDateString()),
            ],
        ];

        if ($visit->visit_ended_at) {
            $payload['period']['end'] = FhirDateTime::fromDateTime($visit->visit_ended_at);
        }

        if ($organizationId !== '') {
            $payload['serviceProvider'] = [
                'reference' => 'Organization/'.$organizationId,
            ];
        }

        return $payload;
    }

    /**
     * Draft Observation lama: tetap satu resource tinggi badan agar endpoint
     * yang sudah dipakai tidak berubah.
     *
     * @return array<string, mixed>
     */
    public function formatObservation(Measurement $measurement): array
    {
        return $this->observationResource(
            $measurement,
            '8302-2',
            'Body height',
            $measurement->height_cm,
            'cm',
        );
    }

    /**
     * Satu penimbangan menghasilkan beberapa Observation.
     *
     * Endpoint lama tetap mengembalikan tinggi badan saja. Bundle ini memuat
     * semua nilai yang tersedia: berat, tinggi, lingkar kepala, dan IMT.
     *
     * @return array<string, mixed>
     */
    public function formatObservationBundle(Measurement $measurement): array
    {
        $components = [
            ['8302-2', 'Body height', $measurement->height_cm, 'cm'],
            ['29463-7', 'Body weight', $measurement->weight_kg, 'kg'],
            ['9843-4', 'Head circumference', $measurement->head_circumference_cm, 'cm'],
        ];

        $bmi = $this->bodyMassIndex($measurement);

        if ($bmi !== null) {
            $components[] = ['39156-5', 'Body mass index', $bmi, 'kg/m2'];
        }

        $entries = [];

        foreach ($components as [$code, $display, $value, $unit]) {
            if ($value === null || $value === '') {
                continue;
            }

            $entries[] = [
                'resource' => $this->observationResource($measurement, $code, $display, $value, $unit),
            ];
        }

        return [
            'resourceType' => 'Bundle',
            'type' => 'collection',
            'entry' => $entries,
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function observationResource(
        Measurement $measurement,
        string $code,
        string $display,
        mixed $value,
        string $unit,
    ): array {
        return [
            'resourceType' => 'Observation',
            'status' => 'final',
            'code' => [
                'coding' => [
                    [
                        'system' => 'http://loinc.org',
                        'code' => $code,
                        'display' => $display,
                    ],
                ],
            ],
            'subject' => [
                'reference' => $this->patientReference($measurement->child),
            ],
            'encounter' => [
                'reference' => 'Encounter/'.optional($measurement->visit)->id,
            ],
            'effectiveDateTime' => FhirDateTime::fromDateTime($measurement->measured_at)
                ?? FhirDateTime::fromDate($measurement->measurement_date),
            'valueQuantity' => [
                'value' => $value,
                'unit' => $unit,
                'system' => 'http://unitsofmeasure.org',
                'code' => $unit,
            ],
        ];
    }

    private function bodyMassIndex(Measurement $measurement): ?float
    {
        $weight = (float) $measurement->weight_kg;
        $height = (float) $measurement->height_cm;

        if ($weight <= 0 || $height <= 0) {
            return null;
        }

        return round($weight / (($height / 100) ** 2), 2);
    }

    /**
     * @return array<string, mixed>
     */
    public function formatImmunization(ImmunizationRecord $record): array
    {
        $type = $record->immunizationType;
        $coding = [];

        if ($type?->kfa_code) {
            $coding[] = [
                'system' => 'http://sys-ids.kemkes.go.id/kfa',
                'code' => $type->kfa_code,
                'display' => $type->name,
            ];
        }

        if ($type?->cvx_code) {
            $coding[] = [
                'system' => 'http://hl7.org/fhir/sid/cvx',
                'code' => $type->cvx_code,
                'display' => $type->cvx_display ?? $type->name,
            ];
        }

        $vaccineCode = $coding === []
            ? ['text' => $type?->name]
            : ['coding' => $coding];

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
            'vaccineCode' => $vaccineCode,
            'patient' => [
                'reference' => $this->patientReference($record->child),
                'display' => $record->child?->name,
            ],
            'encounter' => [
                'reference' => 'Encounter/'.optional($record->visit)->id,
            ],
            'occurrenceDateTime' => FhirDateTime::fromDate(
                $record->date_given?->toDateString()
            ),
            'lotNumber' => $record->batch_number,
            'primarySource' => true,
        ];
    }

    /**
     * Referensi FHIR selalu memakai IHS, bukan NIK.
     */
    private function patientReference(?Child $child): string
    {
        return 'Patient/'.($child?->ihs_number ?? '');
    }

    /**
     * Validasi payload sebelum dikirim.
     *
     * Endpoint baca tetap mengembalikan draft. Validator ini yang memberi tahu
     * bagian mana yang belum lengkap, terutama IHS yang masih kosong.
     *
     * @param  array<string, mixed>  $payload
     * @return array{valid: bool, errors: list<string>, warnings: list<string>, payload: array<string, mixed>}
     */
    public function validatePayload(string $resourceType, array $payload): array
    {
        $errors = [];
        $warnings = [];

        $reference = (string) data_get($payload, 'subject.reference', '');

        if ($resourceType === 'Patient') {
            $reference = 'Patient/'.($payload['id'] ?? '');
        }

        if ($reference === 'Patient/') {
            $errors[] = 'IHS number anak belum diisi; resource belum dapat dikirim.';
        }

        match ($resourceType) {
            'Patient' => $this->validatePatient($payload, $errors),
            'Encounter' => $this->validateEncounter($payload, $errors, $warnings),
            'Observation' => $this->validateObservation($payload, $errors),
            'Bundle' => $this->validateObservationBundle($payload, $errors),
            'Immunization' => $this->validateImmunization($payload, $errors),
            default => $errors[] = 'Resource type tidak didukung.',
        };

        return [
            'valid' => $errors === [],
            'errors' => array_values(array_unique($errors)),
            'warnings' => array_values(array_unique($warnings)),
            'payload' => $payload,
        ];
    }

    /**
     * @param  array<string, mixed>  $payload
     * @param  list<string>  $errors
     */
    private function validatePatient(array $payload, array &$errors): void
    {
        if (empty($payload['id'])) {
            $errors[] = 'Patient.id (IHS number) wajib ada.';
        }

        if (empty($payload['identifier'])) {
            $errors[] = 'Patient.identifier (NIK) wajib ada.';
        }

        if (empty($payload['name'])) {
            $errors[] = 'Patient.name wajib ada.';
        }

        if (empty($payload['birthDate'])) {
            $errors[] = 'Patient.birthDate wajib ada.';
        }
    }

    /**
     * @param  array<string, mixed>  $payload
     * @param  list<string>  $errors
     * @param  list<string>  $warnings
     */
    private function validateEncounter(array $payload, array &$errors, array &$warnings): void
    {
        if (empty(data_get($payload, 'subject.reference'))
            || data_get($payload, 'subject.reference') === 'Patient/') {
            $errors[] = 'Encounter.subject.reference wajib memakai Patient/{ihs_number}.';
        }

        if (empty(data_get($payload, 'period.start'))) {
            $errors[] = 'Encounter.period.start wajib ada.';
        }

        if (empty($payload['serviceProvider'])) {
            $warnings[] = 'Encounter.serviceProvider belum diisi (SATUSEHAT_ORG_ID kosong).';
        }
    }

    /**
     * @param  array<string, mixed>  $payload
     * @param  list<string>  $errors
     */
    private function validateObservation(array $payload, array &$errors): void
    {
        if (empty(data_get($payload, 'subject.reference'))
            || data_get($payload, 'subject.reference') === 'Patient/') {
            $errors[] = 'Observation.subject.reference wajib memakai Patient/{ihs_number}.';
        }

        if (empty(data_get($payload, 'encounter.reference'))
            || data_get($payload, 'encounter.reference') === 'Encounter/') {
            $errors[] = 'Observation.encounter.reference wajib ada.';
        }

        if (empty($payload['effectiveDateTime'])) {
            $errors[] = 'Observation.effectiveDateTime wajib ada.';
        }

        if (empty(data_get($payload, 'valueQuantity.value'))
            || empty(data_get($payload, 'valueQuantity.code'))) {
            $errors[] = 'Observation.valueQuantity wajib berisi nilai dan unit UCUM.';
        }
    }

    /**
     * @param  array<string, mixed>  $payload
     * @param  list<string>  $errors
     */
    private function validateObservationBundle(array $payload, array &$errors): void
    {
        $entries = $payload['entry'] ?? [];

        if (! is_array($entries) || $entries === []) {
            $errors[] = 'Bundle.entry wajib berisi minimal satu Observation.';
        }

        foreach ($entries as $index => $entry) {
            $resource = $entry['resource'] ?? [];

            if (($resource['resourceType'] ?? null) !== 'Observation') {
                $errors[] = "Bundle.entry[{$index}] harus berisi resource Observation.";

                continue;
            }

            $this->validateObservation($resource, $errors);
        }
    }

    /**
     * @param  array<string, mixed>  $payload
     * @param  list<string>  $errors
     */
    private function validateImmunization(array $payload, array &$errors): void
    {
        if (empty(data_get($payload, 'patient.reference'))
            || data_get($payload, 'patient.reference') === 'Patient/') {
            $errors[] = 'Immunization.patient.reference wajib memakai Patient/{ihs_number}.';
        }

        $hasStandardCode = collect(data_get($payload, 'vaccineCode.coding', []))
            ->contains(fn (array $coding): bool => in_array(
                $coding['system'] ?? '',
                ['http://hl7.org/fhir/sid/cvx', 'http://sys-ids.kemkes.go.id/kfa'],
                true,
            ));

        if (! $hasStandardCode) {
            $errors[] = 'Immunization.vaccineCode wajib punya mapping KFA atau CVX.';
        }

        if (empty($payload['occurrenceDateTime'])) {
            $errors[] = 'Immunization.occurrenceDateTime wajib ada.';
        }
    }
}
