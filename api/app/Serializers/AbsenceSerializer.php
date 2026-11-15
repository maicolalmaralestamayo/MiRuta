<?php

namespace App\Serializers;

use App\Models\Itinerary;
use Carbon\Carbon;
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
            'current' => $absence->ends_on === null || ! $absence->ends_on->lt(Carbon::today()),
            'note' => $absence->note,
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'user' => ['users', 'user_id', 'user'],
            'absenceType' => ['absence-types', 'absence_type_id', 'absenceType'],
        ];
    }

    /**
     * Itinerarios que cubre (docs/11 §11.61) y el nombre del tipo, para las
     * tarjetas sin include.
     */
    public function meta(Model $absence, Request $request): array
    {
        $itineraries = Itinerary::with('entity')->whereIn('id', $absence->itineraryIds() ?: [0])->orderBy('name')->get();

        return [
            'absenceTypeName' => $absence->absenceType?->name,
            'itineraries' => $itineraries->map(fn (Itinerary $i) => [
                'id' => (string) $i->id,
                'name' => $i->name,
                'entityAbbreviation' => $i->entity?->abbreviation,
            ])->values()->all(),
        ];
    }
}
