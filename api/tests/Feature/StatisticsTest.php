<?php

use App\Models\Trip;
use App\Models\TripBoarding;
use App\Models\TripLeg;
use App\Models\TripPosition;
use App\Models\Vehicle;
use App\Models\VehicleType;
use Carbon\Carbon;
use Carbon\CarbonImmutable;
use Laravel\Lumen\Testing\DatabaseMigrations;

class StatisticsTest extends TestCase
{
    use DatabaseMigrations;

    private $chief;
    private $itinerary;
    private $driver;
    private $member;
    private $trip;
    private $outbound;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
        Carbon::setTestNow(Carbon::create(2026, 11, 10, 12));
        CarbonImmutable::setTestNow(CarbonImmutable::create(2026, 11, 10, 12));

        $this->chief = $this->createTransportChief();
        $this->itinerary = $this->createItinerary('Ruta Este');
        $this->driver = $this->createDriver();
        $this->member = $this->joinItinerary($this->createWorker(), $this->itinerary, 2);
        $this->joinItinerary($this->createWorker(), $this->itinerary, 3);
        $vehicle = Vehicle::create(['entity_id' => $this->defaultEntity()->id, 'vehicle_type_id' => VehicleType::first()->id, 'plate' => 'B1', 'seats' => 1, 'standing_capacity' => 0]);

