<?php

namespace App\Console\Commands;

use App\Services\Settings;
use App\Services\Trips;
use Illuminate\Console\Command;

/**
 * Marca como realizados los viajes confirmados cuyo regreso ya pasó (7.14).
 */
class AutoCompleteTrips extends Command
{
    protected $signature = 'trips:auto-complete';

    protected $description = 'Marca como realizados los viajes confirmados cuyo regreso ya pasó';

    public function handle(Trips $trips, Settings $settings)
    {
        $due = $trips->dueForAutoCompletion();

        foreach ($due as $trip) {
            $trips->markCompleted($trip, null);
        }

        $this->info("Viajes marcados como realizados: {$due->count()}");
    }
}
