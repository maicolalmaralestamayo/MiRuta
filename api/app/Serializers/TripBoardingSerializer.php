<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class TripBoardingSerializer extends Serializer
{
    public function type(): string
    {
        return 'trip-boardings';
    }

    public function attributes(Model $boarding, Request $request): array
    {
        return [
            'method' => $boarding->method,
            // Hijos que subieron con la persona (cada niño, una vez por trayecto).
            'childIds' => array_map('strval', $boarding->childIds()),
            'childrenCount' => (int) $boarding->children_count,
            // null, itinerary (de otro itinerario) o entity (de otra Entidad).
            'outsider' => $boarding->outsider,
            'qrKind' => $boarding->qr_kind,
            'boardedAt' => $this->date($boarding->boarded_at),
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'tripLeg' => ['trip-legs', 'trip_leg_id', 'tripLeg'],
            'worker' => ['workers', 'worker_id', 'worker'],
            'markedBy' => ['users', 'marked_by', 'marker'],
        ];
    }
}
