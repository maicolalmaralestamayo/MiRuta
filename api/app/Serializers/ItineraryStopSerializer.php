<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class ItineraryStopSerializer extends Serializer
{
    public function type(): string
    {
        return 'itinerary-stops';
    }

    public function attributes(Model $itineraryStop, Request $request): array
    {
        return ['position' => $itineraryStop->position];
    }

    public function toOneRelationships(): array
    {
        return [
            'itinerary' => ['itineraries', 'itinerary_id', 'itinerary'],
            'stop' => ['stops', 'stop_id', 'stop'],
        ];
    }
}
