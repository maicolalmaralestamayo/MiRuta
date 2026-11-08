<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Parada: puede estar en varios itinerarios de varias Entidades (docs/11 §11.24).
 */
class Stop extends Model
{
    protected $fillable = ['landmark', 'street', 'cross_street_1', 'cross_street_2', 'latitude', 'longitude', 'image_path', 'active'];

    protected $casts = ['active' => 'boolean', 'latitude' => 'float', 'longitude' => 'float'];

    public function itineraries()
    {
        return $this->belongsToMany(Itinerary::class, 'itinerary_stop')->withPivot('id', 'position');
    }
}
