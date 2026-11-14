<?php

namespace App\Repositories\Eloquent;

use App\Models\Child;
use App\Models\User;
use App\Repositories\Contracts\ChildRepositoryInterface;

class ChildRepository implements ChildRepositoryInterface
{
    /**
     * @param  array<string, mixed>  $attributes
     */
    public function createForParent(User $parent, array $attributes): Child
    {
        $attributes['user_id'] = $parent->id;

        return Child::query()->create($attributes);
    }

    public function findByNikHash(string $nikHash): ?Child
    {
        return Child::withTrashed()->where('nik_hash', $nikHash)->first();
    }

    public function existsByNikHash(string $nikHash): bool
    {
        return Child::withTrashed()->where('nik_hash', $nikHash)->exists();
    }

    public function countForParent(User $parent): int
    {
        return Child::query()->where('user_id', $parent->id)->count();
    }
}
