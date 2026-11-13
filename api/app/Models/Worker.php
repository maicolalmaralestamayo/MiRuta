<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * La persona en una Entidad (activada o no). Sus itinerarios en ella, con la
 * parada de cada uno y la jefatura, están en worker_itineraries.
 */
class Worker extends Model
{
    protected $fillable = ['user_id', 'entity_id', 'active'];

    protected $casts = [
        'active' => 'boolean',
        'user_id' => 'integer',
        'entity_id' => 'integer',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function entity()
    {
        return $this->belongsTo(Entity::class);
    }

    public function placements()
    {
        return $this->hasMany(WorkerItinerary::class);
    }
}
