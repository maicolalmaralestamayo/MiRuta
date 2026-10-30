<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class TripPositionSerializer extends Serializer
{
    public function type(): string
    {
        return 'trip-positions';
    }

    public function attributes(Model $position, Request $request): array
    {
        return [
            'latitude' => $position->latitude,
            'longitude' => $position->longitude,
            'accuracyM' => $position->accuracy_m,
            'recordedAt' => $position->recorded_at->format('Y-m-d\TH:i:s.vP'),
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'tripLeg' => ['trip-legs', 'trip_leg_id', 'tripLeg'],
            'worker' => ['workers', 'worker_id', 'worker'],
        ];
    }
}
