<?php

namespace App\Policies;

use App\Models\User;
use App\Support\Tenancy;

/**
 * El Jefe de Transporte gestiona los recursos de su Entidad (itinerarios,
 * paradas, vehículos…). El Administrador, todos (Gate::before).
 */
class TransportManagedPolicy extends ManagedPolicy
{
    protected function manages(User $user, $model = null): bool
    {
        if (! $user->isTransportChief()) {
            return false;
        }

        return $model === null || Tenancy::entityOf($model->getTable(), $model->getKey()) === $user->entityId();
    }
}
