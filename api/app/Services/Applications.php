<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Application;
use App\Models\Entity;
use App\Models\Itinerary;
use App\Models\ItineraryStop;
use App\Models\Notice;
use App\Models\Role;
use App\Models\RoleApprover;
use App\Models\User;
use App\Models\Worker;
use App\Models\WorkerRole;
use Carbon\Carbon;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

/**
 * Solicitudes (docs/11 §11.6 y §11.16):
 *
 * - entity_membership: entrar en una Entidad; la aprueba quien tenga
 *   entities.approve_membership (por defecto, solo el Administrador).
 * - itinerary_membership: itinerario y parada; la aprueba quien tenga
 *   members.approve sobre ese itinerario.
 * - role: un rol que se pueda solicitar; la aprueban quienes tengan en esa
 *   Entidad alguno de sus roles aprobadores y roles.approve, y el Administrador.
 *
 * Al rechazar, el motivo es obligatorio. Darse de baja no es una solicitud.
 */
class Applications
{
    /** @var Notices */
    private $notices;

    /** @var Permissions */
    private $permissions;

    /** @var Memberships */
    private $memberships;

    public function __construct(Notices $notices, Permissions $permissions, Memberships $memberships)
    {
        $this->notices = $notices;
        $this->permissions = $permissions;
        $this->memberships = $memberships;
    }

    /**
     * Solicitud de la propia persona.
     *
     * @param array $input ['type', 'entityId', 'itineraryId', 'stopId', 'roleId']
     */
    public function create(User $user, array $input): Application
    {
        $type = $input['type'];
        $entityId = $input['entityId'];
        $itineraryId = $input['itineraryId'];
        $stopId = $input['stopId'];
        $roleId = $input['roleId'];

        switch ($type) {
            case Application::TYPE_ENTITY_MEMBERSHIP:
                if ($entityId === null || ! Entity::whereKey($entityId)->exists()) {
                    throw $this->invalid('Indique la Entidad en la que quiere entrar.', '/data/relationships/entity', 'ENTITY_NOT_FOUND');
                }
                if ($user->workerIn($entityId)) {
                    throw JsonApiException::conflict('ALREADY_MEMBER', 'Ya pertenece a esa Entidad.');
                }
                $itineraryId = $stopId = $roleId = null;
                break;

            case Application::TYPE_ITINERARY_MEMBERSHIP:
                $itinerary = $itineraryId ? Itinerary::find($itineraryId) : null;
                if (! $itinerary) {
                    throw $this->invalid('Indique el itinerario.', '/data/relationships/itinerary');
                }
                $entityId = (int) $itinerary->entity_id;
                $worker = $this->workerOrFail($user, $entityId);
                if (! $stopId || ! ItineraryStop::where('itinerary_id', $itineraryId)->where('stop_id', $stopId)->exists()) {
                    throw $this->invalid('La parada no pertenece a ese itinerario.', '/data/relationships/stop', 'STOP_NOT_IN_ITINERARY');
                }
                if ((int) $worker->itinerary_id === (int) $itineraryId && (int) $worker->stop_id === (int) $stopId) {
                    throw JsonApiException::conflict('ALREADY_MEMBER', 'Ya viaja en ese itinerario y en esa parada.');
                }
                $roleId = null;
                break;

            case Application::TYPE_ROLE:
                $role = $roleId ? Role::find($roleId) : null;
                if (! $role) {
                    throw $this->invalid('Indique el rol.', '/data/relationships/role');
                }
                if (! $role->requestable) {
                    throw $this->invalid('Ese rol no se puede solicitar: solo lo asigna quien tiene permiso.', '/data/relationships/role', 'ROLE_NOT_REQUESTABLE');
                }
                if ($entityId === null && $itineraryId !== null) {
                    $entityId = (int) Itinerary::whereKey($itineraryId)->value('entity_id') ?: null;
                }
                $entityId = $entityId !== null ? $entityId : $user->singleEntityId();
                if ($entityId === null) {
                    throw $this->invalid('Indique la Entidad en la que pide el rol.', '/data/relationships/entity');
                }
                $worker = $this->workerOrFail($user, $entityId);
                $this->memberships->validateRoleItinerary($worker, $role, $itineraryId);
                if (WorkerRole::where('worker_id', $worker->id)->where('role_id', $role->id)->exists()) {
                    throw JsonApiException::conflict('ALREADY_HAS_ROLE', 'Ya tiene ese rol en esa Entidad.');
                }
                $itineraryId = $role->itinerary_scoped ? $itineraryId : null;
                $stopId = null;
                break;

            default:
                throw $this->invalid('Tipo de solicitud no válido.', '/data/attributes/type');
        }

        $this->ensureNoPendingDuplicate($user, $type, $entityId, $roleId);

        return DB::transaction(function () use ($user, $type, $entityId, $itineraryId, $stopId, $roleId) {
            $application = Application::create([
                'user_id' => $user->id,
                'entity_id' => $entityId,
                'type' => $type,
                'status' => Application::STATUS_PENDING,
                'itinerary_id' => $itineraryId,
                'stop_id' => $stopId,
                'role_id' => $roleId,
                'created_by' => $user->id,
            ]);

            $this->notices->send($this->resolverIds($application), Notice::TYPE_APPLICATION_RECEIVED, $application->id, null, (int) $user->id);

            return $application;
        });
    }

