<?php

namespace App\Serializers;

class TripMessageSerializer extends MessageSerializer
{
    public function type(): string
    {
        return 'trip-messages';
    }

    public function toOneRelationships(): array
    {
        return [
            'trip' => ['trips', 'trip_id', 'trip'],
            'worker' => ['workers', 'worker_id', 'worker'],
        ];
    }
}
