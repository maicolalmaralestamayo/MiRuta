<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Absence;
use App\Models\DetentionCause;
use App\Models\Itinerary;
use App\Models\ItineraryStop;
use App\Models\Stop;
use App\Models\Trip;
use App\Models\TripPassenger;
use App\Models\TripStopPass;
use App\Models\TripVehicleReport;
use App\Models\User;
use App\Models\VehicleType;
use App\Models\Worker;
use App\Support\SpanishDate;
use Carbon\Carbon;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;

/**
 * Viajes y su tiempo real (docs/11 §11.42 a §11.47).
 *
 * - Un viaje es de ida (todos suben en la primera parada y se van bajando) o
 *   de regreso (suben por sus paradas y bajan todos en la primera).
 * - Estados: planificado → en_ejecucion → terminado, o planificado → cancelado.
 *   En ejecución ya no se edita.
 * - El estado de cada trabajador lo calcula su teléfono y envía solo los
 *   cambios (report()). Los teléfonos de quienes van en el vehículo (Viajando
 *   en la ida, Recogido en el regreso) son sensores: informan si el vehículo
 *   está detenido o en movimiento y cuál es su próxima parada; el servidor
 *   decide por mayoría (ajuste «Mínimo confirmaciones»).
 * - El estado del viaje cambia a mano (Administrador o Jefe) o solo: empieza
 *   cuando suficientes trabajadores están Viajando (ida) o Recogidos en la
 *   última parada (regreso); termina al pasar la última parada (ida) o al
 *   detenerse en la primera (regreso); y las revisiones de review() (plazos).
 */
class Trips
{
    public function __construct(private Access $access, private Settings $settings, private Notifier $notifier, private ChildEligibility $children)
    {
    }

    /*
    |--------------------------------------------------------------------------
    | Quién ve y quién gestiona
    |--------------------------------------------------------------------------
    */

    /**
     * Viajes que ve: el Administrador, todos; el Jefe, los de su itinerario;
     * el trabajador, los de sus itinerarios si tiene parada (docs/11 §11.24).
     */
    public function visibleQuery(User $user): Builder
    {
        $query = Trip::query();

        if ($this->access->isAdmin($user)) {
            return $query;
        }

        $itineraryIds = $this->access->workersOf($user)
            ->filter(fn (Worker $w) => $w->itinerary_id && $w->active && ($w->stop_id || $w->is_chief))
            ->pluck('itinerary_id')->map(fn ($id) => (int) $id)->values()->all();

        return $query->whereIn('itinerary_id', $itineraryIds ?: [0]);
    }

    public function canManage(User $user, Trip $trip): bool
    {
        return $this->access->canManageItinerary($user, $trip->itinerary_id);
    }

    /**
     * Pasajeros esperados: los activos del itinerario con parada y sin una
     * ausencia ese día (docs/11 §11.33).
     */
    public function expectedQuery(Trip $trip): Builder
    {
        $date = $trip->date->toDateString();

        return Worker::where('itinerary_id', $trip->itinerary_id)->where('active', true)->whereNotNull('stop_id')
            ->whereNotIn('id', Absence::covering($date)->select('worker_id'));
    }

    /*
    |--------------------------------------------------------------------------
    | Planificar, editar y cambiar de estado
    |--------------------------------------------------------------------------
    */

    public function create(User $actor, int $itineraryId, string $direction, string $date, string $time, int $vehicleTypeId, ?string $observation): Trip
    {
        $itinerary = Itinerary::findOrFail($itineraryId);
        $this->access->requireItineraryManager($actor, $itinerary->id, 'Solo el Administrador o el Jefe de ese itinerario planifican sus viajes.');

        if (! $itinerary->active) {
            throw JsonApiException::conflict('ITINERARY_INACTIVE', 'El itinerario está desactivado.', '/data/relationships/itinerary');
        }

        if (ItineraryStop::where('itinerary_id', $itinerary->id)->count() < 2) {
            throw JsonApiException::conflict('ITINERARY_WITHOUT_STOPS', 'El itinerario necesita al menos dos paradas para planificar viajes.', '/data/relationships/itinerary');
        }

        $this->ensureVehicleType($vehicleTypeId);
        $departsAt = $this->departure($date, $time);

        try {
            $trip = Trip::create([
                'itinerary_id' => $itinerary->id,
                'direction' => $direction,
                'date' => $departsAt->toDateString(),
                'departure_time' => $departsAt->format('H:i'),
                'departs_at' => $departsAt,
                'vehicle_type_id' => $vehicleTypeId,
                'observation' => $observation,
                'status' => Trip::PLANNED,
                'status_changed_at' => Carbon::now(),
                'created_by' => $actor->id,
            ]);
        } catch (QueryException $e) {
            throw JsonApiException::conflict('TRIP_EXISTS', 'Ya hay un viaje de '.$direction.' de ese itinerario ese día.', '/data/attributes/date');
        }

        $this->notifier->send($this->notifier->tripAudience($trip), Notifier::TRIP_CREATED, 'Viaje planificado',
            $this->describe($trip).'.', $this->data($trip));

        return $trip;
    }

