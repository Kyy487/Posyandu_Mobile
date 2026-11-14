<?php

namespace App\Services;

use App\Models\Child;
use App\Models\User;
use App\Support\IhsNumber;
use App\Support\NikHasher;
use Carbon\CarbonImmutable;
use Illuminate\Http\UploadedFile;
use Illuminate\Validation\ValidationException;
use InvalidArgumentException;

/**
 * Import IHS number lewat CSV khusus admin.
 *
 * Tidak ada tabel batch di Fase 1. Laporan hasil dikembalikan di respons dan
 * setiap baris diproses independen, sehingga satu baris gagal tidak
 * membatalkan baris lain.
 */
class ChildIhsImportService
{
    public const MAX_ROWS = 5000;

    public function __construct(
        private readonly ChildIhsService $childIhs,
    ) {}

    /**
     * @return array{
     *     dry_run: bool,
     *     total: int,
     *     updated: int,
     *     skipped: int,
     *     failed: int,
     *     errors: list<array{line: int, message: string}>
     * }
     *
     * @throws ValidationException
     */
    public function import(UploadedFile $file, bool $dryRun = false, bool $correctExisting = false): array
    {
        $handle = fopen($file->getRealPath(), 'rb');

        if ($handle === false) {
            throw ValidationException::withMessages([
                'file' => ['File CSV tidak dapat dibaca.'],
            ]);
        }

        try {
            $delimiter = $this->detectDelimiter($handle);
            $headers = $this->readHeaders($handle, $delimiter);
            $total = $this->countRows($handle, $delimiter);

            if ($total > self::MAX_ROWS) {
                throw ValidationException::withMessages([
                    'file' => ['Maksimal '.self::MAX_ROWS.' baris per unggahan.'],
                ]);
            }

            rewind($handle);
            fgetcsv($handle, 0, $delimiter, '"', '\\');

            $result = [
                'dry_run' => $dryRun,
                'total' => $total,
                'updated' => 0,
                'skipped' => 0,
                'failed' => 0,
                'errors' => [],
            ];

            $seenIhs = [];
            $seenChildren = [];
            $lineNumber = 1;

            while (($row = fgetcsv($handle, 0, $delimiter, '"', '\\')) !== false) {
                $lineNumber++;

                if ($this->isBlankRow($row)) {
                    continue;
                }

                $row = $this->combineRow($headers, $row);

                try {
                    $outcome = $this->processRow(
                        $row,
                        $seenIhs,
                        $seenChildren,
                        $dryRun,
                        $correctExisting,
                    );

                    $result[$outcome]++;
                } catch (InvalidArgumentException|ValidationException $exception) {
                    $result['failed']++;
                    $result['errors'][] = [
                        'line' => $lineNumber,
                        'message' => $this->messageFrom($exception),
                    ];
                }
            }

            return $result;
        } finally {
            fclose($handle);
        }
    }

    /**
     * @param  array<string, string>  $row
     * @param  array<string, int>  $seenIhs
     * @param  array<string, string>  $seenChildren
     *
     * @throws InvalidArgumentException|ValidationException
     */
    private function processRow(
        array $row,
        array &$seenIhs,
        array &$seenChildren,
        bool $dryRun,
        bool $correctExisting,
    ): string {
        $ihsNumber = IhsNumber::normalize($row['ihs_number'] ?? null);

        if ($ihsNumber === null) {
            throw new InvalidArgumentException('Kolom ihs_number wajib diisi.');
        }

        $child = $this->findChild($row);

        if (isset($seenChildren[$child->id])
            && $seenChildren[$child->id] !== $ihsNumber) {
            throw new InvalidArgumentException(
                'Anak yang sama muncul lebih dari sekali dengan IHS berbeda di file ini.'
            );
        }

        $seenChildren[$child->id] = $ihsNumber;

        if (isset($seenIhs[$ihsNumber]) && $seenIhs[$ihsNumber] !== $child->id) {
            throw new InvalidArgumentException('IHS number duplikat di file ini.');
        }

        $seenIhs[$ihsNumber] = $child->id;

        if ($child->ihs_number === $ihsNumber) {
            return 'skipped';
        }

        if ($child->ihs_number !== null && ! $correctExisting) {
            throw new InvalidArgumentException(
                'Anak sudah memiliki IHS berbeda. Gunakan mode koreksi untuk menimpa.'
            );
        }

        $this->childIhs->update(
            $child,
            $ihsNumber,
            $child->ihs_number === null ? 'Import CSV IHS' : 'Import CSV IHS (koreksi)',
            $dryRun,
        );

        return 'updated';
    }

