<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;

class AuthServiceProvider extends ServiceProvider
{
    /**
     * Los permisos los decide App\Services\Permissions (roles configurables,
     * docs/11 §11.16); no se usan políticas.
     *
     * @return void
     */
    public function boot()
    {
        // El usuario lo fija el middleware Authenticate.
        $this->app['auth']->viaRequest('api', function () {
            return null;
        });
    }
}
