<?php

namespace App\Providers;

use App\Repositories\Contracts\ChildRepositoryInterface;
use App\Repositories\Contracts\ParentRepositoryInterface;
use App\Repositories\Eloquent\ChildRepository;
use App\Repositories\Eloquent\ParentRepository;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        $this->app->bind(ParentRepositoryInterface::class, ParentRepository::class);
        $this->app->bind(ChildRepositoryInterface::class, ChildRepository::class);
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        //
    }
}
