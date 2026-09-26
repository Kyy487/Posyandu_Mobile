<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Middleware\RoleCheck;

//-- Area Controller --//
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\ChildController;
use App\Http\Controllers\Api\MeasurementController;

// Route Terbuka (Public)
Route::post('/register', [AuthController::class, 'register']);
Route::post('/login', [AuthController::class, 'login']);


// Route Terlindungi (Protected) - Wajib Bearer Token
Route::middleware('auth:sanctum')->group(function () {

    Route::post('/logout', [AuthController::class, 'logout']);
    Route::get('/user', function (Request $request) {
        return response()->json([
            'success' => true,
            'message' => 'Data user aktif',
            'data' => $request->user()
        ]);
    });

    // --------------------------------------------------------
    // AREA BALITA
    // --------------------------------------------------------
    Route::middleware('auth:sanctum')->group(function () {
    Route::post('/logout', [AuthController::class, 'logout']);

    Route::get('/children', [ChildController::class, 'index']);
    Route::post('/children', [ChildController::class, 'store']);
    Route::get('/children/{id}', [ChildController::class, 'show']);
    });
    // --------------------------------------------------------
    // AREA KHUSUS IBU / ORANG TUA
    // --------------------------------------------------------
    Route::middleware([RoleCheck::class.':ibu'])->group(function () {
        Route::post('/children', [ChildController::class, 'store']);
    });

    // --------------------------------------------------------
    // AREA KHUSUS KADER POSYANDU
    // --------------------------------------------------------
    Route::middleware([RoleCheck::class.':kader'])->group(function () {
        Route::post('/measurements', [MeasurementController::class, 'store']);
        Route::get('/kader/children', [ChildController::class, 'indexKader']);
        Route::get('/kader/measurements', [MeasurementController::class, 'index']);
        Route::post('/kader/children', [ChildController::class, 'storeKader']);
        Route::post('/kader/measurements', [MeasurementController::class, 'store']);
        Route::delete('/kader/measurements/{id}', [MeasurementController::class, 'destroy']);
        // Nanti kita tambahkan route POST untuk /measurements (e-KMS) di sini
    });

    // --------------------------------------------------------
    // AREA BERSAMA (Bisa diakses Ibu maupun Kader)
    // --------------------------------------------------------
    Route::middleware([RoleCheck::class.':ibu,kader'])->group(function () {
        Route::get('/children', [ChildController::class, 'index']);
        Route::get('/children/{id}', [ChildController::class, 'show']);
    });

});
