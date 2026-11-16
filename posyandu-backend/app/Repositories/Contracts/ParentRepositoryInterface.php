<?php

namespace App\Repositories\Contracts;

use App\Models\User;

interface ParentRepositoryInterface
{
    public function findByNikHash(string $nikHash): ?User;

    /**
     * @param  array<string, mixed>  $attributes
     */
    public function create(array $attributes): User;

    /**
     * @param  array<string, mixed>  $attributes
     */
    public function update(User $user, array $attributes): User;

    public function hasChildren(User $user): bool;

    public function markOnboardingCompleted(User $user): User;

    public function markOnboardingNeedChildData(User $user): User;
}
