<?php

namespace App\Services;

use App\Models\Notice;
use App\Models\User;
use App\Models\Worker;

/**
 * Avisos del servidor. Los destinatarios son personas (users).
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
     * Personas que pueden hacer la operación en esa Entidad o itinerario.
     *
     * @return int[]
     */
    public function usersWith(string $operation, ?int $entityId = null, ?int $itineraryId = null): array
    {
        return app(Permissions::class)->userIdsWith($operation, $entityId, $itineraryId);
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
