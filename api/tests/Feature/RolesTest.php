<?php

use App\Models\ItineraryChief;
use App\Models\Trip;
use App\Models\Vehicle;
use App\Models\VehicleType;
use Laravel\Lumen\Testing\DatabaseMigrations;

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
        $this->vehicle = $this->createVehicle(null, 10, 0);
        $this->driver = $this->createDriver();
    }

    private function trip($itinerary, string $departs = '2026-12-01T17:00:00Z', string $returns = '2026-12-02T06:00:00Z'): array
    {
        return ['type' => 'trips', 'attributes' => ['departsAt' => $departs, 'returnsAt' => $returns, 'status' => 'confirmed'], 'relationships' => [
            'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $itinerary->id]],
            'vehicle' => ['data' => ['type' => 'vehicles', 'id' => (string) $this->vehicle->id]],
            'driver' => ['data' => ['type' => 'drivers', 'id' => (string) $this->driver->driverId()]],
        ]];
    }

    public function testElJefeDeItinerarioPlanificaSoloSuItinerario()
    {
        $this->jsonApiAs($this->chief, 'POST', '/api/v1/trips', ['data' => $this->trip($this->east)]);
        $this->assertResponseStatus(201);
        $tripId = $this->responseJson()['data']['id'];

        $this->jsonApiAs($this->chief, 'POST', '/api/v1/trips', ['data' => $this->trip($this->west)]);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        // No puede llevarse un viaje suyo a otro itinerario
        $this->jsonApiAs($this->chief, 'PATCH', '/api/v1/trips/'.$tripId, ['data' => ['type' => 'trips', 'id' => $tripId, 'relationships' => [
            'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $this->west->id]],
        ]]]);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        // Ni tocar los de otro itinerario
        $other = Trip::create(['itinerary_id' => $this->west->id, 'vehicle_id' => $this->vehicle->id, 'driver_id' => $this->driver->driverId(),
            'departs_at' => '2026-12-05 17:00', 'returns_at' => '2026-12-06 06:00', 'status' => 'unconfirmed', 'created_by' => $this->chief->user_id]);
        $this->jsonApiAs($this->chief, 'PATCH', '/api/v1/trips/'.$other->id, ['data' => ['type' => 'trips', 'id' => (string) $other->id, 'attributes' => ['status' => 'confirmed']]]);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        // Rango con operaciones atómicas en su itinerario
        $this->jsonApiAs($this->chief, 'POST', '/api/v1/operations', ['atomic:operations' => [
            ['op' => 'add', 'data' => $this->trip($this->east, '2026-12-10T17:00:00Z', '2026-12-11T06:00:00Z')],
            ['op' => 'add', 'data' => $this->trip($this->east, '2026-12-11T17:00:00Z', '2026-12-12T06:00:00Z')],
        ]], ['Content-Type' => 'application/vnd.api+json; ext="https://jsonapi.org/ext/atomic"']);
        $this->assertResponseOk();

        // Un trabajador sin rol no planifica
        $this->jsonApiAs($this->createWorker(), 'POST', '/api/v1/trips', ['data' => $this->trip($this->east)]);
        $this->assertJsonApiError(403, 'FORBIDDEN');
    }

    public function testUnJefeDeItinerarioSoloLoEsDeUno()
    {
        $stop = $this->west->itineraryStops()->value('stop_id');
        $this->jsonApiAs($this->chief, 'POST', '/api/v1/applications', ['data' => ['type' => 'applications', 'attributes' => ['type' => 'itinerary_chief'], 'relationships' => [
            'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $this->west->id]],
            'stop' => ['data' => ['type' => 'stops', 'id' => (string) $stop]],
        ]]]);

        $this->assertJsonApiError(409, 'ALREADY_CHIEF_OF_OTHER');
    }

    public function testVariosRolesALaVez()
    {
        $worker = $this->createDriver();
        \App\Models\TransportChief::create(['worker_id' => $worker->id]);
        ItineraryChief::create(['itinerary_id' => $this->west->id, 'worker_id' => $worker->id]);

        $this->jsonApiAs($worker, 'GET', '/api/v1/workers/'.$worker->id);
        $roles = $this->responseJson()['data']['meta']['roles'];
        $this->assertTrue($roles['isTransportChief']);
        $this->assertNotNull($roles['driverId']);
        $this->assertSame([(string) $this->west->id], $roles['chiefOfItineraries']);
    }

    public function testElAdministradorEsJefeDeTodosLosItinerarios()
    {
        $admin = $this->createAdmin();

        $this->assertTrue($admin->isChiefOf($this->east->id));
        $this->assertTrue($admin->canPlan($this->west->id));
        $this->jsonApiAs($admin, 'POST', '/api/v1/trips', ['data' => $this->trip($this->west)]);
        $this->assertResponseStatus(201);
    }

    private function assign($actor, $worker, string $type, array $relationships = [])
    {
        return $this->jsonApiAs($actor, 'POST', '/api/v1/applications', ['data' => ['type' => 'applications',
            'attributes' => ['type' => $type],
            'relationships' => ['worker' => ['data' => ['type' => 'workers', 'id' => (string) $worker->id]]] + $relationships,
        ]]);
    }

    private function itineraryAndStop($itinerary, int $position = 1): array
    {
        return [
            'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $itinerary->id]],
            'stop' => ['data' => ['type' => 'stops', 'id' => (string) $itinerary->itineraryStops()->where('position', $position)->value('stop_id')]],
        ];
    }

    public function testElJefeDeTransporteAsignaYQuitaChoferYJefeDeItinerario()
    {
        $transportChief = $this->createTransportChief();
        $worker = $this->createWorker();

        $this->assign($transportChief, $worker, 'driver');
        $this->assertResponseStatus(201);
        $this->seeJson(['status' => 'approved', 'assigned' => true]);
        $this->assertNotNull($worker->driverId());
        $this->assertTrue(\App\Models\Notice::where('user_id', $worker->user_id)->where('type', 'role_assigned')->exists());

        $this->assign($transportChief, $worker, 'itinerary_chief', $this->itineraryAndStop($this->west, 2));
        $this->assertResponseStatus(201);
        $this->assertSame($this->west->id, (int) $worker->fresh()->itinerary_id);
        $this->assertTrue(ItineraryChief::where('worker_id', $worker->id)->where('itinerary_id', $this->west->id)->exists());

        $this->assign($transportChief, $worker, 'driver_leave');
        $this->assertResponseStatus(201);
        $this->assertNull($worker->driverId());
        $this->assertTrue(\App\Models\Notice::where('user_id', $worker->user_id)->where('type', 'role_removed')->exists());

        // También con DELETE sobre el rol.
        $role = ItineraryChief::where('worker_id', $worker->id)->first();
        $this->jsonApiAs($transportChief, 'DELETE', '/api/v1/itinerary-chiefs/'.$role->id);
        $this->assertResponseStatus(204);
        $this->assertFalse(ItineraryChief::where('worker_id', $worker->id)->exists());

        // Jefe de Transporte solo lo asigna el Administrador.
        $this->assign($transportChief, $worker, 'transport_chief');
        $this->assertJsonApiError(403, 'FORBIDDEN');
        $this->assign($this->createAdmin(), $worker, 'transport_chief');
        $this->assertResponseStatus(201);
    }

    public function testElJefeDeItinerarioAsignaMiembrosSoloASuItinerario()
    {
        $worker = $this->createWorker();

        $this->assign($this->chief, $worker, 'itinerary_membership', $this->itineraryAndStop($this->east, 3));
        $this->assertResponseStatus(201);
        $this->assertSame($this->east->id, (int) $worker->fresh()->itinerary_id);

        $other = $this->createWorker();
        $this->assign($this->chief, $other, 'itinerary_membership', $this->itineraryAndStop($this->west));
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->assign($this->chief, $other, 'driver');
        $this->assertJsonApiError(403, 'FORBIDDEN');

        // Puede sacar a un miembro de su itinerario.
        $this->assign($this->chief, $worker->fresh(), 'itinerary_leave');
        $this->assertResponseStatus(201);
        $this->assertNull($worker->fresh()->itinerary_id);

        // Un trabajador normal no asigna nada.
        $this->assign($this->createWorker(), $other, 'itinerary_membership', $this->itineraryAndStop($this->east));
        $this->assertResponseStatus(403);
    }

    public function testNoSeAsignaEnOtraEntidad()
    {
        $entity = $this->createEntity('OTRA');
        $foreignChief = $this->createTransportChief([], $entity);
        $worker = $this->createWorker();

        $this->assign($foreignChief, $worker, 'driver');
        $this->assertJsonApiError(404, 'NOT_FOUND');

        // Ni con un itinerario de otra Entidad.
        $foreignItinerary = $this->createItinerary('Ruta ajena', 2, $entity);
        $this->assign($this->createTransportChief(), $worker, 'itinerary_membership', $this->itineraryAndStop($foreignItinerary));
        $this->assertJsonApiError(422, 'ENTITY_MISMATCH');
    }
}
