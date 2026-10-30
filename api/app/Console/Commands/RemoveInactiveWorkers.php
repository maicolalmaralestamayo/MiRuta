<?php

namespace App\Console\Commands;

use App\Services\Inactivity;
use Illuminate\Console\Command;

class RemoveInactiveWorkers extends Command
{
    protected $signature = 'workers:inactivity';

    protected $description = 'Avisa y da de baja de su itinerario a quien no viaja desde hace inactivity_days días';

    public function handle(Inactivity $inactivity)
    {
        list($warned, $removed) = $inactivity->run();

        $this->info("Avisados: {$warned}. Dados de baja: {$removed}.");
    }
}
