<?php

use App\Models\Notice;
use App\Models\Role;
use App\Models\Trip;
use App\Models\Vehicle;
use App\Models\WorkerRole;
use App\Services\Permissions;
use Laravel\Lumen\Testing\DatabaseMigrations;

/**
 * Roles configurables y permisos por ámbito (docs/11 §11.15 y §11.16).
 */
class RolesTest extends TestCase
{
    use DatabaseMigrations;

    private $east;
    private $west;
    private $chief;
    private $vehicle;
    private $driver;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
        $this->east = $this->createItinerary('Ruta Este');
        $this->west = $this->createItinerary('Ruta Oeste');
        $this->chief = $this->createItineraryChief($this->east);
        $this->driver = $this->createDriver();
        $this->vehicle = $this->createVehicle(null, 10, 0);
    }

    private function trip($itinerary, string $departs = '2026-12-01T17:00:00Z', string $returns = '2026-12-02T06:00:00Z'): array
    {
        return ['type' => 'trips', 'attributes' => ['departsAt' => $departs, 'returnsAt' => $returns, 'status' => 'confirmed'], 'relationships' => [
            'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $itinerary->id]],
            'vehicle' => ['data' => ['type' => 'vehicles', 'id' => (string) $this->vehicle->id]],
            'driver' => ['data' => ['type' => 'workers', 'id' => (string) $this->driver->id]],
        ]];
    }

    private function roleDocument(array $attributes, $id = null): array
    {
        $data = ['type' => 'roles', 'attributes' => $attributes];

        if ($id !== null) {
            $data['id'] = (string) $id;
        }

        return ['data' => $data];
    }

    private function assignVia($actor, $worker, Role $role, $itinerary = null)
    {
        $relationships = [
            'worker' => ['data' => ['type' => 'workers', 'id' => (string) $worker->id]],
            'role' => ['data' => ['type' => 'roles', 'id' => (string) $role->id]],
        ];

        if ($itinerary) {
            $relationships['itinerary'] = ['data' => ['type' => 'itineraries', 'id' => (string) $itinerary->id]];
        }

        return $this->jsonApiAs($actor, 'POST', '/api/v1/worker-roles', ['data' => ['type' => 'worker-roles', 'relationships' => $relationships]]);
    }

    public function testElJefeDeItinerarioPlanificaSoloSuItinerario()
    {
        $this->jsonApiAs($this->chief, 'POST', '/api/v1/trips', ['data' => $this->trip($this->east)]);
        $this->assertResponseStatus(201);
        $tripId = $this->responseJson()['data']['id'];

        $this->jsonApiAs($this->chief, 'POST', '/api/v1/trips', ['data' => $this->trip($this->west)]);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        // No puede llevarse un viaje suyo a otro itinerario.
        $this->jsonApiAs($this->chief, 'PATCH', '/api/v1/trips/'.$tripId, ['data' => ['type' => 'trips', 'id' => $tripId, 'relationships' => [
            'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $this->west->id]],
        ]]]);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        // Ni ve los de otro itinerario.
        $other = Trip::create(['itinerary_id' => $this->west->id, 'vehicle_id' => $this->vehicle->id, 'driver_id' => $this->driver->id,
            'departs_at' => '2026-12-05 17:00', 'returns_at' => '2026-12-06 06:00', 'status' => 'unconfirmed', 'created_by' => $this->chief->user_id]);
        $this->jsonApiAs($this->chief, 'PATCH', '/api/v1/trips/'.$other->id, ['data' => ['type' => 'trips', 'id' => (string) $other->id, 'attributes' => ['status' => 'confirmed']]]);
        $this->assertJsonApiError(404, 'NOT_FOUND');

        // Rango con operaciones atómicas en su itinerario.
        $this->jsonApiAs($this->chief, 'POST', '/api/v1/operations', ['atomic:operations' => [
            ['op' => 'add', 'data' => $this->trip($this->east, '2026-12-10T17:00:00Z', '2026-12-11T06:00:00Z')],
            ['op' => 'add', 'data' => $this->trip($this->east, '2026-12-11T17:00:00Z', '2026-12-12T06:00:00Z')],
        ]], ['Content-Type' => 'application/vnd.api+json; ext="https://jsonapi.org/ext/atomic"']);
        $this->assertResponseOk();

        // Un trabajador sin esos permisos no planifica.
        $this->jsonApiAs($this->createWorker(), 'POST', '/api/v1/trips', ['data' => $this->trip($this->east)]);
        $this->assertJsonApiError(403, 'FORBIDDEN');
    }

    public function testElJefeDeTransportePlanificaTodaSuEntidadYElAdministradorTodo()
    {
        $transportChief = $this->createTransportChief();

        $this->jsonApiAs($transportChief, 'POST', '/api/v1/trips', ['data' => $this->trip($this->west)]);
        $this->assertResponseStatus(201);

        $this->jsonApiAs($this->createAdmin(), 'POST', '/api/v1/trips', ['data' => $this->trip($this->east, '2026-12-03T17:00:00Z', '2026-12-04T06:00:00Z')]);
        $this->assertResponseStatus(201);

        // En otra Entidad no.
        $other = $this->createTransportChief([], $this->createEntity('OTRA'));
        $this->jsonApiAs($other, 'POST', '/api/v1/trips', ['data' => $this->trip($this->east, '2026-12-07T17:00:00Z', '2026-12-08T06:00:00Z')]);
        $this->assertJsonApiError(403, 'FORBIDDEN');
    }

    public function testEliminarViajesSoloConTripsDelete()
    {
        $trip = Trip::create(['itinerary_id' => $this->east->id, 'vehicle_id' => $this->vehicle->id, 'driver_id' => $this->driver->id,
            'departs_at' => '2026-12-05 17:00', 'returns_at' => '2026-12-06 06:00', 'status' => 'unconfirmed', 'created_by' => $this->chief->user_id]);

        $this->jsonApiAs($this->chief, 'DELETE', '/api/v1/trips/'.$trip->id);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->jsonApiAs($this->createTransportChief(), 'DELETE', '/api/v1/trips/'.$trip->id);
        $this->assertResponseStatus(204);
        $this->assertTrue(Trip::withTrashed()->find($trip->id)->trashed());
    }

    public function testElChoferDelViajeEsUnaPertenenciaQuePuedeConducir()
    {
        $notDriver = $this->createWorker();
        $data = $this->trip($this->east);
        $data['relationships']['driver']['data']['id'] = (string) $notDriver->id;

        $this->jsonApiAs($this->createAdmin(), 'POST', '/api/v1/trips', ['data' => $data]);

        $this->assertJsonApiError(422, 'NOT_A_DRIVER', '/data/relationships/driver');
    }

    public function testAmbitosDeLosPermisos()
    {
        $permissions = app(Permissions::class);
        $chief = $this->userOf($this->chief);
        $entity = $this->defaultEntity()->id;

        // Itinerario: el del rol por itinerario.
        $this->assertTrue($permissions->can($chief, 'trips.plan', null, $this->east->id));
        $this->assertFalse($permissions->can($chief, 'trips.plan', null, $this->west->id));
        $this->assertFalse($permissions->can($chief, 'trips.plan', $entity));
        // Entidad: en la Entidad donde tiene el rol.
        $driver = $this->userOf($this->driver);
        $this->assertTrue($permissions->can($driver, 'tracking.drive', $entity));
        $this->assertFalse($permissions->can($driver, 'tracking.drive', $this->createEntity('OTRA')->id));
        // Propio: no cuenta para can(), sí para canOwn().
        $this->assertFalse($permissions->can($driver, 'tracking.view_live', $entity));
        $this->assertTrue($permissions->canOwn($driver, 'tracking.view_live', $entity));
        // Todas: el Administrador.
        $this->assertTrue($permissions->can($this->createAdmin(), 'maintenance.run'));

        // Un rol con ámbito «itinerario» sin ser por itinerario usa el itinerario del que es miembro.
        $role = Role::create(['name' => 'Ayudante']);
        $role->permissions()->create(['operation' => 'trips.view', 'scope' => 'itinerary']);
        $member = $this->joinItinerary($this->createWorker(), $this->west);
        $this->assignRole($member, 'Ayudante');
        $this->assertTrue($permissions->can($this->userOf($member), 'trips.view', null, $this->west->id));
        $this->assertFalse($permissions->can($this->userOf($member), 'trips.view', null, $this->east->id));
    }

    public function testGestionDeRoles()
    {
        $admin = $this->createAdmin();
        $transportChief = $this->createTransportChief();

        // Lista con el Administrador como rol fijo; las operaciones solo con roles.view.
        $this->jsonApiAs($this->createWorker(), 'GET', '/api/v1/roles');
        $this->assertResponseOk();
        $this->assertSame('admin', $this->responseJson()['data'][0]['id']);
        $this->assertArrayNotHasKey('permissions', $this->responseJson()['data'][1]['attributes']);

        $this->jsonApiAs($admin, 'GET', '/api/v1/roles');
        $roles = collect($this->responseJson()['data'])->keyBy('attributes.name');
        $this->assertFalse($roles['Administrador']['attributes']['editable']);
        $this->assertContains(['operation' => 'tracking.drive', 'scope' => 'entity'], $roles['Chofer']['attributes']['permissions']);
        $this->assertSame([(string) $this->role('Jefe de Transporte')->id], $roles['Chofer']['attributes']['approverRoleIds']);

        // Catálogo de operaciones.
        $this->jsonApiAs($admin, 'GET', '/api/v1/operations');
        $this->assertResponseOk();
        $this->assertSame(count(\App\Support\Operations::CATALOG), count($this->responseJson()['data']));
        $this->seeJson(['key' => 'workers.delete', 'scopes' => ['all']]);
        $this->jsonApiAs($transportChief, 'GET', '/api/v1/operations');
        $this->assertJsonApiError(403, 'FORBIDDEN');

        // Crear: solo roles.manage.
        $attributes = ['name' => 'Inspector', 'icon' => 'search', 'requestable' => true, 'itineraryScoped' => false,
            'permissions' => [['operation' => 'trips.view', 'scope' => 'entity'], ['operation' => 'statistics.view', 'scope' => 'entity']],
            'approverRoleIds' => [(string) $this->role('Jefe de Transporte')->id]];
        $this->jsonApiAs($transportChief, 'POST', '/api/v1/roles', $this->roleDocument($attributes));
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->jsonApiAs($admin, 'POST', '/api/v1/roles', $this->roleDocument($attributes));
        $this->assertResponseStatus(201);
        $id = $this->responseJson()['data']['id'];
        $this->seeJson(['name' => 'Inspector', 'requestable' => true, 'isDefault' => false]);

        // Ámbito que la operación no admite, u operación inexistente.
        $this->jsonApiAs($admin, 'PATCH', '/api/v1/roles/'.$id, $this->roleDocument(['permissions' => [['operation' => 'workers.delete', 'scope' => 'entity']]], $id));
        $this->assertJsonApiError(422, 'SCOPE_NOT_ALLOWED', '/data/attributes/permissions/0/scope');
        $this->jsonApiAs($admin, 'PATCH', '/api/v1/roles/'.$id, $this->roleDocument(['permissions' => [['operation' => 'no.existe', 'scope' => 'all']]], $id));
        $this->assertJsonApiError(422, 'OPERATION_UNKNOWN');

        // Nombre repetido.
        $this->jsonApiAs($admin, 'POST', '/api/v1/roles', $this->roleDocument(['name' => 'Chofer']));
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/name');

        // Rol por defecto: como mucho uno.
        $this->jsonApiAs($admin, 'PATCH', '/api/v1/roles/'.$id, $this->roleDocument(['isDefault' => true], $id));
        $this->assertResponseOk();
        $this->assertSame(['Inspector'], Role::where('is_default', true)->pluck('name')->all());

        // El Administrador no se edita ni se elimina.
        $this->jsonApiAs($admin, 'PATCH', '/api/v1/roles/admin', $this->roleDocument(['name' => 'Jefe'], 'admin'));
        $this->assertJsonApiError(403, 'ROLE_NOT_EDITABLE');
        $this->jsonApiAs($admin, 'DELETE', '/api/v1/roles/admin');
        $this->assertJsonApiError(403, 'ROLE_NOT_EDITABLE');
    }

    public function testEliminarUnRolSeLoQuitaAQuienLoTiene()
    {
        $admin = $this->createAdmin();
        $role = $this->role('Chofer');
        $this->vehicle->forceFill(['driver_id' => $this->driver->id])->save();

        $this->jsonApiAs($admin, 'DELETE', '/api/v1/roles/'.$role->id);

        $this->assertResponseStatus(204);
        $this->assertTrue(Role::withTrashed()->find($role->id)->trashed());
        $this->assertSame(0, WorkerRole::where('role_id', $role->id)->count());
        $this->assertSame(1, Notice::where('user_id', $this->driver->user_id)->where('type', 'role_removed')->count());
        $this->assertFalse(app(Permissions::class)->can($this->userOf($this->driver)->fresh(), 'tracking.drive', $this->driver->entity_id));
        // Deja de ser el chofer habitual.
        $this->assertNull(Vehicle::find($this->vehicle->id)->driver_id);
    }

    public function testElJefeDeTransporteAsignaYQuitaSoloElRolDeChofer()
    {
        $transportChief = $this->createTransportChief();
        $worker = $this->createWorker();

        $this->assignVia($transportChief, $worker, $this->role('Chofer'));
        $this->assertResponseStatus(201);
        $id = $this->responseJson()['data']['id'];
        $this->assertSame(1, Notice::where('user_id', $worker->user_id)->where('type', 'role_assigned')->count());

        $this->assignVia($transportChief, $worker, $this->role('Chofer'));
        $this->assertJsonApiError(409, 'ALREADY_HAS_ROLE');

        $this->assignVia($transportChief, $worker, $this->role('Jefe de itinerario'), $this->east);
        $this->assertJsonApiError(403, 'FORBIDDEN');
        $this->assignVia($transportChief, $worker, $this->role('Jefe de Transporte'));
        $this->assertJsonApiError(403, 'FORBIDDEN');

        // En otra Entidad, no.
        $outsider = $this->createWorker([], $this->createEntity('OTRA'));
        $this->assignVia($transportChief, $outsider, $this->role('Chofer'));
        $this->assertJsonApiError(403, 'FORBIDDEN');

        // El Jefe de itinerario no asigna nada directamente.
        $this->assignVia($this->chief, $this->createWorker(), $this->role('Chofer'));
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->jsonApiAs($transportChief, 'DELETE', '/api/v1/worker-roles/'.$id);
        $this->assertResponseStatus(204);
        $this->assertSame(1, Notice::where('user_id', $worker->user_id)->where('type', 'role_removed')->count());
    }

    public function testDarseDeBajaDeUnRolDirectamente()
    {
        $id = WorkerRole::where('worker_id', $this->chief->id)->where('role_id', $this->role('Jefe de itinerario')->id)->value('id');

        $this->jsonApiAs($this->chief, 'DELETE', '/api/v1/worker-roles/'.$id);

        $this->assertResponseStatus(204);
        $this->assertFalse(app(Permissions::class)->can($this->userOf($this->chief)->fresh(), 'trips.plan', null, $this->east->id));
        // Sigue en su itinerario.
        $this->assertSame($this->east->id, (int) $this->chief->fresh()->itinerary_id);
    }

    public function testElAdministradorAsignaJefeDeItinerarioConSuItinerario()
    {
        $admin = $this->createAdmin();
        $worker = $this->createWorker();

        $this->assignVia($admin, $worker, $this->role('Jefe de itinerario'));
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/relationships/itinerary');

        $other = $this->createItinerary('Ruta Otra', 2, $this->createEntity('OTRA'));
        $this->assignVia($admin, $worker, $this->role('Jefe de itinerario'), $other);
        $this->assertJsonApiError(422, 'ENTITY_MISMATCH');

        $this->assignVia($admin, $worker, $this->role('Jefe de itinerario'), $this->west);
        $this->assertResponseStatus(201);

        // Un Jefe de itinerario lo es de un solo itinerario en cada Entidad.
        $this->assignVia($admin, $worker, $this->role('Jefe de itinerario'), $this->east);
        $this->assertJsonApiError(409, 'ALREADY_HAS_ROLE');
    }

    public function testVariosRolesEnElMeta()
    {
        $worker = $this->createDriver();
        $this->assignRole($worker, 'Jefe de itinerario', $this->west->id);

        $this->jsonApiAs($worker, 'GET', '/api/v1/workers/'.$worker->id);
        $roles = collect($this->responseJson()['data']['meta']['roles'])->keyBy('name');
        $this->assertSame(['Chofer', 'Jefe de itinerario', 'Trabajador'], $roles->keys()->sort()->values()->all());
        $this->assertSame((string) $this->west->id, $roles['Jefe de itinerario']['itineraryId']);
    }
}
