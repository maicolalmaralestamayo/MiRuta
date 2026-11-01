<?php

use App\Models\Entity;
use App\Models\Trip;
use App\Models\VehicleType;
use Laravel\Lumen\Testing\DatabaseMigrations;

/**
 * Entidades y compartimentación (docs/08-version-2.md §8.2).
 */
class EntitiesTest extends TestCase
{
    use DatabaseMigrations;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
    }

    private function entityDocument(array $attributes): array
    {
        return ['data' => ['type' => 'entities', 'attributes' => $attributes]];
    }

    public function testElAdministradorGestionaLasEntidades()
    {
        $admin = $this->createAdmin();

        $this->jsonApiAs($admin, 'POST', '/api/v1/entities', $this->entityDocument(['abbreviation' => 'emp1', 'name' => 'Empresa Uno', 'number' => '0123']));
        $this->assertResponseStatus(201);
        $this->seeJson(['abbreviation' => 'EMP1', 'number' => '0123', 'name' => 'Empresa Uno']);
        $id = $this->responseJson()['data']['id'];

        $this->jsonApiAs($admin, 'POST', '/api/v1/entities', $this->entityDocument(['abbreviation' => 'EMP1', 'name' => 'Otra']));
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/abbreviation');

        $this->jsonApiAs($admin, 'POST', '/api/v1/entities', $this->entityDocument(['abbreviation' => 'EMP2', 'name' => 'Otra', 'number' => '0123']));
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/number');

        $this->jsonApiAs($admin, 'POST', '/api/v1/entities', $this->entityDocument(['abbreviation' => 'E-2', 'name' => 'Otra', 'number' => '12']));
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/abbreviation');
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/number');

        // Sin número también vale.
        $this->jsonApiAs($admin, 'POST', '/api/v1/entities', $this->entityDocument(['abbreviation' => 'EMP2', 'name' => 'Empresa Dos']));
        $this->assertResponseStatus(201);

        $this->jsonApiAs($admin, 'PATCH', '/api/v1/entities/'.$id, ['data' => ['type' => 'entities', 'id' => $id, 'attributes' => ['name' => 'Empresa Uno S.A.']]]);
        $this->assertResponseOk();
        $this->seeJson(['name' => 'Empresa Uno S.A.']);

        $this->jsonApiAs($admin, 'DELETE', '/api/v1/entities/'.$id);
        $this->assertResponseStatus(204);
        $this->assertTrue(Entity::withTrashed()->find($id)->trashed());

        // Una abreviatura de una Entidad inactiva no se reutiliza.
        $this->jsonApiAs($admin, 'POST', '/api/v1/entities', $this->entityDocument(['abbreviation' => 'EMP1', 'name' => 'Nueva']));
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/abbreviation');

        $this->jsonApiAs($admin, 'PATCH', '/api/v1/entities/'.$id, ['data' => ['type' => 'entities', 'id' => $id, 'attributes' => ['active' => true]]]);
        $this->assertResponseOk();
        $this->assertFalse(Entity::find($id)->trashed());
    }

    public function testSoloElAdministrador()
    {
        $chief = $this->createTransportChief();

        $this->jsonApiAs($chief, 'POST', '/api/v1/entities', $this->entityDocument(['abbreviation' => 'EMP1', 'name' => 'Empresa']));
        $this->assertResponseStatus(403);

        $this->jsonApiAs($chief, 'PATCH', '/api/v1/entities/'.$this->defaultEntity()->id, ['data' => ['type' => 'entities', 'attributes' => ['name' => 'Mía']]]);
        $this->assertResponseStatus(403);
    }

    public function testCadaUnoVeSoloLoDeSuEntidad()
    {
        $other = $this->createEntity('OTRA');
        $chief = $this->createTransportChief();
        $foreignItinerary = $this->createItinerary('Ruta ajena', 2, $other);
        $foreignVehicle = $this->createVehicle(null, 10, 0, $other);
        $foreignDriver = $this->createDriver([], $other);
        $foreignWorker = $this->createWorker([], $other);
        $foreignTrip = Trip::create([
            'itinerary_id' => $foreignItinerary->id, 'vehicle_id' => $foreignVehicle->id, 'driver_id' => $foreignDriver->driverId(),
            'departs_at' => '2026-12-01 17:00', 'returns_at' => '2026-12-02 06:00', 'status' => 'confirmed', 'created_by' => $foreignWorker->user_id,
        ]);
        $own = $this->createItinerary('Ruta propia');

        foreach ([
            '/api/v1/itineraries/'.$foreignItinerary->id,
            '/api/v1/stops/'.$foreignItinerary->itineraryStops()->value('stop_id'),
            '/api/v1/vehicles/'.$foreignVehicle->id,
            '/api/v1/workers/'.$foreignWorker->id,
            '/api/v1/drivers/'.$foreignDriver->driverId(),
            '/api/v1/trips/'.$foreignTrip->id,
        ] as $uri) {
            $this->jsonApiAs($chief, 'GET', $uri);
            $this->assertResponseStatus(404, $uri);
        }

        $this->jsonApiAs($chief, 'GET', '/api/v1/itineraries');
        $this->assertSame([(string) $own->id], array_column($this->responseJson()['data'], 'id'));

        $this->jsonApiAs($chief, 'GET', '/api/v1/trips');
        $this->assertSame(0, $this->responseJson()['meta']['total']);

        $this->jsonApiAs($chief, 'PATCH', '/api/v1/itineraries/'.$foreignItinerary->id, ['data' => ['type' => 'itineraries', 'attributes' => ['name' => 'Mía']]]);
        $this->assertResponseStatus(404);

        // El Administrador ve todo y puede filtrar por Entidad.
        $admin = $this->createAdmin();
        $this->jsonApiAs($admin, 'GET', '/api/v1/itineraries');
        $this->assertSame(2, $this->responseJson()['meta']['total']);
        $this->jsonApiAs($admin, 'GET', '/api/v1/itineraries?filter[entity]='.$other->id);
        $this->assertSame([(string) $foreignItinerary->id], array_column($this->responseJson()['data'], 'id'));
    }

    public function testLoQueSeCreaEsDeSuEntidadYNoSeMezclaConOtras()
    {
        $other = $this->createEntity('OTRA');
        $chief = $this->createTransportChief();
        $foreignDriver = $this->createDriver([], $other);
        $type = VehicleType::first();

        $this->jsonApiAs($chief, 'POST', '/api/v1/itineraries', ['data' => ['type' => 'itineraries', 'attributes' => ['name' => 'Ruta Norte']]]);
        $this->assertResponseStatus(201);
        $this->seeJson(['entity' => ['data' => ['type' => 'entities', 'id' => (string) $this->defaultEntity()->id]]]);

        // El mismo nombre en otra Entidad vale.
        $this->jsonApiAs($this->createTransportChief([], $other), 'POST', '/api/v1/itineraries', ['data' => ['type' => 'itineraries', 'attributes' => ['name' => 'Ruta Norte']]]);
        $this->assertResponseStatus(201);

        $this->jsonApiAs($chief, 'POST', '/api/v1/vehicles', ['data' => ['type' => 'vehicles', 'attributes' => ['plate' => 'B000001', 'seats' => 10, 'standingCapacity' => 0], 'relationships' => [
            'vehicleType' => ['data' => ['type' => 'vehicle-types', 'id' => (string) $type->id]],
            'driver' => ['data' => ['type' => 'drivers', 'id' => (string) $foreignDriver->driverId()]],
        ]]]);
        $this->assertJsonApiError(422, 'ENTITY_MISMATCH', '/data/relationships/driver');

        // Viaje con vehículo de otra Entidad.
        $itinerary = $this->createItinerary();
        $foreignVehicle = $this->createVehicle(null, 10, 0, $other);
        $this->jsonApiAs($chief, 'POST', '/api/v1/trips', ['data' => ['type' => 'trips', 'attributes' => [
            'departsAt' => '2026-12-01T17:00:00Z', 'returnsAt' => '2026-12-02T06:00:00Z',
        ], 'relationships' => [
            'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $itinerary->id]],
            'vehicle' => ['data' => ['type' => 'vehicles', 'id' => (string) $foreignVehicle->id]],
            'driver' => ['data' => ['type' => 'drivers', 'id' => (string) $this->createDriver()->driverId()]],
        ]]]);
        $this->assertJsonApiError(422, 'ENTITY_MISMATCH', '/data/relationships/vehicle');

        // Parada de otra Entidad en un itinerario propio.
        $foreignStop = $this->createStop('Ajena', $other);
        $this->jsonApiAs($chief, 'POST', '/api/v1/itinerary-stops', ['data' => ['type' => 'itinerary-stops', 'relationships' => [
            'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $itinerary->id]],
            'stop' => ['data' => ['type' => 'stops', 'id' => (string) $foreignStop->id]],
        ]]]);
        $this->assertJsonApiError(422, 'ENTITY_MISMATCH', '/data/relationships/stop');
    }

    public function testElAdministradorIndicaLaEntidadAlCrear()
    {
        $admin = $this->createAdmin();

        $this->jsonApiAs($admin, 'POST', '/api/v1/itineraries', ['data' => ['type' => 'itineraries', 'attributes' => ['name' => 'Ruta']]]);
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/relationships/entity');

        $this->jsonApiAs($admin, 'POST', '/api/v1/itineraries', ['data' => ['type' => 'itineraries', 'attributes' => ['name' => 'Ruta'], 'relationships' => [
            'entity' => ['data' => ['type' => 'entities', 'id' => (string) $this->defaultEntity()->id]],
        ]]]);
        $this->assertResponseStatus(201);
    }

    public function testAjustesEnTresNiveles()
    {
        $admin = $this->createAdmin();
        $chief = $this->createTransportChief();
        $worker = $this->createWorker();
        $otherChief = $this->createTransportChief([], $this->createEntity('OTRA'));
        $setting = function (string $key, $value, string $type = 'settings') {
            return ['data' => ['type' => $type, 'id' => $key, 'attributes' => ['value' => $value]]];
        };

        // Los de la app, solo el Administrador.
        $this->jsonApiAs($chief, 'PATCH', '/api/v1/settings/conversation_retention_days', $setting('conversation_retention_days', 10));
        $this->assertJsonApiError(403, 'FORBIDDEN');
        $this->jsonApiAs($admin, 'PATCH', '/api/v1/settings/child_max_age', $setting('child_max_age', 15));
        $this->assertResponseOk();
        $this->jsonApiAs($admin, 'PATCH', '/api/v1/settings/access_token_ttl_minutes', $setting('access_token_ttl_minutes', 1));
        $this->assertJsonApiError(422, 'SETTING_OUT_OF_RANGE');

        // Los de la Entidad, su Jefe de Transporte.
        $this->jsonApiAs($chief, 'PATCH', '/api/v1/entity-settings/child_max_age', $setting('child_max_age', 14, 'entity-settings'));
        $this->assertResponseOk();
        $this->seeJson(['value' => '14', 'appValue' => '15', 'isCustom' => true]);

        $this->jsonApiAs($chief, 'PATCH', '/api/v1/entity-settings/conversation_retention_days', $setting('conversation_retention_days', 5, 'entity-settings'));
        $this->assertJsonApiError(404, 'NOT_FOUND');

        $this->jsonApiAs($worker, 'PATCH', '/api/v1/entity-settings/child_max_age', $setting('child_max_age', 10, 'entity-settings'));
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->jsonApiAs($otherChief, 'GET', '/api/v1/entity-settings');
        $values = array_column(array_map(function ($row) {
            return ['id' => $row['id'], 'value' => $row['attributes']['value']];
        }, $this->responseJson()['data']), 'value', 'id');
        $this->assertSame('15', $values['child_max_age']);

        $this->assertSame(14, app(\App\Services\Settings::class)->int('child_max_age', $this->userOf($worker)));

        // Los del usuario heredan el de su Entidad.
        $this->jsonApiAs($chief, 'PATCH', '/api/v1/entity-settings/departure_notice_minutes_before', $setting('departure_notice_minutes_before', 90, 'entity-settings'));
        $this->jsonApiAs($worker, 'GET', '/api/v1/me/settings');
        $mine = collect($this->responseJson()['data'])->keyBy('id')['departure_notice_minutes_before']['attributes'];
        $this->assertSame(['value' => '90', 'inheritedValue' => '90', 'isCustom' => false], $mine);

        // El Administrador indica la Entidad.
        $this->jsonApiAs($admin, 'GET', '/api/v1/entity-settings');
        $this->assertJsonApiError(400, 'BAD_REQUEST');
        $this->jsonApiAs($admin, 'DELETE', '/api/v1/entity-settings/child_max_age?filter[entity]='.$this->defaultEntity()->id);
        $this->assertResponseStatus(204);
        $this->assertSame(15, app(\App\Services\Settings::class)->int('child_max_age', $this->userOf($worker)));
    }
}
