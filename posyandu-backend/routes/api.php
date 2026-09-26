<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Middleware\RoleCheck;

//-- Area Controller --//
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\ChildController;
use App\Http\Controllers\Api\MeasurementController;

/*
|--------------------------------------------------------------------------
| API Routes
|--------------------------------------------------------------------------
| Struktur dirapikan 26 Sep 2026:
| - Setiap route hanya didaftarkan SATU kali. Sebelumnya ada duplikat
|   (logout, /children, /children/{id}) dan group `auth:sanctum` bersarang
|   di dalam dirinya sendiri.
| - Duplikat menyebabkan group `RoleCheck:ibu` menjadi dead code, karena
|   Laravel selalu memakai route yang cocok PERTAMA.
| - Endpoint e-KMS canonical adalah `/kader/measurements` (dipakai mobile).
*/

// ---------------------------------------------------------------------
// Route Terbuka (Public)
//
// `throttle:` membatasi percobaan berulang per IP untuk menutup serangan
// brute force ke NIK + password. Nilai diambil dari config/posyandu.php
// (env LOGIN_THROTTLE / REGISTER_THROTTLE). Kelewat batas -> 429.
// ---------------------------------------------------------------------
Route::post('/register', [AuthController::class, 'register'])
    ->middleware('throttle:'.config('posyandu.register_throttle'));

Route::post('/login', [AuthController::class, 'login'])
    ->middleware('throttle:'.config('posyandu.login_throttle'));


// ---------------------------------------------------------------------
// Route Terlindungi (Protected) - Wajib Bearer Token
// ---------------------------------------------------------------------
Route::middleware('auth:sanctum')->group(function () {

    Route::post('/logout', [AuthController::class, 'logout']);

    Route::get('/user', function (Request $request) {
        return response()->json([
            'success' => true,
            'message' => 'Data user aktif',
            'data' => $request->user(),
        ]);
    });

    // -----------------------------------------------------------------
    // AREA BALITA - dapat diakses Ibu maupun Kader
    // -----------------------------------------------------------------
    Route::middleware([RoleCheck::class.':ibu,kader'])->group(function () {
        Route::get('/children', [ChildController::class, 'index']);
        Route::get('/children/{id}', [ChildController::class, 'show']);

        // Ibu menambah anaknya sendiri. Kader tetap boleh, dengan mengirim
        // user_id; pembagian peran ini ditangani ChildController@store.
        Route::post('/children', [ChildController::class, 'store']);

        // Partial update: hanya field yang dikirim yang berubah, jadi aman
        // dipanggil lewat PUT maupun PATCH.
        Route::match(['put', 'patch'], '/children/{id}', [ChildController::class, 'update']);
    });

    // -----------------------------------------------------------------
    // AREA KHUSUS KADER POSYANDU
    // -----------------------------------------------------------------
    Route::middleware([RoleCheck::class.':kader'])->group(function () {
        Route::get('/kader/children', [ChildController::class, 'indexKader']);
        Route::post('/kader/children', [ChildController::class, 'store']);

        // Soft delete, khusus Kader. Didaftarkan di sini agar Ibu tidak bisa
        // menghapus data anaknya, meski path endpoint tetap /children/{id}.
        Route::delete('/children/{id}', [ChildController::class, 'destroy']);

        Route::get('/kader/measurements', [MeasurementController::class, 'index']);
        Route::post('/kader/measurements', [MeasurementController::class, 'store']);
        Route::delete('/kader/measurements/{id}', [MeasurementController::class, 'destroy']);
    });
});
