<?php

use App\Models\Trip;
use App\Models\TripBoarding;
use App\Models\TripLeg;
use App\Models\TripStopPass;
use App\Models\Vehicle;
use App\Models\VehicleType;
use Carbon\Carbon;
use Carbon\CarbonImmutable;
use Laravel\Lumen\Testing\DatabaseMigrations;

class TrackingTest extends TestCase
{
    use DatabaseMigrations;

    private $itinerary;
    private $driver;
    private $trip;
    private $member;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
        Carbon::setTestNow(Carbon::create(2026, 11, 3, 17));
        CarbonImmutable::setTestNow(CarbonImmutable::create(2026, 11, 3, 17));

        // Paradas en latitud 23.10, 23.11 y 23.12 (≈ 1,1 km entre ellas)
        $this->itinerary = $this->createItinerary('Ruta Este', 3);
        $this->driver = $this->createDriver();
        $vehicle = Vehicle::create(['entity_id' => $this->defaultEntity()->id, 'vehicle_type_id' => VehicleType::first()->id, 'plate' => 'B1', 'seats' => 10, 'standing_capacity' => 5]);
        $this->trip = Trip::create([
            'itinerary_id' => $this->itinerary->id, 'vehicle_id' => $vehicle->id, 'driver_id' => $this->driver->driverId(),
            'departs_at' => Carbon::create(2026, 11, 3, 17), 'returns_at' => Carbon::create(2026, 11, 4, 6, 30),
            'status' => Trip::STATUS_CONFIRMED, 'created_by' => $this->createTransportChief()->id,
        ]);
        $this->member = $this->joinItinerary($this->createWorker(), $this->itinerary, 2);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }

    private function startLeg($user, string $direction = 'outbound')
    {
        return $this->jsonApiAs($user, 'POST', '/api/v1/trip-legs', ['data' => ['type' => 'trip-legs',
            'attributes' => ['direction' => $direction],
            'relationships' => ['trip' => ['data' => ['type' => 'trips', 'id' => (string) $this->trip->id]]],
        ]]);
    }

    private function sendPosition($user, $legId, float $latitude, ?Carbon $at = null, float $longitude = -82.3)
    {
        return $this->jsonApiAs($user, 'POST', '/api/v1/trip-positions', ['data' => ['type' => 'trip-positions',
            'attributes' => ['latitude' => $latitude, 'longitude' => $longitude, 'accuracyM' => 5, 'recordedAt' => ($at ?: Carbon::now())->toIso8601String()],
            'relationships' => ['tripLeg' => ['data' => ['type' => 'trip-legs', 'id' => (string) $legId]]],
        ]]);
    }

    private function board($user, $legId, string $method, array $attributes = [], $workerId = null)
    {
        $data = ['type' => 'trip-boardings', 'attributes' => ['method' => $method] + $attributes, 'relationships' => [
            'tripLeg' => ['data' => ['type' => 'trip-legs', 'id' => (string) $legId]],
        ]];

        if ($workerId) {
            $data['relationships']['worker'] = ['data' => ['type' => 'workers', 'id' => (string) $workerId]];
        }

        return $this->jsonApiAs($user, 'POST', '/api/v1/trip-boardings', ['data' => $data]);
    }

    public function testIniciarRecorrido()
    {
        $this->startLeg($this->member);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->startLeg($this->driver);
        $this->assertResponseStatus(201);
        $this->seeJson(['direction' => 'outbound', 'endedAt' => null]);

        $this->startLeg($this->driver);
        $this->assertJsonApiError(409, 'LEG_ALREADY_STARTED');

        $this->trip->update(['status' => Trip::STATUS_UNCONFIRMED]);
        $this->startLeg($this->driver, 'return');
        $this->assertJsonApiError(409, 'TRIP_NOT_CONFIRMED');
    }

    public function testPasoPorParadasYFinAutomatico()
    {
        $legId = $this->startLeg($this->driver)->responseJson()['data']['id'];
        $stops = $this->itinerary->stops->pluck('id')->all();

        $this->sendPosition($this->driver, $legId, 23.1003);
        $this->assertResponseStatus(201);
        $this->assertSame([$stops[0]], TripStopPass::pluck('stop_id')->all());

        // Se salta la segunda parada y llega directamente a la tercera (la última)
        Carbon::setTestNow(Carbon::create(2026, 11, 3, 17, 10));
        $this->sendPosition($this->driver, $legId, 23.1199);

        // La segunda queda marcada como saltada (docs/09 §8) y se avisa a los Jefes.
        $this->assertSame([$stops[0], $stops[2], $stops[1]], TripStopPass::orderBy('id')->pluck('stop_id')->all());
        $this->assertSame('skipped', TripStopPass::where('stop_id', $stops[1])->value('status'));
        $this->assertSame(1, \App\Models\TripLegIncident::where('type', 'skipped')->where('stop_id', $stops[1])->count());
        $leg = TripLeg::find($legId);
        $this->assertSame('last_stop', $leg->end_reason);
        $this->assertNotNull($leg->ended_at);

        Carbon::setTestNow(Carbon::create(2026, 11, 3, 17, 11));
        $this->sendPosition($this->driver, $legId, 23.12);
        $this->assertJsonApiError(409, 'LEG_NOT_ACTIVE');
    }

    public function testElRegresoRecorreLasParadasEnOrdenInverso()
    {
        $legId = $this->startLeg($this->driver, 'return')->responseJson()['data']['id'];

        // Cerca de la primera parada del itinerario: en el regreso es la última
        $this->sendPosition($this->driver, $legId, 23.1001);

        $leg = TripLeg::find($legId);
        $this->assertSame('last_stop', $leg->end_reason);
    }

    public function testCombinacionDeSensores()
    {
        $legId = $this->startLeg($this->driver)->responseJson()['data']['id'];
        $other = $this->joinItinerary($this->createWorker(), $this->itinerary);
        $far = $this->joinItinerary($this->createWorker(), $this->itinerary);

        $this->sendPosition($this->driver, $legId, 23.1050);
        $this->sendPosition($this->member, $legId, 23.1052);
        $this->sendPosition($other, $legId, 23.1054);
        $this->sendPosition($far, $legId, 23.2000);

        $this->jsonApiAs($this->member, 'GET', '/api/v1/trip-legs/'.$legId);
        $meta = $this->responseJson()['data']['meta'];
        $this->assertSame(3, $meta['activeSensors']);
        $this->assertEqualsWithDelta(23.1052, $meta['currentPosition']['latitude'], 0.00001);

        // Pasado el tiempo de inactividad (60 s), los sensores dejan de contar
        Carbon::setTestNow(Carbon::create(2026, 11, 3, 17, 2));
        $this->jsonApiAs($this->member, 'GET', '/api/v1/trip-legs/'.$legId);
        $this->assertSame(0, $this->responseJson()['data']['meta']['activeSensors']);
    }

    public function testSoloElChoferYLosMiembrosSonSensores()
    {
        $legId = $this->startLeg($this->driver)->responseJson()['data']['id'];
        $chief = $this->createTransportChief();

        $this->sendPosition($chief, $legId, 23.105);

        $this->assertJsonApiError(403, 'FORBIDDEN');
    }

    public function testSubidaAutomatica()
    {
        $legId = $this->startLeg($this->driver)->responseJson()['data']['id'];

        foreach ([0, 10, 20] as $index => $seconds) {
            Carbon::setTestNow(Carbon::create(2026, 11, 3, 17, 5, $seconds));
            $latitude = 23.1030 + $index * 0.001;
            $this->sendPosition($this->driver, $legId, $latitude);
            $this->sendPosition($this->member, $legId, $latitude + 0.0001);
        }

        $boarding = TripBoarding::where('worker_id', $this->member->id)->first();
        $this->assertNotNull($boarding);
        $this->assertSame('automatic', $boarding->method);
    }

    public function testNoSubeAutomaticamenteSiElVehiculoEstaParado()
    {
        $legId = $this->startLeg($this->driver)->responseJson()['data']['id'];

        foreach ([0, 10, 20] as $seconds) {
            Carbon::setTestNow(Carbon::create(2026, 11, 3, 17, 5, $seconds));
            $this->sendPosition($this->driver, $legId, 23.1050);
            $this->sendPosition($this->member, $legId, 23.1051);
        }

        $this->assertSame(0, TripBoarding::count());
    }

    public function testRegistroDeSubida()
    {
        $legId = $this->startLeg($this->driver, 'return')->responseJson()['data']['id'];

        $this->board($this->member, $legId, 'self', ['childrenCount' => 1]);
        $this->assertJsonApiError(422, 'CHILDREN_COUNT_EXCEEDED');

        $this->board($this->member, $legId, 'self', ['childrenCount' => 0]);
        $this->assertResponseStatus(201);
        $this->seeJson(['method' => 'self', 'childrenCount' => 0]);

        $other = $this->joinItinerary($this->createWorker(), $this->itinerary, 3);
        $this->board($this->member, $legId, 'manual', [], $other->id);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->board($this->driver, $legId, 'manual', [], $other->id);
        $this->assertResponseStatus(201);

        $stranger = $this->createWorker();
        $this->board($this->driver, $legId, 'manual', [], $stranger->id);
        $this->assertJsonApiError(422, 'NOT_A_PASSENGER');

        $this->jsonApiAs($this->driver, 'GET', '/api/v1/trips/'.$this->trip->id.'/passengers?filter[direction]=return');
        $methods = array_column(array_column($this->responseJson()['data'], 'attributes'), 'boardingMethod');
        sort($methods);
        $this->assertSame(['manual', 'self'], $methods);
    }

    public function testSubidaConCodigoQr()
    {
        $legId = $this->startLeg($this->driver, 'return')->responseJson()['data']['id'];

        $this->jsonApiAs($this->member, 'POST', '/api/v1/boarding-passes', ['data' => ['type' => 'boarding-passes', 'relationships' => [
            'tripLeg' => ['data' => ['type' => 'trip-legs', 'id' => (string) $legId]],
        ]]]);
        $this->assertResponseStatus(201);
        $token = $this->responseJson()['data']['attributes']['token'];
        // El QR no lleva datos personales (ni el usuario ni el Pase).
        $payload = base64_decode(strtr(explode('.', $token)[1], '-_', '+/'));
        $this->assertStringNotContainsString((string) $this->member->user->username, $payload);
        $this->assertStringNotContainsString('"pass"', $payload);

        $this->board($this->driver, $legId, 'qr', ['boardingPassToken' => 'basura']);
        $this->assertJsonApiError(422, 'BOARDING_PASS_INVALID');

        $this->board($this->driver, $legId, 'qr', ['boardingPassToken' => $token]);
        $this->assertResponseStatus(201);
        $this->assertSame((string) $this->member->id, $this->responseJson()['data']['relationships']['worker']['data']['id']);

        Carbon::setTestNow(Carbon::create(2026, 11, 3, 17, 5));
        $this->board($this->driver, $legId, 'qr', ['boardingPassToken' => $token]);
        $this->assertJsonApiError(422, 'BOARDING_PASS_INVALID');
    }

    public function testPosicionesAcumuladasConOperacionesYFinManual()
    {
        $legId = $this->startLeg($this->driver)->responseJson()['data']['id'];
        $operations = [];
        foreach ([0, 5, 10] as $seconds) {
            $operations[] = ['op' => 'add', 'data' => ['type' => 'trip-positions',
                'attributes' => ['latitude' => 23.105, 'longitude' => -82.3, 'recordedAt' => Carbon::create(2026, 11, 3, 16, 59, 50 - $seconds)->toIso8601String()],
                'relationships' => ['tripLeg' => ['data' => ['type' => 'trip-legs', 'id' => (string) $legId]]],
            ]];
        }

        $this->jsonApiAs($this->member, 'POST', '/api/v1/operations', ['atomic:operations' => $operations], [
            'Content-Type' => 'application/vnd.api+json; ext="https://jsonapi.org/ext/atomic"',
        ]);
        $this->assertResponseOk();

        $this->jsonApiAs($this->member, 'GET', '/api/v1/trip-positions?filter[tripLeg]='.$legId);
        $this->assertSame(3, $this->responseJson()['meta']['total']);

        $this->jsonApiAs($this->driver, 'PATCH', '/api/v1/trip-legs/'.$legId, ['data' => ['type' => 'trip-legs', 'id' => $legId, 'attributes' => ['endedAt' => Carbon::now()->toIso8601String()]]]);
        $this->assertResponseOk();
        $this->seeJson(['endReason' => 'manual']);
    }
}
