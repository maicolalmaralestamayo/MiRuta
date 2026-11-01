<?php

namespace App\Services;

use App\Models\ItineraryChief;
use App\Models\Notice;
use App\Models\TransportChief;
use App\Models\User;
use App\Models\Worker;

/**
 * Avisos del servidor. Los destinatarios son cuentas (users).
 */
class Notices
{
    /**
     * @param int[] $userIds
     */
    public function send(array $userIds, string $type, ?int $applicationId = null, ?int $tripId = null, ?int $exceptUserId = null, ?array $payload = null): void
    {
        foreach (array_unique(array_filter($userIds)) as $userId) {
            if ($exceptUserId !== null && (int) $userId === $exceptUserId) {
                continue;
            }

            Notice::create([
                'user_id' => $userId,
                'type' => $type,
                'application_id' => $applicationId,
                'trip_id' => $tripId,
                'payload' => $payload,
            ]);
        }
    }

    /**
     * @return int[]
     */
    public function adminIds(): array
    {
        return array_map('intval', User::where('is_admin', true)->pluck('id')->all());
    }

    /**
     * Cuentas de los Jefes de Transporte de una Entidad.
     *
     * @return int[]
     */
    public function transportChiefIds(?int $entityId): array
    {
        if ($entityId === null) {
            return [];
        }

        return array_map('intval', Worker::where('entity_id', $entityId)
            ->whereIn('id', TransportChief::query()->select('worker_id'))
            ->pluck('user_id')->all());
    }

    /**
     * Cuentas de los Jefes de un itinerario.
     *
     * @return int[]
     */
    public function itineraryChiefIds(?int $itineraryId): array
    {
        if ($itineraryId === null) {
            return [];
        }

        return array_map('intval', Worker::whereIn('id', ItineraryChief::where('itinerary_id', $itineraryId)->select('worker_id'))
            ->pluck('user_id')->all());
    }

    public function userIdOfWorker(?int $workerId): ?int
    {
        if ($workerId === null) {
            return null;
        }

        $userId = Worker::withTrashed()->whereKey($workerId)->value('user_id');

        return $userId === null ? null : (int) $userId;
    }
}
