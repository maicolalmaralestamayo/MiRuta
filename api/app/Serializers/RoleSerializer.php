<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Roles vigentes (chofer, Jefe de Transporte, Jefe de itinerario).
 */
abstract class RoleSerializer extends Serializer
{
    public function attributes(Model $role, Request $request): array
    {
        return ['createdAt' => $this->date($role->created_at)];
    }

    public function toOneRelationships(): array
    {
        return ['worker' => ['workers', 'worker_id', 'worker']];
    }
}
