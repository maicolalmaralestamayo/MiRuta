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
        $this->chief = $this->createWorker();
        ItineraryChief::create(['itinerary_id' => $this->east->id, 'worker_id' => $this->chief->id]);
        $this->chief->refreshRoles();
        $this->vehicle = Vehicle::create(['vehicle_type_id' => VehicleType::first()->id, 'plate' => 'B1', 'seats' => 10, 'standing_capacity' => 0]);
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
            'departs_at' => '2026-12-05 17:00', 'returns_at' => '2026-12-06 06:00', 'status' => 'unconfirmed', 'created_by' => $this->chief->id]);
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

        $this->jsonApiAs($worker, 'GET', '/api/v1/me');
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
}
