<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Ausencia declarada (sin aprobación).
 */
class AbsenceSerializer extends Serializer
{
    public function type(): string
    {
        return 'absences';
    }

    public function attributes(Model $absence, Request $request): array
    {
        return [
            'startsOn' => $absence->starts_on ? $absence->starts_on->toDateString() : null,
            'endsOn' => $absence->ends_on ? $absence->ends_on->toDateString() : null,
            'indefinite' => (bool) $absence->indefinite,
            'note' => $absence->note,
            'createdAt' => $this->date($absence->created_at),
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'worker' => ['workers', 'worker_id', 'worker'],
            'absenceType' => ['absence-types', 'absence_type_id', 'absenceType'],
        ];
    }
}
