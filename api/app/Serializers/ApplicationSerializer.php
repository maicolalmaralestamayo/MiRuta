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
            'assigned' => $application->created_by !== null && $application->worker && (int) $application->created_by !== (int) $application->worker->user_id,
            'createdAt' => $this->date($application->created_at),
        ];

        if ($child = $application->related_child) {
            $attributes['childFullName'] = $child->fullName();
            $attributes['possibleDuplicate'] = $application->type === 'child_addition' && $application->isPending()
                && app(\App\Services\Children::class)->hasPossibleDuplicate($child);
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
            'createdBy' => ['users', 'created_by', 'creator'],
            'resolvedBy' => ['users', 'resolved_by', 'resolver'],
            'itinerary' => ['itineraries', 'itinerary_id', 'requested_itinerary'],
            'stop' => ['stops', 'stop_id', 'requested_stop'],
            'child' => ['children', 'child_id', 'related_child'],
            'absenceType' => ['absence-types', 'absence_type_id', 'related_absence_type'],
        ];
    }
}
