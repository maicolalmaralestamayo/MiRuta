<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Viaje de ida o de regreso de un itinerario (docs/11 §11.42 a §11.47).
 */
class Trip extends Model
{
    public const OUTBOUND = 'ida';
    public const RETURN = 'regreso';

    public const PLANNED = 'planificado';
    public const RUNNING = 'en_ejecucion';
    public const FINISHED = 'terminado';
    public const CANCELLED = 'cancelado';

    public const STOPPED = 'detenido';
    public const MOVING = 'en_movimiento';

    protected $fillable = [
        'itinerary_id', 'direction', 'date', 'departure_time', 'departs_at', 'vehicle_type_id', 'observation',
        'status', 'status_changed_at', 'finish_reason', 'created_by', 'route',
        'vehicle_state', 'vehicle_state_since', 'vehicle_at_stop', 'next_stop_index', 'detention_cause_id',
        'long_detention_notified_at', 'arrived_at',
    ];

    protected $casts = [
        'date' => 'date',
        'departs_at' => 'datetime',
        'status_changed_at' => 'datetime',
        'vehicle_state_since' => 'datetime',
        'long_detention_notified_at' => 'datetime',
        'arrived_at' => 'datetime',
        'vehicle_at_stop' => 'boolean',
        'next_stop_index' => 'integer',
        'itinerary_id' => 'integer',
        'vehicle_type_id' => 'integer',
        'created_by' => 'integer',
    ];

    public function itinerary()
    {
        return $this->belongsTo(Itinerary::class);
    }

    public function vehicleType()
    {
        return $this->belongsTo(VehicleType::class);
    }

    public function detentionCause()
    {
        return $this->belongsTo(DetentionCause::class);
    }

    public function creator()
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function isOutbound(): bool
    {
        return $this->direction === self::OUTBOUND;
    }

    public function isOpen(): bool
    {
        return in_array($this->status, [self::PLANNED, self::RUNNING], true);
    }

    /**
     * Paradas en el orden del recorrido (ida: 1…N; regreso: N…1). Fijado al
     * empezar el viaje; antes, el del itinerario.
     *
     * @return int[]
     */
    public function routeStopIds(): array
    {
        if ($this->route) {
            return array_map('intval', explode(',', $this->route));
        }

        $ids = Itinerary::find($this->itinerary_id)?->stopIds() ?? [];

        return $this->isOutbound() ? $ids : array_reverse($ids);
    }
}
