<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
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
use App\Models\WorkerItinerary;
use App\Support\SpanishDate;
use Carbon\Carbon;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;

/**
 * Viajes y su tiempo real (docs/11 §11.42 a §11.47).
 *
 * - Un viaje es de ida o de regreso. Desde la 4.4.0 (docs/11 §11.65) en los dos
 *   sentidos se sube y se baja en cualquier parada: el teléfono detecta la
 *   parada por cercanía y todos los estados valen en los dos sentidos.
 * - Estados: planificado → en_ejecucion → terminado, o planificado → cancelado.
 *   En ejecución ya no se edita.
 * - El estado de cada trabajador lo calcula su teléfono y envía los cambios
 *   y sus observaciones del vehículo con la hora de captura, en cola si no hay
 *   conexión (report()). El servidor los ordena por esa hora. Los teléfonos
 *   de quienes van en el vehículo (Viajando) son sensores: informan si el
 *   vehículo está detenido o en movimiento y cuál es su próxima parada; el
 *   servidor decide por mayoría (ajuste «Mínimo confirmaciones») y fija la
 *   hora de paso por cada parada con las horas de captura.
 * - El estado del viaje cambia a mano (Administrador o Jefe) o solo: empieza
 *   cuando suficientes trabajadores están Viajando; termina al pasar la última
 *   parada (ida) o al detenerse en la última del recorrido (regreso); y las
 *   revisiones de review() (plazos).
 */
class Trips
{
    /** Lo que puede cambiar en «Viaje cambiado» (docs/11 §11.63), en el orden en que se nombra. */
    public const CHANGE_DATE = 'fecha';
    public const CHANGE_TIME = 'hora';
    public const CHANGE_VEHICLE = 'tipo_vehiculo';
    public const CHANGE_OBSERVATION = 'observacion';
    public const CHANGE_DEPARTURE = 'parada_salida';

    /** Estado de la notificación de un viaje eliminado (el viaje ya no existe). */
    public const STATUS_DELETED = 'eliminado';

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
     * el trabajador, los de sus itinerarios (la parada habitual es opcional
     * desde la 4.4.0, docs/11 §11.65).
     */
    public function visibleQuery(User $user): Builder
    {
        $query = Trip::query();

        if ($this->access->isAdmin($user)) {
            return $query;
        }

        // Todos sus itinerarios (de todas sus Entidades) en los que está activo (o es Jefe).
        $activeWorkers = $this->access->workersOf($user)->where('active', true)->pluck('id')->map(fn ($id) => (int) $id)->all();
        $itineraryIds = $this->access->placementsOf($user)
            ->filter(fn (WorkerItinerary $p) => in_array((int) $p->worker_id, $activeWorkers, true) || $p->is_chief)
            ->pluck('itinerary_id')->map(fn ($id) => (int) $id)->values()->all();

        return $query->whereIn('itinerary_id', $itineraryIds ?: [0]);
    }

    public function canManage(User $user, Trip $trip): bool
    {
        return $this->access->canManageItinerary($user, $trip->itinerary_id);
    }

    /**
     * Pasajeros esperados: los activos del itinerario sin una ausencia ese día
     * en ese itinerario (docs/11 §11.33 y §11.61). Cada persona cuenta en cada
     * uno de sus itinerarios. Su parada habitual (opcional) solo sirve para
     * planificar cuántos esperan normalmente en cada parada (docs/11 §11.65).
     */
    public function expectedQuery(Trip $trip): Builder
    {
        $date = $trip->date->toDateString();
        $absent = DB::table('absence_itinerary')->join('absences', 'absences.id', '=', 'absence_itinerary.absence_id')
            ->where('absence_itinerary.itinerary_id', $trip->itinerary_id)
            ->where('absences.starts_on', '<=', $date)
            ->where(fn ($q) => $q->whereNull('absences.ends_on')->orWhere('absences.ends_on', '>=', $date))
            ->whereNotNull('absences.user_id')
            ->select('absences.user_id');

        return WorkerItinerary::where('itinerary_id', $trip->itinerary_id)
            ->whereIn('worker_id', Worker::where('active', true)->select('id'))
            ->whereNotIn('user_id', $absent);
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
        $this->ensureUnique($itinerary->id, $direction, $departsAt->toDateString());

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
            ucfirst($this->describe($trip)).'.', $this->data($trip));

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
        $old = ['date' => $trip->date->toDateString(), 'time' => $trip->departure_time, 'vehicle' => (int) $trip->vehicle_type_id, 'observation' => $trip->observation];

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

