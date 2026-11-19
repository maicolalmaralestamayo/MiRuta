<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Itinerary;
use App\Models\ItineraryStop;
use App\Models\Notification;
use App\Models\Scopes\NotSimulated;
use App\Models\Simulation;
use App\Models\Stop;
use App\Models\Trip;
use App\Models\TripPassenger;
use App\Models\TripStopPass;
use App\Models\User;
use App\Models\VehicleType;
use App\Models\Worker;
use App\Models\WorkerItinerary;
use App\Support\Geo;
use App\Support\SimulationSchema;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * Simulador de trabajadores (docs/11 §11.66), en el servidor y sin cron.
 *
 * - Crear: un viaje de prueba (trips.simulation_id) del itinerario elegido,
 *   que sale ya, y N trabajadores simulados (users, workers y
 *   worker_itineraries con simulation_id), repartidos al azar entre las
 *   paradas y según los porcentajes de comportamiento. El Administrador que
 *   la inicia viaja también en él (si no estaba en el itinerario, se le añade
 *   una pertenencia marcada como simulada). Todo sale de una semilla: el plan
 *   (quién sube dónde, horas de cada uno, horario del vehículo simulado) se
 *   guarda al crear.
 * - Avanzar (tick): no hay cron, así que en cada petición (middleware
 *   AdvanceSimulation, como mucho cada 3 s; y con TASKS_ON_REQUESTS al
 *   terminar cualquier petición) se calcula lo que toca «ahora» desde la hora
 *   de inicio y se envían los informes pendientes con su hora de captura,
 *   por el mismo camino que los teléfonos (Trips::report): sensores, mayoría,
 *   pasos por parada y notificaciones se ejercitan igual. Basta con que la app
 *   del Administrador consulte (frecuencia corta, 10 s).
 * - Vehículo simulado: va de parada en parada a velocidad fija con
 *   detenciones de 1 min; los sensores simulados lo describen. Vehículo real:
 *   los simulados siguen lo que informan los teléfonos reales (suben cuando
 *   un pasajero real sube en su parada, el vehículo está detenido en ella o
 *   pasó por ella).
 * - Eliminar: borra el viaje y todo lo creado.
 */
class Simulations
{
    public const MAX_WORKERS = 60;

    /** Segundos (de simulación) desde que se crea hasta que el vehículo llega a la primera parada. */
    public const LEAD = 120;

    /** Detención en cada parada (segundos de simulación). */
    public const DWELL = 60;

    public const SPEED_FACTORS = [1, 2, 5, 10];

    public const NORMAL = 'viaja';
    public const LATE = 'llegada_tarde';
    public const LEFT_BEHIND = 'no_recogido';
    public const NOT_GOING = 'no_viajare';

    /** Entre dos avances automáticos (las consultas de la simulación siempre avanzan). */
    public const THROTTLE = 3;

    public function __construct(private Trips $trips, private Settings $settings, private Notifier $notifier)
    {
    }

    public function current(): ?Simulation
    {
        return SimulationSchema::ready() ? Simulation::orderByDesc('id')->first() : null;
    }

    /*
    |--------------------------------------------------------------------------
    | Crear
    |--------------------------------------------------------------------------
    */

    /**
     * @param array{itineraryId: int, direction?: string, workers: int, vehicleMode?: string, vehicleTypeId?: ?int,
     *              normal?: int, late?: int, leftBehind?: int, notGoing?: int, speedFactor?: int, vehicleSpeed?: int, seed?: ?int} $p
     */
    public function create(User $admin, array $p): Simulation
    {
        if (Simulation::exists()) {
            throw JsonApiException::conflict('SIMULATION_EXISTS', 'Ya hay una simulación: elimínela antes de crear otra.');
        }

        $itinerary = Itinerary::find($p['itineraryId']);

        if (! $itinerary) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Itinerario no válido', 'Elija un itinerario.', ['pointer' => '/data/relationships/itinerary']);
        }

        $direction = $p['direction'] ?? Trip::OUTBOUND;
        $mode = $p['vehicleMode'] ?? Simulation::VEHICLE_SIMULATED;
        $percent = [
            self::NORMAL => (int) ($p['normal'] ?? 70),
            self::LATE => (int) ($p['late'] ?? 10),
            self::LEFT_BEHIND => (int) ($p['leftBehind'] ?? 10),
            self::NOT_GOING => (int) ($p['notGoing'] ?? 10),
        ];

