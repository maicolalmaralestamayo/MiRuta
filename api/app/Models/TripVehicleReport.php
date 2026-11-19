<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Último informe de un teléfono sensor sobre el vehículo.
 */
class TripVehicleReport extends Model
{
    protected $fillable = ['trip_id', 'user_id', 'vehicle_state', 'at_stop', 'in_radius', 'next_stop_index', 'speed', 'reported_at'];

    protected $casts = ['at_stop' => 'boolean', 'in_radius' => 'boolean', 'speed' => 'float', 'next_stop_index' => 'integer', 'reported_at' => 'datetime', 'user_id' => 'integer'];
}
