<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Trip;
use App\Models\TripBoarding;
use App\Models\TripLeg;
use App\Models\TripPosition;
use App\Models\TripStopPass;
use App\Models\User;
use App\Models\Worker;
use App\Support\Geo;
use Carbon\Carbon;
use Carbon\CarbonInterface;
use Illuminate\Support\Facades\DB;

/**
 * Recorrido en tiempo real: trayectos, sensores (7.17), paso por paradas y
 * fin del trayecto (7.18) y subida automática (7.23).
 */
class Tracking
{
    /** @var Settings */
    private $settings;

    /** @var Boardings */
    private $boardings;

    /** @var Trips */
    private $trips;

    public function __construct(Settings $settings, Boardings $boardings, Trips $trips)
    {
        $this->settings = $settings;
        $this->boardings = $boardings;
        $this->trips = $trips;
    }

    /**
     * Pueden iniciar y finalizar trayectos (y registrar subidas de otros) el
     * chofer del viaje, los Jefes de su itinerario y los Jefes de Transporte.
     */
    public function canOperate(Trip $trip, User $user): bool
    {
        return ($user->driverId() !== null && (int) $trip->driver_id === $user->driverId())
            || $user->isChiefOf((int) $trip->itinerary_id);
    }

    public function start(Trip $trip, string $direction, User $user): TripLeg
    {
        $this->ensureCanOperate($trip, $user);

        if ($trip->status !== Trip::STATUS_CONFIRMED) {
            throw JsonApiException::conflict('TRIP_NOT_CONFIRMED', 'Solo se pueden iniciar recorridos de viajes confirmados.');
        }

        if (TripLeg::withTrashed()->where('trip_id', $trip->id)->where('direction', $direction)->exists()) {
            throw JsonApiException::conflict('LEG_ALREADY_STARTED', 'Ese trayecto ya se inició.');
        }

        return TripLeg::create([
            'trip_id' => $trip->id,
            'direction' => $direction,
            'started_at' => Carbon::now(),
            'started_by' => $user->id,
        ]);
    }

    /**
     * Finalizar a mano. Gana lo que ocurra primero: esto o el paso por la última parada.
     */
    public function end(TripLeg $leg, User $user): TripLeg
    {
        $this->ensureCanOperate($leg->trip, $user);

        if (! $leg->isActive()) {
            throw JsonApiException::conflict('LEG_NOT_ACTIVE', 'El trayecto ya terminó.');
        }

        $leg->forceFill(['ended_at' => Carbon::now(), 'ended_by' => $user->id, 'end_reason' => TripLeg::END_MANUAL])->save();

        return $leg;
    }

