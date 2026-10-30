<?php

namespace App\Providers;

use App\Models\Worker;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\ServiceProvider;

class AuthServiceProvider extends ServiceProvider
{
    /**
     * Políticas de autorización por modelo.
     *
     * @var array
     */
    protected $policies = [];

    /**
     * Boot the authentication services for the application.
     *
     * @return void
     */
    public function boot()
    {
        // El usuario lo fija el middleware Authenticate.
        $this->app['auth']->viaRequest('api', function () {
            return null;
        });

        // El Administrador puede hacer todo.
        Gate::before(function (Worker $worker) {
            return $worker->is_admin ? true : null;
        });

        foreach ($this->policies as $model => $policy) {
            Gate::policy($model, $policy);
        }
    }
}
