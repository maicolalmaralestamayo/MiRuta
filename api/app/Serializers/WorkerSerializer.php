<?php

namespace App\Serializers;

use App\Models\WorkerItinerary;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * La persona en una Entidad (tarjeta de persona: include=user).
 * meta.itineraries: sus itinerarios en esa Entidad, con la parada de cada uno.
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
            'active' => (bool) $worker->active,
            'createdAt' => $this->date($worker->created_at),
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'user' => ['users', 'user_id', 'user'],
            'entity' => ['entities', 'entity_id', 'entity'],
        ];
    }

    public function meta(Model $worker, Request $request): array
    {
        return [
            'itineraries' => WorkerItinerary::where('worker_id', $worker->id)->with('itinerary', 'stop')->orderBy('id')->get()
                ->map(fn (WorkerItinerary $p) => WorkerItinerarySerializer::summary($p))->values()->all(),
        ];
    }
}
