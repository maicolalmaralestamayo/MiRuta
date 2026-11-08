<?php

namespace App\Serializers;

use App\Models\ItineraryStop;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Parada (compartida entre itinerarios). meta.itineraries: en qué itinerarios
 * está y en qué posición (vacía = «Sin itinerario»).
 */
class StopSerializer extends Serializer
{
    public function type(): string
    {
        return 'stops';
    }

    public function attributes(Model $stop, Request $request): array
    {
        return [
            'landmark' => $stop->landmark,
            'street' => $stop->street,
            'crossStreet1' => $stop->cross_street_1,
            'crossStreet2' => $stop->cross_street_2,
            'latitude' => (float) $stop->latitude,
            'longitude' => (float) $stop->longitude,
            'imageUrl' => $this->image($stop->image_path),
            'active' => (bool) $stop->active,
        ];
    }

    public function meta(Model $stop, Request $request): array
    {
        $links = ItineraryStop::where('stop_id', $stop->id)
            ->join('itineraries', 'itineraries.id', '=', 'itinerary_stop.itinerary_id')
            ->orderBy('itineraries.name')
            ->get(['itinerary_stop.id', 'itinerary_stop.itinerary_id', 'itinerary_stop.position', 'itineraries.name', 'itineraries.entity_id']);

        return [
            'itineraries' => $links->map(fn ($link) => [
                'itineraryStopId' => (string) $link->id,
                'itineraryId' => (string) $link->itinerary_id,
                'name' => $link->name,
                'entityId' => (string) $link->entity_id,
                'position' => (int) $link->position,
            ])->values()->all(),
        ];
    }
}
