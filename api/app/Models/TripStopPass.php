<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Estado de una parada del recorrido distinto de En espera (docs/11 §11.67):
 * Recogida (el vehículo se detuvo en ella), Volada (pasó sin detenerse) u
 * Omitida (ni pasó por ella y una parada posterior ya cambió de estado).
 */
class TripStopPass extends Model
{
    public const WAITING = 'en_espera';
    public const PICKED_UP = 'recogida';
    public const FLOWN = 'volada';
    public const SKIPPED = 'omitida';

    protected $fillable = ['trip_id', 'stop_id', 'route_index', 'stop_state', 'passed_at', 'left_at', 'marked_by'];

    protected $casts = ['passed_at' => 'datetime', 'left_at' => 'datetime', 'route_index' => 'integer', 'stop_id' => 'integer', 'marked_by' => 'integer'];
}
