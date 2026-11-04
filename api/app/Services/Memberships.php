<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Application;
use App\Models\Entity;
use App\Models\Itinerary;
use App\Models\ItineraryStop;
use App\Models\Notice;
use App\Models\Role;
use App\Models\Trip;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\Worker;
use App\Models\WorkerRole;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Pertenencias a Entidades, itinerario y parada, y roles (docs/11 §11.6 y
 * §11.16). Son acciones directas: las usan la aprobación de solicitudes,
 * quien asigna con permiso y la propia persona al darse de baja.
 */
class Memberships
{
    /** @var Notices */
    private $notices;

    /** @var Permissions */
    private $permissions;

    public function __construct(Notices $notices, Permissions $permissions)
    {
        $this->notices = $notices;
        $this->permissions = $permissions;
    }

    /**
     * Entra en la Entidad (o vuelve: se restaura su pertenencia anterior) con
     * el rol por defecto.
     */
    public function join(User $user, Entity $entity, ?User $by = null): Worker
    {
        return DB::transaction(function () use ($user, $entity) {
            $worker = Worker::withTrashed()->where('user_id', $user->id)->where('entity_id', $entity->id)->lockForUpdate()->first();

            if ($worker && ! $worker->trashed()) {
                throw JsonApiException::conflict('ALREADY_MEMBER', 'Ya pertenece a esa Entidad.');
            }

            if ($worker) {
                $worker->forceFill(['deleted_at' => null, 'itinerary_id' => null, 'stop_id' => null, 'itinerary_assigned_at' => null])->save();
            } else {
                $worker = Worker::create(['user_id' => $user->id, 'entity_id' => $entity->id]);
            }

            if ($default = Role::defaultRole()) {
                $this->grantRole($worker, $default, null);
            }

            // Ya no hace falta lo que tuviera pedido para entrar.
            Application::where('user_id', $user->id)->where('entity_id', $entity->id)
                ->where('type', Application::TYPE_ENTITY_MEMBERSHIP)->where('status', Application::STATUS_PENDING)
                ->update(['status' => Application::STATUS_CANCELLED, 'updated_at' => Carbon::now()]);

            $user->refreshMemberships();

            return $worker->fresh();
        });
    }

    /**
     * Baja de la Entidad: se borran su itinerario, su parada y sus roles en
     * ella. Para volver hay que solicitarlo de nuevo. $by es quien la da.
     */
    public function leave(Worker $worker, ?User $by = null): void
    {
        DB::transaction(function () use ($worker, $by) {
            $userId = (int) $worker->user_id;
            $self = ! $by || (int) $by->id === $userId;

            foreach (WorkerRole::where('worker_id', $worker->id)->get() as $workerRole) {
                $workerRole->delete();
            }

            Application::where('user_id', $userId)->where('entity_id', $worker->entity_id)
                ->where('status', Application::STATUS_PENDING)
                ->update(['status' => Application::STATUS_CANCELLED, 'updated_at' => Carbon::now()]);

            $worker->forceFill(['itinerary_id' => null, 'stop_id' => null, 'itinerary_assigned_at' => null])->save();
            $worker->delete();
            $this->permissions->flush($userId);
            $this->afterDriveLost($worker);

            if (! $self) {
                $this->notices->send([$userId], Notice::TYPE_ENTITY_REMOVED, null, null, null,
                    ['entity' => $this->entityName($worker), 'by' => $by->fullName()]);
            }
        });
    }

    /**
     * Desactivar o reactivar la pertenencia (conserva itinerario y roles).
     */
    public function setActive(Worker $worker, bool $active): Worker
    {
        DB::transaction(function () use ($worker, $active) {
            if ($active) {
                if ($worker->trashed()) {
                    $worker->restore();
                }
            } elseif (! $worker->trashed()) {
                $worker->delete();
                $this->afterDriveLost($worker);
            }

            $this->permissions->flush((int) $worker->user_id);
        });

        return Worker::withTrashed()->find($worker->id);
    }

