<?php

use App\Models\Absence;
use App\Models\AbsenceType;
use App\Models\Trip;
use App\Services\Absences;
use App\Services\Trips;
use Carbon\Carbon;
use Carbon\CarbonImmutable;
use Laravel\Lumen\Testing\DatabaseMigrations;

/**
 * Ausencias sin aprobación (docs/11 §11.12).
 */
class AbsencesTest extends TestCase
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

    private function declare($who, array $attributes, $worker = null)
    {
        $data = ['type' => 'absences', 'attributes' => $attributes, 'relationships' => [
            'absenceType' => ['data' => ['type' => 'absence-types', 'id' => (string) AbsenceType::first()->id]],
        ]];

        if ($worker) {
            $data['relationships']['worker'] = ['data' => ['type' => 'workers', 'id' => (string) $worker->id]];
        }

        return $this->jsonApiAs($who, 'POST', '/api/v1/absences', ['data' => $data]);
    }

    public function testLaPropiaPersonaLaDeclaraSinAprobacion()
    {
        $itinerary = $this->createItinerary();
        $worker = $this->joinItinerary($this->createWorker(), $itinerary);

        $this->declare($worker, ['startsOn' => '2026-11-05', 'endsOn' => '2026-11-10', 'note' => 'Vacaciones']);

        $this->assertResponseStatus(201);
        $this->seeJson(['startsOn' => '2026-11-05', 'endsOn' => '2026-11-10', 'indefinite' => false, 'note' => 'Vacaciones']);
        $absences = app(Absences::class);
        $this->assertTrue($absences->isAbsent($worker->id, Carbon::create(2026, 11, 7)));
        $this->assertFalse($absences->isAbsent($worker->id, Carbon::create(2026, 11, 11)));

        // Durante la ausencia no cuenta como pasajero esperado.
        $trip = Trip::create(['itinerary_id' => $itinerary->id, 'vehicle_id' => $this->createVehicle()->id, 'driver_id' => $this->createDriver()->id,
            'departs_at' => '2026-11-07 17:00', 'returns_at' => '2026-11-08 06:00', 'status' => 'confirmed', 'created_by' => $worker->user_id]);
        $this->assertFalse(app(Trips::class)->expectedPassengers($trip)->contains('id', $worker->id));
    }

    public function testIndefinidaYDespuesConFechas()
    {
        $worker = $this->createWorker();

        $this->declare($worker, ['indefinite' => true]);
        $this->assertResponseStatus(201);
        $this->seeJson(['indefinite' => true, 'endsOn' => null, 'startsOn' => '2026-11-02']);
        $id = $this->responseJson()['data']['id'];
        $this->assertTrue(app(Absences::class)->isAbsent($worker->id, Carbon::create(2027, 5, 1)));

        $this->jsonApiAs($worker, 'PATCH', '/api/v1/absences/'.$id, ['data' => ['type' => 'absences', 'id' => $id, 'attributes' => [
            'indefinite' => false, 'endsOn' => '2026-11-20',
        ]]]);
        $this->assertResponseOk();
        $this->seeJson(['indefinite' => false, 'endsOn' => '2026-11-20']);

        $this->jsonApiAs($worker, 'PATCH', '/api/v1/absences/'.$id, ['data' => ['type' => 'absences', 'id' => $id, 'attributes' => ['endsOn' => '2026-10-01']]]);
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/endsOn');

        $this->jsonApiAs($worker, 'DELETE', '/api/v1/absences/'.$id);
        $this->assertResponseStatus(204);
        $this->assertSame(0, Absence::count());
    }

    public function testConVariasEntidadesIndicaLaPertenencia()
    {
        $worker = $this->createWorker();
        $other = $this->createWorker(['user_id' => $worker->user_id], $this->createEntity('OTRA'));

        $this->declare($worker, ['startsOn' => '2026-11-05', 'endsOn' => '2026-11-06']);
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/relationships/worker');

        $this->declare($worker, ['startsOn' => '2026-11-05', 'endsOn' => '2026-11-06'], $other);
        $this->assertResponseStatus(201);
        $this->assertSame($other->id, (int) Absence::first()->worker_id);
    }

    public function testLasDeOtrosConPermiso()
    {
        $itinerary = $this->createItinerary();
        $worker = $this->joinItinerary($this->createWorker(), $itinerary);
        $chief = $this->createItineraryChief($itinerary);
        $peer = $this->joinItinerary($this->createWorker(), $itinerary);

        // Un compañero no declara las de otro.
        $this->declare($peer, ['indefinite' => true], $worker);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        // El Administrador sí (absences.manage).
        $this->declare($this->createAdmin(), ['indefinite' => true], $worker);
        $this->assertResponseStatus(201);

        // El Jefe de itinerario las consulta (absences.view), pero no las gestiona.
        $this->jsonApiAs($chief, 'GET', '/api/v1/absences');
        $this->assertSame(1, $this->responseJson()['meta']['total']);
        $this->jsonApiAs($chief, 'DELETE', '/api/v1/absences/'.Absence::first()->id);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->jsonApiAs($peer, 'GET', '/api/v1/absences');
        $this->assertSame(0, $this->responseJson()['meta']['total']);
    }
}
