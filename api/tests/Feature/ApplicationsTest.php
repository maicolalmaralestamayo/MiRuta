<?php

use App\Models\Application;
use App\Models\Child;
use App\Models\Driver;
use App\Models\ItineraryChief;
use App\Models\Notice;
use App\Models\Rank;
use App\Models\Vehicle;
use App\Models\VehicleType;
use App\Services\Absences;
use Carbon\Carbon;
use Carbon\CarbonImmutable;
use Laravel\Lumen\Testing\DatabaseMigrations;

class ApplicationsTest extends TestCase
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

    private function apply($worker, string $type, array $attributes = [], array $relationships = [])
    {
        $data = ['type' => 'applications', 'attributes' => ['type' => $type] + $attributes];

        if ($relationships) {
            $data['relationships'] = [];
            foreach ($relationships as $name => list($jsonType, $id)) {
                $data['relationships'][$name] = ['data' => ['type' => $jsonType, 'id' => (string) $id]];
            }
        }

        return $this->jsonApiAs($worker, 'POST', '/api/v1/applications', ['data' => $data]);
    }

    private function resolve($worker, $applicationId, string $status, ?string $note = null)
    {
        $attributes = ['status' => $status];
        if ($note !== null) {
            $attributes['resolutionNote'] = $note;
        }

        return $this->jsonApiAs($worker, 'PATCH', '/api/v1/applications/'.$applicationId, ['data' => [
            'type' => 'applications', 'id' => (string) $applicationId, 'attributes' => $attributes,
        ]]);
    }

    private function makeChief($worker, $itinerary)
    {
        ItineraryChief::create(['itinerary_id' => $itinerary->id, 'worker_id' => $worker->id]);

        return $worker->refreshRoles();
    }

    private function stopId($itinerary, int $position): int
    {
        return (int) $itinerary->itineraryStops()->where('position', $position)->value('stop_id');
    }

    public function testPertenenciaAprobadaPorUnJefeDelItinerario()
    {
        $east = $this->createItinerary('Ruta Este');
        $west = $this->createItinerary('Ruta Oeste');
        $eastChief = $this->makeChief($this->createWorker(), $east);
        $westChief = $this->makeChief($this->createWorker(), $west);
        $worker = $this->createWorker();

        $this->apply($worker, 'itinerary_membership', [], ['itinerary' => ['itineraries', $east->id], 'stop' => ['stops', $this->stopId($east, 2)]]);
        $this->assertResponseStatus(201);
        $applicationId = $this->responseJson()['data']['id'];
        $this->seeJson(['status' => 'pending', 'type' => 'itinerary_membership']);

        $this->assertTrue(Notice::where('worker_id', $eastChief->id)->where('type', 'application_received')->exists());
        $this->assertFalse(Notice::where('worker_id', $westChief->id)->exists());

        $this->jsonApiAs($eastChief, 'GET', '/api/v1/applications?filter[toResolve]=true');
        $this->assertSame([$applicationId], array_column($this->responseJson()['data'], 'id'));
        $this->jsonApiAs($westChief, 'GET', '/api/v1/applications?filter[toResolve]=true');
        $this->assertSame([], $this->responseJson()['data']);

        $this->resolve($westChief, $applicationId, 'approved');
        $this->assertJsonApiError(404, 'NOT_FOUND');

        $this->resolve($eastChief, $applicationId, 'approved', 'Bienvenido');
        $this->assertResponseOk();
        $this->seeJson(['status' => 'approved', 'resolutionNote' => 'Bienvenido']);

        $worker = $worker->fresh();
        $this->assertSame($east->id, (int) $worker->itinerary_id);
        $this->assertSame($this->stopId($east, 2), (int) $worker->stop_id);
        $this->assertTrue(Notice::where('worker_id', $worker->id)->where('type', 'application_resolved')->exists());

        $this->resolve($eastChief, $applicationId, 'rejected');
        $this->assertJsonApiError(409, 'APPLICATION_NOT_PENDING');
    }

    public function testNadieResuelveSusPropiasSolicitudesNiSiquieraElAdministrador()
    {
        $itinerary = $this->createItinerary();
        $admin = $this->createAdmin();

        $this->apply($admin, 'itinerary_membership', [], ['itinerary' => ['itineraries', $itinerary->id], 'stop' => ['stops', $this->stopId($itinerary, 1)]]);
        $this->resolve($admin, $this->responseJson()['data']['id'], 'approved');

        $this->assertJsonApiError(403, 'SELF_APPROVAL');
    }

    public function testLaParadaDebeSerDelItinerario()
    {
        $east = $this->createItinerary('Ruta Este');
        $west = $this->createItinerary('Ruta Oeste');

        $this->apply($this->createWorker(), 'itinerary_membership', [], ['itinerary' => ['itineraries', $east->id], 'stop' => ['stops', $this->stopId($west, 1)]]);

        $this->assertJsonApiError(422, 'STOP_NOT_IN_ITINERARY', '/data/relationships/stop');
    }

    public function testUnaSolicitudPendienteDeCadaTipoYCancelacion()
    {
        $itinerary = $this->createItinerary();
        $worker = $this->createWorker();
        $relationships = ['itinerary' => ['itineraries', $itinerary->id], 'stop' => ['stops', $this->stopId($itinerary, 1)]];

        $this->apply($worker, 'itinerary_membership', [], $relationships);
        $id = $this->responseJson()['data']['id'];
        $this->apply($worker, 'itinerary_membership', [], $relationships);
        $this->assertJsonApiError(409, 'APPLICATION_ALREADY_PENDING');

        $this->resolve($this->createTransportChief(), $id, 'cancelled');
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->resolve($worker, $id, 'cancelled');
        $this->assertResponseOk();
        $this->seeJson(['status' => 'cancelled']);

        $this->apply($worker, 'itinerary_membership', [], $relationships);
        $this->assertResponseStatus(201);
    }

    public function testJefeDeItinerarioCambiaDeItinerarioYCancelaPendientes()
    {
        $east = $this->createItinerary('Ruta Este');
        $west = $this->createItinerary('Ruta Oeste');
        $transportChief = $this->createTransportChief();
        $worker = $this->joinItinerary($this->createWorker(), $west);

        $this->apply($worker, 'itinerary_membership', [], ['itinerary' => ['itineraries', $west->id], 'stop' => ['stops', $this->stopId($west, 3)]]);
        $pendingMembership = $this->responseJson()['data']['id'];

        $this->apply($worker, 'itinerary_chief', [], ['itinerary' => ['itineraries', $east->id], 'stop' => ['stops', $this->stopId($east, 2)]]);
        $chiefApplication = $this->responseJson()['data']['id'];

        // Un Jefe de itinerario no ve las solicitudes de jefatura
        $this->resolve($this->makeChief($this->createWorker(), $east), $chiefApplication, 'approved');
        $this->assertJsonApiError(404, 'NOT_FOUND');

        $this->resolve($transportChief, $chiefApplication, 'approved');
        $this->assertResponseOk();

        $worker = $worker->fresh()->refreshRoles();
        $this->assertTrue($worker->isChiefOf($east->id));
        $this->assertSame($east->id, (int) $worker->itinerary_id);
        $this->assertSame('cancelled', Application::find($pendingMembership)->status);

        // Sigue siendo jefe del Este aunque se cambie al Oeste
        $this->apply($worker, 'itinerary_membership', [], ['itinerary' => ['itineraries', $west->id], 'stop' => ['stops', $this->stopId($west, 1)]]);
        $this->resolve($transportChief, $this->responseJson()['data']['id'], 'approved');
        $worker = $worker->fresh()->refreshRoles();
        $this->assertSame($west->id, (int) $worker->itinerary_id);
        $this->assertTrue($worker->isChiefOf($east->id));
    }

    public function testJefeDeTransporteLoApruebaSoloElAdministrador()
    {
        $worker = $this->createWorker();
        $admin = $this->createAdmin();

        $this->apply($worker, 'transport_chief');
        $id = $this->responseJson()['data']['id'];
        $this->assertTrue(Notice::where('worker_id', $admin->id)->where('type', 'application_received')->exists());

        // El Jefe de Transporte la ve pero no puede resolverla
        $this->resolve($this->createTransportChief(), $id, 'approved');
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->resolve($admin, $id, 'approved');
        $this->assertResponseOk();
        $this->assertTrue($worker->fresh()->isTransportChief());

        $this->apply($worker, 'transport_chief');
        $this->assertJsonApiError(409, 'ALREADY_HAS_ROLE');
    }

    public function testChoferYCambioDeJerarquia()
    {
        $itinerary = $this->createItinerary();
        $chief = $this->makeChief($this->createWorker(), $itinerary);
        $transportChief = $this->createTransportChief();
        $worker = $this->joinItinerary($this->createWorker(), $itinerary);

        $this->apply($worker, 'driver');
        $driverApplication = $this->responseJson()['data']['id'];
        $this->resolve($chief, $driverApplication, 'approved');
        $this->assertJsonApiError(404, 'NOT_FOUND');
        $this->resolve($transportChief, $driverApplication, 'approved');
        $this->assertTrue($worker->fresh()->isDriver());

        $captain = Rank::where('name', 'Capitán')->first();
        $this->apply($worker, 'rank_change', [], ['rank' => ['ranks', $captain->id]]);
        $this->resolve($chief, $this->responseJson()['data']['id'], 'approved');
        $this->assertResponseOk();
        $this->assertSame($captain->id, (int) $worker->fresh()->rank_id);
    }

    public function testDeclararYQuitarHijos()
    {
        $itinerary = $this->createItinerary();
        $chief = $this->makeChief($this->createWorker(), $itinerary);
        $mother = $this->joinItinerary($this->createWorker(), $itinerary);
        $father = $this->joinItinerary($this->createWorker(), $itinerary);
        $child = ['childFirstName' => 'Pepito', 'childLastName' => 'Pérez', 'childCardNumber' => '15030560011'];

        $this->apply($mother, 'child_addition', ['childCardNumber' => '09120160011'] + $child);
        $this->assertJsonApiError(422, 'CHILD_NOT_ELIGIBLE', '/data/attributes/childCardNumber');

        $this->apply($mother, 'child_addition', ['childCardNumber' => '123'] + $child);
        $this->assertJsonApiError(422, 'CARD_NUMBER_INVALID', '/data/attributes/childCardNumber');

        $this->apply($mother, 'child_addition', $child);
        $this->assertResponseStatus(201);
        $this->seeJson(['childFirstName' => 'Pepito']);
        $this->assertStringNotContainsString('15030560011', $this->response->getContent());
        $addition = $this->responseJson()['data']['id'];

        $this->apply($father, 'child_addition', $child);
        $this->assertJsonApiError(409, 'CHILD_ALREADY_DECLARED');

        $this->jsonApiAs($father, 'GET', '/api/v1/workers/'.$mother->id);
        $this->assertSame(0, $this->responseJson()['data']['meta']['childrenCount']);

        $this->resolve($chief, $addition, 'approved');
        $this->assertResponseOk();

        $this->jsonApiAs($father, 'GET', '/api/v1/workers/'.$mother->id);
        $this->assertSame(1, $this->responseJson()['data']['meta']['childrenCount']);

        $this->jsonApiAs($father, 'GET', '/api/v1/children?filter[worker]='.$mother->id);
        $childResource = $this->responseJson()['data'][0];
        $this->assertSame('Pepito', $childResource['attributes']['firstName']);
        $this->assertArrayNotHasKey('cardNumber', $childResource['attributes']);
        $this->assertArrayNotHasKey('eligibleUntil', $childResource['meta']);

        $this->jsonApiAs($mother, 'GET', '/api/v1/children/'.$childResource['id']);
        $this->seeJson(['cardNumber' => '15030560011', 'eligibleUntil' => '2031-08-31']);

        $this->apply($mother, 'child_removal', [], ['child' => ['children', $childResource['id']]]);
        $this->resolve($chief, $this->responseJson()['data']['id'], 'approved');
        $this->assertResponseOk();
        $this->assertTrue(Child::withTrashed()->find($childResource['id'])->trashed());

        // Ahora puede declararlo el otro padre (se restaura la fila)
        $this->apply($father, 'child_addition', $child);
        $this->assertResponseStatus(201);
        $this->assertSame($father->id, (int) Child::find($childResource['id'])->worker_id);
    }

    public function testAusencias()
    {
        $itinerary = $this->createItinerary();
        $chief = $this->makeChief($this->createWorker(), $itinerary);
        $worker = $this->joinItinerary($this->createWorker(), $itinerary);
        $vacation = \App\Models\AbsenceType::where('name', 'Vacaciones')->first();

        $this->apply($worker, 'absence', ['startsOn' => '2026-11-10', 'endsOn' => '2026-11-05'], ['absenceType' => ['absence-types', $vacation->id]]);
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/endsOn');

        $this->apply($worker, 'absence', ['startsOn' => '2026-11-10', 'endsOn' => '2026-11-20', 'observation' => 'Playa'], ['absenceType' => ['absence-types', $vacation->id]]);
        $this->assertResponseStatus(201);
        $this->seeJson(['startsOn' => '2026-11-10', 'endsOn' => '2026-11-20', 'observation' => 'Playa']);
        $id = $this->responseJson()['data']['id'];

        $absences = app(Absences::class);
        $this->assertFalse($absences->isAbsent($worker->id, Carbon::create(2026, 11, 15)));

        $this->resolve($chief, $id, 'approved');
        $this->assertTrue($absences->isAbsent($worker->id, Carbon::create(2026, 11, 15)));
        $this->assertFalse($absences->isAbsent($worker->id, Carbon::create(2026, 11, 21)));
    }

    public function testBajaDelItinerario()
    {
        $itinerary = $this->createItinerary();
        $chief = $this->makeChief($this->createWorker(), $itinerary);
        $worker = $this->joinItinerary($this->createWorker(), $itinerary, 2);

        $this->apply($worker, 'itinerary_leave');
        $this->assertResponseStatus(201);
        $this->seeJson(['status' => 'approved', 'type' => 'itinerary_leave']);
        $this->assertNull($worker->fresh()->itinerary_id);
        $this->assertTrue(Notice::where('worker_id', $chief->id)->where('type', 'resignation')->exists());

        $this->jsonApiAs($worker, 'GET', '/api/v1/applications?filter[mine]=true&include=itinerary,stop');
        $this->assertSame((string) $itinerary->id, $this->responseJson()['data'][0]['relationships']['itinerary']['data']['id']);
        $this->assertSame((string) $this->stopId($itinerary, 2), $this->responseJson()['data'][0]['relationships']['stop']['data']['id']);

        $this->apply($worker, 'itinerary_leave');
        $this->assertJsonApiError(422, 'VALIDATION_ERROR');
    }

    public function testBajasDeRoles()
    {
        $transportChief = $this->createTransportChief();
        $admin = $this->createAdmin();
        $driver = $this->createDriver();
        $otherDriver = $this->createDriver();
        $vehicle = Vehicle::create([
            'vehicle_type_id' => VehicleType::first()->id, 'plate' => 'B1', 'seats' => 4, 'standing_capacity' => 0,
            'driver_id' => $driver->driverId(),
        ]);

        $this->jsonApiAs($otherDriver, 'DELETE', '/api/v1/drivers/'.$driver->driverId());
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->jsonApiAs($driver, 'DELETE', '/api/v1/drivers/'.$driver->driverId());
        $this->assertResponseStatus(204);
        $this->assertFalse($driver->fresh()->isDriver());
        $this->assertNull($vehicle->fresh()->driver_id);
        $this->assertTrue(Notice::where('worker_id', $transportChief->id)->where('type', 'resignation')->exists());

        $this->jsonApiAs($transportChief, 'DELETE', '/api/v1/drivers/'.$otherDriver->driverId());
        $this->assertResponseStatus(204);
        $this->assertSame($transportChief->id, (int) Application::where('worker_id', $otherDriver->id)->value('resolved_by'));

        $chiefRow = \App\Models\TransportChief::where('worker_id', $transportChief->id)->first();
        $this->jsonApiAs($transportChief, 'DELETE', '/api/v1/transport-chiefs/'.$chiefRow->id);
        $this->assertResponseStatus(204);
        $this->assertTrue(Notice::where('worker_id', $admin->id)->where('type', 'resignation')->exists());
        $this->assertFalse($transportChief->fresh()->isTransportChief());
    }

    public function testVisibilidadDeLasSolicitudes()
    {
        $itinerary = $this->createItinerary();
        $chief = $this->makeChief($this->createWorker(), $itinerary);
        $member = $this->joinItinerary($this->createWorker(), $itinerary);
        $stranger = $this->createWorker();

        $this->apply($member, 'driver');
        $driverApplication = $this->responseJson()['data']['id'];
        $this->apply($member, 'rank_change', [], ['rank' => ['ranks', Rank::where('precedence', 1)->value('id')]]);
        $rankApplication = $this->responseJson()['data']['id'];

        $this->jsonApiAs($stranger, 'GET', '/api/v1/applications');
        $this->assertSame([], $this->responseJson()['data']);

        $this->jsonApiAs($chief, 'GET', '/api/v1/applications');
        $this->assertSame([$rankApplication], array_column($this->responseJson()['data'], 'id'));

        $this->jsonApiAs($member, 'GET', '/api/v1/applications?sort=createdAt');
        $this->assertSame([$driverApplication, $rankApplication], array_column($this->responseJson()['data'], 'id'));

        $this->jsonApiAs($stranger, 'GET', '/api/v1/applications/'.$driverApplication);
        $this->assertJsonApiError(404, 'NOT_FOUND');
    }

    public function testAvisos()
    {
        $admin = $this->createAdmin();
        $this->apply($this->createWorker(), 'transport_chief');

        $this->jsonApiAs($admin, 'GET', '/api/v1/notices?filter[unread]=true&include=application');
        $this->assertResponseOk();
        $notice = $this->responseJson()['data'][0];
        $this->assertSame('application_received', $notice['attributes']['type']);
        $this->assertSame('applications', $this->responseJson()['included'][0]['type']);

        $this->jsonApiAs($admin, 'PATCH', '/api/v1/notices/'.$notice['id'], ['data' => ['type' => 'notices', 'id' => $notice['id'], 'attributes' => ['readAt' => '2026-11-02T10:00:00Z']]]);
        $this->assertResponseOk();

        $this->jsonApiAs($admin, 'GET', '/api/v1/notices?filter[unread]=true');
        $this->assertSame([], $this->responseJson()['data']);

        $this->jsonApiAs($this->createWorker(), 'PATCH', '/api/v1/notices/'.$notice['id'], ['data' => ['type' => 'notices', 'id' => $notice['id'], 'attributes' => ['readAt' => null]]]);
        $this->assertJsonApiError(404, 'NOT_FOUND');
    }
}
