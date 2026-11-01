<?php

namespace App\Providers;

use App\Models\User;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\ServiceProvider;

class AuthServiceProvider extends ServiceProvider
{
    /**
     * Políticas de autorización por modelo.
     *
     * @var array
     */
    protected $policies = [
        \App\Models\Rank::class => \App\Policies\AdminManagedPolicy::class,
        \App\Models\ConversationTopic::class => \App\Policies\AdminManagedPolicy::class,
        \App\Models\VehicleType::class => \App\Policies\AdminManagedPolicy::class,
        \App\Models\AbsenceType::class => \App\Policies\AdminManagedPolicy::class,
        \App\Models\Entity::class => \App\Policies\AdminManagedPolicy::class,
        \App\Models\Itinerary::class => \App\Policies\TransportManagedPolicy::class,
        \App\Models\Stop::class => \App\Policies\TransportManagedPolicy::class,
        \App\Models\ItineraryStop::class => \App\Policies\TransportManagedPolicy::class,
        \App\Models\Vehicle::class => \App\Policies\TransportManagedPolicy::class,
        \App\Models\Worker::class => \App\Policies\ReadOnlyPolicy::class,
        \App\Models\ItineraryChief::class => \App\Policies\ReadOnlyPolicy::class,
        \App\Models\Driver::class => \App\Policies\ReadOnlyPolicy::class,
        \App\Models\TransportChief::class => \App\Policies\ReadOnlyPolicy::class,
    ];

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
        Gate::before(function (User $user) {
            return $user->is_admin ? true : null;
        });

        foreach ($this->policies as $model => $policy) {
            Gate::policy($model, $policy);
        }
    }
}
