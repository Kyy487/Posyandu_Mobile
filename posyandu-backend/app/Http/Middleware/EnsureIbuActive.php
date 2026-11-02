<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureIbuActive
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if ($user && $user->role === 'ibu') {
            if (isset($user->status)) {
                if ($user->status === 'rejected') {
                    $path = $request->path();
                    if (str_contains($path, 'registration/status') || str_contains($path, 'registration/complete') || str_contains($path, 'logout') || str_contains($path, 'profile')) {
                        return $next($request);
                    }
                    $msg = 'Pendaftaran Anda ditolak.';
                    if ($user->rejection_reason) {
                        $msg .= ' Alasan: '.$user->rejection_reason;
                    }
                    return response()->json([
                        'success' => false,
                        'message' => $msg,
                        'errors' => null,
                    ], 403);
                }
                if ($user->status === 'pending') {
                    // Izinkan akses untuk melengkapi pendaftaran
                    $path = $request->path();
                    if (str_contains($path, 'registration/status') || str_contains($path, 'registration/complete') || str_contains($path, 'logout') || str_contains($path, 'profile')) {
                        return $next($request);
                    }
                    return response()->json([
                        'success' => false,
                        'message' => 'Akun Anda masih menunggu persetujuan dari Kader Posyandu.',
                        'errors' => null,
                    ], 403);
                }
            }
        }

        return $next($request);
    }
}


