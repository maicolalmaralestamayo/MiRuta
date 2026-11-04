<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class EntitySerializer extends NomenclatorSerializer
{
    public function type(): string
    {
        return 'entities';
    }

    public function attributes(Model $entity, Request $request): array
    {
        return ['abbreviation' => $entity->abbreviation, 'number' => $entity->number]
            + parent::attributes($entity, $request)
            + [
                'imageUrl' => $entity->image_path ? url($entity->image_path) : null,
                'active' => ! $entity->trashed(),
                'workerCount' => \App\Models\Worker::where('entity_id', $entity->id)->count(),
            ];
    }
}
