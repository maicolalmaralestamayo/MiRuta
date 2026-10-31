<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Stop extends Model
{
    use SoftDeletes;

    protected $fillable = ['entity_id', 'landmark', 'street', 'cross_street_1', 'cross_street_2', 'latitude', 'longitude'];

    protected $casts = [
        'latitude' => 'float',
        'longitude' => 'float',
    ];

    public function itineraryStops()
    {
        return $this->hasMany(ItineraryStop::class);
    }

    /**
     * Dirección legible: "Punto de referencia, Calle entre A y B".
     */
    public function address(): string
    {
        $between = array_filter([$this->cross_street_1, $this->cross_street_2]);
        $street = $this->street.($between ? ' entre '.implode(' y ', $between) : '');

        return $this->landmark.', '.$street;
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
