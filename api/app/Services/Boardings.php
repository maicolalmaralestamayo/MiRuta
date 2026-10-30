<?php

namespace App\Services;

use Illuminate\Support\Facades\Schema;

/**
 * Registros de subida al vehículo.
 */
class Boardings
{
    /**
     * Último registro de subida de cada trabajador en el trayecto del viaje.
     *
     * @return array [id de trabajador => registro]
     */
    public function latestByWorker(int $tripId, string $direction): array
    {
        if (! Schema::hasTable('trip_boardings')) {
            return [];
        }

        return [];
    }
}