    /**
     * Cambia fecha, hora, tipo de vehículo u observación (solo Planificado).
     */
    public function update(User $actor, Trip $trip, array $changes): Trip
    {
        $this->requireManager($actor, $trip);

        if ($trip->status !== Trip::PLANNED) {
            throw JsonApiException::conflict('TRIP_NOT_EDITABLE', 'Solo se cambian los datos de un viaje Planificado.');
        }

        $date = $changes['date'] ?? $trip->date->toDateString();
        $time = $changes['departureTime'] ?? $trip->departure_time;
        $before = $this->describe($trip);

        if (isset($changes['date']) || isset($changes['departureTime'])) {
            $departsAt = $this->departure($date, $time);
            $trip->date = $departsAt->toDateString();
            $trip->departure_time = $departsAt->format('H:i');
            $trip->departs_at = $departsAt;
        }

        if (isset($changes['vehicleTypeId'])) {
            $this->ensureVehicleType((int) $changes['vehicleTypeId']);
            $trip->vehicle_type_id = (int) $changes['vehicleTypeId'];
        }

        if (array_key_exists('observation', $changes)) {
            $trip->observation = $changes['observation'];
        }

        if (! $trip->isDirty()) {
            return $trip;
        }

        try {
            $trip->save();
        } catch (QueryException $e) {
            throw JsonApiException::conflict('TRIP_EXISTS', 'Ya hay un viaje de '.$trip->direction.' de ese itinerario ese día.', '/data/attributes/date');
        }

        $this->notifier->send($this->notifier->tripAudience($trip), Notifier::TRIP_CHANGED, 'Viaje modificado',
            'Antes: '.$before.'. Ahora: '.$this->describe($trip).'.', $this->data($trip));

        return $trip;
    }

    /**
     * Cambio de estado a mano (docs/11 §11.43): Planificado → En ejecución o
     * Cancelado; En ejecución → Terminado.
     */
    public function changeStatus(User $actor, Trip $trip, string $status): Trip
    {
        $this->requireManager($actor, $trip);

        if ($trip->status === Trip::PLANNED && $status === Trip::RUNNING) {
            return $this->start($trip);
        }

        if ($trip->status === Trip::PLANNED && $status === Trip::CANCELLED) {
            // Lo cancela el Administrador o el Jefe que lo planificó.
            if (! $this->access->isAdmin($actor) && (int) $trip->created_by !== (int) $actor->id) {
                throw Access::forbidden('Solo el Administrador o el Jefe que planificó el viaje pueden cancelarlo.');
            }

            return $this->cancel($trip);
        }

        if ($trip->status === Trip::RUNNING && $status === Trip::FINISHED) {
            return $this->finish($trip, 'manual');
        }

        if ($trip->status === $status) {
            return $trip;
        }

        throw JsonApiException::conflict('TRIP_TRANSITION_INVALID',
            'Un viaje '.self::statusName($trip->status).' no puede pasar a '.self::statusName($status).'.', '/data/attributes/status');
    }

    /**
     * Causa de la detención del vehículo en el trayecto (Administrador o Jefe).
     */
    public function setDetentionCause(User $actor, Trip $trip, ?int $causeId): Trip
    {
        $this->requireManager($actor, $trip);

        if ($causeId !== null) {
            if ($trip->status !== Trip::RUNNING || $trip->vehicle_state !== Trip::STOPPED) {
                throw JsonApiException::conflict('VEHICLE_NOT_STOPPED', 'Solo se indica la causa con el vehículo detenido durante el viaje.');
            }

            $cause = DetentionCause::find($causeId);

            if (! $cause || ! $cause->active) {
                throw new JsonApiException(422, 'DETENTION_CAUSE_INVALID', 'Causa no válida', 'Elija una causa de detención activa.', ['pointer' => '/data/relationships/detentionCause']);
            }
        }

        $trip->detention_cause_id = $causeId;
        $trip->save();

        return $trip;
    }

