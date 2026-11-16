<?php

namespace App\Http\Requests\Auth;

use App\Support\NikHasher;
use Closure;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Validasi pelengkapan data pendaftaran.
 *
 * Endpoint wajib Bearer token; akun diambil dari token, bukan NIK. NIK boleh
 * dikirim ulang untuk kompatibilitas klien lama, tetapi tidak boleh diubah.
 */
class CompleteRegistrationRequest extends FormRequest
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
            'nik' => ['nullable', 'string', 'digits:16', $this->immutableNikRule()],
            'no_kk' => ['nullable', 'string', 'digits:16'],
            'name' => ['sometimes', 'required', 'string', 'max:255'],
            'phone_number' => ['nullable', 'string', 'max:16', 'regex:/^[0-9+\-\s]+$/'],
            'place_of_birth' => ['nullable', 'string', 'max:100'],
            'date_of_birth' => ['nullable', 'date', 'before_or_equal:today'],
            'gender' => ['nullable', 'in:L,P'],
            'blood_type' => ['nullable', 'in:A,B,AB,O'],
            'address' => ['required', 'string', 'max:1000'],
            'rt_rw' => ['nullable', 'string', 'max:10', 'regex:/^\d{1,3}\s*\/\s*\d{1,3}$/'],
            'education' => ['nullable', 'in:SD,SMP,SMA,SMK,D3,S1,S2,S3,other'],
            'occupation' => ['nullable', 'string', 'max:100'],

            'verification_file' => ['nullable', 'file', 'mimes:jpg,jpeg,png', 'max:2048'],
            'verification_type' => ['nullable', 'in:self_photo,ktp,kk,other'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'nik.digits' => 'NIK harus tepat 16 digit angka.',
            'no_kk.digits' => 'Nomor KK harus tepat 16 digit angka.',
            'address.required' => 'Alamat lengkap wajib diisi.',
            'rt_rw.regex' => 'Format RT/RW harus seperti 001/002.',
            'verification_file.mimes' => 'Berkas harus berupa JPG atau PNG.',
            'verification_file.max' => 'Ukuran berkas maksimal 2 MB.',
        ];
    }

    private function immutableNikRule(): Closure
    {
        return function (string $attribute, mixed $value, Closure $fail): void {
            $user = $this->user();

            if ($user === null || $user->nik_hash !== NikHasher::hash((string) $value)) {
                $fail('NIK tidak dapat diubah.');
            }
        };
    }
}
