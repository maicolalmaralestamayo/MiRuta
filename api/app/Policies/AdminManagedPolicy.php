<?php

namespace App\Policies;

use App\Models\User;

/**
 * Solo el Administrador (Gate::before), p. ej. Entidades y nomencladores comunes.
 */
class AdminManagedPolicy extends ManagedPolicy
{
    protected function manages(User $user, $model = null): bool
    {
        return false;
    }
}
