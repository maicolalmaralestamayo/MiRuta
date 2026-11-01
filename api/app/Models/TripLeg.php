<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Trayecto de un viaje: salida (paradas en orden) o regreso (orden inverso).
 */
class TripLeg extends Model
{
    use SoftDeletes;

    const DIRECTION_OUTBOUND = 'outbound';
    const DIRECTION_RETURN = 'return';

    const END_LAST_STOP = 'last_stop';
    const END_MANUAL = 'manual';

    protected $fillable = [
        'trip_id', 'direction', 'started_at', 'started_by', 'ended_at', 'ended_by', 'end_reason',
        'last_latitude', 'last_longitude', 'last_position_at', 'deviating',
    ];

    protected $casts = [
        'started_at' => 'datetime',
        'ended_at' => 'datetime',
        'last_position_at' => 'datetime',
        'last_latitude' => 'float',
        'last_longitude' => 'float',
        'deviating' => 'boolean',
    ];

    public function incidents()
    {
        return $this->hasMany(TripLegIncident::class);
    }

    public function trip()
    {
        return $this->belongsTo(Trip::class);
    }

    public function starter()
    {
        return $this->belongsTo(User::class, 'started_by')->withTrashed();
    }

    public function positions()
    {
        return $this->hasMany(TripPosition::class);
    }

    public function stopPasses()
    {
        return $this->hasMany(TripStopPass::class);
    }

    public function boardings()
    {
        return $this->hasMany(TripBoarding::class);
    }

    public function isActive(): bool
    {
        return $this->ended_at === null;
    }

    /**
     * Paradas del itinerario en el orden de este trayecto.
     *
     * @return \Illuminate\Support\Collection|Stop[]
     */
    public function orderedStops()
    {
        $stops = $this->trip->itinerary->stops;

        return $this->direction === self::DIRECTION_RETURN ? $stops->reverse()->values() : $stops->values();
    }
}
