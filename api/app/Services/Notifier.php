<?php

namespace App\Services;

use App\Models\Notification;
use App\Models\Trip;
use App\Models\User;
use App\Models\Worker;
use Carbon\Carbon;

/**
 * Notificaciones del teléfono (docs/11 §11.47 y §11.50). No hay servicio de
 * envío: se guardan aquí y la app las recoge al sincronizar (GET /sync) y las
 * muestra como notificaciones locales. Cada una lleva su título y su texto.
 */
class Notifier
{
    public const APPLICATION_RECEIVED = 'solicitud_recibida';
    public const APPLICATION_RESOLVED = 'solicitud_resuelta';
    public const DEVELOPER_REPLY = 'respuesta_desarrollador';
    public const ACCESS_RECOVERY_RECEIVED = 'olvide_recibida';
    public const TRIP_CREATED = 'viaje_creado';
    public const TRIP_CHANGED = 'viaje_modificado';
    public const TRIP_STATUS = 'viaje_estado';
    public const VEHICLE_LONG_STOP = 'vehiculo_detencion_larga';
    public const VEHICLE_RESUMED = 'vehiculo_reanuda';
    public const VEHICLE_AT_STOP = 'vehiculo_en_parada';

    /** Qué datos cambian con cada clase de notificación (para que la app recargue). */
    public const CHANGES = [
        self::APPLICATION_RECEIVED => 'applications',
        self::APPLICATION_RESOLVED => 'applications',
        self::DEVELOPER_REPLY => 'conversations',
        self::ACCESS_RECOVERY_RECEIVED => 'access-recoveries',
        self::TRIP_CREATED => 'trips',
        self::TRIP_CHANGED => 'trips',
        self::TRIP_STATUS => 'trips',
        self::VEHICLE_LONG_STOP => 'trips',
        self::VEHICLE_RESUMED => 'trips',
        self::VEHICLE_AT_STOP => 'trips',
    ];

    /**
     * @param int[] $userIds
     */
    public function send(array $userIds, string $kind, string $title, string $body, array $data = []): void
    {
        $userIds = array_values(array_unique(array_map('intval', array_filter($userIds))));

        if (! $userIds) {
            return;
        }

        $now = Carbon::now();
        $json = $data ? json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) : null;
        $rows = array_map(fn ($id) => [
            'user_id' => $id,
            'kind' => $kind,
            'title' => mb_substr($title, 0, 150),
            'body' => $body,
            'data' => $json,
            'created_at' => $now,
        ], $userIds);

        foreach (array_chunk($rows, 200) as $chunk) {
            Notification::insert($chunk);
        }
    }

    /** @return int[] */
    public function adminIds(): array
    {
        return array_map('intval', User::where('is_admin', true)->pluck('id')->all());
    }

    /** @return int[] Jefes de ese itinerario */
    public function chiefIds(int $itineraryId): array
    {
        return array_map('intval', Worker::where('itinerary_id', $itineraryId)->where('is_chief', true)->pluck('user_id')->all());
    }

    /**
     * Trabajadores del viaje: los activos del itinerario (con o sin parada) y sus Jefes.
     *
     * @return int[]
     */
    public function tripAudience(Trip $trip): array
    {
        return array_map('intval', Worker::where('itinerary_id', $trip->itinerary_id)->where('active', true)->pluck('user_id')->all());
    }

    /**
     * Borra las notificaciones viejas (la app ya las recogió o no las recogerá).
     */
    public function purgeOld(int $days = 30): int
    {
        return Notification::where('created_at', '<', Carbon::now()->subDays($days))->delete();
    }
}