    /**
     * Registra una posición de un sensor y procesa sus efectos.
     */
    public function addPosition(TripLeg $leg, Worker $sensor, float $latitude, float $longitude, ?float $accuracy, CarbonInterface $recordedAt): TripPosition
    {
        $trip = $leg->trip;
        $isDriver = $trip->driver && (int) $trip->driver->worker_id === (int) $sensor->id;

        if (! $isDriver && (int) $sensor->itinerary_id !== (int) $trip->itinerary_id) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'Solo el chofer del viaje y los miembros del itinerario pueden enviar su ubicación.');
        }

        if (! $leg->isActive() && $recordedAt->greaterThan($leg->ended_at)) {
            throw JsonApiException::conflict('LEG_NOT_ACTIVE', 'El trayecto ya terminó.');
        }

        return DB::transaction(function () use ($leg, $sensor, $latitude, $longitude, $accuracy, $recordedAt) {
            $position = TripPosition::create([
                'trip_leg_id' => $leg->id,
                'worker_id' => $sensor->id,
                'latitude' => $latitude,
                'longitude' => $longitude,
                'accuracy_m' => $accuracy,
                'recorded_at' => $recordedAt,
            ]);

            if ($leg->isActive()) {
                $combined = $this->combinedPosition($leg, $recordedAt);

                if ($combined['position']) {
                    $this->detectStopPasses($leg, $combined['position']['latitude'], $combined['position']['longitude'], $recordedAt);
                }

                $this->detectAutomaticBoarding($leg, $sensor);
            }

            return $position;
        });
    }

    /**
     * Combinación de sensores (7.17): mediana de la última posición reciente de
     * cada sensor, descartando los que se alejan del grupo.
     *
     * @return array ['position' => [latitude, longitude, at]|null, 'activeSensors' => int]
     */
    public function combinedPosition(TripLeg $leg, ?CarbonInterface $at = null, ?int $excludeWorkerId = null): array
    {
        $at = $at ? Carbon::instance($at) : Carbon::now();
        $stale = $this->settings->int('sensor_stale_seconds');

        $query = TripPosition::where('trip_leg_id', $leg->id)
            ->where('recorded_at', '>', $at->copy()->subSeconds($stale))
            ->where('recorded_at', '<=', $at)
            ->orderBy('recorded_at', 'desc');

        if ($excludeWorkerId !== null) {
            $query->where('worker_id', '!=', $excludeWorkerId);
        }

        $latest = [];

        foreach ($query->get() as $position) {
            if (! isset($latest[$position->worker_id])) {
                $latest[$position->worker_id] = $position;
            }
        }

        if (! $latest) {
            return ['position' => null, 'activeSensors' => 0];
        }

        $positions = array_values($latest);
        $median = $this->median($positions);

        if (count($positions) > 1) {
            $limit = $this->settings->int('sensor_outlier_distance_m');
            $close = array_values(array_filter($positions, function (TripPosition $position) use ($median, $limit) {
                return Geo::distance($median[0], $median[1], $position->latitude, $position->longitude) <= $limit;
            }));

            if ($close) {
                $positions = $close;
                $median = $this->median($positions);
            }
        }

        $newest = max(array_map(function (TripPosition $position) {
            return $position->recorded_at->getTimestamp();
        }, $positions));

        return [
            'position' => [
                'latitude' => round($median[0], 7),
                'longitude' => round($median[1], 7),
                'at' => Carbon::createFromTimestamp($newest)->toIso8601String(),
            ],
            'activeSensors' => count($positions),
        ];
    }

    /**
     * Paso por paradas (7.18). Recorre todas las pendientes, para detectar la
     * siguiente aunque el vehículo se salte alguna.
     */
    private function detectStopPasses(TripLeg $leg, float $latitude, float $longitude, CarbonInterface $at): void
    {
        $radius = $this->settings->int('stop_detection_radius_m');
        $stops = $leg->orderedStops();
        $passed = TripStopPass::where('trip_leg_id', $leg->id)->pluck('stop_id')->map(function ($id) {
            return (int) $id;
        })->all();
        $last = $stops->last();

        foreach ($stops as $stop) {
            if (in_array((int) $stop->id, $passed, true)) {
                continue;
            }

            if (Geo::distance($latitude, $longitude, $stop->latitude, $stop->longitude) <= $radius) {
                TripStopPass::create(['trip_leg_id' => $leg->id, 'stop_id' => $stop->id, 'passed_at' => $at]);

                if ((int) $stop->id === (int) $last->id) {
                    $leg->forceFill(['ended_at' => $at, 'end_reason' => TripLeg::END_LAST_STOP])->save();
                }

                return;
            }
        }
    }

    /**
     * Subida automática (7.23): las últimas N posiciones del trabajador están
     * cerca del vehículo y el vehículo se movió entre la primera y la última.
     */
    private function detectAutomaticBoarding(TripLeg $leg, Worker $worker): void
    {
        $trip = $leg->trip;

        if ($trip->driver && (int) $trip->driver->worker_id === (int) $worker->id) {
            return;
        }

        if (TripBoarding::where('trip_leg_id', $leg->id)->where('worker_id', $worker->id)->exists()) {
            return;
        }

        $samples = $this->settings->int('auto_boarding_samples');
        $distance = $this->settings->int('auto_boarding_distance_m');
        $positions = TripPosition::where('trip_leg_id', $leg->id)->where('worker_id', $worker->id)
            ->orderBy('recorded_at', 'desc')->limit($samples)->get()->reverse()->values();

        if ($positions->count() < $samples) {
            return;
        }

        $vehicle = [];

        foreach ($positions as $position) {
            $combined = $this->combinedPosition($leg, $position->recorded_at, $worker->id)['position'];

            if (! $combined || Geo::distance($position->latitude, $position->longitude, $combined['latitude'], $combined['longitude']) > $distance) {
                return;
            }

            $vehicle[] = $combined;
        }

        $first = $vehicle[0];
        $lastPosition = end($vehicle);

        if (Geo::distance($first['latitude'], $first['longitude'], $lastPosition['latitude'], $lastPosition['longitude']) <= $distance) {
            return;
        }

        if (! $this->trips->expectedPassengers($trip)->contains('id', $worker->id)) {
            return;
        }

        $this->boardings->board($leg, $worker, TripBoarding::METHOD_AUTOMATIC, null, null);
    }

    private function median(array $positions): array
    {
        return [
            Geo::median(array_map(function (TripPosition $position) {
                return $position->latitude;
            }, $positions)),
            Geo::median(array_map(function (TripPosition $position) {
                return $position->longitude;
            }, $positions)),
        ];
    }

    private function ensureCanOperate(Trip $trip, User $user): void
    {
        if (! $this->canOperate($trip, $user)) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'Solo el chofer del viaje, los Jefes de su itinerario y los Jefes de Transporte pueden hacerlo.');
        }
    }
}
