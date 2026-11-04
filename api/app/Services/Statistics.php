<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Application;
use App\Models\Trip;
use App\Models\TripBoarding;
use App\Models\TripLeg;
use App\Models\TripPosition;
use App\Models\User;
use App\Models\Worker;
use App\Support\Geo;
use Carbon\Carbon;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Estadísticas (docs/02-procesos.md §2.11 y docs/04-api.md §4.6). Cada una
 * devuelve columnas y filas; la app dibuja los gráficos y las tablas.
 *
 * Con statistics.view se ve lo de su ámbito (sus Entidades o itinerarios;
 * con «all», todas o una con filter[entity]). Sin él, quien conduce ve las
 * de sus viajes y cualquiera, las suyas.
 */
class Statistics
{
    const NAMES = [
        'trips-by-status', 'punctuality', 'duration', 'trips-by-driver', 'trips-by-vehicle', 'overloaded-trips',
        'occupancy', 'attendance', 'children-transported', 'workers-distribution', 'worker-trips',
        'applications-summary', 'stop-activity', 'stop-pass-times', 'distance', 'live-trip', 'trip-incidents',
    ];

    /** Las que puede pedir cualquier trabajador (limitadas a lo suyo). */
    const WORKER_NAMES = ['worker-trips', 'live-trip'];

    /** Las que puede pedir un chofer (limitadas a sus viajes). */
    const DRIVER_NAMES = [
        'trips-by-status', 'punctuality', 'duration', 'overloaded-trips', 'occupancy', 'attendance',
        'children-transported', 'stop-activity', 'stop-pass-times', 'distance', 'worker-trips', 'live-trip', 'trip-incidents',
    ];

    /** @var Trips */
    private $trips;

    /** @var Tracking */
    private $tracking;

    /** @var ChildEligibility */
    private $childEligibility;

    /** @var array */
    private $filters;

    /** @var array ['from' => CarbonImmutable, 'to' => CarbonImmutable, 'dates' => string[]|null] */
    private $period;

    /** @var int[]|null itinerarios a los que se limita; null = todos */
    private $itineraryScope;

    /** @var int[]|null choferes (pertenencias) a los que se limita */
    private $driverScope;

    /** @var int[]|null Entidades a las que se limita; null = todas */
    private $entityScope;

    /** @var int[] Entidades enteras de su ámbito (además de itineraryScope) */
    private $wholeEntities = [];

    /** @var User */
    private $user;

    public function __construct(Trips $trips, Tracking $tracking, ChildEligibility $childEligibility)
    {
        $this->trips = $trips;
        $this->tracking = $tracking;
        $this->childEligibility = $childEligibility;
    }

    /**
     * @return array ['columns' => [...], 'rows' => [...], 'period' => [...]]
     */
    public function compute(string $name, User $user, array $filters): array
    {
        if (! in_array($name, self::NAMES, true)) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', "No existe la estadística \"{$name}\".");
        }

        $this->user = $user;
        $this->filters = $filters;
        $this->period = $this->resolvePeriod($filters);
        $this->resolveScope($name);

        $method = lcfirst(str_replace(' ', '', ucwords(str_replace('-', ' ', $name))));
        list($columns, $rows) = $this->{$method}();

