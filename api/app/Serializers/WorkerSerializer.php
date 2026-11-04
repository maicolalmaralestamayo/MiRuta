<?php

namespace App\Serializers;

use App\Models\WorkerRole;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Pertenencia persona–Entidad. Los nombres y la foto vienen de la persona;
 * el carné, solo para quien puede verlo (ver UserSerializer).
 */
class WorkerSerializer extends Serializer
{
    public function type(): string
    {
        return 'workers';
    }

    public function attributes(Model $worker, Request $request): array
    {
        $user = $worker->user;
        $attributes = [
            'firstName' => $user ? $user->first_name : null,
            'middleName' => $user ? $user->middle_name : null,
            'firstSurname' => $user ? $user->first_surname : null,
            'secondSurname' => $user ? $user->second_surname : null,
            'fullName' => $user ? $user->fullName() : null,
            'sex' => $user ? $user->sex : null,
            'photoUrl' => $user && $user->photo_path ? url($user->photo_path) : null,
            'hasPhone' => $user ? (bool) $user->has_phone : null,
            'active' => ! $worker->trashed(),
            'itineraryAssignedAt' => $this->date($worker->itinerary_assigned_at),
            'createdAt' => $this->date($worker->created_at),
        ];

        if ($user && UserSerializer::canSeeIdentityCard($user, $request)) {
            $attributes['identityCard'] = $user->identityCard();
        }

        return $attributes;
    }

    public function meta(Model $worker, Request $request): array
    {
        if ($worker->trashed()) {
            return [];
        }

        return [
            'roles' => WorkerRole::where('worker_id', $worker->id)->with('role')->get()->filter(function ($workerRole) {
                return $workerRole->role && ! $workerRole->role->trashed();
            })->map(function ($workerRole) {
                return [
                    'id' => (string) $workerRole->id,
                    'roleId' => (string) $workerRole->role_id,
                    'name' => $workerRole->role->name,
                    'icon' => $workerRole->role->icon,
                    'itineraryId' => $workerRole->itinerary_id ? (string) $workerRole->itinerary_id : null,
                ];
            })->values()->all(),
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
