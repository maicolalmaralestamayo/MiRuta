<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * La persona en una Entidad: itinerario y parada (opcionales), si es Jefe de
 * ese itinerario y si está activada.
 */
class Worker extends Model
{
    protected $fillable = ['user_id', 'entity_id', 'itinerary_id', 'stop_id', 'is_chief', 'active'];

    protected $casts = [
        'is_chief' => 'boolean',
        'active' => 'boolean',
        'user_id' => 'integer',
        'entity_id' => 'integer',
        'itinerary_id' => 'integer',
        'stop_id' => 'integer',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function entity()
    {
        return $this->belongsTo(Entity::class);
    }

    public function itinerary()
    {
        return $this->belongsTo(Itinerary::class);
    }

    public function stop()
    {
        return $this->belongsTo(Stop::class);
    }
}
