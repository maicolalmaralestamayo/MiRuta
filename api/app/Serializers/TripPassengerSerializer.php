<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class TripPassengerSerializer extends Serializer
{
    public function type(): string
    {
        return 'trip-passengers';
    }

    public function attributes(Model $passenger, Request $request): array
    {
        return [
            'state' => $passenger->state,
            'stateAt' => $this->date($passenger->state_at),
            'reportedAt' => $this->date($passenger->reported_at),
            'childrenCount' => (int) $passenger->children_count,
            'childIds' => array_map('strval', $passenger->childIds()),
            'lastSeenAt' => $this->date($passenger->last_seen_at),
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'trip' => ['trips', 'trip_id', 'trip'],
            'user' => ['users', 'user_id', 'user'],
            'stop' => ['stops', 'stop_id', 'stop'],
        ];
    }
}
