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
        $attributes = [
            'type' => $application->type,
            'status' => $application->status,
            'resolutionNote' => $application->resolution_note,
            'resolvedAt' => $this->date($application->resolved_at),
            'createdAt' => $this->date($application->created_at),
        ];

        if ($child = $application->related_child) {
            $attributes['childFirstName'] = $child->first_name;
            $attributes['childLastName'] = $child->last_name;
        }

        if ($absence = $application->absenceApplication) {
            $attributes['startsOn'] = $absence->starts_on->toDateString();
            $attributes['endsOn'] = $absence->ends_on->toDateString();
            $attributes['observation'] = $absence->observation;
        }

        return $attributes;
    }

    public function toOneRelationships(): array
    {
        return [
            'worker' => ['workers', 'worker_id', 'worker'],
            'resolvedBy' => ['workers', 'resolved_by', 'resolver'],
            'itinerary' => ['itineraries', 'itinerary_id', 'requested_itinerary'],
            'stop' => ['stops', 'stop_id', 'requested_stop'],
            'rank' => ['ranks', 'rank_id', 'requested_rank'],
            'child' => ['children', 'child_id', 'related_child'],
            'absenceType' => ['absence-types', 'absence_type_id', 'related_absence_type'],
        ];
    }
}
