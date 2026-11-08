<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Último informe de un teléfono sensor sobre el vehículo.
 */
class TripVehicleReport extends Model
{
    protected $fillable = ['trip_id', 'user_id', 'vehicle_state', 'at_stop', 'next_stop_index', 'reported_at'];

    protected $casts = ['at_stop' => 'boolean', 'next_stop_index' => 'integer', 'reported_at' => 'datetime', 'user_id' => 'integer'];
}