    /**
     * Itinerario y parada (siempre juntos). Pierde el anterior en esa Entidad;
     * cambiar de itinerario no quita jefaturas.
     */
    public function assignItinerary(Worker $worker, int $itineraryId, int $stopId, ?User $by = null, string $pointer = '/data/relationships/itinerary'): Worker
    {
        $itinerary = Itinerary::find($itineraryId);

        if (! $itinerary || (int) $itinerary->entity_id !== (int) $worker->entity_id) {
            throw new JsonApiException(422, 'ENTITY_MISMATCH', 'De otra Entidad', 'El itinerario no es de esa Entidad.', ['pointer' => $pointer]);
        }

        if (! ItineraryStop::where('itinerary_id', $itineraryId)->where('stop_id', $stopId)->exists()) {
            throw new JsonApiException(422, 'STOP_NOT_IN_ITINERARY', 'Parada no válida', 'La parada no pertenece a ese itinerario.', ['pointer' => '/data/relationships/stop']);
        }

        DB::transaction(function () use ($worker, $itineraryId, $stopId, $by, $itinerary) {
            $changedItinerary = (int) $worker->itinerary_id !== $itineraryId;
            $worker->itinerary_id = $itineraryId;
            $worker->stop_id = $stopId;

            if ($changedItinerary || ! $worker->itinerary_assigned_at) {
                $worker->itinerary_assigned_at = Carbon::now();
            }

            $worker->save();

            Application::where('user_id', $worker->user_id)->where('entity_id', $worker->entity_id)
                ->where('type', Application::TYPE_ITINERARY_MEMBERSHIP)->where('status', Application::STATUS_PENDING)
                ->update(['status' => Application::STATUS_CANCELLED, 'updated_at' => Carbon::now()]);

            $this->permissions->flush((int) $worker->user_id);

            if ($by && (int) $by->id !== (int) $worker->user_id) {
                $stop = \App\Models\Stop::find($stopId);
                $this->notices->send([(int) $worker->user_id], Notice::TYPE_ITINERARY_ASSIGNED, null, null, null, [
                    'itinerary' => $itinerary->name, 'stop' => $stop ? $stop->landmark : null, 'by' => $by->fullName(),
                ]);
            }
        });

        return $worker->fresh();
    }

    /**
     * Darse de baja del itinerario (o que se lo quite quien tenga permiso).
     */
    public function removeItinerary(Worker $worker, ?User $by = null, string $reason = 'manual'): void
    {
        if (! $worker->itinerary_id) {
            throw JsonApiException::conflict('NO_ITINERARY', 'No tiene itinerario en esa Entidad.');
        }

        $itinerary = Itinerary::withTrashed()->find($worker->itinerary_id);
        $worker->forceFill(['itinerary_id' => null, 'stop_id' => null, 'itinerary_assigned_at' => null])->save();
        $this->permissions->flush((int) $worker->user_id);

        if ($by && (int) $by->id !== (int) $worker->user_id) {
            $this->notices->send([(int) $worker->user_id], Notice::TYPE_ITINERARY_REMOVED, null, null, null, [
                'itinerary' => $itinerary ? $itinerary->name : null, 'by' => $by->fullName(),
            ]);
        }
    }

    /**
     * Asigna un rol en la Entidad de la pertenencia (con su itinerario si el
     * rol es por itinerario).
     */
    public function assignRole(Worker $worker, Role $role, ?int $itineraryId, ?User $by = null): WorkerRole
    {
        $this->validateRoleItinerary($worker, $role, $itineraryId);

        if (WorkerRole::where('worker_id', $worker->id)->where('role_id', $role->id)->exists()) {
            throw JsonApiException::conflict('ALREADY_HAS_ROLE', 'Ya tiene ese rol en esa Entidad.');
        }

        return DB::transaction(function () use ($worker, $role, $itineraryId, $by) {
            $workerRole = $this->grantRole($worker, $role, $role->itinerary_scoped ? $itineraryId : null);

            // Ya no hace falta lo que tuviera pedido.
            Application::where('user_id', $worker->user_id)->where('entity_id', $worker->entity_id)
                ->where('type', Application::TYPE_ROLE)->where('role_id', $role->id)->where('status', Application::STATUS_PENDING)
                ->update(['status' => Application::STATUS_CANCELLED, 'updated_at' => Carbon::now()]);

            if ($by && (int) $by->id !== (int) $worker->user_id) {
                $this->notices->send([(int) $worker->user_id], Notice::TYPE_ROLE_ASSIGNED, null, null, null, $this->rolePayload($workerRole, $by));
            }

            return $workerRole;
        });
    }