    public function start(Trip $trip): Trip
    {
        $now = Carbon::now();
        $route = $trip->routeStopIds();

        DB::transaction(function () use ($trip, $now, $route) {
            $trip->forceFill([
                'status' => Trip::RUNNING,
                'status_changed_at' => $now,
                'route' => implode(',', $route),
                // La parada de salida queda pasada al empezar (docs/11 §11.43).
                'next_stop_index' => min(1, max(0, count($route) - 1)),
                'vehicle_state' => Trip::MOVING,
                'vehicle_state_since' => $now,
                'vehicle_at_stop' => false,
            ])->save();

            if ($route) {
                TripStopPass::firstOrCreate(['trip_id' => $trip->id, 'route_index' => 0], ['stop_id' => $route[0], 'passed_at' => $now]);
            }
        });

        $this->notifier->send($this->notifier->tripAudience($trip), Notifier::TRIP_STATUS, 'Viaje en ejecución',
            ucfirst($this->describe($trip)).': ya está en ejecución.', $this->data($trip));

        return $trip;
    }

    public function finish(Trip $trip, string $reason): Trip
    {
        // La terminación no se notifica (docs/11 §11.47): la app lo sabe al consultar.
        $trip->forceFill(['status' => Trip::FINISHED, 'status_changed_at' => Carbon::now(), 'finish_reason' => $reason])->save();

        return $trip;
    }

    public function cancel(Trip $trip): Trip
    {
        $trip->forceFill(['status' => Trip::CANCELLED, 'status_changed_at' => Carbon::now()])->save();
        $this->notifier->send($this->notifier->tripAudience($trip), Notifier::TRIP_STATUS, 'Viaje cancelado',
            'Se canceló el '.$this->describe($trip).'.', $this->data($trip));

        return $trip;
    }

    /*
    |--------------------------------------------------------------------------
    | Informes de los teléfonos
    |--------------------------------------------------------------------------
    */

    /**
     * Informe de un teléfono durante el viaje: su estado (solo los cambios),
     * los hijos que suben con él y, si es sensor, el estado del vehículo.
     * Es idempotente: se puede reenviar hasta recibir el acuse.
     *
     * @param array $report [workerState?, stopId?, childIds?, childrenCount?, vehicleState?, atStop?, nextStopIndex?, reportedAt?]
     * @return array{applied: bool, reason: ?string, sensor: bool}
     */
    public function report(User $user, Trip $trip, array $report): array
    {
        $worker = Worker::where('user_id', $user->id)->where('itinerary_id', $trip->itinerary_id)->first();

        if (! $worker) {
            throw Access::forbidden('Solo informan su estado los trabajadores del itinerario del viaje.');
        }

        if (! $trip->isOpen()) {
            return ['applied' => false, 'reason' => 'VIAJE_CERRADO', 'sensor' => false];
        }

        $now = Carbon::now();
        $reportedAt = isset($report['reportedAt']) ? Carbon::parse($report['reportedAt'])->setTimezone(config('app.timezone')) : $now->copy();
        $result = ['applied' => true, 'reason' => null, 'sensor' => false];

        $result = DB::transaction(function () use ($user, $trip, $worker, $report, $now, $reportedAt, $result) {
            $passenger = TripPassenger::where('trip_id', $trip->id)->where('user_id', $user->id)->lockForUpdate()->first();

            if (isset($report['workerState'])) {
                [$applied, $reason] = $this->applyWorkerState($trip, $worker, $passenger, $report, $now, $reportedAt);
                $result['applied'] = $applied;
                $result['reason'] = $reason;
                $passenger = TripPassenger::where('trip_id', $trip->id)->where('user_id', $user->id)->first();
            }

            if (! $passenger) {
                $passenger = TripPassenger::create([
                    'trip_id' => $trip->id, 'user_id' => $user->id, 'stop_id' => $worker->stop_id,
                    'state' => TripPassenger::ON_THE_WAY, 'state_at' => $now, 'reported_at' => $reportedAt,
                ]);
            }

            $passenger->last_seen_at = $now;
            $passenger->save();

            $result['sensor'] = $this->isSensorState($trip, $passenger->state);

            if ($result['sensor'] && isset($report['vehicleState'])) {
                $this->storeVehicleReport($trip, $user, $report, $reportedAt);
            }

            return $result;
        });

        $this->evaluate($trip->fresh());

        return $result;
    }

