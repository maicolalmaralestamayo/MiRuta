<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class ItinerarySerializer extends NomenclatorSerializer
{
    public function type(): string
    {
        return 'itineraries';
    }

    public function meta(Model $itinerary, Request $request): array
    {
        $departure = $itinerary->departureStop();
        $return = $itinerary->returnStop();

        return [
            'departurePoint' => $departure ? ['type' => 'stops', 'id' => (string) $departure->id] : null,
            'returnPoint' => $return ? ['type' => 'stops', 'id' => (string) $return->id] : null,
            'stopIds' => $itinerary->stops->pluck('id')->map(function ($id) {
                return (string) $id;
            })->all(),
            'memberCount' => $itinerary->members()->count(),
        ];
    }
}
