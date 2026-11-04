<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\ConversationTopic;
use App\Models\Role;
use App\Models\RoleApprover;
use App\Models\RolePermission;
use App\Models\User;
use App\Models\Worker;
use App\Models\WorkerRole;
use App\Support\Operations;
use Illuminate\Support\Facades\DB;

/**
 * Roles configurables (docs/11 §11.16): los crea, edita y elimina quien
 * tiene roles.manage; elegir el rol por defecto, roles.set_default. El
 * Administrador es un rol fijo (users.is_admin) que no se edita.
 */
class Roles
{
    /** @var Permissions */
    private $permissions;

    /** @var Memberships */
    private $memberships;

    public function __construct(Permissions $permissions, Memberships $memberships)
    {
        $this->permissions = $permissions;
        $this->memberships = $memberships;
    }

    /**
     * @param array $attributes atributos JSON:API ya validados en su forma
     */
    public function save(User $actor, ?Role $role, array $attributes): Role
    {
        $creating = $role === null;
        $role = $role ?: new Role();

        if (array_key_exists('isDefault', $attributes) && (bool) $attributes['isDefault'] !== (bool) $role->is_default) {
            $this->permissions->authorize($actor, 'roles.set_default', null, null, 'No puede elegir el rol por defecto.');
        }

        if (! $creating && array_key_exists('itineraryScoped', $attributes) && (bool) $attributes['itineraryScoped'] !== (bool) $role->itinerary_scoped
            && WorkerRole::where('role_id', $role->id)->exists()) {
            throw JsonApiException::conflict('ROLE_IN_USE', 'Hay personas con este rol: no se puede cambiar si se asigna con un itinerario.', '/data/attributes/itineraryScoped');
        }

        $permissions = array_key_exists('permissions', $attributes) ? $this->validatePermissions($attributes['permissions']) : null;
        $approvers = array_key_exists('approverRoleIds', $attributes) ? $this->validateApprovers($attributes['approverRoleIds'], $role) : null;

        return DB::transaction(function () use ($role, $attributes, $permissions, $approvers, $creating) {
            $hadDrive = ! $creating && RolePermission::where('role_id', $role->id)->where('operation', 'tracking.drive')->exists();

            foreach (['name' => 'name', 'icon' => 'icon', 'requestable' => 'requestable', 'isDefault' => 'is_default', 'itineraryScoped' => 'itinerary_scoped'] as $attribute => $column) {
                if (array_key_exists($attribute, $attributes)) {
                    $value = $attributes[$attribute];
                    $role->{$column} = is_string($value) ? (trim($value) === '' ? null : trim($value)) : $value;
                }
            }

            $role->save();

            if ($role->is_default) {
                Role::where('id', '<>', $role->id)->where('is_default', true)->update(['is_default' => false]);
            }

            if ($permissions !== null) {
                RolePermission::where('role_id', $role->id)->whereNotIn('operation', array_keys($permissions))->delete();

                foreach ($permissions as $operation => $scope) {
                    $permission = RolePermission::withTrashed()->firstOrNew(['role_id' => $role->id, 'operation' => $operation]);
                    $permission->scope = $scope;
                    $permission->deleted_at = null;
                    $permission->save();
                }
            }

            if ($approvers !== null) {
                RoleApprover::where('role_id', $role->id)->whereNotIn('approver_role_id', $approvers)->delete();

                foreach ($approvers as $approverId) {
                    $approver = RoleApprover::withTrashed()->firstOrNew(['role_id' => $role->id, 'approver_role_id' => $approverId]);
                    $approver->deleted_at = null;
                    $approver->save();
                }
            }

            $this->permissions->flush();

            if ($hadDrive && ($permissions !== null && ! isset($permissions['tracking.drive']))) {
                foreach (WorkerRole::where('role_id', $role->id)->pluck('worker_id') as $workerId) {
                    $this->memberships->afterDriveLost(Worker::withTrashed()->find($workerId));
                }
            }

            return $role->fresh();
        });
    }

    /**
     * Eliminar un rol aunque lo tengan personas: lo pierden (aviso de rol quitado).
     */
    public function delete(User $actor, Role $role): void
    {
        DB::transaction(function () use ($actor, $role) {
            foreach (WorkerRole::where('role_id', $role->id)->get() as $workerRole) {
                $this->memberships->removeRole($workerRole, $actor);
            }

            RoleApprover::where('role_id', $role->id)->orWhere('approver_role_id', $role->id)->delete();
            RolePermission::where('role_id', $role->id)->delete();
            ConversationTopic::where('role_id', $role->id)->delete();
            \App\Models\Application::where('role_id', $role->id)->where('status', \App\Models\Application::STATUS_PENDING)
                ->update(['status' => \App\Models\Application::STATUS_CANCELLED]);
            $role->delete();
            $this->permissions->flush();
        });
    }

    /**
     * @return array [operación => ámbito]
     */
    private function validatePermissions($permissions): array
    {
        $pointer = '/data/attributes/permissions';

        if (! is_array($permissions)) {
            throw $this->invalid('Las operaciones deben ser una lista de {operation, scope}.', $pointer);
        }

        $result = [];

        foreach (array_values($permissions) as $index => $permission) {
            $operation = is_array($permission) && isset($permission['operation']) ? $permission['operation'] : null;
            $scope = is_array($permission) && isset($permission['scope']) ? $permission['scope'] : null;

            if (! is_string($operation) || ! Operations::exists($operation)) {
                throw $this->invalid('No existe la operación indicada.', "{$pointer}/{$index}/operation", 'OPERATION_UNKNOWN');
            }

            if (! is_string($scope) || ! Operations::allows($operation, $scope)) {
                throw $this->invalid('Ámbito no válido para '.$operation.'. Puede ser: '.implode(', ', Operations::scopesOf($operation)).'.', "{$pointer}/{$index}/scope", 'SCOPE_NOT_ALLOWED');
            }

            $result[$operation] = $scope;
        }

        return $result;
    }

    /**
     * @return int[]
     */
    private function validateApprovers($ids, Role $role): array
    {
        $pointer = '/data/attributes/approverRoleIds';

        if (! is_array($ids)) {
            throw $this->invalid('Los roles aprobadores deben ser una lista de ids.', $pointer);
        }

        $ids = array_values(array_unique(array_map('intval', $ids)));

        if ($ids && Role::whereIn('id', $ids)->count() !== count($ids)) {
            throw $this->invalid('Alguno de los roles aprobadores no existe.', $pointer);
        }

        return $ids;
    }

    private function invalid(string $detail, string $pointer, string $code = 'VALIDATION_ERROR'): JsonApiException
    {
        return new JsonApiException(422, $code, 'Rol no válido', $detail, ['pointer' => $pointer]);
    }
}
