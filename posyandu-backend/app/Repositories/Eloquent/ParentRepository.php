<?php

namespace App\Repositories\Eloquent;

use App\Models\User;
use App\Repositories\Contracts\ParentRepositoryInterface;

class ParentRepository implements ParentRepositoryInterface
{
    public function findByNikHash(string $nikHash): ?User
    {
        return User::query()->where('nik_hash', $nikHash)->first();
    }

    /**
     * @param  array<string, mixed>  $attributes
     */
    public function create(array $attributes): User
    {
        return User::query()->create($attributes);
    }

    /**
     * @param  array<string, mixed>  $attributes
     */
    public function update(User $user, array $attributes): User
    {
        $user->fill($attributes)->save();

        return $user->refresh();
    }

    public function hasChildren(User $user): bool
    {
        return $user->children()->exists();
    }

    public function markOnboardingCompleted(User $user): User
    {
        if ($user->onboarding_status !== 'completed') {
            $user->forceFill(['onboarding_status' => 'completed'])->save();
        }

        return $user->refresh();
    }

    public function markOnboardingNeedChildData(User $user): User
    {
        if ($user->onboarding_status !== 'need_child_data') {
            $user->forceFill(['onboarding_status' => 'need_child_data'])->save();
        }

        return $user->refresh();
    }
}
