<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\ReminderService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Pengingat untuk Ibu dan Kader.
 *
 * Endpoint:
 *  - `GET /api/ibu/reminders`  — agenda mendatang + imunisasi terlambat
 *  - `GET /api/kader/reminders` — agenda petugas + jumlah anak terlambat
 */
class ReminderController extends Controller
{
    public function __construct(
        private readonly ReminderService $reminders,
    ) {}

    /**
     * Pengingat untuk Ibu.
     */
    public function indexIbu(Request $request): JsonResponse
    {
        $data = $this->reminders->untukIbu($request->user());

        return response()->json([
            'success' => true,
            'message' => 'Data pengingat berhasil diambil.',
            'data' => $data,
        ]);
    }

    /**
     * Pengingat untuk Kader.
     */
    public function indexKader(Request $request): JsonResponse
    {
        $data = $this->reminders->untukKader($request->user());

        return response()->json([
            'success' => true,
            'message' => 'Data pengingat berhasil diambil.',
            'data' => $data,
        ]);
    }
}
