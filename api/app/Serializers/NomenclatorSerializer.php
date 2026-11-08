<?php

namespace App\Serializers;

use App\Services\Nomenclators;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Elemento de nomenclador. meta.usageCount: cuántas veces se usa (en uso no
 * se puede eliminar).
 */
class NomenclatorSerializer extends Serializer
{
    public function __construct(private string $resourceType = 'nomenclators')
    {
    }

    public function type(): string
    {
        return $this->resourceType;
    }

    public function attributes(Model $item, Request $request): array
    {
        $attributes = [
            'name' => $item->name,
            'description' => $item->description,
            'observation' => $item->observation,
            'active' => (bool) $item->active,
        ];

        if ($this->resourceType === 'vehicle-types') {
            $attributes['seats'] = (int) $item->seats;
            $attributes['standing'] = (int) $item->standing;
            $attributes['total'] = (int) $item->seats + (int) $item->standing;
        }

        if ($this->resourceType === 'denial-reasons') {
            $attributes['applicationType'] = $item->application_type;
        }

        return $attributes;
    }

    public function meta(Model $item, Request $request): array
    {
        return ['usageCount' => app(Nomenclators::class)->usageCount($this->resourceType, (int) $item->id)];
    }
}
