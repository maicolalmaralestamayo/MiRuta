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
use App\Models\RankApplication;
use App\Models\TransportChief;
use App\Models\Trip;
use App\Models\Vehicle;
use App\Models\Worker;
use App\Support\CardNumber;
use Carbon\Carbon;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

/**
 * Solicitudes: creación, permisos para resolverlas, efectos de aprobarlas y
 * bajas (docs/07-algoritmos.md §7.6, §7.7 y §7.8).
 */
class Applications
{
    /** Tipos de los que solo puede haber una solicitud pendiente a la vez. */
    const SINGLE_PENDING_TYPES = [
        Application::TYPE_ITINERARY_MEMBERSHIP,
        Application::TYPE_ITINERARY_CHIEF,
        Application::TYPE_DRIVER,
        Application::TYPE_TRANSPORT_CHIEF,
        Application::TYPE_RANK_CHANGE,
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
     * en su forma. Las bajas se aprueban al instante.
     */
    public function create(Worker $worker, array $data): Application
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

        $this->ensureNoPendingDuplicate($worker, $type, $relatedId('itinerary'));

        return DB::transaction(function () use ($worker, $type, $attributes, $relatedId) {
            $application = Application::create([
                'worker_id' => $worker->id,
                'type' => $type,
                'status' => Application::STATUS_PENDING,
            ]);

            switch ($type) {
                case Application::TYPE_ITINERARY_MEMBERSHIP:
                case Application::TYPE_ITINERARY_CHIEF:
                    $this->createItineraryRequest($worker, $application, $relatedId('itinerary'), $relatedId('stop'));
                    break;
                case Application::TYPE_DRIVER:
                    if ($worker->isDriver()) {
                        throw $this->conflict('ALREADY_HAS_ROLE', 'Ya eres chofer.');
                    }
                    break;
                case Application::TYPE_TRANSPORT_CHIEF:
                    if ($worker->isTransportChief()) {
                        throw $this->conflict('ALREADY_HAS_ROLE', 'Ya eres Jefe de Transporte.');
                    }
                    break;
                case Application::TYPE_RANK_CHANGE:
                    $rankId = $relatedId('rank');
                    if ($rankId === (int) $worker->rank_id) {
                        throw $this->invalid('Ya tienes esa jerarquía.', '/data/relationships/rank');
                    }
                    RankApplication::create(['application_id' => $application->id, 'rank_id' => $rankId]);
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
                    AbsenceApplication::create([
                        'application_id' => $application->id,
                        'absence_type_id' => $relatedId('absenceType'),
                        'starts_on' => $attributes['startsOn'],
                        'ends_on' => $attributes['endsOn'],
                        'observation' => isset($attributes['observation']) ? $attributes['observation'] : null,
                    ]);
                    break;
            }

            $this->notices->send($this->resolverIds($application), Notice::TYPE_APPLICATION_RECEIVED, $application->id, null, $worker->id);

            return $application;
        });
    }

    /**
     * Quién puede aprobar o rechazar la solicitud (algoritmo 7.6, sin el
     * estado pendiente ni la regla de no resolver las propias).
     */
    public function canResolve(Worker $user, Application $application): bool
    {
        if ((int) $application->worker_id === (int) $user->id) {
            return false;
        }

        if ($user->isAdmin()) {
            return true;
        }

        switch ($application->type) {
            case Application::TYPE_TRANSPORT_CHIEF:
                return false;
            case Application::TYPE_ITINERARY_CHIEF:
            case Application::TYPE_DRIVER:
                return $user->isTransportChief();
            default:
                return $user->isTransportChief() || $user->isChiefOf($this->relevantItineraryId($application));
        }
    }

    public function approve(Application $application, Worker $by, ?string $note = null): Application
    {
        return $this->resolve($application, $by, Application::STATUS_APPROVED, $note);
    }

    public function reject(Application $application, Worker $by, ?string $note = null): Application
    {
        return $this->resolve($application, $by, Application::STATUS_REJECTED, $note);
    }

