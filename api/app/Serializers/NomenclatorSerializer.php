<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Nomencladores: denominación, descripción y observación.
 */
abstract class NomenclatorSerializer extends Serializer
{
    public function attributes(Model $model, Request $request): array
    {
        return [
            'name' => $model->name,
            'description' => $model->description,
            'observation' => $model->observation,
        ];
    }
}
