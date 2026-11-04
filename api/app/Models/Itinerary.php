<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Itinerary extends Model
{
    use SoftDeletes;

    protected $fillable = ['entity_id', 'name', 'description', 'observation', 'image_path', 'reference_outbound_leg_id', 'reference_return_leg_id'];

    public function referenceOutboundLeg()
    {
        return $this->belongsTo(TripLeg::class, 'reference_outbound_leg_id');
    }

    public function referenceReturnLeg()
    {
        return $this->belongsTo(TripLeg::class, 'reference_return_leg_id');
    }

    /**
     * Viaje de ida o de regreso marcado como recorrido de referencia (opción B, docs/09 §8).
     */
    public function referenceLegId(string $direction): ?int
    {
        $id = $direction === TripLeg::DIRECTION_OUTBOUND ? $this->reference_outbound_leg_id : $this->reference_return_leg_id;

        return $id ? (int) $id : null;
    }

    /**
     * Paradas en orden. La primera es el punto de salida y la última, el de regreso.
     */
    public function itineraryStops()
    {
        return $this->hasMany(ItineraryStop::class)->orderBy('position');
    }

    public function stops()
    {
        return $this->belongsToMany(Stop::class, 'itinerary_stop')
            ->withPivot('id', 'position')
            ->wherePivotNull('deleted_at')
            ->orderBy('itinerary_stop.position');
    }

    public function members()
    {
        return $this->hasMany(Worker::class);
    }

    /**
     * Marca como modificados los viajes que aún no se realizaron ni cancelaron
     * (sus puntos de salida y regreso dependen de las paradas del itinerario).
     */
    public function touchPendingTrips(): void
    {
        if (class_exists(Trip::class)) {
            Trip::where('itinerary_id', $this->id)
                ->whereIn('status', [Trip::STATUS_UNCONFIRMED, Trip::STATUS_CONFIRMED])
                ->update(['updated_at' => \Carbon\Carbon::now()]);
        }
    }

    public function departureStop(): ?Stop
    {
        return $this->stops->first();
    }

    public function returnStop(): ?Stop
    {
        return $this->stops->last();
    }

    public function entity()
    {
        return $this->belongsTo(Entity::class)->withTrashed();
    }
}