    /**
     * Puede aprobar o rechazar la solicitud (sin mirar si está pendiente).
     */
    public function canResolve(User $user, Application $application): bool
    {
        if ($user->isAdmin()) {
            return true;
        }

        if ((int) $application->user_id === (int) $user->id) {
            return false;
        }

        switch ($application->type) {
            case Application::TYPE_ENTITY_MEMBERSHIP:
                return $this->permissions->can($user, 'entities.approve_membership', (int) $application->entity_id);
            case Application::TYPE_ITINERARY_MEMBERSHIP:
                return $this->permissions->can($user, 'members.approve', (int) $application->entity_id, (int) $application->itinerary_id);
            case Application::TYPE_ROLE:
                return $this->canApproveRole($user, (int) $application->role_id, (int) $application->entity_id);
        }

        return false;
    }

    /**
     * Aprueba (o asigna directamente) el rol en esa Entidad: tiene roles.approve
     * (o roles.assign, según $operation) y alguno de los roles aprobadores.
     */
    public function canApproveRole(User $user, int $roleId, int $entityId, string $operation = 'roles.approve'): bool
    {
        if ($user->isAdmin()) {
            return true;
        }

        $scope = $this->permissions->scope($user, $operation);

        if (! $scope['all'] && ! in_array($entityId, $scope['entities'], true)) {
            return false;
        }

        $approvers = array_map('intval', RoleApprover::where('role_id', $roleId)->pluck('approver_role_id')->all());
        $held = $this->permissions->heldRoleIds($user, $scope['all'] ? null : $entityId);

        return (bool) array_intersect($approvers, $held);
    }

    public function approve(Application $application, User $by, ?string $note = null): Application
    {
        return $this->resolve($application, $by, Application::STATUS_APPROVED, $note);
    }

    public function reject(Application $application, User $by, string $note): Application
    {
        return $this->resolve($application, $by, Application::STATUS_REJECTED, $note);
    }

