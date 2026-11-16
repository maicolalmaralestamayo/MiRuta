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
        return [
            'type' => $application->type,
            'status' => $application->status,
            'resolutionNote' => $application->resolution_note,
            'resolvedAt' => $this->date($application->resolved_at),
            'seenAt' => $this->date($application->seen_at),
            'createdAt' => $this->date($application->created_at),
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'user' => ['users', 'user_id', 'user'],
            'entity' => ['entities', 'entity_id', 'entity'],
            'itinerary' => ['itineraries', 'itinerary_id', 'itinerary'],
            'stop' => ['stops', 'stop_id', 'stop'],
            'denialReason' => ['itinerary-denial-reasons', 'itinerary_denial_reason_id', 'itineraryDenialReason'],
            'resolvedBy' => ['users', 'resolved_by', 'resolver'],
        ];
    }

    /** El motivo de rechazo sale de la tabla del tipo de la solicitud (docs/11 §11.65). */
    public function relationshipsFor(Model $application): array
    {
        $relationships = $this->toOneRelationships();

        if ($application->type === 'entidad') {
            $relationships['denialReason'] = ['entity-denial-reasons', 'entity_denial_reason_id', 'entityDenialReason'];
        }

        return $relationships;
    }
}
