<?php

namespace App\Policies;

use App\Models\Worker;

/**
 * Lo gestionan los Jefes de Transporte (y el Administrador).
 */
class TransportManagedPolicy extends ManagedPolicy
{
    protected function manages(Worker $worker): bool
    {
        return $worker->isTransportChief();
    }
}
