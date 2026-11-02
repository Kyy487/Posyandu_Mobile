<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Models\UserVerification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class KaderRegistrationController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $status = $request->query('status', 'pending');
        $query = User::where('role', 'ibu')->with('verifications');

        if (in_array($status, ['pending', 'active', 'rejected'], true)) {
            $query->where('status', $status);
        }

        $users = $query->orderBy('created_at', 'asc')->get()->makeHidden(['nik', 'nik_hash', 'password']);

        return response()->json([
            'success' => true,
            'message' => 'Daftar permohonan registrasi berhasil diambil.',
            'data' => $users,
        ]);
    }

    public function show(User $user): JsonResponse
    {
        if ($user->role !== 'ibu') {
            return response()->json([
                'success' => false,
                'message' => 'Hanya permohonan role ibu yang dapat ditampilkan.',
                'errors' => null,
            ], 404);
        }

        $user->load('verifications', 'approver');
        $user = $user->makeHidden(['nik', 'nik_hash', 'password']);

        return response()->json([
            'success' => true,
            'message' => 'Detail permohonan berhasil diambil.',
            'data' => $user,
        ]);
    }

    public function approve(Request $request, User $user): JsonResponse
    {
        if ($user->role !== 'ibu') {
            return response()->json([
                'success' => false,
                'message' => 'Hanya permohonan role ibu yang dapat disetujui.',
                'errors' => null,
            ], 404);
        }

        if ($user->status !== 'pending') {
            return response()->json([
                'success' => false,
                'message' => 'Permohonan ini tidak dalam status menunggu persetujuan.',
                'errors' => null,
            ], 422);
        }

        $user->status = 'active';
        $user->approved_by = $request->user()->id;
        $user->approved_at = now();
        $user->rejection_reason = null;
        $user->verified_at = now();
        $user->save();

        $user = $user->makeHidden(['nik', 'nik_hash', 'password']);

        return response()->json([
            'success' => true,
            'message' => 'Permohonan registrasi berhasil disetujui.',
            'data' => $user,
        ]);
    }

    public function reject(Request $request, User $user): JsonResponse
    {
        if ($user->role !== 'ibu') {
            return response()->json([
                'success' => false,
                'message' => 'Hanya permohonan role ibu yang dapat ditolak.',
                'errors' => null,
            ], 404);
        }

        if ($user->status !== 'pending') {
            return response()->json([
                'success' => false,
                'message' => 'Permohonan ini tidak dalam status menunggu persetujuan.',
                'errors' => null,
            ], 422);
        }

        $validator = Validator::make($request->all(), [
            'rejection_reason' => ['required', 'string', 'max:1000'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validasi gagal.',
                'errors' => $validator->errors()->toArray(),
            ], 422);
        }

        $user->status = 'rejected';
        $user->approved_by = $request->user()->id;
        $user->approved_at = now();
        $user->rejection_reason = $request->rejection_reason;
        $user->save();

        $user = $user->makeHidden(['nik', 'nik_hash', 'password']);

        return response()->json([
            'success' => true,
            'message' => 'Permohonan registrasi berhasil ditolak.',
            'data' => $user,
        ]);
    }
}

