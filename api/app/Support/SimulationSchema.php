<?php

namespace App\Support;

use Illuminate\Support\Facades\Schema;

/**
 * ¿Ya está la base de datos de la 4.5.0 (simulador, docs/11 §11.66)? Hasta
 * «Actualizar base de datos» no hay columnas simulation_id: entonces nada se
 * filtra (así el Administrador puede entrar y actualizarla desde la app). Se
 * comprueba una vez por petición.
 */
final class SimulationSchema
{
    public static function ready(): bool
    {
        $app = app();

        if ($app->bound('miruta.simulation.ready')) {
            return (bool) $app->make('miruta.simulation.ready');
        }

        try {
            $ready = Schema::hasTable('simulations') && Schema::hasColumn('users', 'simulation_id');
        } catch (\Throwable $e) {
            $ready = false;
        }

        // Solo se recuerda cuando ya está: tras migrar en la misma petición se vuelve a mirar.
        if ($ready) {
            $app->instance('miruta.simulation.ready', true);
        }

        return $ready;
    }
}