    /**
     * Solo el solicitante, mientras esté pendiente.
     */
    public function cancel(Application $application, User $by): Application
    {
        if ((int) $application->user_id !== (int) $by->id) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'Solo quien envió la solicitud puede cancelarla.');
        }

        return DB::transaction(function () use ($application) {
            $application = $this->lockPending($application);
            $application->status = Application::STATUS_CANCELLED;
            $application->save();

            return $application;
        });
    }

    /**
     * Solicitudes que puede ver: las suyas y las que puede resolver.
     */
    public function visibleTo(User $user): Builder
    {
        $query = Application::query();

        if ($user->isAdmin()) {
            return $query;
        }

        return $query->where(function (Builder $query) use ($user) {
            $query->where('user_id', $user->id)->orWhere(function (Builder $query) use ($user) {
                $this->whereResolvable($query, $user);
            });
        });
    }

    /**
     * Filtra a las pendientes que puede resolver.
     */
    public function resolvableBy(User $user, Builder $query): Builder
    {
        $query->where('status', Application::STATUS_PENDING);

        if ($user->isAdmin()) {
            return $query;
        }

        return $query->where('user_id', '!=', $user->id)->where(function (Builder $query) use ($user) {
            $this->whereResolvable($query, $user);
        });
    }

    /**
     * @return int[] personas que pueden resolverla
     */
    public function resolverIds(Application $application): array
    {
        switch ($application->type) {
            case Application::TYPE_ENTITY_MEMBERSHIP:
                return $this->permissions->userIdsWith('entities.approve_membership', (int) $application->entity_id);
            case Application::TYPE_ITINERARY_MEMBERSHIP:
                return $this->permissions->userIdsWith('members.approve', (int) $application->entity_id, (int) $application->itinerary_id);
            default:
                $ids = $this->permissions->userIdsWith('roles.approve', (int) $application->entity_id);

                return array_values(array_filter($ids, function ($id) use ($application) {
                    $user = User::find($id);

                    return $user && $this->canApproveRole($user, (int) $application->role_id, (int) $application->entity_id);
                }));
        }
    }

    private function whereResolvable(Builder $query, User $user): void
    {
        $query->whereRaw('1 = 0');

        $entity = $this->permissions->scope($user, 'entities.approve_membership');
        $query->orWhere(function (Builder $query) use ($entity) {
            $query->where('type', Application::TYPE_ENTITY_MEMBERSHIP);
            if (! $entity['all']) {
                $query->whereIn('entity_id', $entity['entities'] ?: [0]);
            }
        });

        $members = $this->permissions->scope($user, 'members.approve');
        $query->orWhere(function (Builder $query) use ($members) {
            $query->where('type', Application::TYPE_ITINERARY_MEMBERSHIP);
            if (! $members['all']) {
                $query->where(function (Builder $query) use ($members) {
                    $query->whereIn('entity_id', $members['entities'] ?: [0])->orWhereIn('itinerary_id', $members['itineraries'] ?: [0]);
                });
            }
        });

        $roles = $this->permissions->scope($user, 'roles.approve');
        $entityIds = $roles['all'] ? $user->entityIds() : $roles['entities'];

        foreach ($entityIds as $entityId) {
            $held = $this->permissions->heldRoleIds($user, $roles['all'] ? null : $entityId);
            $roleIds = $held ? array_map('intval', RoleApprover::whereIn('approver_role_id', $held)->pluck('role_id')->all()) : [];

            if ($roleIds) {
                $query->orWhere(function (Builder $query) use ($entityId, $roleIds, $roles) {
                    $query->where('type', Application::TYPE_ROLE)->whereIn('role_id', $roleIds);
                    if (! $roles['all']) {
                        $query->where('entity_id', $entityId);
                    }
                });
            }
        }
    }

    private function resolve(Application $application, User $by, string $status, ?string $note): Application
    {
        if ((int) $application->user_id === (int) $by->id && ! $by->isAdmin()) {
            throw new JsonApiException(403, 'SELF_APPROVAL', 'Sin permiso', 'No puede resolver sus propias solicitudes.');
        }

        if (! $this->canResolve($by, $application)) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'No puede resolver esta solicitud.');
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
            }

            $this->notices->send([(int) $application->user_id], Notice::TYPE_APPLICATION_RESOLVED, $application->id);

            return $application;
        });
    }

    private function applyApproval(Application $application): void
    {
        $user = User::findOrFail($application->user_id);

        switch ($application->type) {
            case Application::TYPE_ENTITY_MEMBERSHIP:
                if (! $user->workerIn($application->entity_id)) {
                    $this->memberships->join($user, Entity::findOrFail($application->entity_id));
                }
                break;

            case Application::TYPE_ITINERARY_MEMBERSHIP:
                $worker = $this->workerOrFail($user, (int) $application->entity_id);
                $this->memberships->assignItinerary($worker, (int) $application->itinerary_id, (int) $application->stop_id);
                break;

            case Application::TYPE_ROLE:
                $worker = $this->workerOrFail($user, (int) $application->entity_id);
                $this->memberships->assignRole($worker, Role::findOrFail($application->role_id), $application->itinerary_id ? (int) $application->itinerary_id : null);
                break;
        }
    }

    private function workerOrFail(User $user, int $entityId): Worker
    {
        $worker = $user->workerIn($entityId);

        if (! $worker) {
            throw JsonApiException::conflict('NOT_A_MEMBER', 'Primero hay que pertenecer a esa Entidad.');
        }

        return $worker;
    }

    private function ensureNoPendingDuplicate(User $user, string $type, ?int $entityId, ?int $roleId): void
    {
        $query = Application::where('user_id', $user->id)->where('type', $type)->where('entity_id', $entityId)
            ->where('status', Application::STATUS_PENDING);

        if ($type === Application::TYPE_ROLE) {
            $query->where('role_id', $roleId);
        }

        if ($query->exists()) {
            throw JsonApiException::conflict('APPLICATION_ALREADY_PENDING', 'Ya tiene una solicitud igual pendiente. Cancélela si quiere enviar otra.');
        }
    }

    private function lockPending(Application $application): Application
    {
        $locked = Application::lockForUpdate()->findOrFail($application->id);

        if (! $locked->isPending()) {
            throw JsonApiException::conflict('APPLICATION_NOT_PENDING', 'La solicitud ya no está pendiente.');
        }

        return $locked;
    }

    private function invalid(string $detail, string $pointer, string $code = 'VALIDATION_ERROR'): JsonApiException
    {
        return new JsonApiException(422, $code, 'Solicitud no válida', $detail, ['pointer' => $pointer]);
    }
}
