<?php

namespace App\Repositories\Contracts;

use App\Models\Child;
use App\Models\User;

interface ChildRepositoryInterface
{
    /**
     * @param  array<string, mixed>  $attributes
     */
    public function createForParent(User $parent, array $attributes): Child;

    public function findByNikHash(string $nikHash): ?Child;

    public function existsByNikHash(string $nikHash): bool;

    public function countForParent(User $parent): int;
}
