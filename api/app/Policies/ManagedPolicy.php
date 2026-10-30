<?php

namespace App\Policies;

use App\Models\Worker;

/**
 * Cualquier usuario autenticado puede ver; solo quien gestiona puede crear,
 * modificar o borrar. El Administrador siempre puede (Gate::before).
 */
abstract class ManagedPolicy
{
    abstract protected function manages(Worker $worker): bool;

    public function viewAny(?Worker $worker): bool
    {
        return true;
    }

    public function view(?Worker $worker, $model): bool
    {
        return true;
    }

    public function create(Worker $worker): bool
    {
        return $this->manages($worker);
    }

    public function update(Worker $worker, $model): bool
    {
        return $this->manages($worker);
    }

    public function delete(Worker $worker, $model): bool
    {
        return $this->manages($worker);
    }
}
