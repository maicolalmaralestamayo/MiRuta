<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Rol de una persona en una Entidad (en su pertenencia).
 */
class WorkerRoleSerializer extends Serializer
{
    public function type(): string
    {
        return 'worker-roles';
    }

    public function attributes(Model $workerRole, Request $request): array
    {
        $role = $workerRole->role;

        return [
            'roleName' => $role ? $role->name : null,
            'icon' => $role ? $role->icon : null,
            'createdAt' => $this->date($workerRole->created_at),
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'worker' => ['workers', 'worker_id', 'worker'],
            'role' => ['roles', 'role_id', 'role'],
            'itinerary' => ['itineraries', 'itinerary_id', 'itinerary'],
        ];
    }
}