        if (array_sum($percent) !== 100 || min($percent) < 0) {
            throw new JsonApiException(422, 'PERCENTAGES_INVALID', 'Porcentajes no válidos', 'Los porcentajes deben sumar 100.', ['pointer' => '/data/attributes/normal']);
        }

        $probe = new Trip(['itinerary_id' => $itinerary->id, 'direction' => $direction]);
        $route = $probe->routeStopIds();

        if (count($route) < 2) {
            throw JsonApiException::conflict('ITINERARY_WITHOUT_STOPS', 'El itinerario necesita al menos dos paradas.', '/data/relationships/itinerary');
        }

        $vehicleType = isset($p['vehicleTypeId']) && $p['vehicleTypeId'] ? VehicleType::find($p['vehicleTypeId']) : VehicleType::where('active', true)->orderBy('id')->first();

        if (! $vehicleType) {
            throw new JsonApiException(422, 'VEHICLE_TYPE_INVALID', 'Tipo de vehículo no válido', 'Hace falta un tipo de vehículo activo.', ['pointer' => '/data/relationships/vehicleType']);
        }

        $workers = max(1, min(self::MAX_WORKERS, (int) $p['workers']));
        $factor = $mode === Simulation::VEHICLE_SIMULATED && in_array((int) ($p['speedFactor'] ?? 1), self::SPEED_FACTORS, true) ? (int) ($p['speedFactor'] ?? 1) : 1;
        $speed = max(5, min(120, (int) ($p['vehicleSpeed'] ?? 30)));
        $seed = isset($p['seed']) ? (int) $p['seed'] : random_int(1, 2_000_000_000);
        $now = Carbon::now();

        $simulation = DB::transaction(function () use ($admin, $itinerary, $direction, $mode, $percent, $route, $vehicleType, $workers, $factor, $speed, $seed, $now) {
            $simulation = Simulation::create([
                'itinerary_id' => $itinerary->id, 'created_by' => $admin->id, 'direction' => $direction, 'vehicle_mode' => $mode,
                'workers_count' => $workers, 'pct_normal' => $percent[self::NORMAL], 'pct_late' => $percent[self::LATE],
                'pct_left_behind' => $percent[self::LEFT_BEHIND], 'pct_not_going' => $percent[self::NOT_GOING],
                'speed_factor' => $factor, 'vehicle_speed_kmh' => $speed, 'seed' => $seed,
                'status' => Simulation::RUNNING, 'started_at' => $now,
            ]);

            $departs = $now->copy()->addSeconds((int) round(self::LEAD / $factor));
            $trip = Trip::create([
                'itinerary_id' => $itinerary->id, 'direction' => $direction, 'date' => $departs->toDateString(),
                'departure_time' => $departs->format('H:i'), 'departs_at' => $departs, 'vehicle_type_id' => $vehicleType->id,
                'observation' => 'Simulación', 'status' => Trip::PLANNED, 'status_changed_at' => $now,
                'created_by' => $admin->id, 'simulation_id' => $simulation->id,
            ]);

            $plan = $this->plan($simulation, $route, $percent);
            $this->createPeople($simulation, $itinerary, $admin, $route, $plan);
            $simulation->forceFill(['trip_id' => $trip->id, 'plan' => json_encode($plan)])->save();

            return $simulation;
        });

        $trip = Trip::find($simulation->trip_id);
        $this->trips->announce($trip);
        $this->tick($simulation->fresh(), true);

