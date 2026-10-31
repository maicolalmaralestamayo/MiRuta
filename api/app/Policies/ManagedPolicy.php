<?php

namespace App\Policies;

use App\Models\User;

/**
 * Lectura para todos (lo visible ya lo limita cada consulta por Entidad);
 * crear, modificar y borrar para quien gestiona el recurso.
 */
abstract class ManagedPolicy
{
    abstract protected function manages(User $user, $model = null): bool;

    public function viewAny(?User $user): bool
    {
        return true;
    }

    public function view(?User $user, $model): bool
    {
        return true;
    }

    public function create(User $user): bool
    {
        return $this->manages($user);
    }

    public function update(User $user, $model): bool
    {
        return $this->manages($user, $model);
    }

    public function delete(User $user, $model): bool
    {
        return $this->manages($user, $model);
    }
}
