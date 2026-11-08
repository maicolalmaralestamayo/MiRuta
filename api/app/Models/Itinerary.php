<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Itinerary extends Model
{
    protected $fillable = ['entity_id', 'name', 'description', 'observation', 'image_path', 'active'];

    protected $casts = ['active' => 'boolean', 'entity_id' => 'integer'];

    public function entity()
    {
        return $this->belongsTo(Entity::class);
    }

    /**
     * Paradas en orden (1 = primera).
     */
    public function stops()
    {
        return $this->belongsToMany(Stop::class, 'itinerary_stop')->withPivot('id', 'position')->withTimestamps()->orderBy('itinerary_stop.position');
    }

    /**
     * Ids de las paradas en orden.
     *
     * @return int[]
     */
    public function stopIds(): array
    {
        return array_map('intval', ItineraryStop::where('itinerary_id', $this->id)->orderBy('position')->pluck('stop_id')->all());
    }

    public function hasStop($stopId): bool
    {
        return ItineraryStop::where('itinerary_id', $this->id)->where('stop_id', $stopId)->exists();
    }
}
