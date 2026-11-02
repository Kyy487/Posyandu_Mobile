<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\UserVerification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class RegistrationCompletionController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        $user = $request->user()->load('verifications');
        $user = $user->makeHidden(['nik', 'nik_hash', 'password']);

        return response()->json([
            'success' => true,
            'message' => 'Status pendaftaran berhasil diambil.',
            'data' => $user,
        ]);
    }

    public function update(Request $request): JsonResponse
    {
        $user = $request->user();

        if ($user->role !== 'ibu' || $user->status !== 'pending') {
            return response()->json([
                'success' => false,
                'message' => 'Hanya akun ibu dengan status menunggu persetujuan yang dapat melengkapi data.',
                'errors' => null,
            ], 403);
        }

        $validator = Validator::make($request->all(), [
            'name' => ['sometimes', 'string', 'max:255'],
            'phone_number' => ['sometimes', 'nullable', 'string', 'max:16', 'regex:/^[0-9+\-\s]+$/'],
            'place_of_birth' => ['sometimes', 'nullable', 'string', 'max:100'],
            'date_of_birth' => ['sometimes', 'nullable', 'date'],
            'gender' => ['sometimes', 'nullable', 'in:L,P'],
            'address' => ['required', 'string'],
            'verification_file' => ['nullable', 'file', 'mimes:jpg,jpeg,png,pdf', 'max:5120'],
            'verification_type' => ['nullable', 'in:self_photo,kk,other'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validasi gagal.',
                'errors' => $validator->errors()->toArray(),
            ], 422);
        }

        $data = $validator->validated();
        if (array_key_exists('place_of_birth', $data) && $data['place_of_birth'] === '') {
            unset($data['place_of_birth']);
        }
        if (array_key_exists('date_of_birth', $data) && $data['date_of_birth'] === '') {
            unset($data['date_of_birth']);
        }
        if (array_key_exists('gender', $data) && $data['gender'] === '') {
            unset($data['gender']);
        }
        if (array_key_exists('phone_number', $data) && $data['phone_number'] === '') {
            unset($data['phone_number']);
        }
        if ($user->status === 'rejected') {
            $user->status = 'pending';
            $user->rejection_reason = null;
            $user->approved_by = null;
            $user->approved_at = null;
            $user->verified_at = null;
        }
        $user->fill($data);
        $user->save();

        if ($request->hasFile('verification_file')) {
            $file = $request->file('verification_file');
            $path = $file->store('verifications', 'public');
            UserVerification::create([
                'user_id' => $user->id,
                'type' => $request->input('verification_type', 'other'),
                'file_path' => $path,
                'file_name' => $file->getClientOriginalName(),
                'mime_type' => $file->getMimeType(),
                'uploaded_at' => now(),
            ]);
        }

        $user->load('verifications');
        $user = $user->makeHidden(['nik', 'nik_hash', 'password']);

        return response()->json([
            'success' => true,
            'message' => 'Data pendaftaran berhasil dilengkapi dan menunggu persetujuan kader.',
            'data' => $user,
        ]);
    }
}

