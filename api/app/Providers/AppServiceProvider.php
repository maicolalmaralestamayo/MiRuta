<?php

namespace App\Providers;

use App\Services\Access;
use App\Services\Settings;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        // Se guardan en memoria durante la petición (se vacían al cambiar datos).
        $this->app->scoped(Settings::class);
        $this->app->scoped(Access::class);
    }

    public function boot(): void
    {
    }
}
