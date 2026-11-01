<?php

namespace App\Console\Commands;

use App\Services\TripTimeliness;
use Illuminate\Console\Command;

/**
 * Avisa de los viajes que no comenzaron a su hora (docs/09-repaso-pantallas.md).
 */
class NotifyTripDelays extends Command
{
    protected $signature = 'trips:notify-delays';

    protected $description = 'Avisa de los viajes de ida o de regreso atrasados';

    public function handle(TripTimeliness $timeliness)
    {
        $this->info('Viajes avisados: '.$timeliness->notifyDelays().'.');
    }
}