    /**
     * @return array{0: bool, 1: ?string}
     */
    private function applyWorkerState(Trip $trip, Worker $worker, ?TripPassenger $passenger, array $report, Carbon $now, Carbon $reportedAt): array
    {
        $state = $report['workerState'];
        $allowed = $trip->isOutbound() ? TripPassenger::OUTBOUND_STATES : TripPassenger::RETURN_STATES;

        if (! in_array($state, $allowed, true)) {
            throw new JsonApiException(422, 'WORKER_STATE_INVALID', 'Estado no válido',
                'En un viaje de '.$trip->direction.' los estados son: '.implode(', ', $allowed).'.', ['pointer' => '/data/attributes/workerState']);
        }

        if ($passenger) {
            // Reenvío de un informe ya aplicado o más viejo que el último: acuse sin cambios.
            if ($passenger->reported_at && $reportedAt->lt($passenger->reported_at)) {
                return [false, 'INFORME_ANTERIOR'];
            }

            if ($passenger->state === $state) {
                $this->applyChildren($worker, $passenger, $report);
                $passenger->reported_at = $reportedAt;
                $passenger->save();

                return [true, null];
            }

            if (in_array($passenger->state, TripPassenger::FINAL_STATES, true)) {
                return [false, 'ESTADO_FINAL'];
            }

            // Viajando es semidefinitivo: solo puede pasar a Dejado.
            if ($passenger->state === TripPassenger::TRAVELLING && $state !== TripPassenger::DROPPED) {
                return [false, 'TRANSICION_NO_PERMITIDA'];
            }
        }

        $stopId = $worker->stop_id;

        if ($state === TripPassenger::DROPPED && isset($report['stopId'])) {
            // Se bajó en otra parada del recorrido.
            if (! in_array((int) $report['stopId'], $trip->routeStopIds(), true)) {
                throw new JsonApiException(422, 'STOP_NOT_IN_ITINERARY', 'Parada de otro itinerario', 'La parada no es del recorrido del viaje.', ['pointer' => '/data/attributes/stopId']);
            }
            $stopId = (int) $report['stopId'];
        }

        $passenger = $passenger ?: new TripPassenger(['trip_id' => $trip->id, 'user_id' => $worker->user_id]);
        $passenger->fill(['state' => $state, 'state_at' => $now, 'reported_at' => $reportedAt, 'stop_id' => $stopId]);
        $this->applyChildren($worker, $passenger, $report);
        $passenger->save();

        return [true, null];
    }

    /**
     * Hijos que suben con él: el trabajador elige cuáles (childIds); si no,
     * solo cuántos (childrenCount). Cada niño cuenta una sola vez por viaje.
     */
    private function applyChildren(Worker $worker, TripPassenger $passenger, array $report): void
    {
        if (isset($report['childIds']) && is_array($report['childIds'])) {
            $eligible = $this->children->eligibleChildrenOf((int) $worker->user_id)->pluck('id')->map(fn ($id) => (int) $id)->all();
            $ids = array_values(array_unique(array_map('intval', $report['childIds'])));

            if (array_diff($ids, $eligible)) {
                throw new JsonApiException(422, 'CHILD_NOT_ELIGIBLE', 'Hijo no válido',
                    'Solo pueden subir sus hijos activos con derecho a viajar.', ['pointer' => '/data/attributes/childIds']);
            }

            $passenger->child_ids = $ids ? implode(',', $ids) : null;
            $passenger->children_count = count($ids);
        } elseif (isset($report['childrenCount'])) {
            $passenger->children_count = max(0, min(20, (int) $report['childrenCount']));
            $passenger->child_ids = null;
        }
    }

    private function storeVehicleReport(Trip $trip, User $user, array $report, Carbon $reportedAt): void
    {
        $existing = TripVehicleReport::where('trip_id', $trip->id)->where('user_id', $user->id)->first();

        if ($existing && $reportedAt->lt($existing->reported_at)) {
            return;
        }

        $routeLength = count($trip->routeStopIds());
        TripVehicleReport::updateOrCreate(['trip_id' => $trip->id, 'user_id' => $user->id], [
            'vehicle_state' => $report['vehicleState'],
            'at_stop' => (bool) ($report['atStop'] ?? false),
            'next_stop_index' => max(0, min($routeLength, (int) ($report['nextStopIndex'] ?? $trip->next_stop_index))),
            'reported_at' => $reportedAt,
        ]);
    }

