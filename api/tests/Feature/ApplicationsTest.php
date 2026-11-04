<?php

use App\Models\Application;
use App\Models\Notice;
use App\Models\Worker;
use App\Models\WorkerRole;
use Carbon\Carbon;
use Carbon\CarbonImmutable;
use Laravel\Lumen\Testing\DatabaseMigrations;

/**
 * Solicitudes (docs/11 §11.6 y §11.16): entrar en una Entidad, itinerario y
 * parada, y roles con sus aprobadores.
 */
class ApplicationsTest extends TestCase
{
    use DatabaseMigrations;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
        Carbon::setTestNow(Carbon::create(2026, 11, 2, 10));
        CarbonImmutable::setTestNow(CarbonImmutable::create(2026, 11, 2, 10));
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }

    private function apply($who, string $type, array $relationships = [], array $attributes = [])
    {
        $data = ['type' => 'applications', 'attributes' => ['type' => $type] + $attributes];

        foreach ($relationships as $name => list($jsonType, $id)) {
            $data['relationships'][$name] = ['data' => ['type' => $jsonType, 'id' => (string) $id]];
        }

        return $this->jsonApiAs($who, 'POST', '/api/v1/applications', ['data' => $data]);
    }

    private function resolve($who, $applicationId, string $status, ?string $note = null)
    {
        $attributes = ['status' => $status];

        if ($note !== null) {
            $attributes['resolutionNote'] = $note;
        }

        return $this->jsonApiAs($who, 'PATCH', '/api/v1/applications/'.$applicationId, ['data' => [
            'type' => 'applications', 'id' => (string) $applicationId, 'attributes' => $attributes,
        ]]);
    }

    private function lastId(): string
    {
        return $this->responseJson()['data']['id'];
    }

    public function testEntrarEnUnaEntidadLaApruebaSoloElAdministrador()
    {
        $admin = $this->createAdmin();
        $person = $this->createUser();
        $entity = $this->defaultEntity();
        $transportChief = $this->createTransportChief();

        $this->apply($person, 'entity_membership', [], ['entityAbbreviation' => ' prueba ']);
        $this->assertResponseStatus(201);
        $this->seeJson(['type' => 'entity_membership', 'status' => 'pending', 'entityAbbreviation' => 'PRUEBA']);
        $id = $this->lastId();
        $this->assertSame(1, Notice::where('user_id', $admin->id)->where('type', 'application_received')->count());

        // Repetida, o en una Entidad que no existe.
        $this->apply($person, 'entity_membership', ['entity' => ['entities', $entity->id]]);
        $this->assertJsonApiError(409, 'APPLICATION_ALREADY_PENDING');
        $this->apply($person, 'entity_membership', [], ['entityAbbreviation' => 'NOEXISTE']);
        $this->assertJsonApiError(422, 'ENTITY_NOT_FOUND');

        // El Jefe de Transporte no la ve ni la resuelve.
        $this->resolve($transportChief, $id, 'approved');
        $this->assertJsonApiError(404, 'NOT_FOUND');

        $this->resolve($admin, $id, 'approved');
        $this->assertResponseOk();
        $worker = Worker::where('user_id', $person->id)->first();
        $this->assertSame($entity->id, (int) $worker->entity_id);
        // Con el rol por defecto.
        $this->assertSame(['Trabajador'], WorkerRole::where('worker_id', $worker->id)->with('role')->get()->pluck('role.name')->all());
        $this->assertSame(1, Notice::where('user_id', $person->id)->where('type', 'application_resolved')->count());

        $this->apply($person, 'entity_membership', ['entity' => ['entities', $entity->id]]);
        $this->assertJsonApiError(409, 'ALREADY_MEMBER');
    }

    public function testAlRechazarElMotivoEsObligatorio()
    {
        $admin = $this->createAdmin();
        $person = $this->createUser();
        $this->apply($person, 'entity_membership', ['entity' => ['entities', $this->defaultEntity()->id]]);
        $id = $this->lastId();

        $this->resolve($admin, $id, 'rejected');
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/resolutionNote');

        $this->resolve($admin, $id, 'rejected', 'No trabaja aquí');
        $this->assertResponseOk();
        $this->seeJson(['status' => 'rejected', 'resolutionNote' => 'No trabaja aquí']);
        $this->assertSame(0, Worker::where('user_id', $person->id)->count());

        $notice = Notice::where('user_id', $person->id)->where('type', 'application_resolved')->first();
        $this->assertStringContainsString('Motivo: No trabaja aquí', \App\Support\NoticeText::for($notice));
    }

    public function testItinerarioYParadaLaApruebaElJefeDeEseItinerario()
    {
        $itinerary = $this->createItinerary('Ruta Este');
        $other = $this->createItinerary('Ruta Oeste');
        $chief = $this->createItineraryChief($itinerary);
        $otherChief = $this->createItineraryChief($other);
        $worker = $this->createWorker();
        $stop = $itinerary->stops[1];

        // Sin Entidad no se puede pedir itinerario.
        $this->apply($this->createUser(), 'itinerary_membership', ['itinerary' => ['itineraries', $itinerary->id], 'stop' => ['stops', $stop->id]]);
        $this->assertJsonApiError(409, 'NOT_A_MEMBER');

        // La parada tiene que ser del itinerario.
        $this->apply($worker, 'itinerary_membership', ['itinerary' => ['itineraries', $itinerary->id], 'stop' => ['stops', $other->stops[0]->id]]);
        $this->assertJsonApiError(422, 'STOP_NOT_IN_ITINERARY');

        $this->apply($worker, 'itinerary_membership', ['itinerary' => ['itineraries', $itinerary->id], 'stop' => ['stops', $stop->id]]);
        $this->assertResponseStatus(201);
        $id = $this->lastId();
        $this->assertSame(1, Notice::where('user_id', $chief->user_id)->where('type', 'application_received')->count());
        $this->assertSame(0, Notice::where('user_id', $otherChief->user_id)->count());

        // El Jefe de otro itinerario no la ve.
        $this->resolve($otherChief, $id, 'approved');
        $this->assertJsonApiError(404, 'NOT_FOUND');

        // El Jefe de este itinerario la ve en «por resolver» y ve el carné del solicitante.
        $this->jsonApiAs($chief, 'GET', '/api/v1/applications?filter[toResolve]=true&include=user');
        $this->assertSame([$id], array_column($this->responseJson()['data'], 'id'));
        $this->assertTrue($this->responseJson()['data'][0]['attributes']['canResolve']);
        $this->assertArrayHasKey('identityCard', $this->responseJson()['included'][0]['attributes']);

        $this->resolve($chief, $id, 'approved');
        $this->assertResponseOk();
        $worker = $worker->fresh();
        $this->assertSame($itinerary->id, (int) $worker->itinerary_id);
        $this->assertSame($stop->id, (int) $worker->stop_id);
        $this->assertNotNull($worker->itinerary_assigned_at);
    }

    public function testNadieResuelveSusPropiasSolicitudes()
    {
        $itinerary = $this->createItinerary();
        $chief = $this->createItineraryChief($itinerary);

        $this->apply($chief, 'itinerary_membership', ['itinerary' => ['itineraries', $itinerary->id], 'stop' => ['stops', $itinerary->stops[2]->id]]);
        $this->assertResponseStatus(201);

        $this->resolve($chief, $this->lastId(), 'approved');
        $this->assertJsonApiError(403, 'SELF_APPROVAL');
    }

    public function testCancelarSoloElSolicitante()
    {
        $admin = $this->createAdmin();
        $person = $this->createUser();
        $this->apply($person, 'entity_membership', ['entity' => ['entities', $this->defaultEntity()->id]]);
        $id = $this->lastId();

        $this->resolve($admin, $id, 'cancelled');
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->resolve($person, $id, 'cancelled');
        $this->assertResponseOk();
        $this->seeJson(['status' => 'cancelled']);

        $this->resolve($admin, $id, 'approved');
        $this->assertJsonApiError(409, 'APPLICATION_NOT_PENDING');
    }

    public function testElRolDeChoferLoApruebanElJefeDeTransporteYElAdministrador()
    {
        $worker = $this->createWorker();
        $transportChief = $this->createTransportChief();
        $otherEntityChief = $this->createTransportChief([], $this->createEntity('OTRA'));
        $itineraryChief = $this->createItineraryChief($this->createItinerary());
        $driver = $this->role('Chofer');

        $this->apply($worker, 'role', ['role' => ['roles', $driver->id]]);
        $this->assertResponseStatus(201);
        $id = $this->lastId();
        $this->seeJson(['roleName' => 'Chofer', 'entityAbbreviation' => 'PRUEBA']);
        $this->assertSame(1, Notice::where('user_id', $transportChief->user_id)->where('type', 'application_received')->count());

        $this->resolve($itineraryChief, $id, 'approved');
        $this->assertJsonApiError(404, 'NOT_FOUND');
        $this->resolve($otherEntityChief, $id, 'approved');
        $this->assertJsonApiError(404, 'NOT_FOUND');

        $this->resolve($transportChief, $id, 'approved');
        $this->assertResponseOk();
        $this->assertTrue(WorkerRole::where('worker_id', $worker->id)->where('role_id', $driver->id)->exists());
        $this->assertTrue(app(\App\Services\Permissions::class)->can($this->userOf($worker)->fresh(), 'tracking.drive', $worker->entity_id));

        $this->apply($worker, 'role', ['role' => ['roles', $driver->id]]);
        $this->assertJsonApiError(409, 'ALREADY_HAS_ROLE');
    }

    public function testJefeDeTransporteYJefeDeItinerarioLosApruebaSoloElAdministrador()
    {
        $admin = $this->createAdmin();
        $worker = $this->createWorker();
        $transportChief = $this->createTransportChief();
        $itinerary = $this->createItinerary();

        $this->apply($worker, 'role', ['role' => ['roles', $this->role('Jefe de Transporte')->id]]);
        $id = $this->lastId();
        $this->resolve($transportChief, $id, 'approved');
        $this->assertJsonApiError(404, 'NOT_FOUND');
        $this->resolve($admin, $id, 'approved');
        $this->assertResponseOk();

        // El de Jefe de itinerario se pide con el itinerario.
        $this->apply($worker, 'role', ['role' => ['roles', $this->role('Jefe de itinerario')->id]]);
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/relationships/itinerary');

        $this->apply($worker, 'role', ['role' => ['roles', $this->role('Jefe de itinerario')->id], 'itinerary' => ['itineraries', $itinerary->id]]);
        $this->assertResponseStatus(201);
        $id = $this->lastId();

        // El Jefe de Transporte (que ahora también es el trabajador) no la puede aprobar.
        $this->resolve($transportChief, $id, 'approved');
        $this->assertJsonApiError(404, 'NOT_FOUND');
        $this->resolve($admin, $id, 'approved');
        $this->assertResponseOk();
        $this->assertSame($itinerary->id, (int) WorkerRole::where('worker_id', $worker->id)->where('role_id', $this->role('Jefe de itinerario')->id)->value('itinerary_id'));
    }

    public function testElRolTrabajadorNoSeSolicita()
    {
        $worker = $this->createWorker();
        $this->createWorker(['user_id' => $worker->user_id], $this->createEntity('OTRA'));

        $this->apply($worker, 'role', ['role' => ['roles', $this->role('Trabajador')->id]]);
        $this->assertJsonApiError(422, 'ROLE_NOT_REQUESTABLE');

        // Si pertenece a varias Entidades, indica en cuál pide el rol.
        $this->apply($worker, 'role', ['role' => ['roles', $this->role('Chofer')->id]]);
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/relationships/entity');
        $this->apply($worker, 'role', ['role' => ['roles', $this->role('Chofer')->id], 'entity' => ['entities', $worker->entity_id]]);
        $this->assertResponseStatus(201);
    }

    public function testAprobadoresConfigurables()
    {
        $admin = $this->createAdmin();
        $worker = $this->createWorker();
        $itinerary = $this->createItinerary();
        $itineraryChief = $this->createItineraryChief($itinerary);
        $driver = $this->role('Chofer');

        // El Administrador añade al Jefe de itinerario como aprobador del Chofer
        // (y le da roles.approve en su Entidad).
        $this->jsonApiAs($admin, 'PATCH', '/api/v1/roles/'.$driver->id, ['data' => ['type' => 'roles', 'id' => (string) $driver->id, 'attributes' => [
            'approverRoleIds' => [(string) $this->role('Jefe de Transporte')->id, (string) $this->role('Jefe de itinerario')->id],
        ]]]);
        $this->assertResponseOk();
        \App\Models\RolePermission::create(['role_id' => $this->role('Jefe de itinerario')->id, 'operation' => 'roles.approve', 'scope' => 'entity']);

        $this->apply($worker, 'role', ['role' => ['roles', $driver->id]]);
        $this->resolve($itineraryChief, $this->lastId(), 'approved');
        $this->assertResponseOk();
    }

    public function testVisibilidadDeLasSolicitudes()
    {
        $admin = $this->createAdmin();
        $itinerary = $this->createItinerary();
        $chief = $this->createItineraryChief($itinerary);
        $a = $this->createWorker();
        $b = $this->createWorker();

        $this->apply($a, 'itinerary_membership', ['itinerary' => ['itineraries', $itinerary->id], 'stop' => ['stops', $itinerary->stops[0]->id]]);
        $this->apply($b, 'role', ['role' => ['roles', $this->role('Chofer')->id]]);

        $this->jsonApiAs($a, 'GET', '/api/v1/applications');
        $this->assertSame(1, $this->responseJson()['meta']['total']);
        $this->jsonApiAs($chief, 'GET', '/api/v1/applications');
        $this->assertSame(['itinerary_membership'], array_column(array_column($this->responseJson()['data'], 'attributes'), 'type'));
        $this->jsonApiAs($admin, 'GET', '/api/v1/applications?filter[type]=role');
        $this->assertSame(1, $this->responseJson()['meta']['total']);
        $this->jsonApiAs($b, 'GET', '/api/v1/applications?filter[mine]=true');
        $this->assertSame(['role'], array_column(array_column($this->responseJson()['data'], 'attributes'), 'type'));
    }
}
