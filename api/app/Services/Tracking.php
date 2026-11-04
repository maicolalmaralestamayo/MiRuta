<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Trip;
use App\Models\TripBoarding;
use App\Models\TripLeg;
use App\Models\TripPosition;
use App\Models\Notice;
use App\Models\Stop;
use App\Models\TripLegIncident;
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
     * Pueden iniciar y finalizar trayectos el chofer del viaje, quien tenga
     * tracking.drive en su Entidad y quien pueda marcarlo como realizado.
     */
    public function canOperate(Trip $trip, User $user): bool
    {
        $permissions = app(Permissions::class);

        return $this->trips->isDriverOf($trip, $user)
            || $permissions->can($user, 'tracking.drive', $this->trips->entityOf($trip))
            || $permissions->can($user, 'trips.complete', null, (int) $trip->itinerary_id);
    }

    /**
     * Pueden registrar la subida de otros el chofer del viaje y quien tenga
     * tracking.scan_boarding sobre su itinerario.
     */
    public function canScan(Trip $trip, User $user): bool
    {
        return $this->trips->isDriverOf($trip, $user)
            || app(Permissions::class)->can($user, 'tracking.scan_boarding', null, (int) $trip->itinerary_id);
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

        $leg = TripLeg::create([
            'trip_id' => $trip->id,
            'direction' => $direction,
            'started_at' => Carbon::now(),
            'started_by' => $user->id,
        ]);
        $leg->setRelation('trip', $trip->load('legs'));
        app(TripTimeliness::class)->notifyStarted($leg);

        return $leg;
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
        $isDriver = (int) $trip->driver_id === (int) $sensor->id;

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
                    $latitude = (float) $combined['position']['latitude'];
                    $longitude = (float) $combined['position']['longitude'];
                    $isNewest = ! $leg->last_position_at || $recordedAt->greaterThan($leg->last_position_at);
                    $speed = $isNewest ? $this->speedKmh($leg, $latitude, $longitude, $recordedAt) : null;

                    $this->detectStopPasses($leg, $latitude, $longitude, $recordedAt, $speed);
                    $this->detectDeviation($leg, $latitude, $longitude, $recordedAt);

                    if ($isNewest && $leg->exists) {
                        $leg->forceFill(['last_latitude' => $latitude, 'last_longitude' => $longitude, 'last_position_at' => $recordedAt])->save();
                    }
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
     * Paso por paradas (7.18) y paradas no realizadas (docs/09 §8):
     * - al entrar en el radio de una parada se registra la llegada;
     * - al salir se decide si se detuvo: estuvo al menos stop_min_dwell_seconds
     *   o bajó de stop_pass_speed_kmh; si no, "pasó de largo";
     * - si llega a una parada sin haber pasado por alguna anterior, esas se
     *   marcan como "saltadas".
     * La parada de salida no cuenta para estas incidencias.
     */
    private function detectStopPasses(TripLeg $leg, float $latitude, float $longitude, CarbonInterface $at, ?float $speed): void
    {
        $trip = $leg->trip;
        $entityId = $trip->itinerary ? (int) $trip->itinerary->entity_id : null;
        $radius = $this->settings->int('stop_detection_radius_m', null, $entityId, (int) $trip->itinerary_id);
        $stops = $leg->orderedStops()->values();
        $passes = TripStopPass::where('trip_leg_id', $leg->id)->get()->keyBy('stop_id');
        $first = $stops->first();
        $last = $stops->last();

        // Parada en la que está ahora: ¿sigue dentro o ya salió?
        foreach ($passes as $pass) {
            if ($pass->status !== TripStopPass::STATUS_ARRIVED) {
                continue;
            }

            $stop = $stops->firstWhere('id', $pass->stop_id);
            $inside = $stop && Geo::distance($latitude, $longitude, $stop->latitude, $stop->longitude) <= $radius;

            if ($inside) {
                if ($speed !== null) {
                    $pass->min_speed_kmh = $pass->min_speed_kmh === null ? $speed : min($pass->min_speed_kmh, $speed);
                    $pass->save();
                }
                continue;
            }

            $dwell = $at->getTimestamp() - $pass->passed_at->getTimestamp();
            $stopped = $dwell >= $this->settings->int('stop_min_dwell_seconds', null, $entityId, (int) $trip->itinerary_id, (int) $pass->stop_id)
                || ($pass->min_speed_kmh !== null && $pass->min_speed_kmh <= $this->settings->int('stop_pass_speed_kmh', null, $entityId, (int) $trip->itinerary_id, (int) $pass->stop_id))
                || ($first && (int) $pass->stop_id === (int) $first->id);
            $pass->forceFill([
                'left_at' => $at,
                'status' => $stopped ? TripStopPass::STATUS_STOPPED : TripStopPass::STATUS_NOT_STOPPED,
            ])->save();

            if (! $stopped) {
                $this->recordIncident($leg, TripLegIncident::TYPE_NOT_STOPPED, $stop, $at);
            }
        }

        foreach ($stops as $index => $stop) {
            if ($passes->has($stop->id)) {
                continue;
            }

            if (Geo::distance($latitude, $longitude, $stop->latitude, $stop->longitude) > $radius) {
                continue;
            }

            $isLast = (int) $stop->id === (int) $last->id;
            TripStopPass::create([
                'trip_leg_id' => $leg->id,
                'stop_id' => $stop->id,
                'passed_at' => $at,
                'min_speed_kmh' => $speed,
                'status' => $isLast ? TripStopPass::STATUS_STOPPED : TripStopPass::STATUS_ARRIVED,
            ]);

            // Las anteriores sin paso (salvo la de salida) se las saltó.
            foreach ($stops->slice(1, max(0, $index - 1)) as $skipped) {
                if (! $passes->has($skipped->id)) {
                    TripStopPass::create([
                        'trip_leg_id' => $leg->id, 'stop_id' => $skipped->id, 'passed_at' => $at,
                        'status' => TripStopPass::STATUS_SKIPPED,
                    ]);
                    $this->recordIncident($leg, TripLegIncident::TYPE_SKIPPED, $skipped, $at);
                }
            }

            if ($isLast) {
                $leg->forceFill(['ended_at' => $at, 'end_reason' => TripLeg::END_LAST_STOP])->save();
            }

            return;
        }
    }

    /**
     * Desvío (opción B, docs/09 §8): distancia al recorrido de referencia del
     * itinerario para este sentido. Se avisa al salir y se cierra al volver.
     */
    private function detectDeviation(TripLeg $leg, float $latitude, float $longitude, CarbonInterface $at): void
    {
        $trip = $leg->trip;
        $itinerary = $trip->itinerary;
        $referenceId = $itinerary ? $itinerary->referenceLegId($leg->direction) : null;

        if (! $referenceId || $referenceId === (int) $leg->id) {
            return;
        }

        $line = $this->referenceLine($referenceId);

        if (count($line) < 2) {
            return;
        }

        $distance = Geo::distanceToPolyline($latitude, $longitude, $line);
        $limit = $this->settings->int('route_deviation_m', null, (int) $itinerary->entity_id, (int) $itinerary->id);
        $open = $leg->deviating
            ? TripLegIncident::where('trip_leg_id', $leg->id)->where('type', TripLegIncident::TYPE_DEVIATION)->whereNull('ended_at')->latest('id')->first()
            : null;

        if ($distance > $limit) {
            if ($open) {
                $open->distance_m = max((int) $open->distance_m, (int) round($distance));
                $open->save();
            } elseif (! $leg->deviating) {
                $leg->forceFill(['deviating' => true])->save();
                $this->recordIncident($leg, TripLegIncident::TYPE_DEVIATION, null, $at, $latitude, $longitude, (int) round($distance));
            }
        } elseif ($leg->deviating) {
            $leg->forceFill(['deviating' => false])->save();

            if ($open) {
                $open->forceFill(['ended_at' => $at])->save();
            }
        }
    }

    /** @var array Recorridos de referencia ya leídos (por id del viaje de ida o de regreso). */
    private $referenceLines = [];

    /**
     * Puntos del recorrido de referencia, como mucho unos 1000.
     */
    private function referenceLine(int $legId): array
    {
        if (! isset($this->referenceLines[$legId])) {
            $points = TripPosition::where('trip_leg_id', $legId)->orderBy('recorded_at')->get(['latitude', 'longitude']);
            $step = max(1, (int) ceil($points->count() / 1000));
            $line = [];

            foreach ($points->values() as $index => $point) {
                if ($index % $step === 0) {
                    $line[] = [(float) $point->latitude, (float) $point->longitude];
                }
            }

            $this->referenceLines[$legId] = $line;
        }

        return $this->referenceLines[$legId];
    }

    private function recordIncident(TripLeg $leg, string $type, ?Stop $stop, CarbonInterface $at, ?float $latitude = null, ?float $longitude = null, ?int $distance = null): void
    {
        TripLegIncident::create([
            'trip_leg_id' => $leg->id,
            'type' => $type,
            'stop_id' => $stop ? $stop->id : null,
            'latitude' => $latitude !== null ? $latitude : ($stop ? $stop->latitude : null),
            'longitude' => $longitude !== null ? $longitude : ($stop ? $stop->longitude : null),
            'distance_m' => $distance,
            'started_at' => $at,
        ]);

        $trip = $leg->trip;
        $itinerary = $trip->itinerary;
        $notices = app(Notices::class);
        $notices->send(
            app(Permissions::class)->userIdsWith('trips.edit', $itinerary ? (int) $itinerary->entity_id : null, (int) $trip->itinerary_id, false),
            Notice::TYPE_TRIP_INCIDENT,
            null,
            (int) $trip->id,
            null,
            ['direction' => $leg->direction, 'type' => $type, 'stop' => $stop ? $stop->landmark : null]
        );
    }

    /**
     * Velocidad desde la última posición combinada (km/h), o NULL.
     */
    private function speedKmh(TripLeg $leg, float $latitude, float $longitude, CarbonInterface $at): ?float
    {
        if ($leg->last_latitude === null || ! $leg->last_position_at) {
            return null;
        }

        $seconds = $at->getTimestamp() - $leg->last_position_at->getTimestamp();

        if ($seconds <= 0) {
            return null;
        }

        return Geo::distance($leg->last_latitude, $leg->last_longitude, $latitude, $longitude) / $seconds * 3.6;
    }

    /**
     * Subida automática (7.23): las últimas N posiciones del trabajador están
     * cerca del vehículo y el vehículo se movió entre la primera y la última.
     */
    private function detectAutomaticBoarding(TripLeg $leg, Worker $worker): void
    {
        $trip = $leg->trip;

        if ((int) $trip->driver_id === (int) $worker->id) {
            return;
        }

        if ($this->boardings->existingFor($leg, (int) $worker->user_id)) {
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

        // La automática no marca hijos: los marca quien escanea o la persona ("Ya subí").
        $this->boardings->register($leg, $worker->user, TripBoarding::METHOD_AUTOMATIC);
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
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'Solo el chofer del viaje y quien tenga permiso sobre el recorrido pueden hacerlo.');
        }
    }
}
