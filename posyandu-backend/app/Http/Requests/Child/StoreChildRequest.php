<?php

namespace App\Http\Requests\Child;

use App\Models\Child;
use App\Support\NikHasher;
use Closure;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Validasi onboarding data anak.
 *
 * Dipakai endpoint `POST /registration/child`. Berbeda dari `POST /children`
 * yang masih menerima data minimal (mobile lama), endpoint onboarding
 * mewajibkan data lahir lengkap karena datanya dipakai untuk skrining awal
 * dan koreksi usia prematur.
 */
class StoreChildRequest extends FormRequest
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
            'name' => ['required', 'string', 'max:255'],
            'place_of_birth' => ['required_without:birth_place', 'string', 'max:100'],
            'birth_place' => ['required_without:place_of_birth', 'string', 'max:100'],
            'date_of_birth' => ['required', 'date_format:Y-m-d', 'before_or_equal:today'],
            'gender' => ['required', 'in:L,P'],
            'birth_order' => ['required', 'integer', 'min:1', 'max:20'],
            'birth_weight' => ['required', 'numeric', 'min:0.5', 'max:10'],
            'birth_length' => ['required', 'numeric', 'min:20', 'max:70'],
            'birth_head_circumference' => ['required', 'numeric', 'min:20', 'max:60'],
            'birth_status' => ['required', 'in:normal,premature'],
            'buku_kia_id' => ['nullable', 'string', 'max:50'],

            // Persetujuan UU PDP. Opsional di request, tetapi bila dikirim
            // versi dokumen wajib ikut supaya jejak persetujuan tidak ambigu.
            'consent_type' => ['nullable', 'in:data_processing,data_sharing,research'],
            'consent_document_version' => ['nullable', 'required_with:consent_type', 'string', 'max:20'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'nik.required' => 'NIK anak wajib diisi.',
            'nik.digits' => 'NIK anak harus tepat 16 digit angka.',
            'date_of_birth.date_format' => 'Tanggal lahir harus berformat YYYY-MM-DD.',
            'date_of_birth.before_or_equal' => 'Tanggal lahir tidak boleh di masa depan.',
            'birth_order.min' => 'Urutan kelahiran minimal anak ke-1.',
            'birth_weight.min' => 'Berat lahir minimal 0,5 kg.',
            'birth_weight.max' => 'Berat lahir maksimal 10 kg.',
            'birth_length.min' => 'Panjang lahir minimal 20 cm.',
            'birth_length.max' => 'Panjang lahir maksimal 70 cm.',
            'birth_head_circumference.min' => 'Lingkar kepala lahir minimal 20 cm.',
            'birth_head_circumference.max' => 'Lingkar kepala lahir maksimal 60 cm.',
            'consent_document_version.required_with' => 'Versi dokumen persetujuan wajib diisi bila consent_type dikirim.',
        ];
    }

    private function uniqueNikRule(): Closure
    {
        return function (string $attribute, mixed $value, Closure $fail): void {
            $nik = (string) $value;

            // Termasuk anak yang sudah di-soft delete: NIK tidak boleh dipakai
            // ulang oleh anak yang berbeda.
            if (Child::withTrashed()->where('nik_hash', NikHasher::hash($nik))->exists()) {
                $fail('NIK anak sudah terdaftar.');
            }
        };
    }
}
