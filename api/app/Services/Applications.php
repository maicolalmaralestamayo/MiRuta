<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Application;
use App\Models\DenialReason;
use App\Models\Entity;
use App\Models\Itinerary;
use App\Models\User;
use App\Models\Worker;
use Carbon\Carbon;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

/**
 * Solicitudes de Entidad y de itinerario (docs/11 §11.23 y §11.26).
 *
 * - Entidad: la resuelve el Administrador.
 * - Itinerario (con parada opcional): el Administrador o un Jefe de ese itinerario.
 * - Quien la hizo ve las suyas y su estado, y puede cancelarlas o eliminarlas.
 * - Rechazar exige un motivo del nomenclador (y una observación opcional).
 */
class Applications
{
    public function __construct(private Access $access, private Memberships $memberships, private Notifier $notifier)
    {
    }

    public function requestEntity(User $user, Entity $entity): Application
    {
        if (! $entity->active) {
            throw JsonApiException::conflict('ENTITY_INACTIVE', 'Esa Entidad está desactivada: no admite solicitudes.', '/data/relationships/entity');
        }

        if ($this->access->workerIn($user, $entity->id)) {
            throw JsonApiException::conflict('ALREADY_MEMBER', 'Ya pertenece a esa Entidad.', '/data/relationships/entity');
        }

        $this->ensureNoPending($user, Application::TYPE_ENTITY, $entity->id, null);

        $application = Application::create([
            'user_id' => $user->id, 'type' => Application::TYPE_ENTITY, 'status' => Application::PENDING, 'entity_id' => $entity->id,
        ]);

        $this->notifier->send($this->notifier->adminIds(), Notifier::APPLICATION_RECEIVED, 'Solicitud de Entidad',
            $user->fullName().' solicita entrar en '.$entity->abbreviation.'.', ['applicationId' => (string) $application->id]);

        return $application;
    }

    public function requestItinerary(User $user, Itinerary $itinerary, ?int $stopId): Application
    {
        if (! $itinerary->active) {
            throw JsonApiException::conflict('ITINERARY_INACTIVE', 'Ese itinerario está desactivado: no admite solicitudes.', '/data/relationships/itinerary');
        }

        $worker = $this->access->workerIn($user, $itinerary->entity_id);

        if (! $worker) {
            throw JsonApiException::conflict('NOT_MEMBER', 'Primero tiene que pertenecer a la Entidad de ese itinerario.', '/data/relationships/itinerary');
        }

        if ((int) $worker->itinerary_id === (int) $itinerary->id) {
            throw JsonApiException::conflict('ALREADY_IN_ITINERARY', 'Ya está en ese itinerario. Para cambiar de parada no hace falta solicitud.', '/data/relationships/itinerary');
        }

        if ($stopId !== null && ! $itinerary->hasStop($stopId)) {
            throw new JsonApiException(422, 'STOP_NOT_IN_ITINERARY', 'Parada de otro itinerario', 'La parada no es de ese itinerario.', ['pointer' => '/data/relationships/stop']);
        }

        $this->ensureNoPending($user, Application::TYPE_ITINERARY, $itinerary->entity_id, $itinerary->id);

        $application = Application::create([
            'user_id' => $user->id, 'type' => Application::TYPE_ITINERARY, 'status' => Application::PENDING,
            'entity_id' => $itinerary->entity_id, 'itinerary_id' => $itinerary->id, 'stop_id' => $stopId,
        ]);

        $this->notifier->send(array_merge($this->notifier->adminIds(), $this->notifier->chiefIds($itinerary->id)),
            Notifier::APPLICATION_RECEIVED, 'Solicitud de itinerario',
            $user->fullName().' solicita entrar en el itinerario '.$itinerary->name.'.', ['applicationId' => (string) $application->id]);

        return $application;
    }

    public function canResolve(User $actor, Application $application): bool
    {
        return $application->type === Application::TYPE_ENTITY
            ? $this->access->isAdmin($actor)
            : $this->access->canManageItinerary($actor, $application->itinerary_id);
    }

    public function approve(Application $application, User $actor): Application
    {
        $this->ensureResolvable($application, $actor);

        DB::transaction(function () use ($application, $actor) {
            $user = User::findOrFail($application->user_id);
            $entity = Entity::findOrFail($application->entity_id);

            if ($application->type === Application::TYPE_ENTITY) {
                $this->memberships->join($user, $entity);
            } else {
                $worker = Worker::where('user_id', $user->id)->where('entity_id', $entity->id)->first();

                if (! $worker) {
                    throw JsonApiException::conflict('NOT_MEMBER', 'La persona ya no pertenece a la Entidad de ese itinerario.');
                }

                $this->memberships->place($worker, (int) $application->itinerary_id, $application->stop_id ? (int) $application->stop_id : null);
            }

            $application->forceFill([
                'status' => Application::APPROVED, 'resolved_by' => $actor->id, 'resolved_at' => Carbon::now(),
            ])->save();
        });

        $this->notifyResolved($application);

        return $application;
    }

