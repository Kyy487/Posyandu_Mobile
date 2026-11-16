<?php

namespace App\Services;

use App\Models\UserVerification;
use Illuminate\Http\UploadedFile;

class VerificationDocumentService
{
    /**
     * Simpan berkas verifikasi (KTP/KK/foto diri) ke disk publik.
     *
     * Path disimpan relatif terhadap disk `public`, sehingga mobile bisa
     * membentuk URL lewat `asset('storage/'.$file_path)`.
     */
    public function store(
        UploadedFile $file,
        string $userId,
        string $type = 'other',
    ): UserVerification {
        $path = $file->store("verifications/{$userId}", 'public');

        return UserVerification::query()->create([
            'user_id' => $userId,
            'type' => $type,
            'file_path' => $path,
            'file_name' => $file->getClientOriginalName(),
            'mime_type' => $file->getMimeType(),
            'uploaded_at' => now(),
        ]);
    }
}
