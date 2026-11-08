<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * La persona en una Entidad (tarjeta de persona en Gestión: include=user).
 */
class WorkerSerializer extends Serializer
{
    public function type(): string
    {
        return 'workers';
    }

    public function attributes(Model $worker, Request $request): array
    {
        return [
            'isChief' => (bool) $worker->is_chief,
            'active' => (bool) $worker->active,
            'createdAt' => $this->date($worker->created_at),
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'user' => ['users', 'user_id', 'user'],
            'entity' => ['entities', 'entity_id', 'entity'],
            'itinerary' => ['itineraries', 'itinerary_id', 'itinerary'],
            'stop' => ['stops', 'stop_id', 'stop'],
        ];
    }
}
