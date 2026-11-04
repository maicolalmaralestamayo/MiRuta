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

        // Motivos de conversación: dirigidos a un rol o al desarrollador.
        $topic = $this->nomenclator('conversation-topics', 'Pedir un cambio', ['recipient' => 'role']);
        $this->jsonApiAs($chief, 'POST', '/api/v1/conversation-topics', $topic);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->jsonApiAs($admin, 'POST', '/api/v1/conversation-topics', $topic);
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/relationships/role');

        $topic['data']['relationships'] = ['role' => ['data' => ['type' => 'roles', 'id' => (string) $this->role('Chofer')->id]]];
        $this->jsonApiAs($admin, 'POST', '/api/v1/conversation-topics', $topic);
        $this->assertResponseStatus(201);
        $this->seeJson(['recipient' => 'role', 'roleName' => 'Chofer']);

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
        $chief = $this->createAdmin();
        $itinerary = $this->createItinerary('Ruta Norte', 3);
        $stop = ['data' => ['type' => 'stops', 'attributes' => [
            'landmark' => 'Empresa', 'street' => 'Avenida 1', 'crossStreet1' => 'A', 'crossStreet2' => 'B',
            'latitude' => 23.05, 'longitude' => -82.35,
        ]]];

        // Con permiso en todas las Entidades hay que indicar en cuál.
        $this->jsonApiAs($chief, 'POST', '/api/v1/stops', $stop);
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/relationships/entity');

        $stop['data']['relationships'] = ['entity' => ['data' => ['type' => 'entities', 'id' => (string) $this->defaultEntity()->id]]];
        $this->jsonApiAs($chief, 'POST', '/api/v1/stops', $stop);
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
        $chief = $this->createAdmin();
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
                'driver' => ['data' => $driverId ? ['type' => 'workers', 'id' => $driverId] : null],
            ]]];
        };

        $this->jsonApiAs($chief, 'POST', '/api/v1/vehicles?include=driver.user', $document(['plate' => 'B123456', 'seats' => 10, 'standingCapacity' => 5], (string) $driver->id));
        $this->assertResponseStatus(201);
        $this->assertSame(15, $this->responseJson()['data']['meta']['totalCapacity']);
        $this->assertSame(['workers', 'users'], array_column($this->responseJson()['included'], 'type'));
        $vehicleId = $this->responseJson()['data']['id'];

        $this->jsonApiAs($chief, 'GET', '/api/v1/vehicles/'.$vehicleId.'?include=driver.user,vehicleType');
        $types = array_column($this->responseJson()['included'], 'type');
        sort($types);
        $this->assertSame(['users', 'vehicle-types', 'workers'], $types);

        // El chofer habitual tiene que poder conducir.
        $this->jsonApiAs($chief, 'POST', '/api/v1/vehicles', $document(['plate' => 'P100002', 'seats' => 4, 'standingCapacity' => 0], (string) $this->createWorker()->id));
        $this->assertJsonApiError(422, 'NOT_A_DRIVER', '/data/relationships/driver');

        // Un trabajador sin vehicles.view no los ve; el chofer sí.
        $this->jsonApiAs($this->createWorker(), 'GET', '/api/v1/vehicles');
        $this->assertSame(0, $this->responseJson()['meta']['total']);
        $this->jsonApiAs($driver, 'GET', '/api/v1/vehicles');
        $this->assertSame(1, $this->responseJson()['meta']['total']);

        $this->jsonApiAs($chief, 'POST', '/api/v1/vehicles', $document(['plate' => 'B123456', 'seats' => 4, 'standingCapacity' => 0], null));
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/plate');

        $this->jsonApiAs($chief, 'POST', '/api/v1/vehicles', $document(['plate' => 'P100001', 'seats' => 4, 'standingCapacity' => 0], '999'));
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/relationships/driver/data/id');

        $this->jsonApiAs($this->createWorker(), 'POST', '/api/v1/vehicles', $document(['plate' => 'P100001', 'seats' => 4, 'standingCapacity' => 0], null));
        $this->assertJsonApiError(403, 'FORBIDDEN');
    }

    public function testTrabajadoresYDesactivacion()
    {
        $admin = $this->createAdmin();
        $itinerary = $this->createItinerary();
        $ana = $this->joinItinerary($this->createWorker(['user' => ['first_name' => 'Ana', 'first_surname' => 'Pérez']]), $itinerary);
        $luis = $this->createTransportChief(['user' => ['first_name' => 'Luis', 'first_surname' => 'Gómez']]);

        $this->jsonApiAs($luis, 'GET', '/api/v1/workers?filter[itinerary]='.$itinerary->id);
        $this->assertSame([(string) $ana->id], array_column($this->responseJson()['data'], 'id'));
        $this->assertSame('Ana', $this->responseJson()['data'][0]['attributes']['firstName']);
        $this->assertArrayNotHasKey('identityCard', $this->responseJson()['data'][0]['attributes']);

        $this->jsonApiAs($luis, 'GET', '/api/v1/workers?filter[search]=gómez');
        $this->assertSame(1, $this->responseJson()['meta']['total']);

        $deactivate = ['data' => ['type' => 'workers', 'id' => (string) $ana->id, 'attributes' => ['active' => false]]];
        $this->jsonApiAs($luis, 'PATCH', '/api/v1/workers/'.$ana->id, $deactivate);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->jsonApiAs($admin, 'PATCH', '/api/v1/workers/'.$ana->id, $deactivate);
        $this->assertResponseOk();
        $this->seeJson(['active' => false]);
        $this->assertTrue(Worker::withTrashed()->find($ana->id)->trashed());
        // La persona sigue activa (puede tener otras Entidades).
        $this->assertFalse($this->userOf($ana)->trashed());

        $this->jsonApiAs($admin, 'GET', '/api/v1/workers?filter[active]=false');
        $this->assertSame([(string) $ana->id], array_column($this->responseJson()['data'], 'id'));
        $this->assertArrayHasKey('identityCard', $this->responseJson()['data'][0]['attributes']);

        $this->jsonApiAs($admin, 'PATCH', '/api/v1/workers/'.$ana->id, ['data' => ['type' => 'workers', 'id' => (string) $ana->id, 'attributes' => ['active' => true]]]);
        $this->seeJson(['active' => true]);

        // Eliminar trabajadores (desactivar la cuenta): workers.delete, solo «all».
        $this->jsonApiAs($luis, 'PATCH', '/api/v1/users/'.$ana->user_id, ['data' => ['type' => 'users', 'id' => (string) $ana->user_id, 'attributes' => ['active' => false]]]);
        $this->assertJsonApiError(403, 'FORBIDDEN');
        $this->jsonApiAs($admin, 'PATCH', '/api/v1/users/'.$ana->user_id, ['data' => ['type' => 'users', 'id' => (string) $ana->user_id, 'attributes' => ['active' => false]]]);
        $this->assertResponseOk();
        $this->assertTrue($this->userOf($ana)->fresh() === null || \App\Models\User::withTrashed()->find($ana->user_id)->trashed());

        // Siempre al menos un Administrador.
        $this->jsonApiAs($admin, 'PATCH', '/api/v1/users/'.$admin->id, ['data' => ['type' => 'users', 'id' => (string) $admin->id, 'attributes' => ['active' => false]]]);
        $this->assertJsonApiError(409, 'LAST_ADMIN');
    }

    public function testImagenesDeEntidadItinerarioYParada()
    {
        $admin = $this->createAdmin();
        $itinerary = $this->createItinerary();
        $stop = $itinerary->stops[0];
        $png = base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
        $upload = function ($who, string $uri) use ($png) {
            $path = tempnam(sys_get_temp_dir(), 'imagen');
            file_put_contents($path, $png);
            $this->call('POST', $uri, [], [], ['image' => new \Illuminate\Http\UploadedFile($path, 'imagen.png', 'image/png', null, true)], [
                'HTTP_AUTHORIZATION' => 'Bearer '.$this->accessTokenFor($who),
                'HTTP_ACCEPT' => 'application/vnd.api+json',
                'CONTENT_TYPE' => 'multipart/form-data; boundary=x',
            ]);
        };

        foreach (['entities' => $this->defaultEntity(), 'itineraries' => $itinerary, 'stops' => $stop] as $resource => $model) {
            $upload($this->createWorker(), "/api/v1/{$resource}/{$model->id}/image");
            $this->assertJsonApiError(403, 'FORBIDDEN');

            $upload($admin, "/api/v1/{$resource}/{$model->id}/image");
            $this->assertResponseOk();
            $path = $model->fresh()->image_path;
            $this->assertStringStartsWith('uploads/images/', $path);
            $this->assertSame(url($path), $this->responseJson()['data']['attributes']['imageUrl']);

            $this->jsonApiAs($admin, 'DELETE', "/api/v1/{$resource}/{$model->id}/image");
            $this->assertResponseStatus(204);
            $this->assertNull($model->fresh()->image_path);
            $this->assertFileNotExists(base_path('public/'.$path));
        }
    }
}