    /**
     * @param  array<string, string>  $row
     *
     * @throws InvalidArgumentException|ValidationException
     */
    private function findChild(array $row): Child
    {
        $childId = trim((string) ($row['child_id'] ?? ''));

        if ($childId !== '') {
            $child = Child::query()->find($childId);

            if ($child === null) {
                throw new InvalidArgumentException('child_id tidak ditemukan.');
            }

            $this->verifyMother($child, $row['nik_ibu'] ?? null);

            return $child;
        }

        $nik = trim((string) ($row['nik_anak'] ?? ''));
        $dateOfBirth = $this->parseDate($row['tanggal_lahir'] ?? null);

        if ($nik === '' || $dateOfBirth === null) {
            throw new InvalidArgumentException(
                'Isi child_id, atau isi nik_anak dan tanggal_lahir (format YYYY-MM-DD).'
            );
        }

        $child = Child::query()
            ->where('nik_hash', NikHasher::hash($nik))
            ->whereDate('date_of_birth', $dateOfBirth)
            ->first();

        if ($child === null) {
            throw new InvalidArgumentException(
                'Anak dengan NIK dan tanggal lahir tersebut tidak ditemukan.'
            );
        }

        $this->verifyMother($child, $row['nik_ibu'] ?? null);

        return $child;
    }

    /**
     * @throws InvalidArgumentException
     */
    private function verifyMother(Child $child, ?string $nikIbu): void
    {
        $nikIbu = trim((string) $nikIbu);

        if ($nikIbu === '') {
            return;
        }

        $mother = User::query()
            ->where('nik_hash', NikHasher::hash($nikIbu))
            ->first();

        if ($mother === null || $mother->id !== $child->user_id) {
            throw new InvalidArgumentException('nik_ibu tidak cocok dengan ibu anak tersebut.');
        }
    }

    /**
     * @throws InvalidArgumentException
     */
    private function parseDate(?string $value): ?string
    {
        $value = trim((string) $value);

        if ($value === '') {
            return null;
        }

        foreach (['Y-m-d', 'd/m/Y'] as $format) {
            $date = CarbonImmutable::createFromFormat('!'.$format, $value);

            if ($date !== false && $date->format($format) === $value) {
                return $date->toDateString();
            }
        }

        throw new InvalidArgumentException(
            'tanggal_lahir harus memakai format YYYY-MM-DD atau DD/MM/YYYY.'
        );
    }

    /**
     * @param  resource  $handle
     */
    private function detectDelimiter($handle): string
    {
        $line = fgets($handle) ?: '';
        rewind($handle);

        return substr_count($line, ';') > substr_count($line, ',') ? ';' : ',';
    }

    /**
     * @param  resource  $handle
     * @return list<string>
     *
     * @throws ValidationException
     */
    private function readHeaders($handle, string $delimiter): array
    {
        $headers = fgetcsv($handle, 0, $delimiter, '"', '\\');

        if ($headers === false) {
            throw ValidationException::withMessages([
                'file' => ['File CSV kosong.'],
            ]);
        }

        $headers = array_map(
            fn (string $header): string => strtolower(trim(preg_replace('/^\xEF\xBB\xBF/', '', $header) ?? $header)),
            $headers
        );

        if (! in_array('ihs_number', $headers, true)) {
            throw ValidationException::withMessages([
                'file' => ['Kolom ihs_number wajib ada di header CSV.'],
            ]);
        }

        return $headers;
    }

    /**
     * @param  resource  $handle
     */
    private function countRows($handle, string $delimiter): int
    {
        rewind($handle);
        fgetcsv($handle, 0, $delimiter, '"', '\\');

        $count = 0;

        while (($row = fgetcsv($handle, 0, $delimiter, '"', '\\')) !== false) {
            if (! $this->isBlankRow($row)) {
                $count++;
            }
        }

        return $count;
    }

    /**
     * @param  list<string|null>  $row
     */
    private function isBlankRow(array $row): bool
    {
        return trim(implode('', array_map('strval', $row))) === '';
    }

    /**
     * @param  list<string>  $headers
     * @param  list<string|null>  $row
     * @return array<string, string>
     */
    private function combineRow(array $headers, array $row): array
    {
        $combined = [];

        foreach ($headers as $index => $header) {
            $combined[$header] = (string) ($row[$index] ?? '');
        }

        return $combined;
    }

    private function messageFrom(InvalidArgumentException|ValidationException $exception): string
    {
        if ($exception instanceof ValidationException) {
            return (string) collect($exception->errors())->flatten()->first();
        }

        return $exception->getMessage();
    }
}
