<?php

namespace Database\Seeders;

use App\Models\Role;
use App\Models\RoleApprover;
use App\Models\RolePermission;
use Illuminate\Database\Seeder;

/**
 * Roles de partida (docs/11 §11.15), editables después. El Administrador no
 * es un rol de esta tabla (users.is_admin).
 *
 * Solo se crean si no existen: volver a ejecutar el seeder no deshace lo
 * que el Administrador haya cambiado.
 */
class RoleSeeder extends Seeder
{
    const WORKER = 'Trabajador';
    const DRIVER = 'Chofer';
    const ITINERARY_CHIEF = 'Jefe de itinerario';
    const TRANSPORT_CHIEF = 'Jefe de Transporte';

    public function run()
    {
        if (Role::withTrashed()->exists()) {
            return;
        }

        $this->role(self::WORKER, 'badge', false, true, false, [
            'trips.view' => 'own',
            'tracking.view_live' => 'own',
            'children.view' => 'own',
        ]);

        $transportChief = $this->role(self::TRANSPORT_CHIEF, 'manage_accounts', true, false, false, [
            'vehicles.view' => 'entity',
            'vehicles.manage' => 'entity',
            'vehicles.assign_driver' => 'entity',
            'trips.view' => 'entity',
            'trips.plan' => 'entity',
            'trips.edit' => 'entity',
            'trips.confirm_cancel' => 'entity',
            'trips.delete' => 'entity',
            'trips.complete' => 'entity',
            // Solo aprueba y asigna los roles que lo tienen como aprobador (Chofer).
            'roles.approve' => 'entity',
            'roles.assign' => 'entity',
            'workers.view' => 'entity',
            'itineraries.view' => 'entity',
            'tracking.view_live' => 'entity',
            'chat.role_conversations' => 'entity',
            'statistics.view' => 'entity',
        ]);

        $driver = $this->role(self::DRIVER, 'directions_bus', true, false, false, [
            'tracking.drive' => 'entity',
            'tracking.scan_boarding' => 'entity',
            'tracking.allow_outsiders' => 'entity',
            'tracking.fix_passengers' => 'entity',
            'trips.view' => 'entity',
            'vehicles.view' => 'entity',
        ]);

        $this->role(self::ITINERARY_CHIEF, 'route', true, false, true, [
            'members.approve' => 'itinerary',
            'trips.view' => 'itinerary',
            'trips.plan' => 'itinerary',
            'trips.edit' => 'itinerary',
            'trips.confirm_cancel' => 'itinerary',
            'trips.complete' => 'itinerary',
            'tracking.scan_boarding' => 'itinerary',
            'tracking.allow_outsiders' => 'itinerary',
            'tracking.fix_passengers' => 'itinerary',
            'tracking.view_live' => 'itinerary',
            'workers.view' => 'itinerary',
            'workers.view_identity_card' => 'itinerary',
            'workers.printed_qr' => 'itinerary',
            'absences.view' => 'itinerary',
            'itineraries.view' => 'itinerary',
            'itineraries.reference_route' => 'itinerary',
            'chat.role_conversations' => 'itinerary',
            'statistics.view' => 'itinerary',
        ]);

        // Chofer: lo aprueban el Jefe de Transporte de la Entidad y el
        // Administrador (que siempre puede). Jefe de itinerario y Jefe de
        // Transporte: solo el Administrador (sin roles aprobadores).
        RoleApprover::create(['role_id' => $driver->id, 'approver_role_id' => $transportChief->id]);
    }

    private function role(string $name, string $icon, bool $requestable, bool $isDefault, bool $itineraryScoped, array $permissions): Role
    {
        $role = Role::create([
            'name' => $name, 'icon' => $icon, 'requestable' => $requestable,
            'is_default' => $isDefault, 'itinerary_scoped' => $itineraryScoped,
        ]);

        foreach ($permissions as $operation => $scope) {
            RolePermission::create(['role_id' => $role->id, 'operation' => $operation, 'scope' => $scope]);
        }

        return $role;
    }
}