    private function isSensorState(Trip $trip, string $state): bool
    {
        return $state === ($trip->isOutbound() ? TripPassenger::TRAVELLING : TripPassenger::PICKED_UP);
    }

    /*
    |--------------------------------------------------------------------------
    | Reglas automáticas
    |--------------------------------------------------------------------------
    */

    /**
     * Aplica las reglas automáticas tras un informe.
     */
    public function evaluate(Trip $trip): Trip
    {
        if ($trip->status === Trip::PLANNED && $this->shouldStart($trip)) {
            $trip = $this->start($trip);
        }

        if ($trip->status === Trip::RUNNING) {
            $this->applyVehicleMajority($trip);
            $this->checkLongDetention($trip);
            $this->checkArrival($trip);
        }

        return $trip;
    }

    /**
     * Ida: al menos «Mínimo confirmaciones» trabajadores Viajando. Regreso: al
     * menos ese número de Recogidos en la última parada (la de salida). Si se
     * esperan menos, basta con todos los esperados.
     */
    private function shouldStart(Trip $trip): bool
    {
        $route = $trip->routeStopIds();

        if (! $route) {
            return false;
        }

        if ($trip->isOutbound()) {
            $count = TripPassenger::where('trip_id', $trip->id)->where('state', TripPassenger::TRAVELLING)->count();
            $expected = $this->expectedQuery($trip)->count();
        } else {
            $count = TripPassenger::where('trip_id', $trip->id)->where('state', TripPassenger::PICKED_UP)->where('stop_id', $route[0])->count();
            $expected = $this->expectedQuery($trip)->where('stop_id', $route[0])->count();
        }

        $required = max(1, min($this->settings->int('minimo_confirmaciones'), $expected));

        return $count >= $required;
    }

    /**
     * Sensores activos: van en el vehículo y su teléfono envió algo en los
     * últimos 3 cálculos (docs/11 §11.46).
     *
     * @return int[] ids de las personas
     */
    public function activeSensorIds(Trip $trip): array
    {
        $since = Carbon::now()->subSeconds(3 * $this->settings->seconds('frecuencia_calculo'));

        return array_map('intval', TripPassenger::where('trip_id', $trip->id)
            ->where('state', $trip->isOutbound() ? TripPassenger::TRAVELLING : TripPassenger::PICKED_UP)
            ->where('last_seen_at', '>=', $since)
            ->pluck('user_id')->all());
    }

