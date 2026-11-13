<?php

namespace App\Serializers;

use App\Models\Entity;
use App\Models\WorkerItinerary;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * La persona en un itinerario (recurso "worker-itineraries"): su parada y si
 * es Jefe. meta trae los nombres para las tarjetas sin tener que pedir include.
 */
class WorkerItinerarySerializer extends Serializer
{
    public function type(): string
    {
        return 'worker-itineraries';
    }

    public function attributes(Model $placement, Request $request): array
    {
        return [
            'isChief' => (bool) $placement->is_chief,
            'createdAt' => $this->date($placement->created_at),
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'user' => ['users', 'user_id', 'user'],
            'worker' => ['workers', 'worker_id', 'worker'],
            'itinerary' => ['itineraries', 'itinerary_id', 'itinerary'],
            'stop' => ['stops', 'stop_id', 'stop'],
        ];
    }

    public function meta(Model $placement, Request $request): array
    {
        $itinerary = $placement->itinerary;
        $entity = $itinerary?->entity_id ? Entity::find($itinerary->entity_id) : null;

        return [
            'userName' => $placement->user?->fullName(),
            'photoUrl' => $placement->user?->photo_path ? url($placement->user->photo_path) : null,
            'active' => (bool) ($placement->worker?->active ?? true),
            'itineraryName' => $itinerary?->name,
            'entityId' => $entity ? (string) $entity->id : null,
            'entityAbbreviation' => $entity?->abbreviation,
            'stopLandmark' => $placement->stop?->landmark,
        ];
    }

    /**
     * Resumen para meta.itineraries de la pertenencia y para Inicio.
     */
    public static function summary(WorkerItinerary $p): array
    {
        $image = fn ($path) => $path ? url($path) : null;

        return [
            'id' => (string) $p->id,
            'isChief' => (bool) $p->is_chief,
            'itinerary' => [
                'id' => (string) $p->itinerary_id,
                'name' => $p->itinerary?->name,
                'imageUrl' => $image($p->itinerary?->image_path),
                'active' => (bool) ($p->itinerary?->active ?? true),
                'workerCount' => WorkerItinerary::where('itinerary_id', $p->itinerary_id)->count(),
            ],
            'stop' => $p->stop ? [
                'id' => (string) $p->stop_id,
                'landmark' => $p->stop->landmark,
                'street' => $p->stop->street,
                'imageUrl' => $image($p->stop->image_path),
                'latitude' => (float) $p->stop->latitude,
                'longitude' => (float) $p->stop->longitude,
            ] : null,
        ];
    }
}
