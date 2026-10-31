<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Itinerary extends Model
{
    use SoftDeletes;

    protected $fillable = ['entity_id', 'name', 'description', 'observation'];

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

    public function chiefs()
    {
        return $this->hasMany(ItineraryChief::class);
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

    /**
     * Los de la Entidad de esa cuenta (todos, para el Administrador).
     */
    public function scopeVisibleTo($query, User $user)
    {
        return $user->isAdmin() ? $query : $query->where($this->getTable().'.entity_id', $user->entityId());
    }
}