        return $simulation->fresh();
    }

    /**
     * El plan, determinista a partir de la semilla: comportamiento, paradas
     * de subida y bajada, sensores, demoras de cada uno y, con vehículo
     * simulado, el horario del vehículo (segundos de simulación desde el inicio).
     */
    public function plan(Simulation $simulation, array $route, array $percent): array
    {
        $random = self::random($simulation->seed);
        $n = $simulation->workers_count;
        $count = count($route);

        // Cuántos de cada comportamiento (mayor resto), al menos uno que viaja.
        $quotas = [];
        $remainders = [];

        foreach ($percent as $behaviour => $pct) {
            $exact = $n * $pct / 100;
            $quotas[$behaviour] = (int) floor($exact);
            $remainders[$behaviour] = $exact - floor($exact);
        }

        arsort($remainders);

        foreach (array_keys($remainders) as $behaviour) {
            if (array_sum($quotas) >= $n) {
                break;
            }
            $quotas[$behaviour]++;
        }

        if ($quotas[self::NORMAL] === 0) {
            // Siempre hay al menos uno que viaja (y hace de sensor).
            $largest = array_search(max($quotas), $quotas, true);
            $quotas[$largest]--;
            $quotas[self::NORMAL] = 1;
        }

        $behaviours = [];

        foreach ($quotas as $behaviour => $quota) {
            $behaviours = array_merge($behaviours, array_fill(0, $quota, $behaviour));
        }

        // Barajar (Fisher-Yates con la semilla).
        for ($i = count($behaviours) - 1; $i > 0; $i--) {
            $j = $random(0, $i);
            [$behaviours[$i], $behaviours[$j]] = [$behaviours[$j], $behaviours[$i]];
        }

        $simulated = $simulation->isSimulatedVehicle();
        $minimum = max(1, $this->settings->int('minimo_confirmaciones'));
        $sensors = $simulated ? min($minimum, $quotas[self::NORMAL]) : 0;
        $workers = [];

        foreach ($behaviours as $i => $behaviour) {
            $sensor = $behaviour === self::NORMAL && $sensors > 0;

            if ($sensor) {
                $sensors--;
                // Los sensores suben en la primera parada y siguen hasta la última: el vehículo se ve todo el recorrido.
                [$board, $drop] = [0, $count - 1];
            } else {
                $board = $random(0, $count - 2);
                $drop = $random($board + 1, $count - 1);
            }

            $workers[] = [
                'n' => $i + 1,
                'behaviour' => $behaviour,
                'sensor' => $sensor,
                'board' => $board,
                'drop' => $behaviour === self::NORMAL ? $drop : null,
                'onTheWay' => $random(0, 20),
                'notGoing' => $random(5, 50),
                'atStopFrac' => $random(0, 1000) / 1000,
                'boardDelay' => $random(5, 30),
                'dropDelay' => $random(10, 40),
                'missDelay' => $random(5, 20),
                'jitter' => $random(0, 5),
            ];
        }

        $plan = ['route' => $route, 'workers' => $workers, 'sent' => (object) []];

        if ($simulated) {
            $stops = Stop::whereIn('id', $route)->get()->keyBy('id');
            $speed = $simulation->vehicle_speed_kmh / 3.6;
            $arrive = [self::LEAD];
            $depart = [];

            foreach ($route as $k => $stopId) {
                if ($k > 0) {
                    $a = $stops[$route[$k - 1]] ?? null;
                    $b = $stops[$stopId] ?? null;
                    $meters = $a && $b ? Geo::distance((float) $a->latitude, (float) $a->longitude, (float) $b->latitude, (float) $b->longitude) : 1000;
                    // Al menos 30 s entre paradas (paradas muy juntas o repetidas).
                    $arrive[$k] = $depart[$k - 1] + max(30, (int) round($meters / $speed));
                }
                $depart[$k] = $arrive[$k] + self::DWELL;
            }

            $plan['arrive'] = $arrive;
            $plan['depart'] = $depart;
        }

        return $plan;
    }

    /** Generador de números de la semilla (xorshift32): entero entre $min y $max. */
    private static function random(int $seed): \Closure
    {
        $state = ($seed & 0x7fffffff) ?: 1;

        return function (int $min, int $max) use (&$state): int {
            $state ^= ($state << 13) & 0xffffffff;
            $state ^= $state >> 17;
            $state ^= ($state << 5) & 0xffffffff;
            $state &= 0xffffffff;

            return $max <= $min ? $min : $min + ($state % ($max - $min + 1));
        };
    }

    /**
     * Los trabajadores simulados (sin contraseña utilizable) y, si no estaba
     * en el itinerario, la pertenencia del Administrador.
     */
    private function createPeople(Simulation $simulation, Itinerary $itinerary, User $admin, array $route, array &$plan): void
    {
        $now = Carbon::now();
        $password = Hash::make(Str::random(40));

        foreach ($plan['workers'] as $i => $w) {
            $userId = DB::table('users')->insertGetId([
                'username' => 'sim'.$simulation->id.'-'.$w['n'],
                'password' => $password,
                'first_name' => 'Trabajador',
                'first_surname' => 'Simulado',
                'second_surname' => str_pad((string) $w['n'], 2, '0', STR_PAD_LEFT),
                // Correo único (docs/11 §11.67), de un dominio que no existe.
                'email' => 'sim'.$simulation->id.'-'.$w['n'].'-'.$simulation->seed.'@simulacion.miruta.invalid',
                'sex' => $w['n'] % 2 ? 'F' : 'M',
                'birth_date' => '1990-01-01',
                'is_admin' => false,
                'simulation_id' => $simulation->id,
                'created_at' => $now, 'updated_at' => $now,
            ]);
            $workerId = DB::table('workers')->insertGetId([
                'user_id' => $userId, 'entity_id' => $itinerary->entity_id, 'active' => true,
                'simulation_id' => $simulation->id, 'created_at' => $now, 'updated_at' => $now,
            ]);
            DB::table('worker_itineraries')->insert([
                'worker_id' => $workerId, 'user_id' => $userId, 'itinerary_id' => $itinerary->id,
                // Parada habitual: donde le toca esperar.
                'stop_id' => $route[$w['board']], 'is_chief' => false,
                'simulation_id' => $simulation->id, 'created_at' => $now, 'updated_at' => $now,
            ]);
            $plan['workers'][$i]['userId'] = $userId;
        }

        // El Administrador viaja también en el viaje de prueba (ve «Mi estado» y sus notificaciones).
        if (! WorkerItinerary::where('user_id', $admin->id)->where('itinerary_id', $itinerary->id)->exists()) {
            $workerId = Worker::where('user_id', $admin->id)->where('entity_id', $itinerary->entity_id)->value('id')
                ?? DB::table('workers')->insertGetId([
                    'user_id' => $admin->id, 'entity_id' => $itinerary->entity_id, 'active' => true,
                    'simulation_id' => $simulation->id, 'created_at' => $now, 'updated_at' => $now,
                ]);
            DB::table('worker_itineraries')->insert([
                'worker_id' => $workerId, 'user_id' => $admin->id, 'itinerary_id' => $itinerary->id, 'stop_id' => null,
                'is_chief' => false, 'simulation_id' => $simulation->id, 'created_at' => $now, 'updated_at' => $now,
            ]);
        }
    }

    /*
    |--------------------------------------------------------------------------
    | Avanzar
    |--------------------------------------------------------------------------
    */

    /**
     * Avanza la simulación en curso (si la hay) desde las peticiones.
     */
    public function advance(bool $force = false): void
    {
        if (! SimulationSchema::ready()) {
            return;
        }

        $simulation = Simulation::where('status', Simulation::RUNNING)->first();

        if ($simulation) {
            $this->tick($simulation, $force);
        }
    }

    /**
     * Envía los informes que tocan hasta ahora (con su hora de captura).
     * Una sola petición a la vez (cerrojo de archivo); las demás siguen.
     */
    public function tick(Simulation $simulation, bool $force = false): void
    {
        $now = Carbon::now();

        if ($simulation->status !== Simulation::RUNNING
            || (! $force && $simulation->last_tick_at && $simulation->last_tick_at->gt($now->copy()->subSeconds(self::THROTTLE)))) {
            return;
        }

        $directory = storage_path('app');

        if (! is_dir($directory)) {
            @mkdir($directory, 0775, true);
        }

        $lock = @fopen($directory.'/simulacion.lock', 'c');

        if ($lock === false || ! flock($lock, LOCK_EX | LOCK_NB)) {
            return;
        }

        try {
            $simulation = $simulation->fresh();

            if ($simulation && $simulation->status === Simulation::RUNNING) {
                $this->run($simulation, $now);
            }
        } catch (\Throwable $e) {
            Log::error('Simulación: '.$e->getMessage(), ['exception' => $e]);
        } finally {
            flock($lock, LOCK_UN);
            fclose($lock);
        }
    }

    private function run(Simulation $simulation, Carbon $now): void
    {
        $trip = $simulation->trip_id ? Trip::find($simulation->trip_id) : null;

        if (! $trip || ! $trip->isOpen()) {
            $simulation->forceFill(['status' => Simulation::FINISHED, 'finished_at' => $now, 'last_tick_at' => $now])->save();

            return;
        }

        $plan = $simulation->planData();
        $sent = (array) ($plan['sent'] ?? []);
        $userIds = array_column($plan['workers'], 'userId');
        // Los teléfonos simulados siguen encendidos: cuentan como recientes.
        $this->heartbeat($trip, $userIds, $now);

        $events = $simulation->isSimulatedVehicle()
            ? $this->simulatedEvents($simulation, $plan, $sent, $now)
            : $this->realEvents($simulation, $trip, $plan, $sent, $now);

        usort($events, fn ($a, $b) => [$a['at']->getTimestamp(), $a['w'], $a['order']] <=> [$b['at']->getTimestamp(), $b['w'], $b['order']]);
        $users = User::withoutGlobalScope(NotSimulated::class)->whereIn('id', $userIds ?: [0])->get()->keyBy('id');

        // Los de un mismo trabajador a la misma hora van en un solo informe.
        $batches = [];

        foreach ($events as $event) {
            $last = count($batches) - 1;

            if ($last >= 0 && $batches[$last]['w'] === $event['w'] && $batches[$last]['at']->eq($event['at'])) {
                $batches[$last]['items'][] = $event;
            } else {
                $batches[] = ['w' => $event['w'], 'at' => $event['at'], 'items' => [$event]];
            }
        }

        foreach ($batches as $batch) {
            $w = $plan['workers'][$batch['w']] ?? null;
            $trip = $trip->fresh();

            foreach ($batch['items'] as $item) {
                $sent[$batch['w'].':'.$item['key']] = $item['at']->getTimestamp();
            }

            if (! $trip || ! $trip->isOpen()) {
                break;
            }

            // Arranque a mano (como el Administrador) si no salió solo: pocos trabajadores que viajan.
            if ($batch['w'] === -1) {
                if ($trip->status === Trip::PLANNED) {
                    $this->trips->start($trip, $batch['items'][0]['startAt']);
                }
                continue;
            }

            $user = $users[$w['userId'] ?? 0] ?? null;

            if (! $user) {
                continue;
            }

            $payload = array_map(fn ($item) => $item['event'] + ['capturedAt' => $item['at']->toIso8601String()], $batch['items']);

            try {
                $this->trips->report($user, $trip, ['events' => $payload, 'gps' => (bool) $w['sensor']]);
            } catch (JsonApiException $e) {
                Log::info('Simulación: informe no aplicado: '.$e->getMessage());
            }
        }

        $trip = $trip?->fresh();

        if ($trip && $trip->status === Trip::RUNNING) {
            $this->heartbeat($trip, $userIds, $now);
            $this->trips->evaluate($trip);
            $trip = $trip->fresh();
        }

        $plan['sent'] = (object) $sent;
        $finished = ! $trip || ! $trip->isOpen();
        $simulation->forceFill([
            'plan' => json_encode($plan),
            'last_tick_at' => $now,
            'status' => $finished ? Simulation::FINISHED : Simulation::RUNNING,
            'finished_at' => $finished ? $now : null,
        ])->save();
    }

    private function heartbeat(Trip $trip, array $userIds, Carbon $now): void
    {
        TripPassenger::where('trip_id', $trip->id)->whereIn('user_id', $userIds ?: [0])
            ->whereNotIn('state', TripPassenger::FINAL_STATES)->update(['last_seen_at' => $now]);
    }

    /** Hora real de un instante de la simulación (segundos desde el inicio, con el factor de velocidad). */
    private function at(Simulation $simulation, float $offset): Carbon
    {
        return $simulation->started_at->copy()->addSeconds((int) round($offset / max(1, $simulation->speed_factor)));
    }

    private static function worker(string $state, ?int $stopId, bool $manual = false): array
    {
        return ['kind' => 'worker', 'state' => $state, 'stopId' => $stopId] + ($manual ? ['manual' => true] : []);
    }

    /** Lo que ve un sensor: detenido en la parada (dentro de su radio) o en movimiento, con la velocidad. */
    private static function vehicle(string $state, bool $atStop, int $next, float $speed = 0): array
    {
        return ['kind' => 'vehicle', 'vehicleState' => $state, 'atStop' => $atStop, 'inRadius' => $atStop, 'nextStopIndex' => $next,
            'speed' => $state === Trip::MOVING ? $speed : 0];
    }

    /**
     * Vehículo simulado: todo sale del horario y de las demoras del plan.
     *
     * @return array<int, array{at: Carbon, w: int, order: int, key: string, event: array}>
     */
    private function simulatedEvents(Simulation $simulation, array $plan, array $sent, Carbon $now): array
    {
        $route = $plan['route'];
        $last = count($route) - 1;
        $arrive = $plan['arrive'];
        $depart = $plan['depart'];
        $events = [];
        $add = function (int $w, string $key, float $offset, ?array $event, int $order = 0, array $extra = []) use (&$events, $sent, $now, $simulation) {
            $at = $this->at($simulation, $offset);

            if (! isset($sent[$w.':'.$key]) && $at->lte($now)) {
                $events[] = ['at' => $at, 'w' => $w, 'order' => $order, 'key' => $key, 'event' => $event ?? []] + $extra;
            }
        };

        foreach ($plan['workers'] as $w => $p) {
            $b = $p['board'];

            if ($p['behaviour'] === self::NOT_GOING) {
                $add($w, 'nv', $p['notGoing'], self::worker(TripPassenger::NOT_TRAVELLING, null, true));
                continue;
            }

            $add($w, 'dc', $p['onTheWay'], self::worker(TripPassenger::APPROACHING, $route[$b]));

            if (in_array($p['behaviour'], [self::NORMAL, self::LEFT_BEHIND], true)) {
                $lo = $p['onTheWay'] + 5;
                $hi = $arrive[$b] - 15;
                $add($w, 'ep', $lo + $p['atStopFrac'] * max(0, $hi - $lo), self::worker(TripPassenger::AT_STOP, $route[$b]));
            }

            if ($p['behaviour'] === self::LEFT_BEHIND) {
                $add($w, 'nr', $depart[$b] + $p['missDelay'], self::worker(TripPassenger::LEFT_BEHIND, $route[$b]));
            } elseif ($p['behaviour'] === self::LATE) {
                $add($w, 'rt', $depart[$b] + $p['missDelay'], self::worker(TripPassenger::LATE, $route[$b]));
            } else {
                $board = $arrive[$b] + $p['boardDelay'];
                $add($w, 'vj', $board, self::worker(TripPassenger::TRAVELLING, $route[$b]));

                if ($p['sensor']) {
                    // Lo que ve el teléfono en el vehículo: detenido en la parada, en movimiento hacia la siguiente…
                    $add($w, 'o'.$b, $board, self::vehicle(Trip::STOPPED, true, $b), 1);

                    for ($k = $b; $k <= $last; $k++) {
                        if ($k > $b) {
                            $add($w, 'a'.$k, $arrive[$k] + $p['jitter'], self::vehicle(Trip::STOPPED, true, $k), 1);
                        }
                        $add($w, 'm'.$k, $depart[$k] + $p['jitter'], self::vehicle(Trip::MOVING, false, $k + 1, (float) $simulation->vehicle_speed_kmh), 1);
                    }

                    $add($w, 'dj', $depart[$last] + $p['jitter'] + 3, self::worker(TripPassenger::DROPPED, $route[$last]));
                } else {
                    $add($w, 'dj', $arrive[$p['drop']] + $p['dropDelay'], self::worker(TripPassenger::DROPPED, $route[$p['drop']]));
                }
            }
        }

        // Si no salió solo (menos que «Mínimo confirmaciones» viajando), sale al dejar la primera parada.
        $add(-1, 'start', $depart[0] + 1, null, 0, ['startAt' => $this->at($simulation, $arrive[0])]);

        return $events;
    }

    /**
     * Vehículo real: los simulados reaccionan a lo que informan los teléfonos
     * reales (pasos por parada, vehículo detenido en una parada, pasajeros
     * reales que suben).
     *
     * @return array<int, array{at: Carbon, w: int, order: int, key: string, event: array}>
     */
    private function realEvents(Simulation $simulation, Trip $trip, array $plan, array $sent, Carbon $now): array
    {
        $route = $plan['route'];
        $simulatedIds = array_column($plan['workers'], 'userId');
        $passes = TripStopPass::where('trip_id', $trip->id)->get()->keyBy('route_index');
        $atStopIndex = $trip->status === Trip::RUNNING && $trip->vehicle_at_stop ? (int) $trip->next_stop_index : null;
        // Pasajeros reales que subieron en cada parada.
        $realBoard = [];

        foreach (TripPassenger::where('trip_id', $trip->id)->whereNotIn('user_id', $simulatedIds ?: [0])
            ->whereIn('state', [TripPassenger::TRAVELLING, TripPassenger::DROPPED])->get() as $real) {
            $index = array_search((int) $real->stop_id, $route, true);

            if ($index !== false && $real->state === TripPassenger::TRAVELLING) {
                $realBoard[$index] = isset($realBoard[$index]) ? $realBoard[$index]->min($real->state_at) : $real->state_at;
            }
        }

        // Cuándo llegó el vehículo a la parada $i (o null si aún no).
        $reached = function (int $i) use ($passes, $atStopIndex, $realBoard, $now): ?Carbon {
            $times = array_filter([
                isset($passes[$i]) ? $passes[$i]->passed_at : null,
                $realBoard[$i] ?? null,
                $atStopIndex === $i ? $now : null,
            ]);

            return $times ? min($times) : null;
        };

        $events = [];
        $add = function (int $w, string $key, Carbon $at, array $event, int $order = 0) use (&$events, &$sent, $now) {
            $at = $at->gt($now) ? $now->copy() : $at->copy();

            if (! isset($sent[$w.':'.$key])) {
                $events[] = ['at' => $at, 'w' => $w, 'order' => $order, 'key' => $key, 'event' => $event];
                $sent[$w.':'.$key] = $at->getTimestamp();
            }
        };
        $due = fn (float $offset) => $this->at($simulation, $offset)->lte($now) ? $this->at($simulation, $offset) : null;

        foreach ($plan['workers'] as $w => $p) {
            $b = $p['board'];

            if ($p['behaviour'] === self::NOT_GOING) {
                if ($t = $due($p['notGoing'])) {
                    $add($w, 'nv', $t, self::worker(TripPassenger::NOT_TRAVELLING, null, true));
                }
                continue;
            }

            if ($t = $due($p['onTheWay'])) {
                $add($w, 'dc', $t, self::worker(TripPassenger::APPROACHING, $route[$b]));
            }

            $waiting = in_array($p['behaviour'], [self::NORMAL, self::LEFT_BEHIND], true);
            $atStopTime = $p['onTheWay'] + 10 + $p['atStopFrac'] * 90;

            if ($waiting && ($t = $due($atStopTime))) {
                $add($w, 'ep', $t, self::worker(TripPassenger::AT_STOP, $route[$b]));
            }

            $arrived = $reached($b);

            if ($arrived === null) {
                continue;
            }

            if ($p['behaviour'] === self::NORMAL) {
                // Sube cuando el vehículo llega a su parada (antes, si no, «Acercándose a Parada» y «En Parada»).
                $boardAt = isset($sent[$w.':vj']) ? Carbon::createFromTimestamp($sent[$w.':vj'], config('app.timezone')) : $arrived->copy()->addSeconds(2);
                $add($w, 'dc', $boardAt->copy()->subSeconds(2), self::worker(TripPassenger::APPROACHING, $route[$b]));
                $add($w, 'ep', $boardAt->copy()->subSecond(), self::worker(TripPassenger::AT_STOP, $route[$b]));
                $add($w, 'vj', $boardAt, self::worker(TripPassenger::TRAVELLING, $route[$b]));
                $dropped = $reached($p['drop']);

                if ($dropped !== null) {
                    $add($w, 'dj', $dropped->max($boardAt->copy()->addSecond())->addSeconds(5), self::worker(TripPassenger::DROPPED, $route[$p['drop']]));
                }
            } elseif (isset($passes[$b])) {
                // El vehículo pasó por su parada sin él.
                $at = $passes[$b]->passed_at->copy()->addSeconds($p['missDelay']);
                $add($w, 'dc', $passes[$b]->passed_at->copy()->subSeconds(2), self::worker(TripPassenger::APPROACHING, $route[$b]));

                if ($p['behaviour'] === self::LEFT_BEHIND) {
                    $add($w, 'ep', $passes[$b]->passed_at->copy()->subSecond(), self::worker(TripPassenger::AT_STOP, $route[$b]));
                    $add($w, 'nr', $at, self::worker(TripPassenger::LEFT_BEHIND, $route[$b]));
                } else {
                    $add($w, 'rt', $at, self::worker(TripPassenger::LATE, $route[$b]));
                }
            }
        }

        return $events;
    }

    /*
    |--------------------------------------------------------------------------
    | Estado y eliminar
    |--------------------------------------------------------------------------
    */

    /**
     * Cómo va: viaje, hora de la simulación, cantidades por estado y, con
     * vehículo simulado, dónde está el vehículo.
     */
    public function status(Simulation $simulation): array
    {
        $plan = $simulation->planData();
        $userIds = array_column($plan['workers'] ?? [], 'userId');
        $trip = $simulation->trip_id ? Trip::find($simulation->trip_id) : null;
        $counts = [];
        $mine = null;

        if ($trip) {
            foreach (TripPassenger::where('trip_id', $trip->id)->whereIn('user_id', $userIds ?: [0])->get() as $p) {
                $counts[$p->state] = ($counts[$p->state] ?? 0) + 1;
            }

            $mine = TripPassenger::where('trip_id', $trip->id)->where('user_id', $simulation->created_by)->value('state');
        }

        $reported = array_sum($counts);
        $behaviours = array_count_values(array_column($plan['workers'] ?? [], 'behaviour'));

        return [
            'counts' => (object) $counts,
            'notReported' => max(0, count($userIds) - $reported),
            'behaviours' => (object) $behaviours,
            'sensors' => count(array_filter(array_column($plan['workers'] ?? [], 'sensor'))),
            'tripStatus' => $trip?->status,
            'myState' => $mine,
            'elapsedSeconds' => (int) max(0, $simulation->started_at->diffInSeconds($simulation->finished_at ?? Carbon::now(), true)),
            'vehicle' => $simulation->isSimulatedVehicle() ? $this->vehiclePosition($simulation, $plan) : null,
        ];
    }

    /** Dónde está el vehículo simulado ahora. */
    public function vehiclePosition(Simulation $simulation, array $plan): ?array
    {
        if (! isset($plan['arrive'])) {
            return null;
        }

        $route = $plan['route'];
        $names = Stop::whereIn('id', $route)->pluck('landmark', 'id');
        $offset = $simulation->started_at->diffInSeconds(Carbon::now(), true) * max(1, $simulation->speed_factor);

        foreach ($route as $k => $stopId) {
            if ($offset < $plan['arrive'][$k]) {
                return ['state' => Trip::MOVING, 'atStop' => false, 'stopIndex' => $k, 'text' => 'Hacia '.($names[$stopId] ?? '')];
            }

            if ($offset < $plan['depart'][$k]) {
                return ['state' => Trip::STOPPED, 'atStop' => true, 'stopIndex' => $k, 'text' => 'En '.($names[$stopId] ?? '')];
            }
        }

        return ['state' => null, 'atStop' => false, 'stopIndex' => count($route), 'text' => 'Terminó el recorrido'];
    }

    /**
     * «Eliminar Simulación»: el viaje de prueba (con sus estados, pasos y
     * notificaciones), los trabajadores simulados y la pertenencia añadida
     * al Administrador.
     */
    public function delete(Simulation $simulation): void
    {
        DB::transaction(function () use ($simulation) {
            $trip = $simulation->trip_id ? Trip::find($simulation->trip_id) : null;

            if ($trip) {
                Notification::where('user_id', $simulation->created_by)
                    ->where('data', 'like', '%"tripId":"'.$trip->id.'"%')->delete();
                // Sin aviso (docs/11 §11.67): su teléfono quita la notificación al saber que el viaje ya no existe.
                $this->trips->delete($trip);
            }

            Trip::where('simulation_id', $simulation->id)->delete();
            DB::table('worker_itineraries')->where('simulation_id', $simulation->id)->delete();
            DB::table('workers')->where('simulation_id', $simulation->id)->delete();
            DB::table('users')->where('simulation_id', $simulation->id)->delete();
            $simulation->delete();
        });
    }
}