        return [
            'columns' => array_map(function ($column) {
                return ['key' => $column[0], 'label' => $column[1], 'type' => $column[2]];
            }, $columns),
            'rows' => array_values($rows),
            'period' => [
                'from' => $this->period['from']->toDateString(),
                'to' => $this->period['to']->toDateString(),
                'dates' => $this->period['dates'],
            ],
        ];
    }

    /**
     * Periodo (7.28): un solo tipo entre from+to, dates o last; por defecto, los últimos 30 días.
     */
    public function resolvePeriod(array $filters): array
    {
        $kinds = array_filter([
            isset($filters['from']) || isset($filters['to']),
            isset($filters['dates']),
            isset($filters['last']),
        ]);

        if (count($kinds) > 1) {
            throw JsonApiException::badRequest('Usa un solo tipo de periodo: from y to, dates o last.', 'filter');
        }

        $today = CarbonImmutable::today();

        if (isset($filters['dates'])) {
            $dates = array_values(array_unique(array_map(function ($date) {
                return $this->parseDate(trim($date), 'dates')->toDateString();
            }, explode(',', $filters['dates']))));
            sort($dates);

            return ['from' => CarbonImmutable::parse($dates[0]), 'to' => CarbonImmutable::parse(end($dates)), 'dates' => $dates];
        }

        if (isset($filters['last'])) {
            if (! preg_match('/^(\d+)([dwmy])$/', $filters['last'], $match) || (int) $match[1] < 1) {
                throw JsonApiException::badRequest('filter[last] debe ser un número seguido de d, w, m o y (p. ej. 7d).', 'filter[last]');
            }

            $amount = (int) $match[1];
            $start = [
                'd' => $today->subDays($amount),
                'w' => $today->subWeeks($amount),
                'm' => $today->subMonths($amount),
                'y' => $today->subYears($amount),
            ][$match[2]]->addDay();

            return ['from' => $start, 'to' => $today, 'dates' => null];
        }

        if (isset($filters['from']) || isset($filters['to'])) {
            $from = isset($filters['from']) ? $this->parseDate($filters['from'], 'from') : $today->subDays(29);
            $to = isset($filters['to']) ? $this->parseDate($filters['to'], 'to') : $today;

            if ($from->greaterThan($to)) {
                throw JsonApiException::badRequest('filter[from] debe ser anterior o igual a filter[to].', 'filter[from]');
            }

            return ['from' => $from, 'to' => $to, 'dates' => null];
        }

        return ['from' => $today->subDays(29), 'to' => $today, 'dates' => null];
    }

    private function resolveScope(string $name): void
    {
        $this->itineraryScope = null;
        $this->driverScope = null;
        $this->entityScope = null;
        $this->wholeEntities = [];
        $user = $this->user;
        $permissions = app(Permissions::class);
        $requested = ! empty($this->filters['entity']) ? (int) $this->filters['entity'] : null;
        $scope = $permissions->scope($user, 'statistics.view');

        if ($scope['all']) {
            $this->entityScope = $requested !== null ? [$requested] : null;

            return;
        }

        if ($scope['entities'] || $scope['itineraries']) {
            $entities = $scope['entities'];
            $itineraries = $scope['itineraries'];

            if ($requested !== null) {
                $entities = array_values(array_intersect($entities, [$requested]));
                $itineraries = DB::table('itineraries')->whereIn('id', $itineraries ?: [0])->where('entity_id', $requested)->pluck('id')->map(function ($id) {
                    return (int) $id;
                })->all();
            }

            // Lo de sus Entidades enteras y lo de sus itinerarios.
            $this->wholeEntities = $entities;
            $this->itineraryScope = array_values(array_unique(array_merge($itineraries,
                DB::table('itineraries')->whereIn('entity_id', $entities ?: [0])->pluck('id')->map(function ($id) {
                    return (int) $id;
                })->all())));

            return;
        }

        if ($permissions->canAnywhere($user, 'tracking.drive') && in_array($name, self::DRIVER_NAMES, true)) {
            $this->driverScope = $user->workerIds() ?: [0];

            return;
        }

        if (! in_array($name, self::WORKER_NAMES, true)) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'No puede ver esta estadística.');
        }

        $this->itineraryScope = $user->activeWorkers()->pluck('itinerary_id')->filter()->map(function ($id) {
            return (int) $id;
        })->values()->all();
    }

    /*
    |--------------------------------------------------------------------------
    | Viajes
    |--------------------------------------------------------------------------
    */

    private function tripsByStatus(): array
    {
        $counts = $this->tripQuery()->select('status', DB::raw('COUNT(*) AS total'))->groupBy('status')->pluck('total', 'status');
        $rows = [];

        foreach (Trip::STATUSES as $status) {
            $rows[] = ['status' => $status, 'trips' => (int) ($counts[$status] ?? 0)];
        }

        return [[['status', 'Estado', 'string'], ['trips', 'Viajes', 'integer']], $rows];
    }

    private function punctuality(): array
    {
        $group = $this->groupBy(['itinerary', 'vehicle', 'driver'], 'itinerary');
        $rows = [];

        foreach ($this->tripQuery()->where('status', Trip::STATUS_COMPLETED)->with('itinerary', 'vehicle', 'driver.user')->get() as $trip) {
            $legs = TripLeg::where('trip_id', $trip->id)->get()->keyBy('direction');
            $key = $this->groupKey($trip, $group);
            $rows[$key] = isset($rows[$key]) ? $rows[$key] : ['group' => $this->groupLabel($trip, $group), 'trips' => 0, 'departure' => [], 'arrival' => []];
            $rows[$key]['trips']++;

            if (isset($legs['outbound'])) {
                $rows[$key]['departure'][] = $this->minutesBetween($trip->departs_at, $legs['outbound']->started_at);
            }

            if (isset($legs['return']) && $legs['return']->ended_at) {
                $rows[$key]['arrival'][] = $this->minutesBetween($trip->returns_at, $legs['return']->ended_at);
            }
        }

        $rows = array_map(function ($row) {
            return [
                'group' => $row['group'],
                'trips' => $row['trips'],
                'avgDepartureDelayMinutes' => $this->average($row['departure']),
                'avgArrivalDelayMinutes' => $this->average($row['arrival']),
            ];
        }, $rows);

        return [[
            ['group', $this->groupTitle($group), 'string'], ['trips', 'Viajes', 'integer'],
            ['avgDepartureDelayMinutes', 'Retraso medio en la salida (min)', 'number'],
            ['avgArrivalDelayMinutes', 'Retraso medio en la llegada (min)', 'number'],
        ], $rows];
    }

    private function duration(): array
    {
        $rows = [];
        $trips = $this->tripQuery()->where('status', Trip::STATUS_COMPLETED)->with('itinerary')->get();

        foreach ($trips as $trip) {
            foreach (TripLeg::where('trip_id', $trip->id)->whereNotNull('ended_at')->get() as $leg) {
                $key = $trip->itinerary_id.'-'.$leg->direction;
                $rows[$key] = isset($rows[$key]) ? $rows[$key] : ['itinerary' => $trip->itinerary->name, 'direction' => $leg->direction, 'minutes' => []];
                $rows[$key]['minutes'][] = $this->minutesBetween($leg->started_at, $leg->ended_at);
            }
        }

        $rows = array_map(function ($row) {
            return ['itinerary' => $row['itinerary'], 'direction' => $row['direction'], 'legs' => count($row['minutes']), 'avgMinutes' => $this->average($row['minutes'])];
        }, $rows);

        return [[
            ['itinerary', 'Itinerario', 'string'], ['direction', 'Trayecto', 'string'],
            ['legs', 'Trayectos', 'integer'], ['avgMinutes', 'Duración media (min)', 'number'],
        ], $rows];
    }

    private function tripsByDriver(): array
    {
        return $this->countBy('driver', 'Chofer');
    }

    private function tripsByVehicle(): array
    {
        return $this->countBy('vehicle', 'Vehículo');
    }

    /*
    |--------------------------------------------------------------------------
    | Ocupación
    |--------------------------------------------------------------------------
    */

    private function overloadedTrips(): array
    {
        $rows = [];

        // filter[level]: overloaded (solo los que no caben) o saturated (también los que van de pie).
        $level = isset($this->filters['level']) ? $this->filters['level'] : 'saturated';

        if (! in_array($level, ['saturated', 'overloaded'], true)) {
            throw JsonApiException::badRequest('filter[level] debe ser saturated u overloaded.', 'filter[level]');
        }

        foreach ($this->tripQuery()->where('status', '!=', Trip::STATUS_CANCELLED)->with('itinerary', 'vehicle', 'driver')->orderBy('departs_at')->get() as $trip) {
            $occupancy = $this->trips->occupancy($trip);

            if ($occupancy['overloaded'] || ($level === 'saturated' && $occupancy['saturated'])) {
                $rows[] = [
                    'trip' => (string) $trip->id,
                    'departsAt' => $trip->departs_at->toIso8601String(),
                    'itinerary' => $trip->itinerary->name,
                    'vehicle' => $trip->vehicle->plate,
                    'level' => $occupancy['overloaded'] ? 'Sobresaturado' : 'Saturado',
                    'expectedPassengers' => $occupancy['expectedPassengers'],
                    'seats' => $occupancy['seats'],
                    'totalCapacity' => $occupancy['totalCapacity'],
                    'standing' => max(0, min($occupancy['expectedPassengers'], $occupancy['totalCapacity']) - $occupancy['seats']),
                    'excess' => max(0, $occupancy['expectedPassengers'] - $occupancy['totalCapacity']),
                ];
            }
        }

        return [[
            ['trip', 'Viaje', 'string'], ['departsAt', 'Salida', 'datetime'], ['itinerary', 'Itinerario', 'string'],
            ['vehicle', 'Vehículo', 'string'], ['level', 'Estado', 'string'], ['expectedPassengers', 'Trabajadores', 'integer'],
            ['seats', 'Asientos', 'integer'], ['totalCapacity', 'Capacidad', 'integer'],
            ['standing', 'De pie', 'integer'], ['excess', 'No caben', 'integer'],
        ], $rows];
    }

    private function occupancy(): array
    {
        $group = $this->groupBy(['itinerary', 'vehicle'], 'itinerary');
        $rows = [];

        foreach ($this->tripQuery()->where('status', Trip::STATUS_COMPLETED)->with('itinerary', 'vehicle', 'driver')->get() as $trip) {
            $occupancy = $this->trips->occupancy($trip);
            $boarded = $this->boardedCount($trip, 'return');
            $key = $this->groupKey($trip, $group);
            $rows[$key] = isset($rows[$key]) ? $rows[$key] : ['group' => $this->groupLabel($trip, $group), 'expected' => [], 'boarded' => []];

            if ($occupancy['totalCapacity'] > 0) {
                $rows[$key]['expected'][] = 100 * $occupancy['expectedPassengers'] / $occupancy['totalCapacity'];
                $rows[$key]['boarded'][] = 100 * $boarded / $occupancy['totalCapacity'];
            }
        }

        $rows = array_map(function ($row) {
            return [
                'group' => $row['group'],
                'trips' => count($row['expected']),
                'expectedOccupancy' => $this->average($row['expected']),
                'realOccupancy' => $this->average($row['boarded']),
            ];
        }, $rows);

        return [[
            ['group', $this->groupTitle($group), 'string'], ['trips', 'Viajes', 'integer'],
            ['expectedOccupancy', 'Ocupación esperada', 'percent'], ['realOccupancy', 'Ocupación real', 'percent'],
        ], $rows];
    }

    private function attendance(): array
    {
        $rows = [];

        foreach ($this->tripQuery()->where('status', Trip::STATUS_COMPLETED)->with('itinerary.stops', 'driver')->get() as $trip) {
            $boardedIds = $this->boardedWorkerIds($trip, 'return');

            foreach ($this->trips->expectedPassengers($trip) as $worker) {
                if (! empty($this->filters['stop']) && (int) $worker->stop_id !== (int) $this->filters['stop']) {
                    continue;
                }

                $stop = $trip->itinerary->stops->firstWhere('id', $worker->stop_id);
                $key = $trip->itinerary_id.'-'.$worker->stop_id;
                $rows[$key] = isset($rows[$key]) ? $rows[$key] : ['itinerary' => $trip->itinerary->name, 'stop' => $stop ? $stop->landmark : '', 'expected' => 0, 'boarded' => 0];
                $rows[$key]['expected']++;

                if (in_array((int) $worker->id, $boardedIds, true)) {
                    $rows[$key]['boarded']++;
                }
            }
        }

        $rows = array_map(function ($row) {
            return $row + ['attendance' => $row['expected'] ? round(100 * $row['boarded'] / $row['expected'], 1) : null];
        }, $rows);

        return [[
            ['itinerary', 'Itinerario', 'string'], ['stop', 'Parada', 'string'], ['expected', 'Esperados', 'integer'],
            ['boarded', 'Subieron', 'integer'], ['attendance', 'Asistencia', 'percent'],
        ], $rows];
    }

    private function childrenTransported(): array
    {
        $rows = [];

        foreach ($this->tripQuery()->where('status', Trip::STATUS_COMPLETED)->with('itinerary')->get() as $trip) {
            $children = array_sum(array_map(function (TripBoarding $boarding) {
                return $boarding->children_count;
            }, $this->latestBoardings($trip, 'return')));
            $key = $trip->itinerary_id;
            $rows[$key] = isset($rows[$key]) ? $rows[$key] : ['itinerary' => $trip->itinerary->name, 'trips' => 0, 'children' => 0];
            $rows[$key]['trips']++;
            $rows[$key]['children'] += $children;
        }

        return [[['itinerary', 'Itinerario', 'string'], ['trips', 'Viajes', 'integer'], ['children', 'Niños transportados', 'integer']], $rows];
    }

    /*
    |--------------------------------------------------------------------------
    | Trabajadores y solicitudes
    |--------------------------------------------------------------------------
    */

    private function workersDistribution(): array
    {
        $by = isset($this->filters['by']) ? $this->filters['by'] : 'itinerary';
        $columns = ['itinerary' => 'workers.itinerary_id', 'stop' => 'workers.stop_id', 'sex' => 'users.sex'];

        if (! isset($columns[$by])) {
            throw JsonApiException::badRequest('filter[by] debe ser itinerary, stop o sex.', 'filter[by]');
        }

        $query = Worker::query()->join('users', 'users.id', '=', 'workers.user_id')->whereNull('users.deleted_at')
            ->select($columns[$by].' AS value', DB::raw('COUNT(*) AS total'))->groupBy($columns[$by]);

        if ($this->entityScope !== null) {
            $query->whereIn('workers.entity_id', $this->entityScope);
        }

        if ($this->itineraryScope !== null) {
            $query->where(function ($query) {
                $query->whereIn('workers.itinerary_id', $this->itineraryScope ?: [0])->orWhereIn('workers.entity_id', $this->wholeEntities ?: [0]);
            });
        }

        $names = $this->namesFor($by);
        $rows = $query->get()->map(function ($row) use ($names, $by) {
            $value = $row->value;
            $label = $value === null ? 'Sin asignar' : ($by === 'sex' ? ($value === 'F' ? 'Mujeres' : 'Hombres') : ($names[$value] ?? (string) $value));

            return ['group' => $label, 'workers' => (int) $row->total];
        })->sortBy('group')->values()->all();

        $titles = ['itinerary' => 'Itinerario', 'stop' => 'Parada', 'sex' => 'Sexo'];

        return [[['group', $titles[$by], 'string'], ['workers', 'Trabajadores', 'integer']], $rows];
    }

    private function workerTrips(): array
    {
        $ownIds = $this->user->workerIds();
        $workerId = isset($this->filters['worker']) ? (int) $this->filters['worker'] : ($ownIds ? $ownIds[0] : 0);
        $own = in_array($workerId, $ownIds, true);

        if (! $own) {
            $worker = Worker::withTrashed()->find($workerId);
            $permissions = app(Permissions::class);

            if (! $worker) {
                throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'El trabajador no existe.');
            }

            if (! $permissions->can($this->user, 'statistics.view', (int) $worker->entity_id, $worker->itinerary_id ? (int) $worker->itinerary_id : null)
                && ! $permissions->can($this->user, 'workers.view', (int) $worker->entity_id, $worker->itinerary_id ? (int) $worker->itinerary_id : null)) {
                throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'Solo puede ver sus propios viajes.');
            }
        }

        $rows = DB::table('trip_boardings')
            ->join('trip_legs', 'trip_legs.id', '=', 'trip_boardings.trip_leg_id')
            ->join('trips', 'trips.id', '=', 'trip_legs.trip_id')
            ->join('itineraries', 'itineraries.id', '=', 'trips.itinerary_id')
            ->where('trip_boardings.worker_id', $workerId)
            ->whereNull('trip_boardings.deleted_at')
            ->where(function ($query) {
                $this->applyPeriod($query, 'trips.departs_at');
            })
            ->when($this->itineraryScope !== null && ! $own, function ($query) {
                $query->whereIn('trips.itinerary_id', $this->itineraryScope);
            })
            ->orderBy('trips.departs_at')
            ->get(['trips.id', 'trips.departs_at', 'itineraries.name', 'trip_legs.direction', 'trip_boardings.method', 'trip_boardings.children_count'])
            ->groupBy(function ($row) {
                return $row->id.'-'.$row->direction;
            })
            ->map(function (Collection $rows) {
                $row = $rows->last();

                return [
                    'trip' => (string) $row->id,
                    'departsAt' => Carbon::parse($row->departs_at)->toIso8601String(),
                    'itinerary' => $row->name,
                    'direction' => $row->direction,
                    'method' => $row->method,
                    'children' => (int) $row->children_count,
                ];
            })->values()->all();

        return [[
            ['trip', 'Viaje', 'string'], ['departsAt', 'Salida', 'datetime'], ['itinerary', 'Itinerario', 'string'],
            ['direction', 'Trayecto', 'string'], ['method', 'Forma de subida', 'string'], ['children', 'Niños', 'integer'],
        ], $rows];
    }

    private function applicationsSummary(): array
    {
        $query = Application::query()->where(function ($query) {
            $this->applyPeriod($query, 'created_at');
        });

        if ($this->entityScope !== null) {
            $query->whereIn('entity_id', $this->entityScope);
        }

        if ($this->itineraryScope !== null) {
            $query->where(function ($query) {
                $query->whereIn('itinerary_id', $this->itineraryScope ?: [0])->orWhereIn('entity_id', $this->wholeEntities ?: [0]);
            });
        }

        $rows = [];

        foreach ($query->get() as $application) {
            $key = $application->type.'-'.$application->status;
            $rows[$key] = isset($rows[$key]) ? $rows[$key] : ['type' => $application->type, 'status' => $application->status, 'applications' => 0, 'hours' => []];
            $rows[$key]['applications']++;

            if ($application->resolved_at) {
                $rows[$key]['hours'][] = $application->created_at->diffInMinutes($application->resolved_at) / 60;
            }
        }

        $rows = array_map(function ($row) {
            return ['type' => $row['type'], 'status' => $row['status'], 'applications' => $row['applications'], 'avgResolutionHours' => $this->average($row['hours'])];
        }, $rows);
        ksort($rows);

        return [[
            ['type', 'Tipo', 'string'], ['status', 'Estado', 'string'], ['applications', 'Solicitudes', 'integer'],
            ['avgResolutionHours', 'Tiempo medio de resolución (h)', 'number'],
        ], $rows];
    }

    /*
    |--------------------------------------------------------------------------
    | Paradas y recorrido
    |--------------------------------------------------------------------------
    */

    private function stopActivity(): array
    {
        $rows = [];

        foreach ($this->tripQuery()->where('status', Trip::STATUS_COMPLETED)->with('itinerary.stops')->get() as $trip) {
            foreach (['return' => 'boardings', 'outbound' => 'alightings'] as $direction => $column) {
                foreach ($this->latestBoardings($trip, $direction) as $boarding) {
                    $worker = Worker::withTrashed()->find($boarding->worker_id);
                    $stop = $trip->itinerary->stops->firstWhere('id', $worker ? $worker->stop_id : null);

                    if (! $stop) {
                        continue;
                    }

                    $rows[$stop->id] = isset($rows[$stop->id]) ? $rows[$stop->id] : ['stop' => $stop->landmark, 'boardings' => 0, 'alightings' => 0];
                    $rows[$stop->id][$column]++;
                }
            }
        }

        return [[['stop', 'Parada', 'string'], ['boardings', 'Subidas (regreso)', 'integer'], ['alightings', 'Bajadas (salida)', 'integer']], $rows];
    }

    private function stopPassTimes(): array
    {
        $legIds = TripLeg::whereIn('trip_id', $this->tripQuery()->select('id'))->pluck('direction', 'id');
        $rows = [];

        foreach (DB::table('trip_stop_passes')->join('stops', 'stops.id', '=', 'trip_stop_passes.stop_id')
            ->whereIn('trip_leg_id', $legIds->keys())->whereNull('trip_stop_passes.deleted_at')
            ->where('trip_stop_passes.status', '!=', 'skipped')
            ->get(['trip_leg_id', 'stop_id', 'landmark', 'passed_at']) as $pass) {
            $direction = $legIds[$pass->trip_leg_id];
            $key = $pass->stop_id.'-'.$direction;
            $time = Carbon::parse($pass->passed_at);
            $rows[$key] = isset($rows[$key]) ? $rows[$key] : ['stop' => $pass->landmark, 'direction' => $direction, 'minutes' => []];
            $rows[$key]['minutes'][] = $time->hour * 60 + $time->minute;
        }

        $rows = array_map(function ($row) {
            $average = (int) round(array_sum($row['minutes']) / count($row['minutes']));

            return [
                'stop' => $row['stop'],
                'direction' => $row['direction'],
                'passes' => count($row['minutes']),
                'avgTime' => sprintf('%02d:%02d', intdiv($average, 60), $average % 60),
            ];
        }, $rows);

        return [[
            ['stop', 'Parada', 'string'], ['direction', 'Trayecto', 'string'], ['passes', 'Pasos', 'integer'],
            ['avgTime', 'Hora media de paso', 'string'],
        ], $rows];
    }

    /**
     * Incidencias del recorrido por itinerario (docs/09 §8): paradas donde no
     * se detuvo, paradas saltadas y desvíos del recorrido de referencia.
     */
    private function tripIncidents(): array
    {
        $labels = ['not_stopped' => 'No se detuvo en la parada', 'skipped' => 'Se saltó la parada', 'deviation' => 'Se desvió del recorrido'];
        $rows = DB::table('trip_leg_incidents')
            ->join('trip_legs', 'trip_legs.id', '=', 'trip_leg_incidents.trip_leg_id')
            ->join('trips', 'trips.id', '=', 'trip_legs.trip_id')
            ->join('itineraries', 'itineraries.id', '=', 'trips.itinerary_id')
            ->whereIn('trips.id', $this->tripQuery()->select('trips.id'))
            ->whereNull('trip_leg_incidents.deleted_at')
            ->groupBy('itineraries.name', 'trip_leg_incidents.type')
            ->orderBy('itineraries.name')
            ->get(['itineraries.name as itinerary', 'trip_leg_incidents.type as type', DB::raw('COUNT(*) as total')])
            ->map(function ($row) use ($labels) {
                return ['itinerary' => $row->itinerary, 'type' => $labels[$row->type], 'total' => (int) $row->total];
            })->all();

        return [[
            ['itinerary', 'Itinerario', 'string'], ['type', 'Incidencia', 'string'], ['total', 'Cantidad', 'integer'],
        ], $rows];
    }

    private function distance(): array
    {
        $rows = [];

        foreach ($this->tripQuery()->where('status', Trip::STATUS_COMPLETED)->with('vehicle')->get() as $trip) {
            $meters = 0;

            foreach (TripLeg::where('trip_id', $trip->id)->get() as $leg) {
                $meters += $this->legDistance($leg);
            }

            $key = $trip->vehicle_id;
            $rows[$key] = isset($rows[$key]) ? $rows[$key] : ['vehicle' => $trip->vehicle->plate, 'trips' => 0, 'kilometers' => 0];
            $rows[$key]['trips']++;
            $rows[$key]['kilometers'] = round($rows[$key]['kilometers'] + $meters / 1000, 2);
        }

        return [[['vehicle', 'Vehículo', 'string'], ['trips', 'Viajes', 'integer'], ['kilometers', 'Distancia (km)', 'number']], $rows];
    }

    /**
     * Viaje en marcha: un registro por trayecto iniciado.
     */
    private function liveTrip(): array
    {
        if (empty($this->filters['trip'])) {
            throw JsonApiException::badRequest('Hay que indicar filter[trip].', 'filter[trip]');
        }

        $trip = $this->trips->visibleTo($this->user)->with('itinerary.stops', 'vehicle', 'driver')->find($this->filters['trip']);

        if (! $trip) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'El viaje no existe o no puede verlo.');
        }

        $occupancy = $this->trips->occupancy($trip);
        $rows = [];

        foreach (TripLeg::where('trip_id', $trip->id)->orderBy('started_at')->get() as $leg) {
            $boardings = $this->latestBoardings($trip, $leg->direction);
            $stops = $leg->orderedStops();
            $passedIds = $leg->stopPasses()->pluck('stop_id')->map(function ($id) {
                return (int) $id;
            })->all();
            $combined = $leg->isActive() ? $this->tracking->combinedPosition($leg) : ['position' => null, 'activeSensors' => 0];
            $planned = $leg->direction === TripLeg::DIRECTION_OUTBOUND ? $trip->departs_at : $trip->returns_at;

            $rows[] = [
                'direction' => $leg->direction,
                'active' => $leg->isActive(),
                'boarded' => count($boardings),
                'expected' => $occupancy['expectedPassengers'],
                'capacity' => $occupancy['totalCapacity'],
                'children' => array_sum(array_map(function (TripBoarding $boarding) {
                    return $boarding->children_count;
                }, $boardings)),
                'stopsPassed' => count($passedIds),
                'stopsNotStopped' => $leg->stopPasses()->where('status', 'not_stopped')->count(),
                'stopsSkipped' => $leg->stopPasses()->where('status', 'skipped')->count(),
                'stopsRemaining' => $stops->count() - count($passedIds),
                'startDelayMinutes' => $this->minutesBetween($planned, $leg->started_at),
                'traveledKm' => round($this->legDistance($leg) / 1000, 2),
                'remainingKm' => round($this->remainingDistance($stops, $passedIds, $combined['position']) / 1000, 2),
                'activeSensors' => $combined['activeSensors'],
            ];
        }

        return [[
            ['direction', 'Trayecto', 'string'], ['active', 'En curso', 'string'], ['boarded', 'A bordo', 'integer'],
            ['expected', 'Esperados', 'integer'], ['capacity', 'Capacidad', 'integer'], ['children', 'Niños a bordo', 'integer'],
            ['stopsPassed', 'Paradas pasadas', 'integer'], ['stopsRemaining', 'Paradas restantes', 'integer'], ['stopsNotStopped', 'Paradas donde no se detuvo', 'integer'], ['stopsSkipped', 'Paradas saltadas', 'integer'],
            ['startDelayMinutes', 'Retraso al iniciar (min)', 'number'], ['traveledKm', 'Recorrido (km)', 'number'],
            ['remainingKm', 'Restante (km)', 'number'], ['activeSensors', 'Sensores activos', 'integer'],
        ], $rows];
    }

    /*
    |--------------------------------------------------------------------------
    | Utilidades
    |--------------------------------------------------------------------------
    */

    private function tripQuery(): Builder
    {
        $query = Trip::query()->where(function ($query) {
            $this->applyPeriod($query, 'departs_at');
        });

        if ($this->entityScope !== null) {
            $query->whereHas('itinerary', function (Builder $query) {
                $query->withTrashed()->whereIn('entity_id', $this->entityScope);
            });
        }

        if ($this->itineraryScope !== null) {
            $query->whereIn('itinerary_id', $this->itineraryScope);
        }

        if ($this->driverScope !== null) {
            $query->whereIn('driver_id', $this->driverScope);
        }

        foreach (['itinerary' => 'itinerary_id', 'vehicle' => 'vehicle_id', 'driver' => 'driver_id'] as $filter => $column) {
            if (! empty($this->filters[$filter])) {
                $query->where($column, $this->filters[$filter]);
            }
        }

        return $query;
    }

    private function applyPeriod($query, string $column): void
    {
        if ($this->period['dates'] !== null) {
            $query->whereIn(DB::raw("DATE({$column})"), $this->period['dates']);

            return;
        }

        $query->whereBetween($column, [$this->period['from']->startOfDay(), $this->period['to']->endOfDay()]);
    }

    private function countBy(string $field, string $title): array
    {
        $rows = [];

        foreach ($this->tripQuery()->where('status', Trip::STATUS_COMPLETED)->with('vehicle', 'driver.user')->get() as $trip) {
            $key = $this->groupKey($trip, $field);
            $rows[$key] = isset($rows[$key]) ? $rows[$key] : [$field => $this->groupLabel($trip, $field), 'trips' => 0];
            $rows[$key]['trips']++;
        }

        return [[[$field, $title, 'string'], ['trips', 'Viajes realizados', 'integer']], $rows];
    }

    private function groupBy(array $allowed, string $default): string
    {
        $group = isset($this->filters['by']) ? $this->filters['by'] : $default;

        if (! in_array($group, $allowed, true)) {
            throw JsonApiException::badRequest('filter[by] debe ser '.implode(', ', $allowed).'.', 'filter[by]');
        }

        return $group;
    }

    private function groupKey(Trip $trip, string $group): string
    {
        return (string) $trip->{$group.'_id'};
    }

    private function groupLabel(Trip $trip, string $group): string
    {
        switch ($group) {
            case 'vehicle':
                return $trip->vehicle ? $trip->vehicle->plate : '';
            case 'driver':
                return $trip->driver ? $trip->driver->fullName() : '';
            default:
                return $trip->itinerary ? $trip->itinerary->name : '';
        }
    }

    private function groupTitle(string $group): string
    {
        return ['itinerary' => 'Itinerario', 'vehicle' => 'Vehículo', 'driver' => 'Chofer'][$group];
    }

    private function namesFor(string $by): array
    {
        switch ($by) {
            case 'itinerary':
                return DB::table('itineraries')->pluck('name', 'id')->all();
            case 'stop':
                return DB::table('stops')->pluck('landmark', 'id')->all();
            default:
                return [];
        }
    }

    /**
     * @return TripBoarding[] último registro de cada trabajador en el trayecto
     */
    private function latestBoardings(Trip $trip, string $direction): array
    {
        return app(Boardings::class)->latestByWorker($trip->id, $direction);
    }

    private function boardedCount(Trip $trip, string $direction): int
    {
        return count($this->latestBoardings($trip, $direction));
    }

    /**
     * @return int[]
     */
    private function boardedWorkerIds(Trip $trip, string $direction): array
    {
        return array_map('intval', array_keys($this->latestBoardings($trip, $direction)));
    }

    /**
     * Distancia recorrida: la del sensor con más posiciones en el trayecto.
     */
    private function legDistance(TripLeg $leg): float
    {
        $sensor = TripPosition::where('trip_leg_id', $leg->id)
            ->select('worker_id', DB::raw('COUNT(*) AS total'))->groupBy('worker_id')->orderBy('total', 'desc')->value('worker_id');

        if (! $sensor) {
            return 0.0;
        }

        $positions = TripPosition::where('trip_leg_id', $leg->id)->where('worker_id', $sensor)->orderBy('recorded_at')->get(['latitude', 'longitude']);
        $meters = 0.0;

        for ($i = 1; $i < $positions->count(); $i++) {
            $meters += Geo::distance($positions[$i - 1]->latitude, $positions[$i - 1]->longitude, $positions[$i]->latitude, $positions[$i]->longitude);
        }

        return $meters;
    }

    /**
     * Distancia en línea recta desde la posición actual por las paradas que faltan.
     */
    private function remainingDistance($stops, array $passedIds, ?array $position): float
    {
        $pending = $stops->reject(function ($stop) use ($passedIds) {
            return in_array((int) $stop->id, $passedIds, true);
        })->values();

        if ($pending->isEmpty()) {
            return 0.0;
        }

        $meters = 0.0;
        $previous = $position ? [$position['latitude'], $position['longitude']] : [$pending[0]->latitude, $pending[0]->longitude];

        foreach ($pending as $stop) {
            $meters += Geo::distance($previous[0], $previous[1], $stop->latitude, $stop->longitude);
            $previous = [$stop->latitude, $stop->longitude];
        }

        return $meters;
    }

    private function minutesBetween($planned, $actual): float
    {
        return round(($actual->getTimestamp() - $planned->getTimestamp()) / 60, 1);
    }

    private function average(array $values): ?float
    {
        return $values ? round(array_sum($values) / count($values), 1) : null;
    }

    private function parseDate(string $value, string $filter): CarbonImmutable
    {
        if (! preg_match('/^\d{4}-\d{2}-\d{2}$/', $value)) {
            throw JsonApiException::badRequest("filter[{$filter}] debe tener el formato AAAA-MM-DD.", "filter[{$filter}]");
        }

        return CarbonImmutable::parse($value);
    }
}
