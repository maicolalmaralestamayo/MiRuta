<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\AbsenceApplication;
use App\Models\Application;
use App\Models\Child;
use App\Models\ChildApplication;
use App\Models\Driver;
use App\Models\ItineraryApplication;
use App\Models\ItineraryChief;
use App\Models\ItineraryStop;
use App\Models\Notice;
use App\Models\TransportChief;
use App\Models\Trip;
use App\Models\Vehicle;
use App\Models\User;
use App\Models\Worker;
use App\Support\Tenancy;
use Carbon\Carbon;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

/**
 * Solicitudes: creación, permisos para resolverlas, efectos de aprobarlas y
 * bajas (docs/07-algoritmos.md §7.6, §7.7 y §7.8).
 *
 * Un superior también puede asignar directamente un rol, un itinerario y
 * una parada: queda como una solicitud creada por él y ya aprobada
 * (docs/08-version-2.md §8.5).
 */
class Applications
{
    /** Tipos de los que solo puede haber una solicitud pendiente a la vez. */
    const SINGLE_PENDING_TYPES = [
        Application::TYPE_ITINERARY_MEMBERSHIP,
        Application::TYPE_ITINERARY_CHIEF,
        Application::TYPE_DRIVER,
        Application::TYPE_TRANSPORT_CHIEF,
    ];

    /** Lo que un superior puede asignar directamente. */
    const ASSIGNABLE_TYPES = [
        Application::TYPE_ITINERARY_MEMBERSHIP,
        Application::TYPE_ITINERARY_CHIEF,
        Application::TYPE_DRIVER,
        Application::TYPE_TRANSPORT_CHIEF,
    ];

    /** @var Notices */
    private $notices;

    /** @var ChildEligibility */
    private $childEligibility;

    public function __construct(Notices $notices, ChildEligibility $childEligibility)
    {
        $this->notices = $notices;
        $this->childEligibility = $childEligibility;
    }

    /**
     * Crea una solicitud a partir del objeto "data" de JSON:API, ya validado
     * en su forma. Las bajas se aprueban al instante. Si $actor no es el
     * propio trabajador, es una asignación (o una retirada) de un superior.
     */
    public function create(User $actor, Worker $worker, array $data): Application
    {
        if ((int) $worker->user_id !== (int) $actor->id) {
            return $this->assign($actor, $worker, $data);
        }

        return $this->request($worker, $data);
    }

    /**
     * Un superior asigna directamente (o retira, con un tipo de baja).
     */
    private function assign(User $actor, Worker $worker, array $data): Application
    {
        $type = $data['attributes']['type'];
        $relationships = isset($data['relationships']) ? $data['relationships'] : [];
        $itineraryId = isset($relationships['itinerary']['data']['id']) ? (int) $relationships['itinerary']['data']['id'] : null;

        if (in_array($type, Application::LEAVE_TYPES, true)) {
            if (! $this->canRemove($actor, $worker, $type, $itineraryId)) {
                throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'No puedes quitar ese rol a este trabajador.');
            }

            return $this->leave($worker, $type, $itineraryId, $actor);
        }

        if (! in_array($type, self::ASSIGNABLE_TYPES, true)) {
            throw $this->invalid('Eso solo lo puede pedir el propio trabajador.', '/data/attributes/type');
        }

