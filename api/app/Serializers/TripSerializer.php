<?php

namespace App\Serializers;

use App\Models\TripLeg;
use App\Services\TripTimeliness;
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
            // Atraso (docs/09): minutos de atraso al comenzar o hasta ahora; NULL si no hay.
            'outboundDelayed' => app(TripTimeliness::class)->isDelayed($trip, TripLeg::DIRECTION_OUTBOUND),
            'returnDelayed' => app(TripTimeliness::class)->isDelayed($trip, TripLeg::DIRECTION_RETURN),
            'outboundDelayMinutes' => app(TripTimeliness::class)->delayMinutes($trip, TripLeg::DIRECTION_OUTBOUND),
            'returnDelayMinutes' => app(TripTimeliness::class)->delayMinutes($trip, TripLeg::DIRECTION_RETURN),
            'updatedAt' => $this->date($trip->updated_at),
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'itinerary' => ['itineraries', 'itinerary_id', 'itinerary'],
            'vehicle' => ['vehicles', 'vehicle_id', 'vehicle'],
            'driver' => ['workers', 'driver_id', 'driver'],
            'createdBy' => ['users', 'created_by', 'creator'],
        ];
    }

    public function meta(Model $trip, Request $request): array
    {
        $itinerary = $trip->itinerary;
        $departure = $itinerary ? $itinerary->departureStop() : null;
        $return = $itinerary ? $itinerary->returnStop() : null;

        return app(Trips::class)->occupancy($trip) + [
            // El chofer se dio de baja o ya no puede conducir.
            'needsReassignment' => $trip->isPending() && ! app(\App\Services\Memberships::class)->canDrive($trip->driver),
            'departurePoint' => $departure ? ['type' => 'stops', 'id' => (string) $departure->id] : null,
            'returnPoint' => $return ? ['type' => 'stops', 'id' => (string) $return->id] : null,
        ];
    }
}
