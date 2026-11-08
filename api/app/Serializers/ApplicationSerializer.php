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
            'denialReason' => ['denial-reasons', 'denial_reason_id', 'denialReason'],
            'resolvedBy' => ['users', 'resolved_by', 'resolver'],
        ];
    }
}