        return DB::transaction(function () use ($actor, $worker, $data, $type) {
            $application = $this->request($worker, $data, $actor);

            if (! $this->canResolve($actor, $application)) {
                throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'No puedes asignar eso a este trabajador.');
            }

            $application->forceFill([
                'status' => Application::STATUS_APPROVED,
                'resolved_by' => $actor->id,
                'resolved_at' => Carbon::now(),
            ])->save();
            $this->applyApproval($application);
            $this->notices->send([(int) $worker->user_id], Notice::TYPE_ROLE_ASSIGNED, $application->id);

            return $application;
        });
    }

    /**
     * Solicitud del propio trabajador (o la base de una asignación, si $assignedBy).
     */
    private function request(Worker $worker, array $data, ?User $assignedBy = null): Application
    {
        $attributes = $data['attributes'];
        $relationships = isset($data['relationships']) ? $data['relationships'] : [];
        $type = $attributes['type'];
        $relatedId = function (string $name) use ($relationships) {
            return isset($relationships[$name]['data']['id']) ? (int) $relationships[$name]['data']['id'] : null;
        };

        if ($type === Application::TYPE_ITINERARY_REMOVAL) {
            throw $this->invalid('Las bajas automáticas solo las genera el sistema.', '/data/attributes/type');
        }

        if (in_array($type, Application::LEAVE_TYPES, true)) {
            return $this->leave($worker, $type, $relatedId('itinerary'), null);
        }

        if (! $assignedBy) {
            $this->ensureNoPendingDuplicate($worker, $type, $relatedId('itinerary'));
        }

        // Varios hijos en una misma solicitud: una por hijo, agrupadas (docs/09 §11).
        if ($type === Application::TYPE_CHILD_ADDITION && isset($attributes['children']) && is_array($attributes['children'])) {
            return $this->declareChildren($worker, $attributes['children'], $assignedBy);
        }

        return DB::transaction(function () use ($worker, $type, $attributes, $relatedId, $assignedBy) {
            $application = Application::create([
                'worker_id' => $worker->id,
                'type' => $type,
                'status' => Application::STATUS_PENDING,
                'created_by' => $assignedBy ? $assignedBy->id : $worker->user_id,
            ]);
            $user = $worker->user->refreshRoles();
            $you = $assignedBy ? 'El trabajador ya' : 'Ya';

            switch ($type) {
                case Application::TYPE_ITINERARY_MEMBERSHIP:
                case Application::TYPE_ITINERARY_CHIEF:
                    $this->createItineraryRequest($worker, $application, $relatedId('itinerary'), $relatedId('stop'));
                    break;
                case Application::TYPE_DRIVER:
                    if ($user->isDriver()) {
                        throw $this->conflict('ALREADY_HAS_ROLE', $you.' es chofer.');
                    }
                    break;
                case Application::TYPE_TRANSPORT_CHIEF:
                    if ($user->isTransportChief()) {
                        throw $this->conflict('ALREADY_HAS_ROLE', $you.' es Jefe de Transporte.');
                    }
                    break;
                case Application::TYPE_CHILD_ADDITION:
                    $child = $this->declareChild($worker, $attributes);
                    ChildApplication::create(['application_id' => $application->id, 'child_id' => $child->id]);
                    break;
                case Application::TYPE_CHILD_REMOVAL:
                    $child = Child::declared()->where('worker_id', $worker->id)->find($relatedId('child'));
                    if (! $child) {
                        throw $this->invalid('Ese niño no está declarado por ti.', '/data/relationships/child');
                    }
                    ChildApplication::create(['application_id' => $application->id, 'child_id' => $child->id]);
                    break;
                case Application::TYPE_ABSENCE:
                    $indefinite = ! empty($attributes['indefinite']);
                    AbsenceApplication::create([
                        'application_id' => $application->id,
                        'absence_type_id' => $relatedId('absenceType'),
                        'starts_on' => $indefinite ? null : $attributes['startsOn'],
                        'ends_on' => $indefinite ? null : $attributes['endsOn'],
                        'observation' => isset($attributes['observation']) ? $attributes['observation'] : null,
                    ]);
                    break;
            }

            if (! $assignedBy) {
                $this->notices->send($this->resolverIds($application), Notice::TYPE_APPLICATION_RECEIVED, $application->id, null, (int) $worker->user_id);
            }

            return $application;
        });
    }

    /**
     * Quién puede aprobar o rechazar la solicitud (algoritmo 7.6, sin el
     * estado pendiente ni la regla de no resolver las propias).
     */
    public function canResolve(User $user, Application $application): bool
    {
        if ((int) $application->worker_id === $user->workerId()) {
            return false;
        }

        if ($user->isAdmin()) {
            return true;
        }

        $worker = $application->worker;

        if (! $worker || (int) $worker->entity_id !== $user->entityId()) {
            return false;
        }

        switch ($application->type) {
            case Application::TYPE_TRANSPORT_CHIEF:
                return false;
            case Application::TYPE_ITINERARY_CHIEF:
            case Application::TYPE_DRIVER:
                return $user->isTransportChief();
            default:
                return $user->isChiefOf($this->relevantItineraryId($application));
        }
    }

    /**
     * Un superior puede quitar a otro: el Administrador todo; el Jefe de
     * Transporte, en su Entidad, los roles de Jefe de itinerario y chofer y
     * el itinerario; el Jefe de itinerario, el itinerario de los de su itinerario.
     */
    public function canRemove(User $user, Worker $worker, string $type, ?int $itineraryId): bool
    {
        if ($user->isAdmin()) {
            return true;
        }

        if ((int) $worker->entity_id !== $user->entityId()) {
            return false;
        }

        switch ($type) {
            case Application::TYPE_TRANSPORT_CHIEF_LEAVE:
                return false;
            case Application::TYPE_ITINERARY_CHIEF_LEAVE:
            case Application::TYPE_DRIVER_LEAVE:
                return $user->isTransportChief();
            case Application::TYPE_ITINERARY_LEAVE:
                return $user->isChiefOf($worker->itinerary_id ? (int) $worker->itinerary_id : null);
            default:
                return false;
        }
    }

    public function approve(Application $application, User $by, ?string $note = null): Application
    {
        return $this->resolve($application, $by, Application::STATUS_APPROVED, $note);
    }

    public function reject(Application $application, User $by, ?string $note = null): Application
    {
        return $this->resolve($application, $by, Application::STATUS_REJECTED, $note);
    }

    /**
     * Solo el solicitante, mientras esté pendiente.
     */
    public function cancel(Application $application, User $by): Application
    {
        if ((int) $application->worker_id !== $by->workerId()) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'Solo quien envió la solicitud puede cancelarla.');
        }

        return DB::transaction(function () use ($application) {
            $application = $this->lockPending($application);
            $application->status = Application::STATUS_CANCELLED;
            $application->save();
            $this->discardChild($application);

            return $application;
        });
    }

    /**
     * Baja (algoritmo 7.8). $by es quien la da: el propio trabajador o un superior.
     */
    public function leave(Worker $worker, string $type, ?int $itineraryId, ?User $by): Application
    {
        $self = ! $by || (int) $by->id === (int) $worker->user_id;
        $subject = $self ? 'No eres' : 'El trabajador no es';

        return DB::transaction(function () use ($worker, $type, $itineraryId, $by, $self, $subject) {
            $notify = [];
            $stopId = null;

            switch ($type) {
                case Application::TYPE_ITINERARY_LEAVE:
                    if (! $worker->itinerary_id) {
                        throw $this->invalid($subject.' miembro de ningún itinerario.', '/data/attributes/type');
                    }
                    $itineraryId = (int) $worker->itinerary_id;
                    $stopId = (int) $worker->stop_id;
                    $worker->itinerary_id = null;
                    $worker->stop_id = null;
                    $worker->save();
                    $notify = $this->notices->itineraryChiefIds($itineraryId);
                    break;

                case Application::TYPE_ITINERARY_CHIEF_LEAVE:
                    $chief = ItineraryChief::where('worker_id', $worker->id)->where('itinerary_id', $itineraryId)->first();
                    if (! $chief) {
                        throw $this->invalid($subject.' Jefe de ese itinerario.', '/data/relationships/itinerary');
                    }
                    $chief->delete();
                    $notify = $this->notices->transportChiefIds((int) $worker->entity_id);
                    break;

                case Application::TYPE_DRIVER_LEAVE:
                    $driver = Driver::where('worker_id', $worker->id)->first();
                    if (! $driver) {
                        throw $this->invalid($subject.' chofer.', '/data/attributes/type');
                    }
                    $driver->delete();
                    Vehicle::where('driver_id', $driver->id)->update(['driver_id' => null]);
                    $notify = $this->notices->transportChiefIds((int) $worker->entity_id);
                    $this->notifyTripsToReassign($driver->id, $notify);
                    break;

                case Application::TYPE_TRANSPORT_CHIEF_LEAVE:
                    $transportChief = TransportChief::where('worker_id', $worker->id)->first();
                    if (! $transportChief) {
                        throw $this->invalid($subject.' Jefe de Transporte.', '/data/attributes/type');
                    }
                    $transportChief->delete();
                    $notify = $this->notices->adminIds();
                    break;
            }

            $application = Application::create([
                'worker_id' => $worker->id,
                'type' => $type,
                'status' => Application::STATUS_APPROVED,
                'created_by' => $by ? $by->id : $worker->user_id,
                'resolved_by' => $self ? null : $by->id,
                'resolved_at' => Carbon::now(),
            ]);

            if (in_array($type, Application::ITINERARY_TYPES, true)) {
                ItineraryApplication::create(['application_id' => $application->id, 'itinerary_id' => $itineraryId, 'stop_id' => $stopId]);
            }

            $this->notices->send($notify, Notice::TYPE_RESIGNATION, $application->id, null, $by ? (int) $by->id : (int) $worker->user_id);

            if (! $self) {
                $this->notices->send([(int) $worker->user_id], Notice::TYPE_ROLE_REMOVED, $application->id);
            }

            return $application;
        });
    }

    /**
     * Solicitudes que el usuario puede ver: las suyas, las que puede resolver
     * y, para el Administrador y los Jefes de Transporte, todas.
     */
    public function visibleTo(User $user): Builder
    {
        $query = Application::query();

        if ($user->isAdmin()) {
            return $query;
        }

        $entityId = $user->entityId();

        if ($user->isTransportChief()) {
            return $query->whereHas('worker', function (Builder $query) use ($entityId) {
                $query->withTrashed()->where('entity_id', $entityId);
            });
        }

        $itineraryIds = $user->chiefItineraryIds();

        return $query->where(function (Builder $query) use ($user, $itineraryIds) {
            $query->where('worker_id', $user->workerId());

            if ($itineraryIds) {
                $query->orWhere(function (Builder $query) use ($itineraryIds) {
                    $query->whereIn('type', [Application::TYPE_ITINERARY_MEMBERSHIP, Application::TYPE_ITINERARY_LEAVE, Application::TYPE_ITINERARY_REMOVAL])
                        ->whereHas('itineraryApplication', function (Builder $query) use ($itineraryIds) {
                            $query->whereIn('itinerary_id', $itineraryIds);
                        });
                })->orWhere(function (Builder $query) use ($itineraryIds) {
                    $query->whereIn('type', [Application::TYPE_CHILD_ADDITION, Application::TYPE_CHILD_REMOVAL, Application::TYPE_ABSENCE])
                        ->whereHas('worker', function (Builder $query) use ($itineraryIds) {
                            $query->whereIn('itinerary_id', $itineraryIds);
                        });
                });
            }
        });
    }

    /**
     * Filtra una consulta a las solicitudes pendientes que el usuario puede resolver.
     */
    public function resolvableBy(User $user, Builder $query): Builder
    {
        $query->where('status', Application::STATUS_PENDING);

        if ($user->isAdmin()) {
            return $query;
        }

        $query->where('worker_id', '!=', (int) $user->workerId());
        $itineraryIds = $user->chiefItineraryIds();
        $isTransportChief = $user->isTransportChief();
        $entityId = $user->entityId();

        return $query->where(function (Builder $query) use ($isTransportChief, $itineraryIds, $entityId) {
            $query->whereRaw('1 = 0');

            if ($isTransportChief) {
                $query->orWhere(function (Builder $query) use ($entityId) {
                    $query->where('type', '!=', Application::TYPE_TRANSPORT_CHIEF)
                        ->whereHas('worker', function (Builder $query) use ($entityId) {
                            $query->where('entity_id', $entityId);
                        });
                });

                return;
            }

            if ($itineraryIds) {
                $query->orWhere(function (Builder $query) use ($itineraryIds) {
                    $query->where('type', Application::TYPE_ITINERARY_MEMBERSHIP)
                        ->whereHas('itineraryApplication', function (Builder $query) use ($itineraryIds) {
                            $query->whereIn('itinerary_id', $itineraryIds);
                        });
                })->orWhere(function (Builder $query) use ($itineraryIds) {
                    $query->whereIn('type', [Application::TYPE_CHILD_ADDITION, Application::TYPE_CHILD_REMOVAL, Application::TYPE_ABSENCE])
                        ->whereHas('worker', function (Builder $query) use ($itineraryIds) {
                            $query->whereIn('itinerary_id', $itineraryIds);
                        });
                });
            }
        });
    }

    /**
     * Itinerario al que se refiere la solicitud: el pedido, o el actual del solicitante.
     */
    private function relevantItineraryId(Application $application): ?int
    {
        if (in_array($application->type, Application::ITINERARY_TYPES, true)) {
            $itineraryApplication = $application->itineraryApplication;

            return $itineraryApplication ? (int) $itineraryApplication->itinerary_id : null;
        }

        $worker = $application->worker;

        return $worker && $worker->itinerary_id ? (int) $worker->itinerary_id : null;
    }

    /**
     * @return int[] trabajadores que pueden resolver la solicitud
     */
    private function resolverIds(Application $application): array
    {
        $ids = $this->notices->adminIds();
        $entityId = $application->worker ? (int) $application->worker->entity_id : null;

        if ($application->type !== Application::TYPE_TRANSPORT_CHIEF) {
            $ids = array_merge($ids, $this->notices->transportChiefIds($entityId));
        }

        if (! in_array($application->type, [Application::TYPE_TRANSPORT_CHIEF, Application::TYPE_ITINERARY_CHIEF, Application::TYPE_DRIVER], true)) {
            $ids = array_merge($ids, $this->notices->itineraryChiefIds($this->relevantItineraryId($application)));
        }

        return array_values(array_unique($ids));
    }

    private function resolve(Application $application, User $by, string $status, ?string $note): Application
    {
        if ((int) $application->worker_id === $by->workerId()) {
            throw new JsonApiException(403, 'SELF_APPROVAL', 'Sin permiso', 'No puedes resolver tus propias solicitudes.');
        }

        if (! $this->canResolve($by, $application)) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'No puedes resolver esta solicitud.');
        }

        return DB::transaction(function () use ($application, $by, $status, $note) {
            $application = $this->lockPending($application);
            $application->forceFill([
                'status' => $status,
                'resolved_by' => $by->id,
                'resolved_at' => Carbon::now(),
                'resolution_note' => $note,
            ])->save();

            if ($status === Application::STATUS_APPROVED) {
                $this->applyApproval($application);
            } else {
                $this->discardChild($application);
            }

            $this->notices->send([(int) $application->worker->user_id], Notice::TYPE_APPLICATION_RESOLVED, $application->id);

            return $application;
        });
    }

    /**
     * Efectos de aprobar (algoritmo 7.7).
     */
    private function applyApproval(Application $application): void
    {
        $worker = Worker::findOrFail($application->worker_id);

        switch ($application->type) {
            case Application::TYPE_ITINERARY_MEMBERSHIP:
                $this->moveWorker($worker, $application->itineraryApplication);
                break;

            case Application::TYPE_ITINERARY_CHIEF:
                $request = $application->itineraryApplication;
                $this->ensureChiefOfNoOther($worker, (int) $request->itinerary_id);
                $chief = ItineraryChief::withTrashed()->firstOrNew(['itinerary_id' => $request->itinerary_id, 'worker_id' => $worker->id]);
                $chief->deleted_at = null;
                $chief->save();

                if ((int) $worker->itinerary_id !== (int) $request->itinerary_id || (int) $worker->stop_id !== (int) $request->stop_id) {
                    $this->moveWorker($worker, $request);
                }

                $pending = Application::where('worker_id', $worker->id)
                    ->where('type', Application::TYPE_ITINERARY_MEMBERSHIP)
                    ->where('status', Application::STATUS_PENDING)
                    ->get();

                foreach ($pending as $membership) {
                    $membership->forceFill(['status' => Application::STATUS_CANCELLED])->save();
                }
                break;

            case Application::TYPE_DRIVER:
                $driver = Driver::withTrashed()->firstOrNew(['worker_id' => $worker->id]);
                $driver->deleted_at = null;
                $driver->save();
                break;

            case Application::TYPE_TRANSPORT_CHIEF:
                $chief = TransportChief::withTrashed()->firstOrNew(['worker_id' => $worker->id]);
                $chief->deleted_at = null;
                $chief->save();
                break;

            case Application::TYPE_CHILD_REMOVAL:
                $application->childApplication->child->delete();
                break;
        }
    }

    /**
     * Un Jefe de itinerario solo puede serlo de un itinerario.
     */
    private function ensureChiefOfNoOther(Worker $worker, ?int $itineraryId): void
    {
        $current = ItineraryChief::where('worker_id', $worker->id)->lockForUpdate()->pluck('itinerary_id')->map(function ($id) {
            return (int) $id;
        })->all();

        if (in_array($itineraryId, $current, true)) {
            throw $this->conflict('ALREADY_HAS_ROLE', 'Ya es Jefe de ese itinerario.');
        }

        if ($current) {
            throw $this->conflict('ALREADY_CHIEF_OF_OTHER', 'Ya es Jefe de otro itinerario. Un Jefe de itinerario solo puede serlo de uno: primero hay que darlo de baja de ese.');
        }
    }

    private function moveWorker(Worker $worker, ItineraryApplication $request): void
    {
        $stillInItinerary = ItineraryStop::where('itinerary_id', $request->itinerary_id)->where('stop_id', $request->stop_id)->exists();

        if (! $stillInItinerary) {
            throw $this->conflict('STOP_NOT_IN_ITINERARY', 'La parada pedida ya no pertenece a ese itinerario.');
        }

        $worker->itinerary_id = $request->itinerary_id;
        $worker->stop_id = $request->stop_id;
        $worker->save();
    }

    private function createItineraryRequest(Worker $worker, Application $application, ?int $itineraryId, ?int $stopId): void
    {
        Tenancy::ensureSame((int) $worker->entity_id, 'itineraries', $itineraryId, '/data/relationships/itinerary');

        if (! ItineraryStop::where('itinerary_id', $itineraryId)->where('stop_id', $stopId)->exists()) {
            throw $this->invalid('La parada no pertenece a ese itinerario.', '/data/relationships/stop', 'STOP_NOT_IN_ITINERARY');
        }

        if ($application->type === Application::TYPE_ITINERARY_MEMBERSHIP
            && (int) $worker->itinerary_id === $itineraryId && (int) $worker->stop_id === $stopId) {
            throw $this->conflict('ALREADY_MEMBER', 'Ya viaja en ese itinerario y en esa parada.');
        }

        if ($application->type === Application::TYPE_ITINERARY_CHIEF) {
            $this->ensureChiefOfNoOther($worker, $itineraryId);
        }

        ItineraryApplication::create(['application_id' => $application->id, 'itinerary_id' => $itineraryId, 'stop_id' => $stopId]);
    }

    /**
     * Crea la fila del niño. Cuenta cuando se aprueba la solicitud.
     */
    /**
     * Declara varios hijos a la vez: una solicitud por hijo con el mismo
     * group_id (el id de la primera). Se aprueban o rechazan por separado.
     */
    private function declareChildren(Worker $worker, array $children, ?User $assignedBy): Application
    {
        return DB::transaction(function () use ($worker, $children, $assignedBy) {
            $first = null;

            foreach (array_values($children) as $index => $child) {
                $application = Application::create([
                    'worker_id' => $worker->id,
                    'group_id' => $first ? $first->id : null,
                    'type' => Application::TYPE_CHILD_ADDITION,
                    'status' => Application::STATUS_PENDING,
                    'created_by' => $assignedBy ? $assignedBy->id : $worker->user_id,
                ]);

                if (! $first) {
                    $first = $application;
                    $application->forceFill(['group_id' => $application->id])->save();
                }

                try {
                    $declared = $this->declareChild($worker, [
                        'childFirstName' => $child['firstName'],
                        'childMiddleName' => isset($child['middleName']) ? $child['middleName'] : null,
                        'childFirstSurname' => $child['firstSurname'],
                        'childSecondSurname' => $child['secondSurname'],
                        'childBirthDate' => $child['birthDate'],
                    ]);
                } catch (JsonApiException $exception) {
                    // El error se refiere al hijo concreto dentro de la lista.
                    $error = $exception->toError();
                    $pointer = isset($error['source']['pointer']) ? $error['source']['pointer'] : '';
                    $field = lcfirst((string) preg_replace('#^/data/attributes/child#', '', $pointer));
                    throw new JsonApiException($exception->getStatus(), $error['code'], $error['title'], $error['detail'],
                        ['pointer' => "/data/attributes/children/{$index}/".($field ?: 'birthDate')]);
                }
                ChildApplication::create(['application_id' => $application->id, 'child_id' => $declared->id]);
            }

            if (! $assignedBy) {
                $this->notices->send($this->resolverIds($first), Notice::TYPE_APPLICATION_RECEIVED, $first->id, null, (int) $worker->user_id);
            }

            return $first;
        });
    }

    /**
     * El trabajador pone o cambia las fechas de su ausencia indefinida ya
     * aprobada (no hace falta volver a aprobarla).
     */
    public function setAbsenceDates(Application $application, User $user, string $startsOn, string $endsOn): Application
    {
        if ((int) $application->worker_id !== (int) $user->workerId()) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'Solo el propio trabajador puede cambiar las fechas de su ausencia.');
        }

        if ($application->status !== Application::STATUS_APPROVED || $application->absenceApplication->starts_on !== null) {
            throw $this->conflict('ABSENCE_NOT_INDEFINITE', 'Solo se pueden poner fechas a una ausencia indefinida aprobada.');
        }

        $application->absenceApplication->forceFill(['starts_on' => $startsOn, 'ends_on' => $endsOn])->save();

        return $application;
    }

    private function declareChild(Worker $worker, array $attributes): Child
    {
        $birthDate = CarbonImmutable::parse($attributes['childBirthDate'])->startOfDay();

        if ($birthDate->isFuture()) {
            throw $this->invalid('La fecha de nacimiento no puede ser futura.', '/data/attributes/childBirthDate');
        }

        if (! $this->childEligibility->isEligible($birthDate, (int) $worker->entity_id)) {
            throw $this->invalid(
                'El niño ya no tiene derecho a viajar: lo tuvo hasta el '.$this->childEligibility->eligibleUntil($birthDate, (int) $worker->entity_id)->format('d/m/Y').'.',
                '/data/attributes/childBirthDate',
                'CHILD_NOT_ELIGIBLE'
            );
        }

        return Child::create([
            'worker_id' => $worker->id,
            'first_name' => self::cleanName($attributes['childFirstName']),
            'middle_name' => isset($attributes['childMiddleName']) ? self::cleanName($attributes['childMiddleName']) : null,
            'first_surname' => self::cleanName($attributes['childFirstSurname']),
            'second_surname' => self::cleanName($attributes['childSecondSurname']),
            'birth_date' => $birthDate->toDateString(),
        ]);
    }

    private static function cleanName(?string $name): ?string
    {
        $name = preg_replace('/\s+/u', ' ', trim((string) $name));

        return $name === '' ? null : $name;
    }

    /**
     * Si se rechaza o cancela la declaración de un niño, su fila se borra para
     * que pueda volver a declararse.
     */
    private function discardChild(Application $application): void
    {
        if ($application->type === Application::TYPE_CHILD_ADDITION) {
            $application->childApplication->child->delete();
        }
    }

    private function ensureNoPendingDuplicate(Worker $worker, string $type, ?int $itineraryId): void
    {
        if (! in_array($type, self::SINGLE_PENDING_TYPES, true)) {
            return;
        }

        $query = Application::where('worker_id', $worker->id)->where('type', $type)->where('status', Application::STATUS_PENDING);

        if ($type === Application::TYPE_ITINERARY_CHIEF) {
            $query->whereHas('itineraryApplication', function (Builder $query) use ($itineraryId) {
                $query->where('itinerary_id', $itineraryId);
            });
        }

        if ($query->exists()) {
            throw $this->conflict('APPLICATION_ALREADY_PENDING', 'Ya tienes una solicitud de ese tipo pendiente. Cancélala si quieres enviar otra.');
        }
    }

    private function notifyTripsToReassign(int $driverId, array $transportChiefIds): void
    {
        if (! class_exists(Trip::class)) {
            return;
        }

        $trips = Trip::where('driver_id', $driverId)
            ->whereIn('status', [Trip::STATUS_UNCONFIRMED, Trip::STATUS_CONFIRMED])
            ->where('departs_at', '>', Carbon::now())
            ->pluck('id');

        foreach ($trips as $tripId) {
            $this->notices->send(array_merge($transportChiefIds, $this->notices->adminIds()), Notice::TYPE_TRIP_NEEDS_REASSIGNMENT, null, (int) $tripId);
        }
    }

    private function lockPending(Application $application): Application
    {
        $locked = Application::lockForUpdate()->findOrFail($application->id);

        if (! $locked->isPending()) {
            throw $this->conflict('APPLICATION_NOT_PENDING', 'La solicitud ya no está pendiente.');
        }

        return $locked;
    }

    private function invalid(string $detail, string $pointer, string $code = 'VALIDATION_ERROR'): JsonApiException
    {
        return new JsonApiException(422, $code, 'Solicitud no válida', $detail, ['pointer' => $pointer]);
    }

    private function conflict(string $code, string $detail, ?string $pointer = null): JsonApiException
    {
        return JsonApiException::conflict($code, $detail, $pointer);
    }
}
