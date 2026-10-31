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
            'childrenCount' => $boarding->children_count,
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
