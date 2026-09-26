<?php

use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        //
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson(),
        );

        /*
        |--------------------------------------------------------------------------
        | JSON Envelope untuk error di luar controller (Aturan #8)
        |--------------------------------------------------------------------------
        |
        | Tanpa blok di bawah ini, Laravel membalas error dengan bentuk bawaan
        | yang berbeda-beda, sehingga Flutter tidak bisa parse:
        |   401 -> {"message":"Unauthenticated."}
        |   405 -> {"message":"The GET method is not supported..."}
        |   404 -> {"message":"No query results for model [...]"}
        |
        | Semua bentuk di bawah sekarang seragam: {success, message, errors}.
        |
        */

        // 401 - token tidak ada, kedaluwarsa, atau sudah dicabut saat logout.
        $exceptions->render(function (AuthenticationException $e, Request $request) {
            if ($request->is('api/*') || $request->expectsJson()) {
                return response()->json([
                    'success' => false,
                    'message' => 'Sesi tidak valid atau telah berakhir. Silakan login kembali.',
                    'errors' => null,
                ], 401);
            }
        });

        // 403 - authenticated, tapi role tidak berwenang.
        $exceptions->render(function (AuthorizationException $e, Request $request) {
            if ($request->is('api/*') || $request->expectsJson()) {
                return response()->json([
                    'success' => false,
                    'message' => 'Akses ditolak.',
                    'errors' => [
                        'authorization' => ['Anda tidak memiliki izin (role) yang sesuai.'],
                    ],
                ], 403);
            }
        });

        // 422 - validasi gagal di luar controller (mis. throttle/filter).
        $exceptions->render(function (ValidationException $e, Request $request) {
            if ($request->is('api/*') || $request->expectsJson()) {
                return response()->json([
                    'success' => false,
                    'message' => 'Validasi gagal.',
                    'errors' => $e->errors(),
                ], 422);
            }
        });

        // 404 - model tidak ditemukan / URL salah.
        $exceptions->render(function (ModelNotFoundException $e, Request $request) {
            if ($request->is('api/*') || $request->expectsJson()) {
                return response()->json([
                    'success' => false,
                    'message' => 'Data yang diminta tidak ditemukan.',
                    'errors' => null,
                ], 404);
            }
        });

        $exceptions->render(function (NotFoundHttpException $e, Request $request) {
            if ($request->is('api/*') || $request->expectsJson()) {
                return response()->json([
                    'success' => false,
                    'message' => 'Endpoint tidak ditemukan.',
                    'errors' => null,
                ], 404);
            }
        });

        // 405 / 419 / 429 / dll - METHOD atau route lain tidak dikenali.
        $exceptions->render(function (HttpExceptionInterface $e, Request $request) {
            if ($request->is('api/*') || $request->expectsJson()) {
                $status = $e->getStatusCode();

                // Pesan bawaan Symfony menyebut nama route dan method yang
                // didukung. Itu detail internal, jadi diganti di sini.
                $message = match ($status) {
                    401 => 'Sesi tidak valid atau telah berakhir. Silakan login kembali.',
                    403 => 'Akses ditolak.',
                    404 => 'Endpoint tidak ditemukan.',
                    405 => 'Metode HTTP tidak diizinkan untuk endpoint ini.',
                    419 => 'Sesi kedaluwarsa. Silakan login kembali.',
                    429 => 'Terlalu banyak percobaan. Silakan coba lagi beberapa saat lagi.',
                    default => 'Permintaan tidak dapat diproses.',
                };

                return response()->json([
                    'success' => false,
                    'message' => $message,
                    'errors' => null,
                ], $status, $e->getHeaders());
            }
        });
    })->create();
