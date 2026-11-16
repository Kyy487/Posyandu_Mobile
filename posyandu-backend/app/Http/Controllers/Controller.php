<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Pagination\LengthAwarePaginator;

abstract class Controller
{
    protected function perPage(Request $request, int $default = 50, int $max = 100): int
    {
        $value = filter_var($request->query('per_page', $default), FILTER_VALIDATE_INT);

        if ($value === false) {
            return $default;
        }

        return max(1, min($value, $max));
    }

    protected function paginationMeta(LengthAwarePaginator $paginator): array
    {
        return [
            'current_page' => $paginator->currentPage(),
            'per_page' => $paginator->perPage(),
            'total' => $paginator->total(),
            'last_page' => $paginator->lastPage(),
            'from' => $paginator->firstItem(),
            'to' => $paginator->lastItem(),
        ];
    }
}