    /**
     * Estado del vehículo, si está en la parada y avance de la próxima parada,
     * por mayoría de los sensores activos (docs/11 §11.43).
     */
    private function applyVehicleMajority(Trip $trip): void
    {
        $sensors = $this->activeSensorIds($trip);
        $reports = $sensors ? TripVehicleReport::where('trip_id', $trip->id)->whereIn('user_id', $sensors)->get() : collect();
        $n = $reports->count();

        if ($n === 0) {
            return;
        }

        $minimum = $this->settings->int('minimo_confirmaciones');
        // Con al menos «Mínimo confirmaciones» sensores, deben coincidir ese número;
        // con menos, basta la mayoría de los que haya. Siempre más de la mitad.
        $required = $n >= $minimum ? $minimum : intdiv($n, 2) + 1;
        $wins = fn (int $votes) => $votes >= $required && $votes * 2 > $n;
        $now = Carbon::now();
        $route = $trip->routeStopIds();
        $events = [];

        // Avance de la próxima parada: la más lejana que confirme la mayoría.
        $maxReported = (int) $reports->max('next_stop_index');

        for ($k = min($maxReported, count($route)); $k > $trip->next_stop_index; $k--) {
            if ($wins($reports->where('next_stop_index', '>=', $k)->count())) {
                for ($i = $trip->next_stop_index; $i < $k; $i++) {
                    TripStopPass::firstOrCreate(['trip_id' => $trip->id, 'route_index' => $i], ['stop_id' => $route[$i] ?? null, 'passed_at' => $now]);
                }
                $trip->next_stop_index = $k;
                $trip->vehicle_at_stop = false;
                break;
            }
        }

        // Detenido o en movimiento.
        $stopped = $reports->where('vehicle_state', Trip::STOPPED)->count();
        $moving = $n - $stopped;
        $state = $wins($stopped) ? Trip::STOPPED : ($wins($moving) ? Trip::MOVING : null);

        if ($state !== null && $state !== $trip->vehicle_state) {
            if ($state === Trip::MOVING && $trip->long_detention_notified_at !== null) {
                $events[] = [Notifier::VEHICLE_RESUMED, 'El vehículo sigue', 'El vehículo vuelve a moverse tras una detención larga.'];
            }

            $trip->vehicle_state = $state;
            $trip->vehicle_state_since = $now;
            $trip->long_detention_notified_at = null;

            if ($state === Trip::MOVING) {
                $trip->detention_cause_id = null;
                $trip->vehicle_at_stop = false;
            }
        }

        // Detenido en el radio de la próxima parada: «Recogiendo» (o «Dejando», en la ida).
        if ($trip->vehicle_state === Trip::STOPPED) {
            $atStop = $wins($reports->where('vehicle_state', Trip::STOPPED)->where('at_stop', true)->count());

            if ($atStop && ! $trip->vehicle_at_stop && isset($route[$trip->next_stop_index])) {
                $stop = Stop::find($route[$trip->next_stop_index]);
                $events[] = [Notifier::VEHICLE_AT_STOP, 'El vehículo llegó a una parada',
                    ($trip->isOutbound() ? 'Dejando' : 'Recogiendo').' en la parada '.($stop?->landmark ?? '').'.'];
            }

            $trip->vehicle_at_stop = $atStop;
        }

        $trip->save();

        foreach ($events as [$kind, $title, $body]) {
            $this->notifyAtStop($trip, $kind, $title, $body);
        }
    }

    /**
     * Detención de más de «Detención larga»: se avisa una vez a quienes están En la parada.
     */
    public function checkLongDetention(Trip $trip): void
    {
        if ($trip->status !== Trip::RUNNING || $trip->vehicle_state !== Trip::STOPPED || $trip->long_detention_notified_at !== null
            || ! $trip->vehicle_state_since || $trip->vehicle_state_since->gt(Carbon::now()->subSeconds($this->settings->seconds('detencion_larga')))) {
            return;
        }

        $trip->long_detention_notified_at = Carbon::now();
        $trip->save();
        $this->notifyAtStop($trip, Notifier::VEHICLE_LONG_STOP, 'Vehículo detenido',
            'El vehículo lleva detenido más de '.\App\Support\Units::formatSeconds($this->settings->seconds('detencion_larga')).'.');
    }

    /**
     * Ida: el vehículo pasó la última parada. Regreso: está detenido en la
     * primera parada (la última del recorrido).
     */
    private function checkArrival(Trip $trip): void
    {
        $count = count($trip->routeStopIds());
        $arrived = $trip->isOutbound()
            ? $trip->next_stop_index >= $count
            : $trip->next_stop_index >= $count - 1 && $trip->vehicle_state === Trip::STOPPED && $trip->vehicle_at_stop;

        if ($arrived && $trip->status === Trip::RUNNING) {
            $trip->arrived_at = Carbon::now();

            if (! $trip->isOutbound()) {
                TripStopPass::firstOrCreate(['trip_id' => $trip->id, 'route_index' => $count - 1], ['stop_id' => $trip->routeStopIds()[$count - 1], 'passed_at' => Carbon::now()]);
            }

            $this->finish($trip, 'llegada');
        }
    }

