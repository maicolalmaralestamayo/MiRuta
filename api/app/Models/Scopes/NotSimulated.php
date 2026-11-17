<?php

namespace App\Models\Scopes;

use App\Support\SimulationSchema;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Scope;

/**
 * Lo creado por el simulador (docs/11 §11.66) no existe para el resto de la
 * app: Gestión, listas, cantidades, inicio de sesión. Solo el código de la
 * simulación y de su viaje de prueba lo ve (withoutGlobalScope(self::class)).
 */
class NotSimulated implements Scope
{
    public function apply(Builder $builder, Model $model): void
    {
        if (SimulationSchema::ready()) {
            $builder->whereNull($model->qualifyColumn('simulation_id'));
        }
    }
}