    public function reject(Application $application, User $actor, int $denialReasonId, ?string $note): Application
    {
        $this->ensureResolvable($application, $actor);
        $reason = DenialReason::find($denialReasonId);

        if (! $reason || ! $reason->active || ($reason->application_type !== null && $reason->application_type !== $application->type)) {
            throw new JsonApiException(422, 'DENIAL_REASON_INVALID', 'Motivo no válido',
                'Elija un motivo de denegación activo para este tipo de solicitud.', ['pointer' => '/data/relationships/denialReason']);
        }

        $application->forceFill([
            'status' => Application::REJECTED, 'denial_reason_id' => $reason->id, 'resolution_note' => $note,
            'resolved_by' => $actor->id, 'resolved_at' => Carbon::now(),
        ])->save();

        $this->notifyResolved($application);

        return $application;
    }

    /**
     * Solicitudes que ve: las suyas; el Jefe, además, las de su itinerario; el
     * Administrador, todas.
     */
    public function visibleQuery(User $user): Builder
    {
        $query = Application::query();

        if ($this->access->isAdmin($user)) {
            return $query;
        }

        $itineraryId = $this->access->chiefItineraryId($user);

        return $query->where(function ($q) use ($user, $itineraryId) {
            $q->where('user_id', $user->id);

            if ($itineraryId !== null) {
                $q->orWhere(fn ($q) => $q->where('type', Application::TYPE_ITINERARY)->where('itinerary_id', $itineraryId));
            }
        });
    }

    /**
     * Pendientes que le toca resolver (número en la pestaña Gestión).
     */
    public function pendingToResolve(User $user): int
    {
        if ($this->access->isAdmin($user)) {
            return Application::where('status', Application::PENDING)->count();
        }

        $itineraryId = $this->access->chiefItineraryId($user);

        return $itineraryId === null ? 0 : Application::where('status', Application::PENDING)
            ->where('type', Application::TYPE_ITINERARY)->where('itinerary_id', $itineraryId)->count();
    }

    /**
     * Las suyas resueltas que aún no vio.
     */
    public function unseenResolved(User $user): int
    {
        return Application::where('user_id', $user->id)->where('status', '<>', Application::PENDING)->whereNull('seen_at')->count();
    }

    public function markSeen(User $user): int
    {
        return Application::where('user_id', $user->id)->where('status', '<>', Application::PENDING)->whereNull('seen_at')
            ->update(['seen_at' => Carbon::now()]);
    }

    private function ensureResolvable(Application $application, User $actor): void
    {
        if (! $this->canResolve($actor, $application)) {
            throw Access::forbidden($application->type === Application::TYPE_ENTITY
                ? 'Las solicitudes de Entidad las resuelve el Administrador.'
                : 'Las solicitudes de itinerario las resuelven el Administrador y los Jefes de ese itinerario.');
        }

        if ($application->status !== Application::PENDING) {
            throw JsonApiException::conflict('APPLICATION_NOT_PENDING', 'La solicitud ya está resuelta.');
        }
    }

    private function ensureNoPending(User $user, string $type, int $entityId, ?int $itineraryId): void
    {
        $exists = Application::where('user_id', $user->id)->where('type', $type)->where('status', Application::PENDING)
            ->where('entity_id', $entityId)
            ->when($itineraryId !== null, fn ($q) => $q->where('itinerary_id', $itineraryId))
            ->exists();

        if ($exists) {
            throw JsonApiException::conflict('APPLICATION_PENDING', 'Ya tiene una solicitud pendiente igual.');
        }
    }

    private function notifyResolved(Application $application): void
    {
        $target = $application->type === Application::TYPE_ENTITY
            ? 'entrar en '.Entity::find($application->entity_id)?->abbreviation
            : 'entrar en el itinerario '.Itinerary::find($application->itinerary_id)?->name;
        $approved = $application->status === Application::APPROVED;
        $reason = $approved ? '' : ' Motivo: '.DenialReason::find($application->denial_reason_id)?->name.'.';

        $this->notifier->send([(int) $application->user_id], Notifier::APPLICATION_RESOLVED,
            $approved ? 'Solicitud aprobada' : 'Solicitud rechazada',
            'Su solicitud de '.$target.' fue '.($approved ? 'aprobada.' : 'rechazada.'.$reason),
            ['applicationId' => (string) $application->id, 'status' => $application->status]);
    }
}