        $this->ensureUnique((int) $trip->itinerary_id, $trip->direction, $trip->date->toDateString(), (int) $trip->id);

        try {
            $trip->save();
        } catch (QueryException $e) {
            throw JsonApiException::conflict('TRIP_EXISTS', 'Ya hay un viaje de '.$trip->direction.' de ese itinerario ese día.', '/data/attributes/date');
        }

        // Qué cambió (docs/11 §11.63): la app lo muestra en «Cambió la fecha, hora y …».
        $changed = array_keys(array_filter([
            self::CHANGE_DATE => $old['date'] !== $trip->date->toDateString(),
            self::CHANGE_TIME => $old['time'] !== $trip->departure_time,
            self::CHANGE_VEHICLE => $old['vehicle'] !== (int) $trip->vehicle_type_id,
            self::CHANGE_OBSERVATION => (string) $old['observation'] !== (string) $trip->observation,
        ]));

        if ($changed) {
            $this->notifier->send($this->notifier->tripAudience($trip), Notifier::TRIP_CHANGED, 'Viaje modificado',
                'Antes: '.$before.'. Ahora: '.$this->describe($trip).'.', $this->data($trip, $changed));
        }

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

    /**
     * @param Carbon|null $at hora real de salida (p. ej. la hora de captura del
     *                       primer Viajando); por omisión, ahora.
     */
    public function start(Trip $trip, ?Carbon $at = null): Trip
    {
        $now = $at ?? Carbon::now();
        $route = $trip->routeStopIds();

        DB::transaction(function () use ($trip, $now, $route) {
            $trip->forceFill([
                'status' => Trip::RUNNING,
                'status_changed_at' => $now,
                'route' => implode(',', $route),
                // La parada de salida queda pasada al empezar (docs/11 §11.43).
                'next_stop_index' => max((int) $trip->next_stop_index, min(1, max(0, count($route) - 1))),
                // Sin datos del vehículo hasta que informen los sensores (docs/11 §11.61).
                'vehicle_state' => null,
                'vehicle_state_since' => null,
                'vehicle_at_stop' => false,
            ])->save();

            if ($route) {
                $this->recordPass($trip, 0, $now);
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

        // Al llegar a la parada final se bajan todos: quien sigue Viajando queda Dejado allí.
        if ($reason === 'llegada') {
            $route = $trip->routeStopIds();
            $at = $trip->arrived_at ?? Carbon::now();

            foreach (TripPassenger::where('trip_id', $trip->id)->where('state', TripPassenger::TRAVELLING)->get() as $passenger) {
                $passenger->forceFill([
                    'state' => TripPassenger::DROPPED, 'state_at' => $at, 'stop_id' => $route ? end($route) : $passenger->stop_id, 'set_by_server' => true,
                ])->save();
            }
        }

        return $trip;
    }

    /**
     * Elimina el viaje (a mano o por «Plazo eliminación») y lo avisa: la app
     * pone «Viaje eliminado» en la notificación de ese viaje (docs/11 §11.63).
     */
    public function delete(Trip $trip): void
    {
        $audience = $this->notifier->tripAudience($trip);
        $data = ['status' => self::STATUS_DELETED] + $this->data($trip);
        $description = $this->describe($trip);
        $trip->delete();
        $this->notifier->send($audience, Notifier::TRIP_DELETED, 'Viaje eliminado', 'Se eliminó el '.$description.'.', $data);
    }

    /**
     * Cambios del recorrido de un itinerario (añadir, quitar u ordenar sus
     * paradas): si cambia la parada de salida de sus viajes planificados, se
     * avisa como «Viaje cambiado» con «Cambió la parada de salida».
     *
     * @param int[] $itineraryIds
     */
    public function watchDeparture(array $itineraryIds, callable $change): mixed
    {
        $planned = fn () => Trip::whereIn('itinerary_id', $itineraryIds ?: [0])->where('status', Trip::PLANNED)->whereNull('route')->get();
        $before = $planned()->mapWithKeys(fn (Trip $t) => [$t->id => $t->routeStopIds()[0] ?? null])->all();
        $result = $change();

        foreach ($planned() as $trip) {
            $departure = $trip->routeStopIds()[0] ?? null;

            if (array_key_exists($trip->id, $before) && $departure !== null && $before[$trip->id] !== $departure) {
                $this->notifier->send($this->notifier->tripAudience($trip), Notifier::TRIP_CHANGED, 'Viaje modificado',
                    'Cambió la parada de salida del '.$this->describe($trip).'.', $this->data($trip, [self::CHANGE_DEPARTURE]));
            }
        }

        return $result;
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
     * Informe de un teléfono durante el viaje (docs/11 §11.65): los cambios
     * de estado del trabajador y las observaciones del vehículo (si es sensor),
     * cada uno con su hora de captura (capturedAt), que el teléfono guarda en
     * cola mientras no hay conexión. Se aplican en el orden de esa hora. Es
     * idempotente: se puede reenviar hasta recibir el acuse.
     *
     * Formato 4.4.0: events = [{kind: worker, state, stopId?, childIds?,
     * childrenCount?, capturedAt} | {kind: vehicle, vehicleState, atStop,
     * nextStopIndex, capturedAt}], gps. Formato 4.3.0 (un solo cambio):
     * workerState, stopId, childIds, childrenCount, vehicleState, atStop,
     * nextStopIndex, reportedAt, gps.
     *
     * @return array{applied: bool, reason: ?string, sensor: bool, accepted: int}
     */
    public function report(User $user, Trip $trip, array $report): array
    {
        $worker = WorkerItinerary::where('user_id', $user->id)->where('itinerary_id', $trip->itinerary_id)->first();

        if (! $worker) {
            throw Access::forbidden('Solo informan su estado los trabajadores del itinerario del viaje.');
        }

        $events = self::events($report);

        if (! $trip->isOpen()) {
            return ['applied' => false, 'reason' => 'VIAJE_CERRADO', 'sensor' => false, 'accepted' => count($events)];
        }

        $now = Carbon::now();
        $result = ['applied' => true, 'reason' => null, 'sensor' => false, 'accepted' => count($events)];

        $result = DB::transaction(function () use ($user, $trip, $worker, $report, $events, $now, $result) {
            $passenger = TripPassenger::where('trip_id', $trip->id)->where('user_id', $user->id)->lockForUpdate()->first();

            foreach ($events as $event) {
                $at = $this->capturedAt($event['capturedAt'] ?? null, $now);

                if ($event['kind'] === 'worker') {
                    [$applied, $reason] = $this->applyWorkerState($trip, $worker, $passenger, $event, $at);
                    $result['applied'] = $applied;
                    $result['reason'] = $reason;
                    $passenger = TripPassenger::where('trip_id', $trip->id)->where('user_id', $user->id)->first();
                } elseif ($passenger && $this->isSensorState($trip, $passenger->state)) {
                    $this->storeVehicleReport($trip, $user, $event, $at);
                }
            }

            if (! $passenger) {
                $passenger = TripPassenger::create([
                    'trip_id' => $trip->id, 'user_id' => $user->id, 'stop_id' => $worker->stop_id,
                    // Sin estado informado aún: cualquier cambio en cola vale después.
                    'state' => TripPassenger::ON_THE_WAY, 'state_at' => $now, 'reported_at' => $trip->departs_at->copy()->subDay(),
                ]);
            }

            $passenger->last_seen_at = $now;

            if (array_key_exists('gps', $report) && $report['gps'] !== null) {
                $passenger->gps_ok = (bool) $report['gps'];
            }

            $passenger->save();
            $result['sensor'] = $this->isSensorState($trip, $passenger->state);

            return $result;
        });

        $this->evaluate($trip->fresh());

        return $result;
    }

    /**
     * Los cambios de un informe, ordenados por hora de captura (los de la
     * 4.3.0 llegan sueltos, con reportedAt).
     *
     * @return array<int, array>
     */
    public static function events(array $report): array
    {
        $events = [];

        foreach ((array) ($report['events'] ?? []) as $event) {
            if (is_array($event) && in_array($event['kind'] ?? null, ['worker', 'vehicle'], true)) {
                $events[] = $event;
            }
        }

        if (! $events) {
            $at = $report['reportedAt'] ?? null;

            if (isset($report['workerState'])) {
                $events[] = ['kind' => 'worker', 'state' => $report['workerState'], 'capturedAt' => $at]
                    + array_intersect_key($report, array_flip(['stopId', 'childIds', 'childrenCount']));
            }

            if (isset($report['vehicleState'])) {
                $events[] = ['kind' => 'vehicle', 'capturedAt' => $at]
                    + array_intersect_key($report, array_flip(['vehicleState', 'atStop', 'nextStopIndex']));
            }
        }

        // Orden estable por hora de captura (a igual hora, primero el estado del trabajador).
        $keyed = [];

        foreach ($events as $i => $event) {
            $time = isset($event['capturedAt']) ? strtotime((string) $event['capturedAt']) : false;
            $keyed[] = [$time === false ? PHP_INT_MAX : $time, $event['kind'] === 'worker' ? 0 : 1, $i, $event];
        }

        usort($keyed, fn ($a, $b) => [$a[0], $a[1], $a[2]] <=> [$b[0], $b[1], $b[2]]);

        return array_map(fn ($k) => $k[3], $keyed);
    }

    /** Hora de captura en la zona del servidor; sin ella (o en el futuro), ahora. */
    private function capturedAt($value, Carbon $now): Carbon
    {
        if ($value === null || $value === '') {
            return $now->copy();
        }

        try {
            $at = Carbon::parse((string) $value)->setTimezone(config('app.timezone'));
        } catch (\Throwable $e) {
            return $now->copy();
        }

        return $at->gt($now) ? $now->copy() : $at;
    }

    /**
     * @return array{0: bool, 1: ?string}
     */
    private function applyWorkerState(Trip $trip, WorkerItinerary $worker, ?TripPassenger $passenger, array $event, Carbon $at): array
    {
        // Nombres viejos de los teléfonos 4.2.0 / 4.3.0 (recogido, botado, dormido).
        $state = TripPassenger::normalize((string) ($event['state'] ?? ''));

        if (! in_array($state, TripPassenger::STATES, true)) {
            throw new JsonApiException(422, 'WORKER_STATE_INVALID', 'Estado no válido',
                'Los estados son: '.implode(', ', TripPassenger::STATES).'.', ['pointer' => '/data/attributes/events']);
        }

        // Parada detectada por cercanía (docs/11 §11.65): debe ser del recorrido.
        $stopId = null;

        if (isset($event['stopId']) && $event['stopId'] !== null && $event['stopId'] !== '') {
            if (! in_array((int) $event['stopId'], $trip->routeStopIds(), true)) {
                throw new JsonApiException(422, 'STOP_NOT_IN_ITINERARY', 'Parada de otro itinerario', 'La parada no es del recorrido del viaje.', ['pointer' => '/data/attributes/stopId']);
            }
            $stopId = (int) $event['stopId'];
        }

        if ($passenger) {
            // Reenvío de un informe ya aplicado o más viejo que el último: acuse sin cambios.
            if ($passenger->reported_at && $at->lt($passenger->reported_at) && ! $passenger->set_by_server) {
                return [false, 'INFORME_ANTERIOR'];
            }

            if ($passenger->state === $state && ($stopId === null || $stopId === (int) $passenger->stop_id)) {
                $this->applyChildren($worker, $passenger, $event);
                $passenger->reported_at = $at;
                $passenger->set_by_server = false;
                $passenger->save();

                return [true, null];
            }

            // Los finales no cambian; salvo lo que puso el servidor por un teléfono
            // sin enviar (el teléfono sabe más) y No recogido que en realidad subió.
            if (TripPassenger::isFinal($passenger->state) && $passenger->state !== $state) {
                $correction = $passenger->set_by_server
                    || ($passenger->state === TripPassenger::LEFT_BEHIND && $state === TripPassenger::TRAVELLING);

                if (! $correction) {
                    return [false, 'ESTADO_FINAL'];
                }
            }

            // Viajando solo pasa a Dejado.
            if ($passenger->state === TripPassenger::TRAVELLING && ! in_array($state, [TripPassenger::TRAVELLING, TripPassenger::DROPPED], true)) {
                return [false, 'TRANSICION_NO_PERMITIDA'];
            }
        }

        $passenger = $passenger ?: new TripPassenger(['trip_id' => $trip->id, 'user_id' => $worker->user_id]);
        // Sin parada detectada (teléfonos viejos), la que tenía o su parada habitual.
        $stopId = $stopId ?? ($passenger->stop_id ? (int) $passenger->stop_id : ($worker->stop_id ? (int) $worker->stop_id : null));
        $passenger->fill(['state' => $state, 'state_at' => $at, 'reported_at' => $at, 'stop_id' => $stopId, 'set_by_server' => false]);
        $this->applyChildren($worker, $passenger, $event);
        $passenger->save();

        return [true, null];
    }

    /**
     * Hijos que suben con él: el trabajador elige cuáles (childIds); si no,
     * solo cuántos (childrenCount). Cada niño cuenta una sola vez por viaje.
     */
    private function applyChildren(WorkerItinerary $worker, TripPassenger $passenger, array $report): void
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

    /**
     * Observación de un sensor: la última de cada teléfono decide el estado del
     * vehículo; cada próxima parada vista queda como voto con su hora de
     * captura, para fijar la hora de paso por cada parada (docs/11 §11.65).
     */
    private function storeVehicleReport(Trip $trip, User $user, array $event, Carbon $at): void
    {
        $routeLength = count($trip->routeStopIds());
        $next = max(0, min($routeLength, (int) ($event['nextStopIndex'] ?? $trip->next_stop_index)));

        for ($k = 1; $k <= $next; $k++) {
            DB::table('trip_stop_votes')->insertOrIgnore(['trip_id' => $trip->id, 'user_id' => $user->id, 'next_stop_index' => $k, 'voted_at' => $at]);
        }

        $existing = TripVehicleReport::where('trip_id', $trip->id)->where('user_id', $user->id)->first();

        if ($existing && $at->lt($existing->reported_at)) {
            return;
        }

        TripVehicleReport::updateOrCreate(['trip_id' => $trip->id, 'user_id' => $user->id], [
            'vehicle_state' => in_array($event['vehicleState'] ?? null, [Trip::STOPPED, Trip::MOVING], true) ? $event['vehicleState'] : Trip::MOVING,
            'at_stop' => (bool) ($event['atStop'] ?? false),
            'next_stop_index' => $next,
            'reported_at' => $at,
        ]);
    }

    private function isSensorState(Trip $trip, string $state): bool
    {
        return $state === TripPassenger::TRAVELLING;
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
            // Salió cuando subió el primero (hora de captura de su Viajando).
            $first = TripPassenger::where('trip_id', $trip->id)->where('state', TripPassenger::TRAVELLING)->min('state_at');
            $trip = $this->start($trip, $first ? Carbon::parse($first) : null);
        }

        if ($trip->status === Trip::RUNNING) {
            $this->applyVehicleMajority($trip);
            $this->checkLongDetention($trip);
            $this->checkArrival($trip);
        }

        return $trip;
    }

    /**
     * Empieza solo con al menos «Mínimo confirmaciones» trabajadores Viajando,
     * en cualquier parada y en los dos sentidos (docs/11 §11.65). Si se
     * esperan menos, basta con todos los esperados.
     */
    private function shouldStart(Trip $trip): bool
    {
        if (! $trip->routeStopIds()) {
            return false;
        }

        $count = TripPassenger::where('trip_id', $trip->id)->where('state', TripPassenger::TRAVELLING)->count();
        $expected = $this->expectedQuery($trip)->count();
        $required = max(1, min($this->settings->int('minimo_confirmaciones'), $expected));

        return $count >= $required;
    }

    /** Un teléfono que no envía nada en 3 veces la «Frecuencia corta» deja de contar. */
    private function recentSince(): Carbon
    {
        return Carbon::now()->subSeconds(3 * max(1, $this->settings->seconds('frecuencia_corta')));
    }

    /**
     * Sensores activos: van en el vehículo, su teléfono envió algo en los
     * últimos 3 cálculos (docs/11 §11.46) y tenía posición del GPS.
     *
     * @return int[] ids de las personas
     */
    public function activeSensorIds(Trip $trip): array
    {
        return array_map('intval', TripPassenger::where('trip_id', $trip->id)
            ->where('state', TripPassenger::TRAVELLING)
            ->where('last_seen_at', '>=', $this->recentSince())
            // Sin posición del GPS no puede informar del vehículo.
            ->where(fn ($q) => $q->whereNull('gps_ok')->orWhere('gps_ok', true))
            ->pluck('user_id')->all());
    }

    /**
     * Estado del vehículo, si está en la parada y avance de la próxima parada,
     * por mayoría de los sensores activos (docs/11 §11.43). La hora de paso por
     * cada parada sale de las horas de captura de los sensores que la confirman.
     */
    private function applyVehicleMajority(Trip $trip): void
    {
        $sensors = $this->activeSensorIds($trip);
        $reports = $sensors ? TripVehicleReport::where('trip_id', $trip->id)->whereIn('user_id', $sensors)->get() : collect();
        // Cuentan todos los sensores activos, aunque alguno aún no haya informado del vehículo.
        $n = count($sensors);

        if ($reports->isEmpty()) {
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
                    $this->recordPass($trip, $i, $this->passTime($trip, $i, $sensors, $required) ?? $now);
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

            // Desde cuándo: la hora de captura más reciente de quienes lo confirman.
            $since = $reports->where('vehicle_state', $state)->max('reported_at');
            $trip->vehicle_state = $state;
            $trip->vehicle_state_since = $since ? Carbon::parse($since) : $now;
            $trip->long_detention_notified_at = null;

            if ($state === Trip::MOVING) {
                $trip->detention_cause_id = null;
                $trip->vehicle_at_stop = false;
            }
        }

        // Detenido en el radio de la próxima parada: «Recogiendo» o «Dejando».
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
     * Hora de paso por la parada $index: cuando el $required-ésimo sensor
     * (por hora de captura) vio la próxima parada más allá de ella.
     *
     * @param int[] $sensors
     */
    private function passTime(Trip $trip, int $index, array $sensors, int $required): ?Carbon
    {
        $times = DB::table('trip_stop_votes')->where('trip_id', $trip->id)->whereIn('user_id', $sensors ?: [0])
            ->where('next_stop_index', '>=', $index + 1)->groupBy('user_id')->selectRaw('min(voted_at) as t')->pluck('t')
            ->map(fn ($t) => Carbon::parse($t))->sort()->values();

        return $times->isEmpty() ? null : $times[min($times->count(), max(1, $required)) - 1];
    }

    /**
     * Paso por una parada (sensores o a mano). Si el teléfono de quien
     * esperaba en ella (o iba de camino a ella) no envía, el servidor lo pone
     * No recogido o Retrasado (docs/11 §11.65); su teléfono, al volver a
     * enviar, manda sobre esto.
     */
    private function recordPass(Trip $trip, int $index, Carbon $at, ?int $markedBy = null): TripStopPass
    {
        $route = $trip->routeStopIds();
        $pass = TripStopPass::firstOrCreate(['trip_id' => $trip->id, 'route_index' => $index], ['stop_id' => $route[$index] ?? null, 'passed_at' => $at]);

        if ($markedBy !== null && $pass->wasRecentlyCreated) {
            $pass->marked_by = $markedBy;
            $pass->save();
        }

        if ($pass->wasRecentlyCreated && isset($route[$index])) {
            $silent = fn ($q) => $q->whereNull('last_seen_at')->orWhere('last_seen_at', '<', $this->recentSince());

            foreach ([TripPassenger::AT_STOP => TripPassenger::LEFT_BEHIND, TripPassenger::ON_THE_WAY => TripPassenger::LATE] as $from => $to) {
                foreach (TripPassenger::where('trip_id', $trip->id)->where('stop_id', $route[$index])->where('state', $from)->where($silent)->get() as $passenger) {
                    $passenger->forceFill(['state' => $to, 'state_at' => $pass->passed_at, 'set_by_server' => true])->save();
                }
            }
        }

        return $pass;
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
                $this->recordPass($trip, $count - 1, Carbon::now());
            }

            $this->finish($trip, 'llegada');
        }
    }

    /**
     * Revisión periódica (tarea programada, cada minuto; docs/11 §11.44):
     * - Planificado sin salir: se elimina pasado «Plazo eliminación» desde la
     *   salida (o desde su último estado, si es posterior);
     * - En ejecución: termina pasada «Duración máxima» desde que empezó, o
     *   pasada «Espera cierre» desde el último Dejado (en los dos sentidos);
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
                $this->delete($trip);
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

            $last = TripPassenger::where('trip_id', $trip->id)->where('state', TripPassenger::DROPPED)->max('state_at');

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

    /**
     * «Pasó por la parada X», a mano (docs/11 §11.61): el Jefe del itinerario
     * o el Administrador. Cuenta igual que la confirmación de los sensores:
     * hora de paso (también de las saltadas), avance de la próxima parada y,
     * en los teléfonos, Retrasado / No recogido. Marcar la salida de un viaje
     * Planificado lo pone En ejecución; pasar la parada final lo termina.
     */
    public function markStopPassed(User $actor, Trip $trip, int $index): Trip
    {
        $this->requireManager($actor, $trip);

        if (! $trip->isOpen()) {
            throw JsonApiException::conflict('TRIP_CLOSED', 'El viaje ya terminó o se canceló.');
        }

        $route = $trip->routeStopIds();

        if ($index < 0 || $index >= count($route)) {
            throw new JsonApiException(422, 'STOP_INDEX_INVALID', 'Parada no válida', 'La parada no es del recorrido del viaje.', ['pointer' => '/data/attributes/routeIndex']);
        }

        if ($trip->status === Trip::PLANNED) {
            $trip = $this->start($trip);
            $route = $trip->routeStopIds();
        }

        $now = Carbon::now();

        DB::transaction(function () use ($trip, $index, $now, $actor) {
            for ($i = 0; $i <= $index; $i++) {
                $this->recordPass($trip, $i, $now, $i === $index ? (int) $actor->id : null);
            }

            if ($index + 1 > (int) $trip->next_stop_index) {
                $trip->next_stop_index = $index + 1;
                $trip->vehicle_at_stop = false;
                $trip->save();
            }
        });

        // Ida: pasó la última parada. Regreso: llegó a la final (la primera del itinerario).
        if ($trip->status === Trip::RUNNING && $index >= count($route) - 1) {
            $trip->arrived_at = $now;
            $this->finish($trip, 'llegada');
        }

        return $trip;
    }

    /**
     * Por qué cada trabajador del viaje es o no sensor (docs/11 §11.61):
     * sensor, no_en_vehiculo (no está Viajando), sin_gps (su
     * último envío fue sin posición) o sin_enviar (no envía desde
     * last_seen_at; quizá la app esté cerrada o sin conexión).
     *
     * @return array{sensor: bool, reason: string}
     */
    public function sensorStatus(Trip $trip, ?TripPassenger $passenger): array
    {
        if (! $passenger) {
            return ['sensor' => false, 'reason' => 'sin_enviar'];
        }

        $recent = $passenger->last_seen_at !== null && $passenger->last_seen_at->gte($this->recentSince());

        if (! $this->isSensorState($trip, $passenger->state)) {
            return ['sensor' => false, 'reason' => 'no_en_vehiculo'];
        }

        if (! $recent) {
            return ['sensor' => false, 'reason' => 'sin_enviar'];
        }

        if ($passenger->gps_ok === false) {
            return ['sensor' => false, 'reason' => 'sin_gps'];
        }

        return ['sensor' => true, 'reason' => 'sensor'];
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
        $inVehicleState = TripPassenger::TRAVELLING;
        $inVehicle = $passengers->where('state', $inVehicleState);
        $statesByStop = [];

        // Cada parada: cuántos De camino, En la parada, Retrasado, No recogido y
        // Dejado hay en ella (la parada detectada; docs/11 §11.65), en los dos sentidos.
        foreach ($passengers as $passenger) {
            if ($passenger->stop_id !== null && in_array($passenger->state, TripPassenger::STOP_STATES, true)) {
                $statesByStop[$passenger->stop_id][$passenger->state] = ($statesByStop[$passenger->stop_id][$passenger->state] ?? 0) + 1;
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
                'latitude' => $stop?->latitude !== null ? (float) $stop->latitude : null,
                'longitude' => $stop?->longitude !== null ? (float) $stop->longitude : null,
                'passed' => $pass !== null,
                'passedAt' => $pass?->passed_at?->toIso8601String(),
                'passedManually' => $pass !== null && $pass->marked_by !== null,
                // Los que la tienen como parada habitual (para planificar).
                'expected' => $expected->where('stop_id', $stopId)->count(),
                'counts' => (object) ($statesByStop[$stopId] ?? []),
                'mine' => $viewer !== null && $expected->where('user_id', $viewer->id)->where('stop_id', $stopId)->isNotEmpty(),
            ];
        }

        $mine = $viewer ? $passengers->firstWhere('user_id', $viewer->id) : null;
        $placement = $viewer ? WorkerItinerary::where('user_id', $viewer->id)->where('itinerary_id', $trip->itinerary_id)->first() : null;
        $myStop = $mine && $mine->stop_id ? ($stops[$mine->stop_id] ?? Stop::find($mine->stop_id)) : null;
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
                // Para la notificación del vehículo que compone la app (docs/11 §11.63).
                'itineraryName' => Itinerary::find($trip->itinerary_id)?->name,
                'vehicleTypeName' => $capacity?->name,
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
                    // La parada detectada (en Dejado, donde se bajó).
                    'stopId' => $mine->stop_id ? (string) $mine->stop_id : null,
                    'stopName' => $myStop?->landmark,
                    'childrenCount' => (int) $mine->children_count,
                    'sensor' => $this->isSensorState($trip, $mine->state),
                    'setByServer' => (bool) $mine->set_by_server,
                ] : null,
                // Su parada habitual (opcional) y si viaja en este itinerario.
                'myStopId' => $placement && $placement->stop_id ? (string) $placement->stop_id : null,
                'travels' => $placement !== null,
                'canManage' => $viewer !== null && $this->canManage($viewer, $trip),
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

    /**
     * Un viaje por itinerario, sentido y fecha, sin contar los cancelados (los
     * eliminados ya no existen; docs/11 §11.65). Ya no es un índice único.
     */
    private function ensureUnique(int $itineraryId, string $direction, string $date, ?int $except = null): void
    {
        $exists = Trip::where('itinerary_id', $itineraryId)->where('direction', $direction)->whereDate('date', $date)
            ->where('status', '<>', Trip::CANCELLED)
            ->when($except !== null, fn ($q) => $q->where('id', '<>', $except))->exists();

        if ($exists) {
            throw JsonApiException::conflict('TRIP_EXISTS', 'Ya hay un viaje de '.$direction.' de ese itinerario ese día.', '/data/attributes/date');
        }
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

    /**
     * Datos de las notificaciones del viaje: con ellos la app compone la suya
     * (docs/11 §11.63): itinerario, sentido, salida, parada de salida, tipo de
     * vehículo y, en «Viaje cambiado», qué cambió.
     *
     * @param string[] $changes
     */
    private function data(Trip $trip, array $changes = []): array
    {
        $departure = $trip->routeStopIds()[0] ?? null;

        return [
            'tripId' => (string) $trip->id,
            'status' => $trip->status,
            'direction' => $trip->direction,
            'itineraryName' => Itinerary::find($trip->itinerary_id)?->name,
            'departsAt' => $trip->departs_at?->toIso8601String(),
            'departureStop' => $departure ? Stop::find($departure)?->landmark : null,
            'vehicleType' => VehicleType::find($trip->vehicle_type_id)?->name,
            'changes' => array_values($changes),
        ];
    }

    private function notifyAtStop(Trip $trip, string $kind, string $title, string $body): void
    {
        $ids = TripPassenger::where('trip_id', $trip->id)->where('state', TripPassenger::AT_STOP)->pluck('user_id')->all();
        $this->notifier->send($ids, $kind, $title, $body, $this->data($trip));
    }
}
