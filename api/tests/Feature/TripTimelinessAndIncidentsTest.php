<?php

use App\Models\Notice;
use App\Models\Trip;
use App\Models\TripLeg;
use App\Models\TripLegIncident;
use App\Models\TripPosition;
use App\Models\TripStopPass;
use Carbon\Carbon;
use Carbon\CarbonImmutable;
use Laravel\Lumen\Testing\DatabaseMigrations;

/**
 * Viajes atrasados, aviso de comienzo, paradas no realizadas y desvíos
 * (docs/09-repaso-pantallas.md).
 */
class TripTimelinessAndIncidentsTest extends TestCase
{
    use DatabaseMigrations;

    private $itinerary;
    private $driver;
    private $trip;
    private $member;
    private $chief;
    private $transportChief;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
        $this->clock(17, 0);

        // Paradas en latitud 23.10, 23.11 y 23.12, longitud -82.3 (≈ 1,1 km entre ellas).
        $this->itinerary = $this->createItinerary('Ruta Este', 3);
        $this->driver = $this->createDriver();
        $this->chief = $this->createItineraryChief($this->itinerary);
        $this->transportChief = $this->createTransportChief();
        $this->trip = $this->createTripAt(Carbon::create(2026, 11, 3, 17));
        $this->member = $this->joinItinerary($this->createWorker(), $this->itinerary, 2);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }

    private function clock(int $hour, int $minute, int $second = 0): Carbon
    {
        $now = Carbon::create(2026, 11, 3, $hour, $minute, $second);
        Carbon::setTestNow($now);
        CarbonImmutable::setTestNow(CarbonImmutable::instance($now));

        return $now;
    }

    private function createTripAt(Carbon $departsAt): Trip
    {
        return Trip::create([
            'itinerary_id' => $this->itinerary->id, 'vehicle_id' => $this->createVehicle()->id, 'driver_id' => $this->driver->driverId(),
            'departs_at' => $departsAt, 'returns_at' => $departsAt->copy()->addHours(10),
            'status' => Trip::STATUS_CONFIRMED, 'created_by' => $this->transportChief->user_id,
        ]);
    }

    private function startLeg(Trip $trip, string $direction = 'outbound'): string
    {
        $this->jsonApiAs($this->driver, 'POST', '/api/v1/trip-legs', ['data' => ['type' => 'trip-legs',
            'attributes' => ['direction' => $direction],
            'relationships' => ['trip' => ['data' => ['type' => 'trips', 'id' => (string) $trip->id]]],
        ]]);
        $this->assertResponseStatus(201);

        return $this->responseJson()['data']['id'];
    }

    private function sendPosition($legId, float $latitude, float $longitude = -82.3)
    {
        $this->jsonApiAs($this->driver, 'POST', '/api/v1/trip-positions', ['data' => ['type' => 'trip-positions',
            'attributes' => ['latitude' => $latitude, 'longitude' => $longitude, 'accuracyM' => 5, 'recordedAt' => Carbon::now()->toIso8601String()],
            'relationships' => ['tripLeg' => ['data' => ['type' => 'trip-legs', 'id' => (string) $legId]]],
        ]]);
        $this->assertResponseStatus(201);
    }

    private function noticesOf($worker, string $type)
    {
        return Notice::where('user_id', $worker->user_id)->where('type', $type)->get();
    }

    public function testViajeAtrasadoYAvisoUnaSolaVez()
    {
        // Dentro de la tolerancia (5 min) todavía no está atrasado.
        $this->clock(17, 4);
        $this->jsonApiAs($this->member, 'GET', '/api/v1/trips/'.$this->trip->id);
        $this->seeJson(['outboundDelayed' => false, 'outboundDelayMinutes' => null]);

        $this->clock(17, 10);
        $this->jsonApiAs($this->member, 'GET', '/api/v1/trips/'.$this->trip->id);
        $this->seeJson(['outboundDelayed' => true, 'outboundDelayMinutes' => 10, 'returnDelayed' => false]);

        $this->artisan('trips:notify-delays');
        $this->artisan('trips:notify-delays');
        $notices = $this->noticesOf($this->member, Notice::TYPE_TRIP_DELAYED);
        $this->assertCount(1, $notices);
        $this->assertSame(1, $this->noticesOf($this->chief, Notice::TYPE_TRIP_DELAYED)->count());

        $this->jsonApiAs($this->member, 'GET', '/api/v1/notices');
        $this->seeJson(['message' => 'El viaje de ida de Ruta Este está atrasado: debía comenzar a las 17:00.']);
    }

    public function testAvisoDeComienzoConElAtraso()
    {
        // Quien lo desactiva en sus ajustes no lo recibe.
        $other = $this->joinItinerary($this->createWorker(), $this->itinerary, 3);
        $this->jsonApiAs($other, 'PATCH', '/api/v1/me/settings/trip_start_notice_enabled', [
            'data' => ['type' => 'user-settings', 'id' => 'trip_start_notice_enabled', 'attributes' => ['value' => false]],
        ]);
        $this->assertResponseOk();

        $this->clock(17, 12);
        $this->startLeg($this->trip);

        $this->assertCount(1, $this->noticesOf($this->member, Notice::TYPE_TRIP_STARTED));
        $this->assertCount(0, $this->noticesOf($other, Notice::TYPE_TRIP_STARTED));
        $this->assertCount(0, $this->noticesOf($this->driver, Notice::TYPE_TRIP_STARTED), 'quien lo inicia no se avisa a sí mismo');

        $this->jsonApiAs($this->member, 'GET', '/api/v1/notices');
        $this->seeJson(['message' => 'Comenzó el viaje de ida de Ruta Este (12 min de atraso).']);
        $this->jsonApiAs($this->member, 'GET', '/api/v1/trips/'.$this->trip->id);
        $this->seeJson(['outboundDelayed' => false, 'outboundDelayMinutes' => 12]);
    }

    public function testParadaDondeNoSeDetuvoYParadaDondeSiParo()
    {
        $legId = $this->startLeg($this->trip);
        $stops = $this->itinerary->stops->pluck('id')->all();

        // Sale de la primera parada (la de salida nunca cuenta como incidencia).
        $this->sendPosition($legId, 23.1000);
        $this->clock(17, 0, 5);
        $this->sendPosition($legId, 23.1020);

        // Pasa por la segunda sin detenerse: 10 s dentro del radio y siempre rápido.
        $this->clock(17, 2, 0);
        $this->sendPosition($legId, 23.1095);
        $this->clock(17, 2, 5);
        $this->sendPosition($legId, 23.1102);
        $this->clock(17, 2, 10);
        $this->sendPosition($legId, 23.1120);

        $this->assertSame('stopped', TripStopPass::where('stop_id', $stops[0])->value('status'));
        $this->assertSame('not_stopped', TripStopPass::where('stop_id', $stops[1])->value('status'));
        $incident = TripLegIncident::where('type', 'not_stopped')->first();
        $this->assertSame((int) $stops[1], (int) $incident->stop_id);
        $this->assertCount(1, $this->noticesOf($this->chief, Notice::TYPE_TRIP_INCIDENT));
        $this->assertCount(1, $this->noticesOf($this->transportChief, Notice::TYPE_TRIP_INCIDENT));
        $this->assertCount(0, $this->noticesOf($this->member, Notice::TYPE_TRIP_INCIDENT), 'a los pasajeros no se les avisa');

        $this->jsonApiAs($this->chief, 'GET', '/api/v1/notices');
        $this->seeJson(['message' => 'Viaje de ida de Ruta Este: no se detuvo en la parada Ruta Este parada 2.']);

        $this->jsonApiAs($this->chief, 'GET', '/api/v1/trip-legs/'.$legId);
        $this->assertSame('not_stopped', $this->responseJson()['data']['meta']['incidents'][0]['type']);
    }

    public function testSiSeDetieneLoSuficienteNoHayIncidencia()
    {
        $legId = $this->startLeg($this->trip);
        $this->sendPosition($legId, 23.1000);
        $this->clock(17, 2, 0);
        $this->sendPosition($legId, 23.1100);
        $this->clock(17, 2, 30);
        $this->sendPosition($legId, 23.1100);
        $this->clock(17, 3, 0);
        $this->sendPosition($legId, 23.1130);

        $stops = $this->itinerary->stops->pluck('id')->all();
        $this->assertSame('stopped', TripStopPass::where('stop_id', $stops[1])->value('status'));
        $this->assertSame(0, TripLegIncident::count());
    }

    public function testDesvioDelRecorridoDeReferencia()
    {
        // Un viaje anterior ya realizado sirve de recorrido de referencia.
        $previous = $this->createTripAt(Carbon::create(2026, 11, 2, 17));
        $reference = TripLeg::create([
            'trip_id' => $previous->id, 'direction' => 'outbound', 'started_at' => Carbon::create(2026, 11, 2, 17),
            'started_by' => $this->driver->user_id, 'ended_at' => Carbon::create(2026, 11, 2, 17, 30), 'end_reason' => 'last_stop',
        ]);
        foreach ([23.100, 23.105, 23.110, 23.115, 23.120] as $i => $latitude) {
            TripPosition::create(['trip_leg_id' => $reference->id, 'worker_id' => $this->driver->id, 'latitude' => $latitude,
                'longitude' => -82.3, 'recorded_at' => Carbon::create(2026, 11, 2, 17, $i)]);
        }

        $this->jsonApiAs($this->chief, 'PATCH', '/api/v1/itineraries/'.$this->itinerary->id, ['data' => ['type' => 'itineraries',
            'id' => (string) $this->itinerary->id,
            'relationships' => ['referenceOutboundLeg' => ['data' => ['type' => 'trip-legs', 'id' => (string) $reference->id]]],
        ]]);
        $this->assertResponseOk();
        $this->seeJson(['referenceOutboundLeg' => ['data' => ['type' => 'trip-legs', 'id' => (string) $reference->id]]]);

        // Uno de regreso no sirve como referencia de ida.
        $this->jsonApiAs($this->chief, 'PATCH', '/api/v1/itineraries/'.$this->itinerary->id, ['data' => ['type' => 'itineraries',
            'id' => (string) $this->itinerary->id,
            'relationships' => ['referenceReturnLeg' => ['data' => ['type' => 'trip-legs', 'id' => (string) $reference->id]]],
        ]]);
        $this->assertJsonApiError(422, 'INVALID_REFERENCE_LEG', '/data/relationships/referenceReturnLeg');

        $legId = $this->startLeg($this->trip);
        $this->sendPosition($legId, 23.1050);
        $this->assertSame(0, TripLegIncident::count());

        // Se aleja ≈ 1 km del recorrido.
        $this->clock(17, 1);
        $this->sendPosition($legId, 23.1050, -82.31);
        $this->clock(17, 2);
        $this->sendPosition($legId, 23.1060, -82.312);
        $incident = TripLegIncident::where('type', 'deviation')->first();
        $this->assertNotNull($incident);
        $this->assertNull($incident->ended_at);
        $this->assertTrue(TripLeg::find($legId)->deviating);
        $this->assertCount(1, $this->noticesOf($this->chief, Notice::TYPE_TRIP_INCIDENT));

        // Vuelve al recorrido.
        $this->clock(17, 3);
        $this->sendPosition($legId, 23.1070);
        $this->assertNotNull($incident->fresh()->ended_at);
        $this->assertFalse(TripLeg::find($legId)->deviating);
        $this->assertSame(1, TripLegIncident::count());
    }
}