    /**
     * Revisión periódica (tarea programada, cada minuto; docs/11 §11.44):
     * - Planificado sin salir: se elimina pasado «Plazo eliminación» desde la
     *   salida (o desde su último estado, si es posterior);
     * - En ejecución: termina pasada «Duración máxima» desde que empezó, o
     *   pasada «Espera cierre» desde el último Dejado (ida) o Recogido (regreso);
     * - detenciones largas.
     *
     * @return array{deleted: int, finished: int}
     */
    public function review(): array
    {
        $now = Carbon::now();
        $deleted = 0;
        $finished = 0;
        $deleteAfter = $this->settings->seconds('plazo_eliminacion');

        foreach (Trip::where('status', Trip::PLANNED)->where('departs_at', '<=', $now->copy()->subSeconds($deleteAfter))->get() as $trip) {
            $from = $trip->status_changed_at && $trip->status_changed_at->gt($trip->departs_at) ? $trip->status_changed_at : $trip->departs_at;

            if ($from->copy()->addSeconds($deleteAfter)->lte($now)) {
                $trip->delete();
                $deleted++;
            }
        }

        $maxDuration = $this->settings->seconds('duracion_maxima');
        $closeAfter = $this->settings->seconds('espera_cierre');

        foreach (Trip::where('status', Trip::RUNNING)->get() as $trip) {
            if ($trip->status_changed_at->copy()->addSeconds($maxDuration)->lte($now)) {
                $this->finish($trip, 'duracion_maxima');
                $finished++;
                continue;
            }

            $last = TripPassenger::where('trip_id', $trip->id)
                ->where('state', $trip->isOutbound() ? TripPassenger::DROPPED : TripPassenger::PICKED_UP)->max('state_at');

            if ($last && $trip->arrived_at === null && Carbon::parse($last)->addSeconds($closeAfter)->lte($now)) {
                $this->finish($trip, 'espera_cierre');
                $finished++;
                continue;
            }

            $this->applyVehicleMajority($trip);
            $this->checkLongDetention($trip);
        }

        return ['deleted' => $deleted, 'finished' => $finished];
    }

    /*
    |--------------------------------------------------------------------------
    | Línea del recorrido
    |--------------------------------------------------------------------------
    */

    /**
     * Lo que muestra la línea del recorrido (docs/11 §11.43 y §11.46): paradas en
     * el orden del recorrido con sus cantidades y hora de paso, el vehículo, los
     * sensores, las personas en el vehículo y «Mi estado».
     */
    public function live(Trip $trip, ?User $viewer): array
    {
        $route = $trip->routeStopIds();
        $stops = Stop::whereIn('id', $route ?: [0])->get()->keyBy('id');
        $passes = TripStopPass::where('trip_id', $trip->id)->get()->keyBy('route_index');
        $passengers = TripPassenger::where('trip_id', $trip->id)->get();
        $expected = $this->expectedQuery($trip)->get(['id', 'user_id', 'stop_id']);
        $outbound = $trip->isOutbound();
        $inVehicleState = $outbound ? TripPassenger::TRAVELLING : TripPassenger::PICKED_UP;
        $inVehicle = $passengers->where('state', $inVehicleState);
        $statesByStop = [];

        foreach ($passengers as $passenger) {
            // Ida: De camino y En la parada son respecto a la primera parada.
            $stopId = $outbound && in_array($passenger->state, [TripPassenger::ON_THE_WAY, TripPassenger::AT_STOP], true)
                ? ($route[0] ?? null)
                : $passenger->stop_id;

            if ($stopId !== null && $passenger->state !== $inVehicleState && $passenger->state !== TripPassenger::NOT_GOING) {
                $statesByStop[$stopId][$passenger->state] = ($statesByStop[$stopId][$passenger->state] ?? 0) + 1;
            }
        }

        $line = [];

        foreach ($route as $index => $stopId) {
            $stop = $stops[$stopId] ?? null;
            $pass = $passes[$index] ?? null;
            $line[] = [
                'index' => $index,
                'stopId' => (string) $stopId,
                'landmark' => $stop?->landmark,
                'street' => $stop?->street,
                'passed' => $pass !== null,
                'passedAt' => $pass?->passed_at?->toIso8601String(),
                'expected' => $outbound ? ($index === 0 ? $expected->count() : $expected->where('stop_id', $stopId)->count()) : $expected->where('stop_id', $stopId)->count(),
                'counts' => (object) ($statesByStop[$stopId] ?? []),
                'mine' => $viewer !== null && $expected->where('user_id', $viewer->id)->where('stop_id', $stopId)->isNotEmpty(),
            ];
        }

        $mine = $viewer ? $passengers->firstWhere('user_id', $viewer->id) : null;
        $childIds = $inVehicle->flatMap(fn (TripPassenger $p) => $p->childIds())->unique()->count();
        $children = $inVehicle->sum(fn (TripPassenger $p) => $p->child_ids ? 0 : (int) $p->children_count) + $childIds;
        $cause = $trip->detention_cause_id ? DetentionCause::find($trip->detention_cause_id) : null;
        $capacity = VehicleType::find($trip->vehicle_type_id);

        return [
            'type' => 'trip-lives',
            'id' => (string) $trip->id,
            'attributes' => [
                'direction' => $trip->direction,
                'status' => $trip->status,
                'departsAt' => $trip->departs_at->toIso8601String(),
                'vehicle' => [
                    'state' => $trip->vehicle_state,
                    'since' => $trip->vehicle_state_since?->toIso8601String(),
                    'atStop' => (bool) $trip->vehicle_at_stop,
                    'nextStopIndex' => (int) $trip->next_stop_index,
                    'nextStopId' => isset($route[$trip->next_stop_index]) ? (string) $route[$trip->next_stop_index] : null,
                    'longDetention' => $trip->long_detention_notified_at !== null,
                    'detentionCause' => $cause ? ['id' => (string) $cause->id, 'name' => $cause->name] : null,
                ],
                'sensors' => count($this->activeSensorIds($trip)),
                'inVehicle' => [
                    'workers' => $inVehicle->count(),
                    'children' => $children,
                    'total' => $inVehicle->count() + $children,
                    'capacity' => $capacity?->capacity(),
                    'seats' => $capacity?->seats,
                ],
                'expectedPassengers' => $expected->count(),
                'notGoing' => $passengers->where('state', TripPassenger::NOT_GOING)->count(),
                'stops' => $line,
                'myState' => $mine ? [
                    'state' => $mine->state,
                    'stateAt' => $mine->state_at?->toIso8601String(),
                    'stopId' => $mine->stop_id ? (string) $mine->stop_id : null,
                    'childrenCount' => (int) $mine->children_count,
                    'sensor' => $this->isSensorState($trip, $mine->state),
                ] : null,
                'serverTime' => Carbon::now()->toIso8601String(),
            ],
            'relationships' => [
                'trip' => ['data' => ['type' => 'trips', 'id' => (string) $trip->id]],
            ],
        ];
    }

