<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\ChildController;
use App\Http\Controllers\Api\ImmunizationController;
// -- Area Controller --//
use App\Http\Controllers\Api\MeasurementController;
use App\Http\Controllers\Api\MedicalNoteController;
use App\Http\Controllers\Api\PetugasController;
use App\Http\Controllers\Api\PosyanduScheduleController;
use App\Http\Middleware\RoleCheck;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

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

        // -----------------------------------------------------------------
        // AREA IMUNISASI - dapat diakses Ibu maupun Kader (Ibu read-only)
        //
        // Checklist dihitung di PHP setiap request (lihat
        // ImmunizationChecklistService) karena status bergantung pada tanggal
        // lahir anak, bukan data yang bisa disimpan.
        // -----------------------------------------------------------------
        Route::get('/immunization-types', [ImmunizationController::class, 'types']);
        Route::get('/children/{id}/immunizations', [ImmunizationController::class, 'show']);

        // -----------------------------------------------------------------
        // AREA CATATAN KELUHAN - Ibu hanya membaca
        //
        // Satu path untuk Ibu dan Kader, sama seperti checklist imunisasi di
        // atas. Beda peran ditangani middleware RoleCheck dan pemeriksaan
        // kepemilikan di MedicalNoteController@findAccessibleChild.
        //
        // Default-nya bulan berjalan; `?month=YYYY-MM` untuk bulan lain dan
        // `?all=1` untuk seluruh riwayat.
        // -----------------------------------------------------------------
        Route::get('/children/{id}/medical-notes', [MedicalNoteController::class, 'index']);

        // -----------------------------------------------------------------
        // AREA JADWAL POSYANDU - Ibu hanya membaca
        // -----------------------------------------------------------------
        Route::get('/schedules', [PosyanduScheduleController::class, 'index']);

        // Daftar petugas. NIK tidak pernah ikut respons; lihat PetugasController.
        Route::get('/petugas', [PetugasController::class, 'index']);
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

        // -----------------------------------------------------------------
        // AREA IMUNISASI - Kader mencatat dan mengoreksi
        //
        // `child` tanpa `{id}` agar tidak bentrok dengan route `DELETE
        // /children/{id}` di group di atas; keduanya dibedakan oleh prefix
        // `/kader/`.
        // -----------------------------------------------------------------
        Route::post('/kader/children/{child}/immunizations', [ImmunizationController::class, 'store']);

        // Koreksi suntikan memakai PATCH, bukan hapus-lalu-simpan, karena
        // unique constraint `immunization_child_type_unique` melarang dua
        // record untuk dosis yang sama pada satu anak.
        Route::patch('/kader/immunizations/{record}', [ImmunizationController::class, 'update']);

        // Batalkan suntikan (soft delete). Endpoint ini yang menutup kasus
        // "salah pilih dosis": PATCH sengaja tidak bisa memindahkan
        // `immunization_type_id`, jadi tanpa DELETE salah pilihan jadi permanen.
        Route::delete('/kader/immunizations/{record}', [ImmunizationController::class, 'destroy']);

        // -----------------------------------------------------------------
        // AREA CATATAN KELUHAN - Kader mencatat dan mengoreksi
        //
        // `child` tanpa `{id}` agar tidak bentrok dengan route `DELETE
        // /children/{id}` di group di atas; keduanya dibedakan oleh prefix
        // `/kader/`.
        //
        // Berbeda dari suntikan, `note_date` BOLEH diubah lewat PATCH: kesalahan
        // tanggal di sini adalah salah pilih hari di kalender, bukan keputusan
        // yang perlu dibatalkan lalu diulang.
        // -----------------------------------------------------------------
        Route::post('/kader/children/{child}/medical-notes', [MedicalNoteController::class, 'store']);
        Route::patch('/kader/medical-notes/{note}', [MedicalNoteController::class, 'update']);

        // Batalkan catatan keluhan (soft delete), supaya salah input tidak
        // hilang permanen dan tanggal yang sama bisa dicatat ulang.
        Route::delete('/kader/medical-notes/{note}', [MedicalNoteController::class, 'destroy']);

        // -----------------------------------------------------------------
        // AREA JADWAL POSYANDU - Kader membuat, mengubah, menghapus
        // -----------------------------------------------------------------
        Route::post('/kader/schedules', [PosyanduScheduleController::class, 'store']);
        Route::patch('/kader/schedules/{id}', [PosyanduScheduleController::class, 'update']);
        Route::delete('/kader/schedules/{id}', [PosyanduScheduleController::class, 'destroy']);
    });
});
