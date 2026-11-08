<?php

namespace App\Serializers;

use App\Models\TripPassenger;
use App\Services\Trips;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Viaje de ida o de regreso. meta: pasajeros esperados, capacidad y el estado
 * de quien consulta («Mi estado»).
 */
class TripSerializer extends Serializer
{
    public function type(): string
    {
        return 'trips';
    }

    public function attributes(Model $trip, Request $request): array
    {
        return [
            'direction' => $trip->direction,
            'date' => $this->day($trip->date),
            'departureTime' => $trip->departure_time,
            'departsAt' => $this->date($trip->departs_at),
            'status' => $trip->status,
            'statusChangedAt' => $this->date($trip->status_changed_at),
            'finishReason' => $trip->finish_reason,
            'observation' => $trip->observation,
            'vehicleState' => $trip->vehicle_state,
            'vehicleStateSince' => $this->date($trip->vehicle_state_since),
            'vehicleAtStop' => (bool) $trip->vehicle_at_stop,
            'nextStopIndex' => (int) $trip->next_stop_index,
            'arrivedAt' => $this->date($trip->arrived_at),
            'editable' => $trip->status === \App\Models\Trip::PLANNED,
            'updatedAt' => $this->date($trip->updated_at),
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'itinerary' => ['itineraries', 'itinerary_id', 'itinerary'],
            'vehicleType' => ['vehicle-types', 'vehicle_type_id', 'vehicleType'],
            'detentionCause' => ['detention-causes', 'detention_cause_id', 'detentionCause'],
            'createdBy' => ['users', 'created_by', 'creator'],
        ];
    }

    public function meta(Model $trip, Request $request): array
    {
        $viewer = $request->user();
        $mine = $viewer ? TripPassenger::where('trip_id', $trip->id)->where('user_id', $viewer->id)->value('state') : null;
        $type = $trip->vehicleType;

        return [
            'expectedPassengers' => app(Trips::class)->expectedQuery($trip)->count(),
            'capacity' => $type ? $type->capacity() : null,
            'myState' => $mine,
        ];
    }
}
