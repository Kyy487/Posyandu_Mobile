<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

class KaderRegistrationController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $status = $request->query('status', 'pending');
        $query = User::where('role', 'ibu')->with('verifications');

        if (in_array($status, ['pending', 'active', 'rejected'], true)) {
            $query->where('status', $status);
        }

        $users = $query->orderBy('created_at', 'asc')->orderBy('id')->paginate($this->perPage($request));

        $users->getCollection()->transform(
            fn (User $user) => $user->makeHidden(['nik', 'nik_hash', 'password'])
        );

        return response()->json([
            'success' => true,
            'message' => 'Daftar permohonan registrasi berhasil diambil.',
            'data' => $users->items(),
            'meta' => $this->paginationMeta($users),
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

    public function correct(Request $request, User $user): JsonResponse
    {
        if ($user->role !== 'ibu') {
            return response()->json([
                'success' => false,
                'message' => 'Hanya permohonan role ibu yang dapat dikoreksi.',
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
            'name' => ['sometimes', 'string', 'max:255'],
            'phone_number' => ['sometimes', 'nullable', 'string', 'max:16', 'regex:/^[0-9+\-\s]+$/'],
            'place_of_birth' => ['sometimes', 'nullable', 'string', 'max:100'],
            'date_of_birth' => ['sometimes', 'nullable', 'date'],
            'gender' => ['sometimes', 'nullable', 'string', 'in:L,P'],
            'address' => ['sometimes', 'nullable', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validasi gagal.',
                'errors' => $validator->errors()->toArray(),
            ], 422);
        }

        try {
            $user = DB::transaction(function () use ($request, $user, $validator): User {
                $locked = $this->lockPendingIbu($user);
                $locked->fill($validator->validated());

                if (! $locked->isDirty()) {
                    return $locked;
                }

                $oldValues = [];
                foreach (array_keys($locked->getDirty()) as $column) {
                    $oldValues[$column] = $locked->getOriginal($column);
                }

                $locked->save();

                $newValues = [];
                foreach ($locked->getChanges() as $column => $value) {
                    if ($column === 'updated_at') {
                        continue;
                    }

                    $newValues[$column] = $value;
                }

                $this->recordAudit($request, $locked, $oldValues, $newValues);

                return $locked;
            });
        } catch (ModelNotFoundException) {
            return $this->registrationNotFound();
        } catch (ValidationException $e) {
            return $this->validationFailed($e);
        }

        $user = $user->makeHidden(['nik', 'nik_hash', 'password']);

        return response()->json([
            'success' => true,
            'message' => 'Data permohonan berhasil dikoreksi oleh Kader.',
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

        try {
            $user = DB::transaction(function () use ($request, $user): User {
                $locked = $this->lockPendingIbu($user);
                $oldValues = $this->verificationSnapshot($locked);

                $locked->status = 'active';
                $locked->approved_by = $request->user()->id;
                $locked->approved_at = now();
                $locked->rejection_reason = null;
                $locked->verified_at = now();
                $locked->save();

                $this->recordAudit($request, $locked, $oldValues, $this->verificationSnapshot($locked));

                return $locked;
            });
        } catch (ModelNotFoundException) {
            return $this->registrationNotFound();
        } catch (ValidationException $e) {
            return $this->validationFailed($e);
        }

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

        try {
            $user = DB::transaction(function () use ($request, $user): User {
                $locked = $this->lockPendingIbu($user);
                $oldValues = $this->verificationSnapshot($locked);

                $locked->status = 'rejected';
                $locked->approved_by = $request->user()->id;
                $locked->approved_at = now();
                $locked->rejection_reason = $request->rejection_reason;
                $locked->save();

                $this->recordAudit($request, $locked, $oldValues, $this->verificationSnapshot($locked));

                return $locked;
            });
        } catch (ModelNotFoundException) {
            return $this->registrationNotFound();
        } catch (ValidationException $e) {
            return $this->validationFailed($e);
        }

        $user = $user->makeHidden(['nik', 'nik_hash', 'password']);

        return response()->json([
            'success' => true,
            'message' => 'Permohonan registrasi berhasil ditolak.',
            'data' => $user,
        ]);
    }

    private function lockPendingIbu(User $user): User
    {
        $locked = User::query()->whereKey($user->getKey())->lockForUpdate()->first();

        if ($locked === null || $locked->role !== 'ibu') {
            throw (new ModelNotFoundException)->setModel(User::class, [$user->getKey()]);
        }

        if ($locked->status !== 'pending') {
            throw ValidationException::withMessages([
                'status' => ['Permohonan ini tidak dalam status menunggu persetujuan.'],
            ]);
        }

        return $locked;
    }

    private function verificationSnapshot(User $user): array
    {
        return [
            'status' => $user->status,
            'approved_by' => $user->approved_by,
            'approved_at' => $user->approved_at?->toDateTimeString(),
            'rejection_reason' => $user->rejection_reason,
            'verified_at' => $user->verified_at?->toDateTimeString(),
        ];
    }

    private function recordAudit(Request $request, User $user, array $oldValues, array $newValues): void
    {
        if ($newValues === []) {
            return;
        }

        AuditLog::create([
            'auditable_type' => $user->getMorphClass(),
            'auditable_id' => $user->getKey(),
            'event' => 'updated',
            'actor_id' => $request->user()->id,
            'old_values' => $oldValues,
            'new_values' => $newValues,
            'ip_address' => $request->ip(),
        ]);
    }

    private function registrationNotFound(): JsonResponse
    {
        return response()->json([
            'success' => false,
            'message' => 'Permohonan registrasi tidak ditemukan.',
            'errors' => null,
        ], 404);
    }

    private function validationFailed(ValidationException $e): JsonResponse
    {
        return response()->json([
            'success' => false,
            'message' => 'Permohonan ini tidak dalam status menunggu persetujuan.',
            'errors' => $e->errors(),
        ], 422);
    }
}
