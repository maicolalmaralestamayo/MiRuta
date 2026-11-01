<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Incidencia de un viaje de ida o de regreso: una parada donde no se detuvo,
 * una parada que se saltó o un desvío del recorrido de referencia (docs/09 §8).
 */
class TripLegIncident extends Model
{
    use SoftDeletes;

    const TYPE_NOT_STOPPED = 'not_stopped';
    const TYPE_SKIPPED = 'skipped';
    const TYPE_DEVIATION = 'deviation';

    protected $fillable = ['trip_leg_id', 'type', 'stop_id', 'latitude', 'longitude', 'distance_m', 'started_at', 'ended_at'];

    protected $casts = [
        'started_at' => 'datetime',
        'ended_at' => 'datetime',
        'latitude' => 'float',
        'longitude' => 'float',
        'distance_m' => 'integer',
    ];

    public function leg()
    {
        return $this->belongsTo(TripLeg::class, 'trip_leg_id');
    }

    public function stop()
    {
        return $this->belongsTo(Stop::class);
    }
}
