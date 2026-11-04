<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class ApplicationSerializer extends Serializer
{
    public function type(): string
    {
        return 'applications';
    }

    public function attributes(Model $application, Request $request): array
    {
        $user = $application->user;
        $entity = $application->entity;
        $role = $application->role;

        return [
            'type' => $application->type,
            'status' => $application->status,
            'resolutionNote' => $application->resolution_note,
            'resolvedAt' => $this->date($application->resolved_at),
            'createdAt' => $this->date($application->created_at),
            // Para las tarjetas, sin tener que incluir los recursos.
            'applicantName' => $user ? $user->fullName() : null,
            'entityAbbreviation' => $entity ? $entity->abbreviation : null,
            'itineraryName' => $application->itinerary ? $application->itinerary->name : null,
            'stopLandmark' => $application->stop ? $application->stop->landmark : null,
            'roleName' => $role ? $role->name : null,
            'canResolve' => $request->user() && $application->isPending()
                ? app(\App\Services\Applications::class)->canResolve($request->user(), $application)
                : false,
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'user' => ['users', 'user_id', 'user'],
            'entity' => ['entities', 'entity_id', 'entity'],
            'itinerary' => ['itineraries', 'itinerary_id', 'itinerary'],
            'stop' => ['stops', 'stop_id', 'stop'],
            'role' => ['roles', 'role_id', 'role'],
            'createdBy' => ['users', 'created_by', 'creator'],
            'resolvedBy' => ['users', 'resolved_by', 'resolver'],
        ];
    }
}
