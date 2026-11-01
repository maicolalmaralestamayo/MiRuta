<?php

use App\Models\AbsenceType;
use App\Models\ItineraryStop;
use App\Models\VehicleType;
use App\Models\Worker;
use Laravel\Lumen\Testing\DatabaseMigrations;

class CatalogTest extends TestCase
{
    use DatabaseMigrations;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
    }

    private function nomenclator(string $type, string $name, array $extra = []): array
    {
        return ['data' => ['type' => $type, 'attributes' => array_merge(['name' => $name], $extra)]];
    }

    public function testPermisosDeLosNomencladores()
    {
        $worker = $this->createWorker();
        $chief = $this->createTransportChief();
        $admin = $this->createAdmin();

        $this->jsonApiAs($worker, 'POST', '/api/v1/vehicle-types', $this->nomenclator('vehicle-types', 'Microbús'));
        $this->assertJsonApiError(403, 'FORBIDDEN');

        // Los nomencladores son comunes a todas las Entidades: solo el Administrador.
        $this->jsonApiAs($chief, 'POST', '/api/v1/vehicle-types', $this->nomenclator('vehicle-types', 'Microbús'));
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->jsonApiAs($admin, 'POST', '/api/v1/vehicle-types', $this->nomenclator('vehicle-types', 'Microbús'));
        $this->assertResponseStatus(201);

        $this->jsonApiAs($chief, 'POST', '/api/v1/ranks', $this->nomenclator('ranks', 'Nueva', ['sortOrder' => 19]));
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->jsonApiAs($admin, 'POST', '/api/v1/ranks', $this->nomenclator('ranks', 'Nueva', ['sortOrder' => 19]));
        $this->assertResponseStatus(201);

        $this->jsonApiAs($worker, 'GET', '/api/v1/absence-types');
        $this->assertResponseOk();
        $this->assertSame(4, $this->responseJson()['meta']['total']);
    }

    public function testDenominacionRepetidaYRestauracion()
    {
        $chief = $this->createAdmin();

        $this->jsonApiAs($chief, 'POST', '/api/v1/absence-types', $this->nomenclator('absence-types', 'Vacaciones'));
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/name');

        $vacations = AbsenceType::where('name', 'Vacaciones')->first();
        $this->jsonApiAs($chief, 'DELETE', '/api/v1/absence-types/'.$vacations->id);
        $this->assertResponseStatus(204);

        $this->jsonApiAs($chief, 'POST', '/api/v1/absence-types', $this->nomenclator('absence-types', 'Vacaciones', ['description' => 'Anuales']));
        $this->assertResponseStatus(201);
        $this->assertSame((string) $vacations->id, $this->responseJson()['data']['id']);
        $this->assertSame('Anuales', $vacations->fresh()->description);
    }

    public function testParadasDeUnItinerarioEnOrden()
    {
        $chief = $this->createTransportChief();
        $itinerary = $this->createItinerary('Ruta Norte', 3);
        $this->jsonApiAs($chief, 'POST', '/api/v1/stops', ['data' => ['type' => 'stops', 'attributes' => [
            'landmark' => 'Empresa', 'street' => 'Avenida 1', 'crossStreet1' => 'A', 'crossStreet2' => 'B',
            'latitude' => 23.05, 'longitude' => -82.35,
        ]]]);
        $this->assertResponseStatus(201);
        $companyStopId = $this->responseJson()['data']['id'];
        $this->assertSame('Empresa, Avenida 1 entre A y B', $this->responseJson()['data']['attributes']['address']);

        $this->jsonApiAs($chief, 'POST', '/api/v1/itinerary-stops', ['data' => ['type' => 'itinerary-stops',
            'attributes' => ['position' => 1],
            'relationships' => [
                'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $itinerary->id]],
                'stop' => ['data' => ['type' => 'stops', 'id' => $companyStopId]],
            ],
        ]]);
        $this->assertResponseStatus(201);

        $this->assertSame([1, 2, 3, 4], ItineraryStop::where('itinerary_id', $itinerary->id)->orderBy('position')->pluck('position')->all());

        $this->jsonApiAs($chief, 'GET', '/api/v1/itineraries/'.$itinerary->id);
        $meta = $this->responseJson()['data']['meta'];
        $this->assertSame($companyStopId, $meta['departurePoint']['id']);
        $this->assertCount(4, $meta['stopIds']);

        // Mover la empresa al final: pasa a ser el punto de regreso
        $companyLink = ItineraryStop::where('stop_id', $companyStopId)->first();
        $this->jsonApiAs($chief, 'PATCH', '/api/v1/itinerary-stops/'.$companyLink->id, ['data' => [
            'type' => 'itinerary-stops', 'id' => (string) $companyLink->id, 'attributes' => ['position' => 99],
        ]]);
        $this->assertResponseOk();
        $this->assertSame(4, $companyLink->fresh()->position);
        $this->jsonApiAs($chief, 'GET', '/api/v1/itineraries/'.$itinerary->id);
        $this->assertSame($companyStopId, $this->responseJson()['data']['meta']['returnPoint']['id']);

        // Quitar la primera: las demás se renumeran
        $first = ItineraryStop::where('itinerary_id', $itinerary->id)->where('position', 1)->first();
        $this->jsonApiAs($chief, 'DELETE', '/api/v1/itinerary-stops/'.$first->id);
        $this->assertResponseStatus(204);
        $this->assertSame([1, 2, 3], ItineraryStop::where('itinerary_id', $itinerary->id)->orderBy('position')->pluck('position')->all());

        // Volver a añadirla restaura la fila
        $this->jsonApiAs($chief, 'POST', '/api/v1/itinerary-stops', ['data' => ['type' => 'itinerary-stops',
            'relationships' => [
                'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $itinerary->id]],
                'stop' => ['data' => ['type' => 'stops', 'id' => (string) $first->stop_id]],
            ],
        ]]);
        $this->assertResponseStatus(201);
        $this->assertSame((string) $first->id, $this->responseJson()['data']['id']);
        $this->assertSame(4, $this->responseJson()['data']['attributes']['position']);

        $this->jsonApiAs($chief, 'POST', '/api/v1/itinerary-stops', ['data' => ['type' => 'itinerary-stops',
            'relationships' => [
                'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $itinerary->id]],
                'stop' => ['data' => ['type' => 'stops', 'id' => (string) $first->stop_id]],
            ],
        ]]);
        $this->assertJsonApiError(409, 'STOP_ALREADY_IN_ITINERARY');
    }

    public function testNoSeQuitaUnaParadaConMiembrosNiUnItinerarioConMiembros()
    {
        $chief = $this->createTransportChief();
        $itinerary = $this->createItinerary();
        $this->joinItinerary($this->createWorker(), $itinerary, 2);
        $link = ItineraryStop::where('itinerary_id', $itinerary->id)->where('position', 2)->first();

        $this->jsonApiAs($chief, 'DELETE', '/api/v1/itinerary-stops/'.$link->id);
        $this->assertJsonApiError(409, 'STOP_HAS_MEMBERS');

        $this->jsonApiAs($chief, 'DELETE', '/api/v1/itineraries/'.$itinerary->id);
        $this->assertJsonApiError(409, 'ITINERARY_HAS_MEMBERS');

        $this->jsonApiAs($chief, 'DELETE', '/api/v1/stops/'.$link->stop_id);
        $this->assertJsonApiError(409, 'STOP_IN_USE');
    }

    public function testLaParadaDelTrabajadorDebeSerDeSuItinerario()
    {
        $east = $this->createItinerary('Ruta Este');
        $west = $this->createItinerary('Ruta Oeste');
        $worker = $this->createWorker();
        $worker->itinerary_id = $east->id;
        $worker->stop_id = $west->itineraryStops()->value('stop_id');

        $this->expectException(\Illuminate\Database\QueryException::class);
        $worker->save();
    }

    public function testVehiculos()
    {
        $chief = $this->createTransportChief();
        $driver = $this->createDriver();
        $bus = VehicleType::where('name', 'Guagua')->first();
        $document = function (array $attributes, ?string $driverId) use ($bus) {
            return ['data' => ['type' => 'vehicles', 'attributes' => $attributes, 'relationships' => [
                'vehicleType' => ['data' => ['type' => 'vehicle-types', 'id' => (string) $bus->id]],
                'driver' => ['data' => $driverId ? ['type' => 'drivers', 'id' => $driverId] : null],
            ]]];
        };

        $this->jsonApiAs($chief, 'POST', '/api/v1/vehicles?include=driver.worker', $document(['plate' => 'B123456', 'seats' => 10, 'standingCapacity' => 5], (string) $driver->driverId()));
        $this->assertResponseStatus(201);
        $this->assertSame(15, $this->responseJson()['data']['meta']['totalCapacity']);
        $this->assertSame(['drivers', 'workers'], array_column($this->responseJson()['included'], 'type'));
        $vehicleId = $this->responseJson()['data']['id'];

        $this->jsonApiAs($chief, 'GET', '/api/v1/vehicles/'.$vehicleId.'?include=driver.worker,vehicleType');
        $types = array_column($this->responseJson()['included'], 'type');
        sort($types);
        $this->assertSame(['drivers', 'vehicle-types', 'workers'], $types);

        $this->jsonApiAs($chief, 'POST', '/api/v1/vehicles', $document(['plate' => 'B123456', 'seats' => 4, 'standingCapacity' => 0], null));
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/plate');

        $this->jsonApiAs($chief, 'POST', '/api/v1/vehicles', $document(['plate' => 'P100001', 'seats' => 4, 'standingCapacity' => 0], '999'));
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/relationships/driver/data/id');

        $this->jsonApiAs($this->createWorker(), 'POST', '/api/v1/vehicles', $document(['plate' => 'P100001', 'seats' => 4, 'standingCapacity' => 0], null));
        $this->assertJsonApiError(403, 'FORBIDDEN');
    }

    public function testTrabajadoresYActivacion()
    {
        $admin = $this->createAdmin();
        $itinerary = $this->createItinerary();
        $ana = $this->joinItinerary($this->createWorker(['user' => ['first_name' => 'Ana', 'first_surname' => 'Pérez']]), $itinerary);
        $luis = $this->createWorker(['user' => ['first_name' => 'Luis', 'first_surname' => 'Gómez']]);

        $this->jsonApiAs($luis, 'GET', '/api/v1/workers?filter[itinerary]='.$itinerary->id);
        $this->assertSame([(string) $ana->id], array_column($this->responseJson()['data'], 'id'));
        $this->assertSame('Ana', $this->responseJson()['data'][0]['attributes']['firstName']);
        $this->assertArrayNotHasKey('pass', $this->responseJson()['data'][0]['attributes']);

        $this->jsonApiAs($luis, 'GET', '/api/v1/workers?filter[search]=gómez');
        $this->assertSame(1, $this->responseJson()['meta']['total']);

        $deactivate = ['data' => ['type' => 'workers', 'id' => (string) $ana->id, 'attributes' => ['active' => false]]];
        $this->jsonApiAs($luis, 'PATCH', '/api/v1/workers/'.$ana->id, $deactivate);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->jsonApiAs($admin, 'PATCH', '/api/v1/workers/'.$ana->id, $deactivate);
        $this->assertResponseOk();
        $this->seeJson(['active' => false]);
        $this->assertTrue(Worker::withTrashed()->find($ana->id)->trashed());
        $this->assertTrue($this->userOf($ana)->trashed());

        $this->jsonApiAs($admin, 'GET', '/api/v1/workers?filter[active]=false');
        $this->assertSame([(string) $ana->id], array_column($this->responseJson()['data'], 'id'));
        $this->assertArrayHasKey('pass', $this->responseJson()['data'][0]['attributes']);

        $this->jsonApiAs($admin, 'PATCH', '/api/v1/workers/'.$ana->id, ['data' => ['type' => 'workers', 'id' => (string) $ana->id, 'attributes' => ['active' => true]]]);
        $this->seeJson(['active' => true]);
    }

    public function testRoles()
    {
        $driver = $this->createDriver();
        $this->createTransportChief();

        $this->jsonApiAs($driver, 'GET', '/api/v1/drivers?include=worker');
        $this->assertSame(1, $this->responseJson()['meta']['total']);
        $this->assertSame((string) $driver->id, $this->responseJson()['included'][0]['id']);

        $this->jsonApiAs($driver, 'GET', '/api/v1/transport-chiefs');
        $this->assertSame(1, $this->responseJson()['meta']['total']);
    }

    public function testJerarquiasPublicas()
    {
        $this->jsonApi('GET', '/api/v1/ranks/1');
        $this->assertResponseOk();
        $this->seeJson(['name' => 'Coronel']);
    }
}
