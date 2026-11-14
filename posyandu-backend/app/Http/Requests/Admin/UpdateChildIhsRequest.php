<?php

namespace App\Http\Requests\Admin;

use Illuminate\Contracts\Validation\ValidationRule;
use Illuminate\Foundation\Http\FormRequest;

class UpdateChildIhsRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->isAdmin() ?? false;
    }

    /**
     * @return array<string, ValidationRule|array<mixed>|string>
     */
    public function rules(): array
    {
        return [
            'ihs_number' => ['required', 'string', 'max:50'],
            'reason' => ['required', 'string', 'max:500'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'ihs_number.required' => 'IHS number wajib diisi.',
            'ihs_number.max' => 'IHS number maksimal 50 karakter.',
            'reason.required' => 'Alasan koreksi wajib diisi.',
            'reason.max' => 'Alasan koreksi maksimal 500 karakter.',
        ];
    }
}
