<?php

namespace App\Http\Middleware;

use App\Repositories\Contracts\ParentRepositoryInterface;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Mewajibkan Ibu yang sudah diverifikasi untuk melengkapi data anak sebelum
 * masuk dashboard.
 *
 * Kader selalu lolos. Bila Ibu sudah punya anak (data lama atau ditambahkan
 * lewat endpoint lain), status onboarding otomatis diselesaikan supaya tidak
 * terjadi lock-out palsu.
 */
class CheckChildOnboarding
{
    public function __construct(
        private readonly ParentRepositoryInterface $parents,
    ) {}

    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if ($user === null || $user->role !== 'ibu') {
            return $next($request);
        }

        if ($user->onboarding_status === 'completed') {
            return $next($request);
        }

        if ($this->parents->hasChildren($user)) {
            $this->parents->markOnboardingCompleted($user);

            return $next($request);
        }

        return response()->json([
            'success' => false,
            'message' => 'Lengkapi data anak terlebih dahulu sebelum mengakses dashboard.',
            'errors' => [
                'onboarding_status' => ['Data anak belum dilengkapi.'],
                'next_action' => ['add_child'],
                'endpoint' => ['POST /api/registration/child'],
            ],
        ], 403);
    }
}
