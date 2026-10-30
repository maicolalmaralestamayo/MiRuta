<?php

namespace App\Serializers;

use App\Services\Trips;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class TripSerializer extends Serializer
{
    public function type(): string
    {
        return 'trips';
    }

    public function attributes(Model $trip, Request $request): array
    {
        return [
            'departsAt' => $this->date($trip->departs_at),
            'returnsAt' => $this->date($trip->returns_at),
            'status' => $trip->status,
            'updatedAt' => $this->date($trip->updated_at),
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'itinerary' => ['itineraries', 'itinerary_id', 'itinerary'],
            'vehicle' => ['vehicles', 'vehicle_id', 'vehicle'],
            'driver' => ['drivers', 'driver_id', 'driver'],
            'createdBy' => ['workers', 'created_by', 'creator'],
        ];
    }

    public function meta(Model $trip, Request $request): array
    {
        $itinerary = $trip->itinerary;
        $departure = $itinerary ? $itinerary->departureStop() : null;
        $return = $itinerary ? $itinerary->returnStop() : null;

        return app(Trips::class)->occupancy($trip) + [
            'needsReassignment' => $trip->isPending() && (! $trip->driver || $trip->driver->trashed()),
            'departurePoint' => $departure ? ['type' => 'stops', 'id' => (string) $departure->id] : null,
            'returnPoint' => $return ? ['type' => 'stops', 'id' => (string) $return->id] : null,
        ];
    }
}
