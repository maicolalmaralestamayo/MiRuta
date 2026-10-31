<?php

use App\Models\AbsenceType;
use App\Models\Application;
use App\Models\AbsenceApplication;
use App\Models\Child;
use App\Models\ChildApplication;
use App\Models\ItineraryChief;
use App\Models\Notice;
use App\Models\Rank;
use App\Models\Trip;
use App\Models\TripCompletion;
use App\Models\Vehicle;
use App\Models\VehicleType;
use Carbon\Carbon;
use Carbon\CarbonImmutable;
use Laravel\Lumen\Testing\DatabaseMigrations;

class TripsTest extends TestCase
{
    use DatabaseMigrations;

    private $chief;
    private $itinerary;
    private $vehicle;
    private $driver;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
        Carbon::setTestNow(Carbon::create(2026, 11, 2, 10));
        CarbonImmutable::setTestNow(CarbonImmutable::create(2026, 11, 2, 10));

        $this->chief = $this->createTransportChief();
        $this->itinerary = $this->createItinerary();
        $this->driver = $this->createDriver();
        $this->vehicle = $this->createVehicle(null, 2, 1);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }


    private function tripDocument(string $departs, string $returns, string $status = 'unconfirmed', $vehicle = null, $driver = null, $itinerary = null): array
    {
        return ['type' => 'trips', 'attributes' => ['departsAt' => $departs, 'returnsAt' => $returns, 'status' => $status], 'relationships' => [
            'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) ($itinerary ?: $this->itinerary)->id]],
            'vehicle' => ['data' => ['type' => 'vehicles', 'id' => (string) ($vehicle ?: $this->vehicle)->id]],
            'driver' => ['data' => ['type' => 'drivers', 'id' => (string) ($driver ?: $this->driver)->driverId()]],
        ]];
    }

    private function createTrip(string $departs = '2026-11-03 17:00', string $returns = '2026-11-04 06:30', string $status = 'confirmed'): Trip
    {
        return Trip::create([
            'itinerary_id' => $this->itinerary->id, 'vehicle_id' => $this->vehicle->id, 'driver_id' => $this->driver->driverId(),
            'departs_at' => Carbon::parse($departs), 'returns_at' => Carbon::parse($returns), 'status' => $status, 'created_by' => $this->chief->user_id,
        ]);
    }

    private function setStatus($user, Trip $trip, string $status)
    {
        return $this->jsonApiAs($user, 'PATCH', '/api/v1/trips/'.$trip->id, ['data' => ['type' => 'trips', 'id' => (string) $trip->id, 'attributes' => ['status' => $status]]]);
    }

    public function testCrearViajeConPuntosYOcupacion()
    {
        $this->joinItinerary($this->createWorker(), $this->itinerary, 2);

        $this->jsonApiAs($this->chief, 'POST', '/api/v1/trips?include=vehicle', ['data' => $this->tripDocument('2026-11-03T17:00:00+00:00', '2026-11-04T06:30:00+00:00')]);

        $this->assertResponseStatus(201);
        $json = $this->responseJson()['data'];
        $this->assertSame('unconfirmed', $json['attributes']['status']);
        $this->assertSame('2026-11-03T17:00:00+00:00', $json['attributes']['departsAt']);
        $this->assertSame(1, $json['meta']['expectedPassengers']);
        $this->assertSame(3, $json['meta']['totalCapacity']);
        $this->assertFalse($json['meta']['overloaded']);
        $stops = $this->itinerary->stops->pluck('id')->map(function ($id) {
            return (string) $id;
        })->all();
        $this->assertSame($stops[0], $json['meta']['departurePoint']['id']);
        $this->assertSame(end($stops), $json['meta']['returnPoint']['id']);
    }

    public function testSoloLosJefesDeTransportePlanifican()
    {
        $this->jsonApiAs($this->createWorker(), 'POST', '/api/v1/trips', ['data' => $this->tripDocument('2026-11-03T17:00:00Z', '2026-11-04T06:30:00Z')]);

        $this->assertJsonApiError(403, 'FORBIDDEN');
    }

    public function testElRegresoDebeSerPosterior()
    {
        $this->jsonApiAs($this->chief, 'POST', '/api/v1/trips', ['data' => $this->tripDocument('2026-11-03T17:00:00Z', '2026-11-03T16:00:00Z')]);

        $this->assertJsonApiError(422, 'TRIP_DATES_INVALID', '/data/attributes/returnsAt');
    }

    public function testSolapamientoSoloEntreConfirmados()
    {
        $first = $this->createTrip('2026-11-03 17:00', '2026-11-04 06:30', 'confirmed');
        $otherVehicle = $this->createVehicle(null, 10, 0);

        // Mismo chofer, otro vehículo, se solapa: no confirmado sí se permite
        $this->jsonApiAs($this->chief, 'POST', '/api/v1/trips', ['data' => $this->tripDocument('2026-11-04T05:00:00Z', '2026-11-04T08:00:00Z', 'unconfirmed', $otherVehicle)]);
        $this->assertResponseStatus(201);
        $second = Trip::find($this->responseJson()['data']['id']);

        $this->setStatus($this->chief, $second, 'confirmed');
        $this->assertJsonApiError(409, 'TRIP_OVERLAP');
        $this->assertSame((string) $first->id, $this->responseJson()['errors'][0]['meta']['conflictingTripId']);
        $this->assertSame('driver', $this->responseJson()['errors'][0]['meta']['reason']);

        // Justo después del regreso no se solapa
        $this->jsonApiAs($this->chief, 'POST', '/api/v1/trips', ['data' => $this->tripDocument('2026-11-04T06:30:00Z', '2026-11-04T08:00:00Z', 'confirmed')]);
        $this->assertResponseStatus(201);
    }

    public function testReglasDeEstado()
    {
        $trip = $this->createTrip();

        $this->setStatus($this->chief, $trip, 'completed');
        $this->assertResponseOk();
        $this->assertSame(1, TripCompletion::where('trip_id', $trip->id)->count());

        $this->setStatus($this->chief, $trip, 'cancelled');
        $this->assertJsonApiError(409, 'TRIP_TRANSITION_NOT_ALLOWED');

        // Revertir "realizado" conserva las marcas con borrado lógico
        $this->setStatus($this->chief, $trip, 'confirmed');
        $this->assertResponseOk();
        $this->assertSame(0, TripCompletion::where('trip_id', $trip->id)->count());
        $this->assertSame(1, TripCompletion::withTrashed()->where('trip_id', $trip->id)->count());

        $this->setStatus($this->chief, $trip, 'cancelled');
        $this->assertResponseOk();
        $this->setStatus($this->chief, $trip, 'completed');
        $this->assertJsonApiError(409, 'TRIP_TRANSITION_NOT_ALLOWED');

        // Cancelado → no confirmado sí se permite
        $this->setStatus($this->chief, $trip, 'unconfirmed');
        $this->assertResponseOk();
    }

    public function testQuienPuedeMarcarComoRealizado()
    {
        $trip = $this->createTrip();
        $member = $this->joinItinerary($this->createWorker(), $this->itinerary);
        $itineraryChief = $this->createItineraryChief($this->itinerary);
        $mark = function ($user) use ($trip) {
            return $this->jsonApiAs($user, 'POST', '/api/v1/trip-completions', ['data' => ['type' => 'trip-completions', 'relationships' => [
                'trip' => ['data' => ['type' => 'trips', 'id' => (string) $trip->id]],
            ]]]);
        };

        $mark($member);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $mark($this->driver);
        $this->assertResponseStatus(201);
        $this->seeJson(['role' => 'driver']);
        $this->assertSame('completed', $trip->fresh()->status);

        $mark($itineraryChief);
        $this->seeJson(['role' => 'itinerary_chief']);
        $mark($itineraryChief);

        $this->jsonApiAs($member, 'GET', '/api/v1/trip-completions?filter[trip]='.$trip->id.'&include=user');
        $this->assertSame(2, $this->responseJson()['meta']['total']);
    }

    public function testRealizadoAutomatico()
    {
        $past = $this->createTrip('2026-11-01 17:00', '2026-11-02 06:30', 'confirmed');
        $future = $this->createTrip('2026-11-03 17:00', '2026-11-04 06:30', 'confirmed');
        $unconfirmed = $this->createTrip('2026-10-30 17:00', '2026-10-31 06:30', 'unconfirmed');

        $this->artisan('trips:auto-complete');

        $this->assertSame('completed', $past->fresh()->status);
        $this->assertSame('system', TripCompletion::where('trip_id', $past->id)->value('role'));
        $this->assertSame('confirmed', $future->fresh()->status);
        $this->assertSame('unconfirmed', $unconfirmed->fresh()->status);
    }

    public function testSobresaturacionAusenciasYChofer()
    {
        // Capacidad 3. Cuatro miembros, uno ausente y el chofer es miembro → 3 esperados.
        $trip = $this->createTrip();
        foreach (range(1, 3) as $i) {
            $this->joinItinerary($this->createWorker(), $this->itinerary);
        }
        $absent = $this->joinItinerary($this->createWorker(), $this->itinerary);
        $this->joinItinerary($this->driver, $this->itinerary);
        $application = Application::create(['worker_id' => $absent->id, 'type' => 'absence', 'status' => 'approved']);
        AbsenceApplication::create(['application_id' => $application->id, 'absence_type_id' => AbsenceType::first()->id, 'starts_on' => '2026-11-01', 'ends_on' => '2026-11-05']);

        // 2 asientos y 1 de pie: 3 trabajadores van de pie (saturado), pero caben.
        $this->jsonApiAs($this->chief, 'GET', '/api/v1/trips/'.$trip->id);
        $meta = $this->responseJson()['data']['meta'];
        $this->assertSame(3, $meta['expectedPassengers']);
        $this->assertSame(2, $meta['seats']);
        $this->assertSame('saturated', $meta['occupancyLevel']);
        $this->assertTrue($meta['saturated']);
        $this->assertFalse($meta['overloaded']);

        $this->joinItinerary($this->createWorker(), $this->itinerary);
        $this->jsonApiAs($this->chief, 'GET', '/api/v1/trips/'.$trip->id);
        $this->assertTrue($this->responseJson()['data']['meta']['overloaded']);
        $this->assertSame('overloaded', $this->responseJson()['data']['meta']['occupancyLevel']);

        $this->jsonApiAs($this->chief, 'GET', '/api/v1/trips?filter[overloaded]=true');
        $this->assertSame([(string) $trip->id], array_column($this->responseJson()['data'], 'id'));
    }

    public function testVisibilidadYSincronizacion()
    {
        $trip = $this->createTrip();
        $member = $this->joinItinerary($this->createWorker(), $this->itinerary);
        $other = $this->joinItinerary($this->createWorker(), $this->createItinerary('Ruta Oeste'));

        $this->jsonApiAs($member, 'GET', '/api/v1/trips');
        $this->assertSame([(string) $trip->id], array_column($this->responseJson()['data'], 'id'));
        $this->jsonApiAs($other, 'GET', '/api/v1/trips');
        $this->assertSame([], $this->responseJson()['data']);
        $this->jsonApiAs($this->driver, 'GET', '/api/v1/trips/'.$trip->id);
        $this->assertResponseOk();

        Carbon::setTestNow(Carbon::create(2026, 11, 2, 11));
        $this->jsonApiAs($member, 'GET', '/api/v1/trips?filter[updatedSince]='.urlencode('2026-11-02T10:30:00+00:00'));
        $this->assertSame([], $this->responseJson()['data']);

        $this->setStatus($this->chief, $trip, 'cancelled');
        $this->jsonApiAs($member, 'GET', '/api/v1/trips?filter[updatedSince]='.urlencode('2026-11-02T10:30:00+00:00'));
        $this->assertSame('cancelled', $this->responseJson()['data'][0]['attributes']['status']);
    }

    public function testCambiarLasParadasExtremasMarcaLosViajesPendientes()
    {
        $trip = $this->createTrip();
        $done = $this->createTrip('2026-10-20 17:00', '2026-10-21 06:30', 'completed');
        Carbon::setTestNow(Carbon::create(2026, 11, 2, 12));

        $first = $this->itinerary->itineraryStops()->where('position', 1)->first();
        $this->jsonApiAs($this->chief, 'PATCH', '/api/v1/itinerary-stops/'.$first->id, ['data' => ['type' => 'itinerary-stops', 'id' => (string) $first->id, 'attributes' => ['position' => 2]]]);

        $this->assertSame('2026-11-02 12:00:00', $trip->fresh()->updated_at->toDateTimeString());
        $this->assertNotSame('2026-11-02 12:00:00', $done->fresh()->updated_at->toDateTimeString());
    }

    public function testRangoDeFechasConOperacionesAtomicas()
    {
        $operations = [];
        foreach (['02', '03', '04', '05'] as $day) {
            $next = str_pad((string) ((int) $day + 1), 2, '0', STR_PAD_LEFT);
            $operations[] = ['op' => 'add', 'data' => $this->tripDocument("2026-11-{$day}T17:00:00Z", "2026-11-{$next}T06:30:00Z", 'confirmed')];
        }

        $this->jsonApiAs($this->chief, 'POST', '/api/v1/operations', ['atomic:operations' => $operations], [
            'Content-Type' => 'application/vnd.api+json; ext="https://jsonapi.org/ext/atomic"',
        ]);

        $this->assertResponseOk();
        $this->assertStringContainsString('ext="https://jsonapi.org/ext/atomic"', $this->response->headers->get('Content-Type'));
        $this->assertCount(4, $this->responseJson()['atomic:results']);
        $this->assertSame(4, Trip::where('status', 'confirmed')->count());

        // Confirmación masiva: desconfirmar dos
        $ids = Trip::orderBy('id')->pluck('id')->take(2);
        $updates = $ids->map(function ($id) {
            return ['op' => 'update', 'data' => ['type' => 'trips', 'id' => (string) $id, 'attributes' => ['status' => 'unconfirmed']]];
        })->all();
        $this->jsonApiAs($this->chief, 'POST', '/api/v1/operations', ['atomic:operations' => $updates], [
            'Content-Type' => 'application/vnd.api+json; ext="https://jsonapi.org/ext/atomic"',
        ]);
        $this->assertResponseOk();
        $this->assertSame(2, Trip::where('status', 'unconfirmed')->count());
    }

    public function testRangoConDiasQueChocanNoCreaNinguno()
    {
        $this->createTrip('2026-11-04 17:00', '2026-11-05 06:30', 'confirmed');
        $otherVehicle = $this->createVehicle(null, 10, 0);
        $operations = [];
        foreach (['03', '04', '05'] as $day) {
            $next = str_pad((string) ((int) $day + 1), 2, '0', STR_PAD_LEFT);
            $operations[] = ['op' => 'add', 'data' => $this->tripDocument("2026-11-{$day}T17:00:00Z", "2026-11-{$next}T06:30:00Z", 'confirmed', $otherVehicle)];
        }

        $this->jsonApiAs($this->chief, 'POST', '/api/v1/operations', ['atomic:operations' => $operations], [
            'Content-Type' => 'application/vnd.api+json; ext="https://jsonapi.org/ext/atomic"',
        ]);

        $this->assertJsonApiError(409, 'TRIP_OVERLAP');
        $this->assertSame(['/atomic:operations/1'], array_column(array_column($this->responseJson()['errors'], 'source'), 'pointer'));
        $this->assertSame(1, Trip::count());
    }

    public function testOperacionesSinExtensionOVacias()
    {
        $this->jsonApiAs($this->chief, 'POST', '/api/v1/operations', ['atomic:operations' => []]);
        $this->assertJsonApiError(415, 'UNSUPPORTED_MEDIA_TYPE');

        $this->jsonApiAs($this->chief, 'POST', '/api/v1/operations', ['atomic:operations' => []], [
            'Content-Type' => 'application/vnd.api+json; ext="https://jsonapi.org/ext/atomic"',
        ]);
        $this->assertJsonApiError(400, 'BAD_REQUEST');
    }

    public function testLosNinosNoCuentanParaLaOcupacion()
    {
        $trip = $this->createTrip();
        $parent = $this->joinItinerary($this->createWorker(), $this->itinerary);
        $this->joinItinerary($this->createWorker(), $this->itinerary);

        foreach (['Pepe', 'Juan', 'Rosa'] as $name) {
            $child = Child::create(['worker_id' => $parent->id, 'first_name' => $name, 'middle_name' => 'X', 'first_surname' => 'Pérez', 'second_surname' => 'Y', 'birth_date' => '2018-05-05']);
            $application = Application::create(['worker_id' => $parent->id, 'type' => 'child_addition', 'status' => 'approved']);
            ChildApplication::create(['application_id' => $application->id, 'child_id' => $child->id]);
        }

        $this->jsonApiAs($this->chief, 'GET', '/api/v1/trips/'.$trip->id);
        $meta = $this->responseJson()['data']['meta'];
        $this->assertSame(2, $meta['expectedPassengers']);
        $this->assertSame(3, $meta['expectedChildren']);
        $this->assertSame('normal', $meta['occupancyLevel']);
    }

    public function testListaDePasajerosPorParadaYAlfabetica()
    {
        $trip = $this->createTrip();
        $make = function (string $first, string $surname, int $stop) {
            return $this->joinItinerary($this->createWorker(['user' => ['first_name' => $first, 'first_surname' => $surname]]), $this->itinerary, $stop);
        };

        $zayas = $make('Juan', 'Zayas', 1);
        $alvarez = $make('Pedro', 'Álvarez', 2);
        $nunezB = $make('Ana', 'Nuñez', 1);
        $nunezE = $make('Eva', 'Ñúñez', 1);
        $perez = $make('Luis', 'Pérez', 3);
        $rodriguez = $make('María', 'Rodríguez', 2);

        $child = Child::create(['worker_id' => $perez->id, 'first_name' => 'Pepe', 'middle_name' => 'Luis', 'first_surname' => 'Pérez', 'second_surname' => 'Gómez', 'birth_date' => '2015-03-05']);
        $application = Application::create(['worker_id' => $perez->id, 'type' => 'child_addition', 'status' => 'approved']);
        ChildApplication::create(['application_id' => $application->id, 'child_id' => $child->id]);

        $this->jsonApiAs($this->driver, 'GET', '/api/v1/trips/'.$trip->id.'/passengers');

        $this->assertResponseOk();
        $data = $this->responseJson()['data'];
        $order = array_map(function ($passenger) {
            return explode('-', $passenger['id'])[1];
        }, $data);
        $expected = array_map('strval', [$nunezB->id, $nunezE->id, $zayas->id, $alvarez->id, $rodriguez->id, $perez->id]);
        $this->assertSame($expected, $order);
        $this->assertSame(1, $data[5]['attributes']['eligibleChildren']);
        $this->assertSame(6, $data[5]['attributes']['position']);
        $this->assertArrayNotHasKey('boardingOrder', $data[0]['attributes']);
    }
}
