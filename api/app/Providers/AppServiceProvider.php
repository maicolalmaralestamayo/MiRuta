<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     *
     * @return void
     */
    public function register()
    {
        // Lumen 7 busca el seeder "DatabaseSeeder" sin espacio de nombres; los
        // seeders usan ya el de Laravel 8+ (Database\Seeders).
        $this->app->bind('DatabaseSeeder', \Database\Seeders\DatabaseSeeder::class);

        // Permisos leídos: una sola vez por petición (Authenticate los olvida al empezar).
        $this->app->singleton(\App\Services\Permissions::class);
    }
}