    /**
     * Solo el solicitante, mientras esté pendiente.
     */
    public function cancel(Application $application, Worker $by): Application
    {
        if ((int) $application->worker_id !== (int) $by->id) {
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
    public function leave(Worker $worker, string $type, ?int $itineraryId, ?Worker $by): Application
    {
        return DB::transaction(function () use ($worker, $type, $itineraryId, $by) {
            $notify = [];
            $stopId = null;

            switch ($type) {
                case Application::TYPE_ITINERARY_LEAVE:
                    if (! $worker->itinerary_id) {
                        throw $this->invalid('No eres miembro de ningún itinerario.', '/data/attributes/type');
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
                        throw $this->invalid('No eres Jefe de ese itinerario.', '/data/relationships/itinerary');
                    }
                    $chief->delete();
                    $notify = $this->notices->transportChiefIds();
                    break;

                case Application::TYPE_DRIVER_LEAVE:
                    $driver = Driver::where('worker_id', $worker->id)->first();
                    if (! $driver) {
                        throw $this->invalid('No eres chofer.', '/data/attributes/type');
                    }
                    $driver->delete();
                    Vehicle::where('driver_id', $driver->id)->update(['driver_id' => null]);
                    $notify = $this->notices->transportChiefIds();
                    $this->notifyTripsToReassign($driver->id, $notify);
                    break;

                case Application::TYPE_TRANSPORT_CHIEF_LEAVE:
                    $transportChief = TransportChief::where('worker_id', $worker->id)->first();
                    if (! $transportChief) {
                        throw $this->invalid('No eres Jefe de Transporte.', '/data/attributes/type');
                    }
                    $transportChief->delete();
                    $notify = $this->notices->adminIds();
                    break;
            }

            $application = Application::create([
                'worker_id' => $worker->id,
                'type' => $type,
                'status' => Application::STATUS_APPROVED,
                'resolved_by' => $by && (int) $by->id !== (int) $worker->id ? $by->id : null,
                'resolved_at' => Carbon::now(),
            ]);

            if (in_array($type, Application::ITINERARY_TYPES, true)) {
                ItineraryApplication::create(['application_id' => $application->id, 'itinerary_id' => $itineraryId, 'stop_id' => $stopId]);
            }

            $this->notices->send($notify, Notice::TYPE_RESIGNATION, $application->id, null, $by ? (int) $by->id : (int) $worker->id);
            $worker->refreshRoles();

            return $application;
        });
    }

    /**
     * Solicitudes que el usuario puede ver: las suyas, las que puede resolver
     * y, para el Administrador y los Jefes de Transporte, todas.
     */
    public function visibleTo(Worker $user): Builder
    {
        $query = Application::query();

        if ($user->isAdmin() || $user->isTransportChief()) {
            return $query;
        }

        $itineraryIds = $user->chiefItineraryIds();

        return $query->where(function (Builder $query) use ($user, $itineraryIds) {
            $query->where('worker_id', $user->id);

            if ($itineraryIds) {
                $query->orWhere(function (Builder $query) use ($itineraryIds) {
                    $query->whereIn('type', [Application::TYPE_ITINERARY_MEMBERSHIP, Application::TYPE_ITINERARY_LEAVE, Application::TYPE_ITINERARY_REMOVAL])
                        ->whereHas('itineraryApplication', function (Builder $query) use ($itineraryIds) {
                            $query->whereIn('itinerary_id', $itineraryIds);
                        });
                })->orWhere(function (Builder $query) use ($itineraryIds) {
                    $query->whereIn('type', [Application::TYPE_RANK_CHANGE, Application::TYPE_CHILD_ADDITION, Application::TYPE_CHILD_REMOVAL, Application::TYPE_ABSENCE])
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
    public function resolvableBy(Worker $user, Builder $query): Builder
    {
        $query->where('status', Application::STATUS_PENDING)->where('worker_id', '!=', $user->id);

        if ($user->isAdmin()) {
            return $query;
        }

        $itineraryIds = $user->chiefItineraryIds();
        $isTransportChief = $user->isTransportChief();

        return $query->where(function (Builder $query) use ($isTransportChief, $itineraryIds) {
            $query->whereRaw('1 = 0');

            if ($isTransportChief) {
                $query->orWhere('type', '!=', Application::TYPE_TRANSPORT_CHIEF);

                return;
            }

            if ($itineraryIds) {
                $query->orWhere(function (Builder $query) use ($itineraryIds) {
                    $query->where('type', Application::TYPE_ITINERARY_MEMBERSHIP)
                        ->whereHas('itineraryApplication', function (Builder $query) use ($itineraryIds) {
                            $query->whereIn('itinerary_id', $itineraryIds);
                        });
                })->orWhere(function (Builder $query) use ($itineraryIds) {
                    $query->whereIn('type', [Application::TYPE_RANK_CHANGE, Application::TYPE_CHILD_ADDITION, Application::TYPE_CHILD_REMOVAL, Application::TYPE_ABSENCE])
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

        if ($application->type !== Application::TYPE_TRANSPORT_CHIEF) {
            $ids = array_merge($ids, $this->notices->transportChiefIds());
        }

        if (! in_array($application->type, [Application::TYPE_TRANSPORT_CHIEF, Application::TYPE_ITINERARY_CHIEF, Application::TYPE_DRIVER], true)) {
            $ids = array_merge($ids, $this->notices->itineraryChiefIds($this->relevantItineraryId($application)));
        }

        return array_values(array_unique($ids));
    }

    private function resolve(Application $application, Worker $by, string $status, ?string $note): Application
    {
        if ((int) $application->worker_id === (int) $by->id) {
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

            $this->notices->send([(int) $application->worker_id], Notice::TYPE_APPLICATION_RESOLVED, $application->id);

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

            case Application::TYPE_RANK_CHANGE:
                $worker->rank_id = $application->rankApplication->rank_id;
                $worker->save();
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
            throw $this->conflict('ALREADY_HAS_ROLE', 'Ya eres Jefe de ese itinerario.');
        }

        if ($current) {
            throw $this->conflict('ALREADY_CHIEF_OF_OTHER', 'Ya eres Jefe de otro itinerario. Un Jefe de itinerario solo puede serlo de uno: date de baja primero.');
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
        if (! ItineraryStop::where('itinerary_id', $itineraryId)->where('stop_id', $stopId)->exists()) {
            throw $this->invalid('La parada no pertenece a ese itinerario.', '/data/relationships/stop', 'STOP_NOT_IN_ITINERARY');
        }

        if ($application->type === Application::TYPE_ITINERARY_MEMBERSHIP
            && (int) $worker->itinerary_id === $itineraryId && (int) $worker->stop_id === $stopId) {
            throw $this->conflict('ALREADY_MEMBER', 'Ya viajas en ese itinerario y en esa parada.');
        }

        if ($application->type === Application::TYPE_ITINERARY_CHIEF) {
            $this->ensureChiefOfNoOther($worker, $itineraryId);
        }

        ItineraryApplication::create(['application_id' => $application->id, 'itinerary_id' => $itineraryId, 'stop_id' => $stopId]);
    }

    /**
     * Crea (o restaura) la fila del niño. Cuenta cuando se aprueba la solicitud.
     */
    private function declareChild(Worker $worker, array $attributes): Child
    {
        $card = CardNumber::tryParse($attributes['childCardNumber']);

        if (! $this->childEligibility->isEligible($card)) {
            throw $this->invalid(
                'El niño ya no tiene derecho a viajar: lo tuvo hasta el '.$this->childEligibility->eligibleUntil($card)->format('d/m/Y').'.',
                '/data/attributes/childCardNumber',
                'CHILD_NOT_ELIGIBLE'
            );
        }

        $child = Child::withTrashed()->where('card_number_hash', $card->hash())->first();

        if ($child && ! $child->trashed()) {
            throw $this->conflict('CHILD_ALREADY_DECLARED', 'Ese niño ya está declarado (o pendiente de aprobar).', '/data/attributes/childCardNumber');
        }

        $child = $child ?: new Child(['card_number_hash' => $card->hash()]);
        $child->forceFill([
            'worker_id' => $worker->id,
            'first_name' => trim($attributes['childFirstName']),
            'last_name' => trim($attributes['childLastName']),
            'card_number_encrypted' => $card->encrypt(),
            'deleted_at' => null,
        ])->save();

        return $child;
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
