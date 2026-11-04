<?php

namespace App\Services;

use App\Models\Notice;
use App\Models\Trip;
use App\Models\TripLeg;
use App\Models\User;
use Carbon\Carbon;
use Carbon\CarbonInterface;

/**
 * Viajes atrasados y aviso de comienzo (docs/09-repaso-pantallas.md):
 * un viaje de ida o de regreso está atrasado si, pasada su hora más la
 * tolerancia de la Entidad, no ha comenzado.
 */
class TripTimeliness
{
    /** @var Settings */
    private $settings;

    /** @var Trips */
    private $trips;

    /** @var Notices */
    private $notices;

    /** @var Absences */
    private $absences;

    public function __construct(Settings $settings, Trips $trips, Notices $notices, Absences $absences)
    {
        $this->settings = $settings;
        $this->trips = $trips;
        $this->notices = $notices;
        $this->absences = $absences;
    }

    public static function scheduledAt(Trip $trip, string $direction): CarbonInterface
    {
        return $direction === TripLeg::DIRECTION_OUTBOUND ? $trip->departs_at : $trip->returns_at;
    }

    public function tolerance(Trip $trip): int
    {
        $entityId = $trip->itinerary ? (int) $trip->itinerary->entity_id : null;

        return $this->settings->int('trip_delay_tolerance_minutes', null, $entityId, (int) $trip->itinerary_id);
    }

    /**
     * No ha comenzado y ya pasó su hora más la tolerancia.
     */
    public function isDelayed(Trip $trip, string $direction, ?CarbonInterface $now = null): bool
    {
        $now = $now ?: Carbon::now();

        if ($trip->status !== Trip::STATUS_CONFIRMED || $this->leg($trip, $direction)) {
            return false;
        }

        return $now->greaterThan(self::scheduledAt($trip, $direction)->copy()->addMinutes($this->tolerance($trip)));
    }

    /**
     * Minutos de atraso: al comenzar (si ya comenzó) o hasta ahora (si está
     * atrasado). NULL si no hay atraso.
     */
    public function delayMinutes(Trip $trip, string $direction, ?CarbonInterface $now = null): ?int
    {
        $scheduled = self::scheduledAt($trip, $direction);
        $leg = $this->leg($trip, $direction);

        if ($leg) {
            $minutes = (int) floor(($leg->started_at->getTimestamp() - $scheduled->getTimestamp()) / 60);

            return $minutes > $this->tolerance($trip) ? $minutes : null;
        }

        if (! $this->isDelayed($trip, $direction, $now)) {
            return null;
        }

        return (int) floor((($now ?: Carbon::now())->getTimestamp() - $scheduled->getTimestamp()) / 60);
    }

    /**
     * Aviso de comienzo: a los pasajeros esperados, al chofer y a los Jefes
     * del itinerario que lo tengan activado.
     */
    public function notifyStarted(TripLeg $leg): void
    {
        $trip = $leg->trip;
        $delay = $this->delayMinutes($trip, $leg->direction) ?: 0;
        $this->notify($trip, 'trip_start_notice_enabled', Notice::TYPE_TRIP_STARTED, [
            'direction' => $leg->direction,
            'delayMinutes' => $delay,
        ], (int) $leg->started_by);
    }

    /**
     * Aviso de atraso, una sola vez por viaje de ida o de regreso.
     *
     * @return int viajes avisados
     */
    public function notifyDelays(?CarbonInterface $now = null): int
    {
        $now = $now ?: Carbon::now();
        $count = 0;
        $trips = Trip::where('status', Trip::STATUS_CONFIRMED)
            ->where('departs_at', '>', $now->copy()->subDays(2))
            ->where('departs_at', '<', $now)
            ->with('itinerary', 'legs', 'driver')
            ->get();

        foreach ($trips as $trip) {
            foreach ([TripLeg::DIRECTION_OUTBOUND, TripLeg::DIRECTION_RETURN] as $direction) {
                if (! $this->isDelayed($trip, $direction, $now)) {
                    continue;
                }

                $already = Notice::where('trip_id', $trip->id)->where('type', Notice::TYPE_TRIP_DELAYED)
                    ->where('payload', 'like', '%"direction":"'.$direction.'"%')->exists();

                if (! $already) {
                    $this->notify($trip, 'trip_delay_notice_enabled', Notice::TYPE_TRIP_DELAYED, [
                        'direction' => $direction,
                        'scheduledAt' => self::scheduledAt($trip, $direction)->toIso8601String(),
                    ]);
                    $count++;
                }
            }
        }

        return $count;
    }

    private function notify(Trip $trip, string $settingKey, string $type, array $payload, ?int $exceptUserId = null): void
    {
        $userIds = $this->trips->expectedPassengers($trip)->pluck('user_id')->all();

        if ($trip->driver) {
            $userIds[] = $trip->driver->user_id;
        }

        $entityId = $trip->itinerary ? (int) $trip->itinerary->entity_id : null;
        $userIds = array_merge($userIds, app(Permissions::class)->userIdsWith('trips.edit', $entityId, (int) $trip->itinerary_id, false));
        $absent = $this->absences->absentOn($trip->departs_at);

        $recipients = User::whereIn('id', array_unique(array_map('intval', array_filter($userIds))))->get()
            ->filter(function (User $user) use ($settingKey, $absent, $entityId) {
                if (! $this->settings->get($settingKey, $user, $entityId)) {
                    return false;
                }

                $worker = $user->workerIn($entityId);
                $workerId = $worker ? (int) $worker->id : null;

                return ! ($workerId && in_array($workerId, $absent, true) && ! $this->settings->get('notify_during_absence', $user));
            })
            ->pluck('id')->all();

        $this->notices->send($recipients, $type, null, (int) $trip->id, $exceptUserId, $payload);
    }

    private function leg(Trip $trip, string $direction): ?TripLeg
    {
        return $trip->legs->firstWhere('direction', $direction);
    }
}