    /*
    |--------------------------------------------------------------------------
    | Ayudas
    |--------------------------------------------------------------------------
    */

    public static function statusName(string $status): string
    {
        return ['planificado' => 'Planificado', 'en_ejecucion' => 'En ejecución', 'terminado' => 'Terminado', 'cancelado' => 'Cancelado'][$status] ?? $status;
    }

    private function requireManager(User $actor, Trip $trip): void
    {
        $this->access->requireItineraryManager($actor, $trip->itinerary_id, 'Solo el Administrador o el Jefe de ese itinerario gestionan sus viajes.');
    }

    private function ensureVehicleType(int $id): void
    {
        $type = VehicleType::find($id);

        if (! $type || ! $type->active) {
            throw new JsonApiException(422, 'VEHICLE_TYPE_INVALID', 'Tipo de vehículo no válido', 'Elija un tipo de vehículo activo.', ['pointer' => '/data/relationships/vehicleType']);
        }
    }

    private function departure(string $date, string $time): Carbon
    {
        if (! preg_match('/^\d{4}-\d{2}-\d{2}$/', $date) || ! preg_match('/^([01]\d|2[0-3]):[0-5]\d$/', $time)) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Fecha u hora no válida', 'La fecha va como AAAA-MM-DD y la hora como HH:MM (24 h).', ['pointer' => '/data/attributes/date']);
        }

        $departsAt = Carbon::createFromFormat('Y-m-d H:i', $date.' '.$time, config('app.timezone'));

        if ($departsAt->copy()->startOfDay()->lt(Carbon::today())) {
            throw new JsonApiException(422, 'TRIP_IN_PAST', 'Fecha pasada', 'No se planifican viajes en días pasados.', ['pointer' => '/data/attributes/date']);
        }

        return $departsAt->second(0);
    }

    private function describe(Trip $trip): string
    {
        $itinerary = Itinerary::find($trip->itinerary_id);

        return 'viaje de '.$trip->direction.' de '.($itinerary?->name ?? '').' del '.SpanishDate::date($trip->departs_at).' a las '.$trip->departure_time;
    }

    private function data(Trip $trip): array
    {
        return ['tripId' => (string) $trip->id, 'status' => $trip->status, 'direction' => $trip->direction];
    }

    private function notifyAtStop(Trip $trip, string $kind, string $title, string $body): void
    {
        $ids = TripPassenger::where('trip_id', $trip->id)->where('state', TripPassenger::AT_STOP)->pluck('user_id')->all();
        $this->notifier->send($ids, $kind, $title, $body, $this->data($trip));
    }
}
