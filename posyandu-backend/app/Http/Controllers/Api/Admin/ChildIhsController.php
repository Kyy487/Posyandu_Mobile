<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\ImportChildIhsRequest;
use App\Http\Requests\Admin\UpdateChildIhsRequest;
use App\Models\Child;
use App\Services\ChildIhsImportService;
use App\Services\ChildIhsService;
use Illuminate\Http\JsonResponse;
use Symfony\Component\HttpFoundation\StreamedResponse;

class ChildIhsController extends Controller
{
    public function __construct(
        private readonly ChildIhsService $childIhs,
        private readonly ChildIhsImportService $imports,
    ) {}

    public function update(UpdateChildIhsRequest $request, Child $child): JsonResponse
    {
        $child = $this->childIhs->update(
            $child,
            (string) $request->validated('ihs_number'),
            (string) $request->validated('reason'),
        );

        return response()->json([
            'success' => true,
            'message' => 'IHS number berhasil diperbarui.',
            'data' => $child,
        ]);
    }

    public function import(ImportChildIhsRequest $request): JsonResponse
    {
        $result = $this->imports->import(
            $request->file('file'),
            $request->boolean('dry_run'),
            $request->boolean('correct_existing'),
        );

        return response()->json([
            'success' => true,
            'message' => $result['dry_run']
                ? 'Pratinjau import IHS selesai. Tidak ada data yang diubah.'
                : 'Import IHS selesai.',
            'data' => $result,
        ]);
    }

    public function template(): StreamedResponse
    {
        return response()->streamDownload(function (): void {
            $handle = fopen('php://output', 'wb');
            fwrite($handle, "\xEF\xBB\xBF");
            fputcsv($handle, [
                'child_id',
                'nik_anak',
                'nama_anak',
                'tanggal_lahir',
                'nik_ibu',
                'ihs_number',
            ], ',', '"', '\\');
            fclose($handle);
        }, 'template-import-ihs.csv', [
            'Content-Type' => 'text/csv; charset=UTF-8',
        ]);
    }
}
