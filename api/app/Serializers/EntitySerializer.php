<?php

namespace App\Serializers;

use App\Models\Worker;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class EntitySerializer extends Serializer
{
    public function type(): string
    {
        return 'entities';
    }

    public function attributes(Model $entity, Request $request): array
    {
        return [
            'abbreviation' => $entity->abbreviation,
            'number' => $entity->number,
            'name' => $entity->name,
            'description' => $entity->description,
            'observation' => $entity->observation,
            'imageUrl' => $this->image($entity->image_path),
            'active' => (bool) $entity->active,
        ];
    }

    public function meta(Model $entity, Request $request): array
    {
        return [
            'workerCount' => Worker::where('entity_id', $entity->id)->count(),
            'itineraryCount' => $entity->itineraries()->count(),
        ];
    }
}
