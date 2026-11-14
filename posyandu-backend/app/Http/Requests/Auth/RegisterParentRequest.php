<?php

namespace App\Http\Requests\Auth;

use App\Models\User;
use App\Support\NikHasher;
use Closure;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Validasi pendaftaran akun baru.
 *
 * Dipakai bersama oleh pendaftaran Ibu dan Kader (role kader hanya boleh
 * dibuat bila `kader_code` cocok, dan itu diputuskan AuthController - bukan
 * oleh request ini).
 *
 * Aturan penting:
 * - NIK dicek unik lewat `nik_hash`, BUKAN kolom `nik`. Kolom `nik` memakai
 *   cast `encrypted` dengan IV acak, jadi dua NIK yang sama menghasilkan
 *   ciphertext berbeda dan `unique:users,nik` tidak akan pernah menangkap
 *   duplikat.
 * - `no_kk` tidak unik karena satu KK dipakai bersama seluruh anggota
 *   keluarga. Yang unik hanya NIK.
 * - Field profil yang belum dikirim tetap opsional agar klien lama tidak
 *   rusak; kelengkapannya ditegakkan di endpoint /registration/complete.
 */
class RegisterParentRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'nik' => [
                'required',
                'string',
                'digits:16',
                $this->uniqueNikRule(),
            ],
            'no_kk' => ['nullable', 'string', 'digits:16'],
            'name' => ['required', 'string', 'max:255'],
            'password' => ['required', 'string', 'min:8', 'confirmed'],

            'phone_number' => ['nullable', 'string', 'max:16', 'regex:/^[0-9+\-\s]+$/'],
            'place_of_birth' => ['nullable', 'string', 'max:100'],
            'date_of_birth' => ['nullable', 'date', 'before_or_equal:today'],
            'gender' => ['nullable', 'in:L,P'],
            'blood_type' => ['nullable', 'in:A,B,AB,O'],
            'address' => ['nullable', 'string', 'max:1000'],
            'rt_rw' => ['nullable', 'string', 'max:10', 'regex:/^\d{1,3}\s*\/\s*\d{1,3}$/'],
            'education' => ['nullable', 'in:SD,SMP,SMA,SMK,D3,S1,S2,S3,other'],
            'occupation' => ['nullable', 'string', 'max:100'],

            'verification_file' => ['nullable', 'file', 'mimes:jpg,jpeg,png', 'max:2048'],
            'verification_type' => ['nullable', 'in:self_photo,kk,other'],

            // Permintaan kader. Role tetap diputuskan server.
            'role' => ['nullable', 'in:kader'],
            'kader_code' => ['nullable', 'string', 'max:100'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'nik.required' => 'NIK wajib diisi.',
            'nik.digits' => 'NIK harus tepat 16 digit angka.',
            'no_kk.digits' => 'Nomor KK harus tepat 16 digit angka.',
            'password.confirmed' => 'Konfirmasi password tidak cocok.',
            'rt_rw.regex' => 'Format RT/RW harus seperti 001/002.',
            'verification_file.mimes' => 'Berkas harus berupa JPG atau PNG.',
            'verification_file.max' => 'Ukuran berkas maksimal 2 MB.',
        ];
    }

    private function uniqueNikRule(): Closure
    {
        return function (string $attribute, mixed $value, Closure $fail): void {
            $nik = (string) $value;

            if (User::query()->where('nik_hash', NikHasher::hash($nik))->exists()) {
                $fail('NIK sudah terdaftar. Silakan login atau hubungi Kader Posyandu.');
            }
        };
    }
}
