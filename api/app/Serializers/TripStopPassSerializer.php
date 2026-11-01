<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class TripStopPassSerializer extends Serializer
{
    public function type(): string
    {
        return 'trip-stop-passes';
    }

    public function attributes(Model $pass, Request $request): array
    {
        return [
            'passedAt' => $this->date($pass->passed_at),
            'leftAt' => $this->date($pass->left_at),
            'status' => $pass->status,
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'tripLeg' => ['trip-legs', 'trip_leg_id', 'tripLeg'],
            'stop' => ['stops', 'stop_id', 'stop'],
        ];
    }
}
