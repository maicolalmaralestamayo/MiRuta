<?php

namespace App\Services;

use App\Models\Notice;
use App\Models\TransportChief;
use App\Models\Worker;

/**
 * Crea avisos del servidor para uno o varios trabajadores.
 */
class Notices
{
    /**
     * @param int[] $workerIds
     */
    public function send(array $workerIds, string $type, ?int $applicationId = null, ?int $tripId = null, ?int $exceptWorkerId = null): void
    {
        foreach (array_unique($workerIds) as $workerId) {
            if ($exceptWorkerId !== null && (int) $workerId === $exceptWorkerId) {
                continue;
            }

            Notice::create([
                'worker_id' => $workerId,
                'type' => $type,
                'application_id' => $applicationId,
                'trip_id' => $tripId,
            ]);
        }
    }

    /**
     * @return int[]
     */
    public function adminIds(): array
    {
        return array_map('intval', Worker::where('is_admin', true)->pluck('id')->all());
    }

    /**
     * @return int[]
     */
    public function transportChiefIds(): array
    {
        return array_map('intval', TransportChief::whereHas('worker')->pluck('worker_id')->all());
    }

    /**
     * @return int[]
     */
    public function itineraryChiefIds(?int $itineraryId): array
    {
        if ($itineraryId === null) {
            return [];
        }

        return array_map('intval', \App\Models\ItineraryChief::where('itinerary_id', $itineraryId)->whereHas('worker')->pluck('worker_id')->all());
    }
}
