<?php

namespace App\Serializers;

use App\Models\ItineraryStop;
use App\Models\Worker;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class ItinerarySerializer extends Serializer
{
    public function type(): string
    {
        return 'itineraries';
    }

    public function attributes(Model $itinerary, Request $request): array
    {
        return [
            'name' => $itinerary->name,
            'description' => $itinerary->description,
            'observation' => $itinerary->observation,
            'imageUrl' => $this->image($itinerary->image_path),
            'active' => (bool) $itinerary->active,
        ];
    }

    public function toOneRelationships(): array
    {
        return ['entity' => ['entities', 'entity_id', 'entity']];
    }

    public function meta(Model $itinerary, Request $request): array
    {
        return [
            'stopCount' => ItineraryStop::where('itinerary_id', $itinerary->id)->count(),
            'workerCount' => Worker::where('itinerary_id', $itinerary->id)->count(),
        ];
    }
}
