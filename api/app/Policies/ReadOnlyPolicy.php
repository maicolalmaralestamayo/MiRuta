<?php

namespace App\Policies;

use App\Models\Worker;

/**
 * Se puede ver, pero no se crea ni modifica directamente: lo hacen las
 * solicitudes o el propio sistema. El Administrador sí puede (Gate::before).
 */
class ReadOnlyPolicy extends ManagedPolicy
{
    protected function manages(Worker $worker): bool
    {
        return false;
    }
}
