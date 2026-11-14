<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Membatasi endpoint internal ke role admin.
 *
 * Admin sengaja tidak memakai `RoleCheck` agar aturan akses internal tidak
 * tercampur dengan role operasional posyandu (`ibu`/`kader`).
 */
class EnsureAdmin
{
    /**
     * @param  Closure(Request): (Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        if (! $request->user()?->isAdmin()) {
            return response()->json([
                'success' => false,
                'message' => 'Akses ditolak',
                'errors' => [
                    'authorization' => 'Endpoint ini hanya dapat diakses admin.',
                ],
            ], 403);
        }

        return $next($request);
    }
}
