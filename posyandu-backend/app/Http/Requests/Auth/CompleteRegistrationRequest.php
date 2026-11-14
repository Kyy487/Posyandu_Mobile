<?php

namespace App\Http\Requests\Auth;

use App\Models\User;
use App\Support\NikHasher;
use Closure;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Validasi pelengkapan data pendaftaran.
 *
 * Endpoint ini boleh dipanggil dengan Bearer token ATAU dengan `nik` + status
 * pending (alur lama mobile). Karena itu NIK tetap opsional, tetapi bila
 * dikirim harus valid dan tidak dipakai akun lain.
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
            'nik' => ['nullable', 'string', 'digits:16', $this->uniqueNikRule()],
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
            'verification_type' => ['nullable', 'in:self_photo,kk,other'],
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

    private function uniqueNikRule(): Closure
    {
        return function (string $attribute, mixed $value, Closure $fail): void {
            $nik = (string) $value;
            $currentId = $this->user()?->id;

            // Tanpa token, endpoint ini mengidentifikasi akun lewat NIK.
            // Akun pending/rejected dengan NIK tersebut adalah akun yang
            // sedang diperbaiki, bukan duplikat.
            if ($currentId === null) {
                $currentId = User::query()
                    ->where('nik_hash', NikHasher::hash($nik))
                    ->whereIn('status', ['pending', 'rejected'])
                    ->value('id');
            }

            $query = User::query()->where('nik_hash', NikHasher::hash($nik));

            if ($currentId !== null) {
                $query->whereKeyNot($currentId);
            }

            if ($query->exists()) {
                $fail('NIK sudah terdaftar pada akun lain.');
            }
        };
    }
}
