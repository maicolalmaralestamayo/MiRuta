<?php

namespace App\Console\Commands;

use App\Services\AccessRecoveries;
use Illuminate\Console\Command;

class ExpireAccessRecoveries extends Command
{
    protected $signature = 'access-recoveries:expire';

    protected $description = 'Cierra las solicitudes "No puedo entrar" caducadas y borra su teléfono';

    public function handle(AccessRecoveries $recoveries)
    {
        $this->info('Caducadas: '.$recoveries->expireOld().'.');
    }
}
