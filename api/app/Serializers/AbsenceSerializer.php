<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class AbsenceSerializer extends Serializer
{
    public function type(): string
    {
        return 'absences';
    }

    public function attributes(Model $absence, Request $request): array
    {
        return [
            'startsOn' => $this->day($absence->starts_on),
            'endsOn' => $this->day($absence->ends_on),
            'indefinite' => $absence->ends_on === null,
            'note' => $absence->note,
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
