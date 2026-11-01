<?php

namespace App\Serializers;

use App\Services\Tracking;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class TripLegSerializer extends Serializer
{
    public function type(): string
    {
        return 'trip-legs';
    }

    public function attributes(Model $leg, Request $request): array
    {
        return [
            'direction' => $leg->direction,
            'startedAt' => $this->date($leg->started_at),
            'endedAt' => $this->date($leg->ended_at),
            'endReason' => $leg->end_reason,
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'trip' => ['trips', 'trip_id', 'trip'],
            'startedBy' => ['users', 'started_by', 'starter'],
        ];
    }

    public function meta(Model $leg, Request $request): array
    {
        $combined = $leg->isActive() ? app(Tracking::class)->combinedPosition($leg) : ['position' => null, 'activeSensors' => 0];

        return [
            'currentPosition' => $combined['position'],
            'activeSensors' => $combined['activeSensors'],
            'stopPasses' => $leg->stopPasses()->orderBy('passed_at')->get()->map(function ($pass) {
                return [
                    'stopId' => (string) $pass->stop_id,
                    'passedAt' => $pass->passed_at->toIso8601String(),
                    'status' => $pass->status,
                ];
            })->all(),
            'deviating' => (bool) $leg->deviating,
            'incidents' => $leg->incidents()->orderBy('started_at')->get()->map(function ($incident) {
                return [
                    'type' => $incident->type,
                    'stopId' => $incident->stop_id ? (string) $incident->stop_id : null,
                    'latitude' => $incident->latitude,
                    'longitude' => $incident->longitude,
                    'distanceM' => $incident->distance_m,
                    'startedAt' => $incident->started_at->toIso8601String(),
                    'endedAt' => $incident->ended_at ? $incident->ended_at->toIso8601String() : null,
                ];
            })->all(),
        ];
    }
}
