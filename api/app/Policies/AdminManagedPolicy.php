<?php

namespace App\Policies;

use App\Models\Worker;

/**
 * Solo lo gestiona el Administrador.
 */
class AdminManagedPolicy extends ManagedPolicy
{
    protected function manages(Worker $worker): bool
    {
        return false;
    }
}