    /**
     * Quita un rol (darse de baja o quitárselo a otro).
     */
    public function removeRole(WorkerRole $workerRole, ?User $by = null): void
    {
        DB::transaction(function () use ($workerRole, $by) {
            $worker = Worker::withTrashed()->find($workerRole->worker_id);
            $payload = $this->rolePayload($workerRole, $by);
            $workerRole->delete();
            $this->permissions->flush((int) $worker->user_id);
            $this->afterDriveLost($worker);

            if ($by && (int) $by->id !== (int) $worker->user_id) {
                $this->notices->send([(int) $worker->user_id], Notice::TYPE_ROLE_REMOVED, null, null, null, $payload);
            } else {
                // Avisa a quien puede asignar ese rol en la Entidad.
                $this->notices->send($this->permissions->userIdsWith('roles.assign', (int) $worker->entity_id), Notice::TYPE_RESIGNATION,
                    null, null, (int) $worker->user_id, $payload + ['person' => $worker->fullName()]);
            }
        });
    }

    /**
     * Si la pertenencia ya no puede conducir: deja de ser chofer habitual y se
     * avisa de los viajes pendientes que necesitan otro chofer.
     */
    public function afterDriveLost(Worker $worker): void
    {
        $user = User::withTrashed()->find($worker->user_id);
        $this->permissions->flush((int) $worker->user_id);

        if ($user && ! $worker->trashed() && ! $user->trashed() && $this->permissions->can($user, 'tracking.drive', (int) $worker->entity_id)) {
            return;
        }

        Vehicle::where('driver_id', $worker->id)->update(['driver_id' => null]);
        $trips = Trip::where('driver_id', $worker->id)
            ->whereIn('status', [Trip::STATUS_UNCONFIRMED, Trip::STATUS_CONFIRMED])
            ->where('departs_at', '>', Carbon::now())
            ->get();

        foreach ($trips as $trip) {
            $this->notices->send($this->permissions->userIdsWith('trips.edit', null, (int) $trip->itinerary_id), Notice::TYPE_TRIP_NEEDS_REASSIGNMENT, null, (int) $trip->id);
        }
    }

    /**
     * El conductor de un viaje: pertenencia activa con tracking.drive en su Entidad.
     */
    public function canDrive(?Worker $worker): bool
    {
        if (! $worker || $worker->trashed()) {
            return false;
        }

        $user = $worker->user;

        return $user && ! $user->trashed() && $this->permissions->can($user, 'tracking.drive', (int) $worker->entity_id);
    }

    public function validateRoleItinerary(Worker $worker, Role $role, ?int $itineraryId): void
    {
        if (! $role->itinerary_scoped) {
            return;
        }

        if ($itineraryId === null) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Falta el itinerario', 'Ese rol se asigna con un itinerario.', ['pointer' => '/data/relationships/itinerary']);
        }

        if ((int) Itinerary::whereKey($itineraryId)->value('entity_id') !== (int) $worker->entity_id) {
            throw new JsonApiException(422, 'ENTITY_MISMATCH', 'De otra Entidad', 'El itinerario no es de esa Entidad.', ['pointer' => '/data/relationships/itinerary']);
        }
    }

    private function grantRole(Worker $worker, Role $role, ?int $itineraryId): WorkerRole
    {
        $workerRole = WorkerRole::withTrashed()->firstOrNew(['worker_id' => $worker->id, 'role_id' => $role->id]);
        $workerRole->itinerary_id = $itineraryId;
        $workerRole->deleted_at = null;
        $workerRole->save();
        $this->permissions->flush((int) $worker->user_id);

        return $workerRole;
    }

    private function rolePayload(WorkerRole $workerRole, ?User $by): array
    {
        $role = Role::withTrashed()->find($workerRole->role_id);
        $itinerary = $workerRole->itinerary_id ? Itinerary::withTrashed()->find($workerRole->itinerary_id) : null;
        $worker = Worker::withTrashed()->find($workerRole->worker_id);

        return [
            'role' => $role ? $role->name : null,
            'itinerary' => $itinerary ? $itinerary->name : null,
            'entity' => $worker ? $this->entityName($worker) : null,
            'by' => $by ? $by->fullName() : null,
        ];
    }

    private function entityName(Worker $worker): ?string
    {
        $entity = Entity::withTrashed()->find($worker->entity_id);

        return $entity ? $entity->abbreviation : null;
    }
}