        $this->trip = Trip::create([
            'itinerary_id' => $this->itinerary->id, 'vehicle_id' => $vehicle->id, 'driver_id' => $this->driver->id,
            'departs_at' => Carbon::create(2026, 11, 5, 17), 'returns_at' => Carbon::create(2026, 11, 6, 6),
            'status' => Trip::STATUS_COMPLETED, 'created_by' => $this->chief->id,
        ]);
        $outbound = TripLeg::create(['trip_id' => $this->trip->id, 'direction' => 'outbound', 'started_at' => Carbon::create(2026, 11, 5, 17, 10),
            'ended_at' => Carbon::create(2026, 11, 5, 17, 40), 'started_by' => $this->driver->id]);
        $return = TripLeg::create(['trip_id' => $this->trip->id, 'direction' => 'return', 'started_at' => Carbon::create(2026, 11, 6, 6),
            'ended_at' => Carbon::create(2026, 11, 6, 6, 50), 'started_by' => $this->driver->id]);
        $boarding = TripBoarding::create(['trip_leg_id' => $return->id, 'worker_id' => $this->member->id, 'method' => 'qr', 'children_count' => 1, 'boarded_at' => Carbon::create(2026, 11, 6, 6, 5)]);
        // Un hijo con derecho que sube y otro que no viaja.
        $child = $this->createChild($this->member);
        $this->createChild($this->member, '2019-02-02');
        \App\Models\TripBoardingChild::create(['trip_boarding_id' => $boarding->id, 'trip_leg_id' => $return->id, 'child_id' => $child->id]);
        $this->outbound = $outbound;
        foreach ([23.10, 23.11, 23.12] as $index => $latitude) {
            TripPosition::create(['trip_leg_id' => $outbound->id, 'worker_id' => $this->driver->id, 'latitude' => $latitude, 'longitude' => -82.3, 'recorded_at' => Carbon::create(2026, 11, 5, 17, 10 + $index * 10)]);
        }
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }

    private function statistic($user, string $query)
    {
        $this->jsonApiAs($user, 'GET', '/api/v1/statistics/'.$query);

        return $this->responseJson();
    }

    public function testViajesPorEstadoConPeriodos()
    {
        $json = $this->statistic($this->chief, 'trips-by-status?filter[last]=7d');
        $this->assertResponseOk();
        $this->assertSame('statistics', $json['data']['type']);
        $this->assertSame(['from' => '2026-11-04', 'to' => '2026-11-10', 'dates' => null], $json['data']['meta']['period']);
        $this->assertContains(['status' => 'completed', 'trips' => 1], $json['data']['attributes']['rows']);

        $json = $this->statistic($this->chief, 'trips-by-status?filter[last]=3d');
        $this->assertContains(['status' => 'completed', 'trips' => 0], $json['data']['attributes']['rows']);

        $json = $this->statistic($this->chief, 'trips-by-status?filter[dates]=2026-11-05,2026-11-01');
        $this->assertSame(['2026-11-01', '2026-11-05'], $json['data']['meta']['period']['dates']);
        $this->assertContains(['status' => 'completed', 'trips' => 1], $json['data']['attributes']['rows']);

        $this->statistic($this->chief, 'trips-by-status?filter[last]=7d&filter[from]=2026-11-01');
        $this->assertJsonApiError(400, 'BAD_REQUEST');
        $this->statistic($this->chief, 'trips-by-status?filter[from]=2026-11-09&filter[to]=2026-11-01');
        $this->assertJsonApiError(400, 'BAD_REQUEST');
    }

    public function testPuntualidadDuracionYDistancia()
    {
        $rows = $this->statistic($this->chief, 'punctuality')['data']['attributes']['rows'];
        $this->assertEquals(10.0, $rows[0]['avgDepartureDelayMinutes']);
        $this->assertEquals(50.0, $rows[0]['avgArrivalDelayMinutes']);

        $rows = $this->statistic($this->chief, 'duration')['data']['attributes']['rows'];
        $this->assertEquals([30, 50], array_column($rows, 'avgMinutes'));

        $rows = $this->statistic($this->chief, 'distance')['data']['attributes']['rows'];
        $this->assertEqualsWithDelta(2.22, $rows[0]['kilometers'], 0.01);
    }

    public function testOcupacionAsistenciaYNinos()
    {
        $rows = $this->statistic($this->chief, 'overloaded-trips')['data']['attributes']['rows'];
        $this->assertSame(1, $rows[0]['excess']);

        $rows = $this->statistic($this->chief, 'attendance')['data']['attributes']['rows'];
        $this->assertSame([1, 0], array_column($rows, 'boarded'));

        $rows = $this->statistic($this->chief, 'children-transported')['data']['attributes']['rows'];
        $this->assertSame(1, $rows[0]['children']);
        $this->assertSame(1, $rows[0]['distinctChildren']);
        $this->assertSame(2, $rows[0]['eligibleChildren']);

        $rows = $this->statistic($this->chief, 'occupancy')['data']['attributes']['rows'];
        $this->assertEquals(200.0, $rows[0]['expectedOccupancy']);
        $this->assertEquals(100.0, $rows[0]['realOccupancy']);
    }

    public function testTrabajadoresQueViajanFueraDeSuItinerario()
    {
        $otherItinerary = $this->createItinerary('Ruta Oeste');
        $visitor = $this->joinItinerary($this->createWorker(), $otherItinerary);
        $foreign = $this->createWorker([], $this->createEntity('OTRA'));
        TripBoarding::create(['trip_leg_id' => $this->outbound->id, 'worker_id' => $visitor->id, 'method' => 'qr', 'outsider' => 'itinerary', 'boarded_at' => Carbon::create(2026, 11, 5, 17, 15)]);
        TripBoarding::create(['trip_leg_id' => $this->outbound->id, 'worker_id' => $foreign->id, 'method' => 'manual', 'outsider' => 'entity', 'boarded_at' => Carbon::create(2026, 11, 5, 17, 16)]);

        $json = $this->statistic($this->chief, 'outsider-travellers');
        $this->assertResponseOk();
        $rows = $json['data']['attributes']['rows'];
        $this->assertCount(2, $rows);
        $byType = array_column($rows, null, 'outsider');
        $this->assertSame('Ruta Oeste', $byType['De otro itinerario']['ownItinerary']);
        $this->assertSame('Ruta Este', $byType['De otro itinerario']['itinerary']);
        $this->assertSame('OTRA', $byType['De otra Entidad']['entity']);
        $this->assertSame(1, $byType['De otra Entidad']['trips']);

        // El chofer la ve de sus viajes; un trabajador, no.
        $this->assertCount(2, $this->statistic($this->driver, 'outsider-travellers')['data']['attributes']['rows']);
        $this->statistic($this->member, 'outsider-travellers');
        $this->assertJsonApiError(403, 'FORBIDDEN');
    }

    public function testDistribucionDeTrabajadores()
    {
        $rows = $this->statistic($this->chief, 'workers-distribution?filter[by]=itinerary')['data']['attributes']['rows'];
        $this->assertContains(['group' => 'Ruta Este', 'workers' => 2], $rows);

        $this->statistic($this->chief, 'workers-distribution?filter[by]=color');
        $this->assertJsonApiError(400, 'BAD_REQUEST');
    }

    public function testPermisosPorRol()
    {
        $this->statistic($this->member, 'trips-by-status');
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $rows = $this->statistic($this->member, 'worker-trips')['data']['attributes']['rows'];
        $this->assertSame([['trip' => (string) $this->trip->id, 'departsAt' => '2026-11-05T17:00:00+00:00', 'itinerary' => 'Ruta Este', 'direction' => 'return', 'method' => 'qr', 'children' => 1]], $rows);

        $this->statistic($this->member, 'worker-trips?filter[worker]='.$this->driver->id);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        // Un Jefe de otro itinerario no ve los viajes de este
        $otherChief = $this->createItineraryChief($this->createItinerary('Ruta Oeste'));
        $rows = $this->statistic($otherChief, 'trips-by-status')['data']['attributes']['rows'];
        $this->assertContains(['status' => 'completed', 'trips' => 0], $rows);

        // El chofer ve las suyas
        $rows = $this->statistic($this->driver, 'trips-by-status')['data']['attributes']['rows'];
        $this->assertContains(['status' => 'completed', 'trips' => 1], $rows);
    }

    public function testViajeEnMarcha()
    {
        $this->trip->update(['status' => Trip::STATUS_CONFIRMED]);

        $rows = $this->statistic($this->member, 'live-trip?filter[trip]='.$this->trip->id)['data']['attributes']['rows'];

        $this->assertSame(['outbound', 'return'], array_column($rows, 'direction'));
        $this->assertSame(1, $rows[1]['boarded']);
        $this->assertSame(1, $rows[1]['children']);
        $this->assertEquals(10.0, $rows[0]['startDelayMinutes']);
    }

    public function testEstadisticaInexistente()
    {
        $this->statistic($this->chief, 'no-existe');
        $this->assertJsonApiError(404, 'NOT_FOUND');
    }
}
