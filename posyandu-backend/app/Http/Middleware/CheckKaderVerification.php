<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Membatasi akses Ibu yang belum diverifikasi Kader.
 *
 * Kader selalu lolos. Ibu dengan `verification_status` pending/rejected hanya
 * boleh memakai endpoint pendaftaran, profil, dan logout (endpoint tersebut
 * memang berada di luar group middleware ini).
 */
class CheckKaderVerification
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if ($user === null || $user->role !== 'ibu') {
            return $next($request);
        }

        if ($user->verification_status === 'pending') {
            return response()->json([
                'success' => false,
                'message' => 'Akun Anda sedang menunggu verifikasi oleh Kader Posyandu.',
                'errors' => [
                    'verification_status' => ['Akun belum diverifikasi.'],
                    'next_action' => ['complete_registration'],
                ],
            ], 403);
        }

        if ($user->verification_status === 'rejected') {
            $message = 'Pendaftaran Anda ditolak.';
            if ($user->rejection_reason) {
                $message .= ' Alasan: '.$user->rejection_reason;
            }

            return response()->json([
                'success' => false,
                'message' => $message,
                'errors' => [
                    'verification_status' => ['Pendaftaran ditolak Kader Posyandu.'],
                    'next_action' => ['fix_registration'],
                ],
            ], 403);
        }

        return $next($request);
    }
}
