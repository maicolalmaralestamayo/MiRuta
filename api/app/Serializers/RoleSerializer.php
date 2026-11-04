<?php

namespace App\Serializers;

use App\Models\RoleApprover;
use App\Models\RolePermission;
use App\Models\WorkerRole;
use App\Services\Permissions;
use App\Support\Operations;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Rol configurable. Las operaciones y los aprobadores los ve quien tiene
 * roles.view (o roles.manage).
 */
class RoleSerializer extends Serializer
{
    /** Id del rol fijo del Administrador. */
    const ADMIN_ID = 'admin';

    public function type(): string
    {
        return 'roles';
    }

    public function attributes(Model $role, Request $request): array
    {
        $attributes = [
            'name' => $role->name,
            'icon' => $role->icon,
            'requestable' => (bool) $role->requestable,
            'isDefault' => (bool) $role->is_default,
            'itineraryScoped' => (bool) $role->itinerary_scoped,
            'isAdministrator' => false,
            'editable' => true,
        ];

        if (self::canSeeDetails($request)) {
            $attributes['permissions'] = RolePermission::where('role_id', $role->id)->orderBy('operation')->get(['operation', 'scope'])
                ->map(function ($permission) {
                    return ['operation' => $permission->operation, 'scope' => $permission->scope];
                })->all();
            $attributes['approverRoleIds'] = RoleApprover::where('role_id', $role->id)->pluck('approver_role_id')->map(function ($id) {
                return (string) $id;
            })->all();
            $attributes['holderCount'] = WorkerRole::where('role_id', $role->id)->whereHas('worker')->count();
        }

        return $attributes;
    }

    /**
     * El Administrador como rol virtual de solo lectura.
     */
    public static function administrator(): array
    {
        $attributes = [
            'name' => 'Administrador',
            'icon' => 'admin_panel_settings',
            'requestable' => false,
            'isDefault' => false,
            'itineraryScoped' => false,
            'isAdministrator' => true,
            'editable' => false,
        ];

        if (self::canSeeDetails(app('request'))) {
            $attributes['permissions'] = array_map(function ($operation) {
                return ['operation' => $operation, 'scope' => Operations::SCOPE_ALL];
            }, Operations::keys());
            $attributes['approverRoleIds'] = [];
            $attributes['holderCount'] = \App\Models\User::where('is_admin', true)->count();
        }

        return [
            'type' => 'roles',
            'id' => self::ADMIN_ID,
            'attributes' => $attributes,
            'links' => ['self' => url('api/v1/roles/'.self::ADMIN_ID)],
        ];
    }

    private static function canSeeDetails(Request $request): bool
    {
        $user = $request->user();
        $permissions = app(Permissions::class);

        return $user && ($permissions->can($user, 'roles.view') || $permissions->can($user, 'roles.manage'));
    }
}
