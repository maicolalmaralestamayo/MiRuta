<?php

namespace Tests\Feature;

use App\Models\Application;
use App\Models\ItineraryStop;
use App\Models\Notification;
use App\Models\Trip;
use App\Models\TripPassenger;
use App\Services\Applications;
use App\Services\Organization;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Versión 4.3.0 (docs/11 §11.63): Viajando y Recogido unificados (con los
 * teléfonos 4.2.0 que aún envían «recogido»), qué cambió en «Viaje cambiado»,
 * «Viaje eliminado», datos de las notificaciones con que la app compone las
 * suyas y lo nuevo de sync (viajes terminados y solicitudes pendientes por tipo).
 */
class Version43Test extends TestCase
{
    private $entity;
    private $itinerary;
    private array $stops;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow(Carbon::create(2026, 11, 16, 6, 0, 0));
        $this->entity = $this->createEntity();
        $this->itinerary = $this->createItinerary($this->entity, 3);
        $this->stops = $this->itinerary->stopIds();
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function trip(string $direction = 'ida'): Trip
    {
        return Trip::create([
            'itinerary_id' => $this->itinerary->id, 'direction' => $direction, 'date' => Carbon::today(), 'departure_time' => '07:00',
            'departs_at' => Carbon::today()->setTime(7, 0), 'vehicle_type_id' => $this->vehicleType()->id,
            'status' => Trip::PLANNED, 'status_changed_at' => Carbon::now(),
        ]);
    }

    private function report($who, Trip $trip, array $attributes, array $headers = [])
    {
        return $this->jsonApiAs($who, 'POST', "/api/v1/trips/{$trip->id}/reports", self::resource('trip-reports', $attributes), $headers);
    }

    private function lastData(int $userId, string $kind): array
    {
        return Notification::where('user_id', $userId)->where('kind', $kind)->orderByDesc('id')->firstOrFail()->dataArray();
    }

    public function test_la_actualizacion_convierte_recogido_en_viajando(): void
    {
        $trip = $this->trip('regreso');
        $worker = $this->createWorker($this->entity, $this->itinerary, $this->stops[1]);
        // Con MariaDB la columna ya tiene la lista nueva: se amplía como en la versión vieja.
        if (DB::getDriverName() !== 'sqlite') {
            DB::statement("ALTER TABLE trip_passengers MODIFY state ENUM('de_camino','en_parada','viajando','dejado','recogido','botado','dormido','no_recogido','retrasado','no_voy') NOT NULL");
        }
        DB::table('trip_passengers')->insert([
            'trip_id' => $trip->id, 'user_id' => $worker->user_id, 'stop_id' => $this->stops[1], 'state' => 'recogido',
            'state_at' => Carbon::now(), 'reported_at' => Carbon::now(), 'children_count' => 0, 'created_at' => Carbon::now(), 'updated_at' => Carbon::now(),
        ]);

        (require database_path('migrations/2026_11_16_000001_upgrade_4_3.php'))->up();

        $this->assertSame('viajando', TripPassenger::where('trip_id', $trip->id)->value('state'));
        $this->assertSame(0, TripPassenger::where('state', 'recogido')->count());
    }

    public function test_regreso_viajando_es_sensor_y_definitivo_y_se_acepta_recogido_de_la_4_2(): void
    {
        $trip = $this->trip('regreso');
        [$a, $b] = array_map(fn ($i) => $this->createWorker($this->entity, $this->itinerary, $this->stops[$i]), [2, 1]);

        // Un teléfono 4.2.0 envía «recogido»: se guarda como viajando y a él se le devuelve «recogido».
        $this->report($a, $trip, ['workerState' => 'recogido'], ['X-App-Version' => '12'])
            ->assertJsonPath('meta.applied', true)->assertJsonPath('meta.sensor', true)
            ->assertJsonPath('data.attributes.myState.state', 'recogido');
        $this->assertSame('viajando', TripPassenger::where('user_id', $a->user_id)->value('state'));
        $this->jsonApiAs($a, 'GET', "/api/v1/trips/{$trip->id}/live", null, ['X-App-Version' => '13'])
            ->assertJsonPath('data.attributes.myState.state', 'viajando')->assertJsonPath('data.attributes.myState.sensor', true);

        // La 4.3.0 envía viajando; desde la 4.4.0 Viajando solo pasa a Dejado (también en el regreso).
        $this->report($b, $trip, ['workerState' => 'viajando'])->assertJsonPath('meta.sensor', true);
        $this->report($b, $trip, ['workerState' => 'no_voy'])->assertJsonPath('meta.applied', false)->assertJsonPath('meta.reason', 'TRANSICION_NO_PERMITIDA');
        $this->jsonApiAs($b, 'GET', "/api/v1/trips/{$trip->id}/live")->assertJsonPath('data.attributes.inVehicle.workers', 2)
            ->assertJsonPath('data.attributes.itineraryName', $this->itinerary->name)
            ->assertJsonPath('data.attributes.vehicleTypeName', $this->vehicleType()->name);
    }

    public function test_viaje_cambiado_lleva_los_campos_que_cambiaron(): void
    {
        $trip = $this->trip();
        $chief = $this->createChief($this->itinerary, $this->stops[0]);
        $worker = $this->createWorker($this->entity, $this->itinerary, $this->stops[1]);
        $patch = fn (array $attributes) => $this->jsonApiAs($chief, 'PATCH', "/api/v1/trips/{$trip->id}", self::resource('trips', $attributes, [], (string) $trip->id))->assertOk();

        $patch(['departureTime' => '07:30']);
        $data = $this->lastData($worker->user_id, 'viaje_modificado');
        $this->assertSame(['hora'], $data['changes']);
        $this->assertSame($this->itinerary->name, $data['itineraryName']);
        $this->assertSame('planificado', $data['status']);
        $this->assertNotEmpty($data['departureStop']);
        $this->assertNotEmpty($data['vehicleType']);
        $this->assertStringStartsWith('2026-11-16T07:30', $data['departsAt']);

        $patch(['date' => '2026-11-17', 'departureTime' => '08:00', 'observation' => 'Lleve nasobuco']);
        $this->assertSame(['fecha', 'hora', 'observacion'], $this->lastData($worker->user_id, 'viaje_modificado')['changes']);

        // Sin cambios reales no se avisa.
        $count = Notification::where('kind', 'viaje_modificado')->count();
        $patch(['departureTime' => '08:00']);
        $this->assertSame($count, Notification::where('kind', 'viaje_modificado')->count());
    }

    public function test_cambia_la_parada_de_salida_al_ordenar_las_paradas(): void
    {
        $outbound = $this->trip();
        $worker = $this->createWorker($this->entity, $this->itinerary, $this->stops[1]);

        // La última pasa a ser la primera: cambia la salida de la ida (y también la del regreso).
        $link = ItineraryStop::where('itinerary_id', $this->itinerary->id)->where('stop_id', $this->stops[2])->first();
        app(Organization::class)->move($link, 1);

        $data = $this->lastData($worker->user_id, 'viaje_modificado');
        $this->assertSame(['parada_salida'], $data['changes']);
        $this->assertSame((string) $outbound->id, $data['tripId']);

        // Mover una parada intermedia no cambia la salida.
        $count = Notification::where('kind', 'viaje_modificado')->count();
        $middle = ItineraryStop::where('itinerary_id', $this->itinerary->id)->where('position', 2)->first();
        app(Organization::class)->move($middle, 3);
        $this->assertSame($count, Notification::where('kind', 'viaje_modificado')->count());
    }

    public function test_viaje_eliminado_se_avisa(): void
    {
        $trip = $this->trip();
        $chief = $this->createChief($this->itinerary, $this->stops[0]);
        $worker = $this->createWorker($this->entity, $this->itinerary, $this->stops[1]);

        $this->jsonApiAs($chief, 'DELETE', "/api/v1/trips/{$trip->id}")->assertNoContent();

        $data = $this->lastData($worker->user_id, 'viaje_eliminado');
        $this->assertSame('eliminado', $data['status']);
        $this->assertSame((string) $trip->id, $data['tripId']);
    }

    public function test_sync_trae_viajes_terminados_y_solicitudes_pendientes_por_tipo(): void
    {
        $admin = $this->createAdmin();
        $chief = $this->createChief($this->itinerary, $this->stops[0]);
        $trip = $this->trip();
        $trip->forceFill(['status' => Trip::FINISHED, 'status_changed_at' => Carbon::now()])->save();

        $other = $this->createEntity('OTRA');
        $user = $this->createUser();
        Application::create(['user_id' => $user->id, 'type' => Application::TYPE_ENTITY, 'status' => Application::PENDING, 'entity_id' => $other->id]);
        $member = $this->createWorker($this->entity);
        Application::create(['user_id' => $member->user_id, 'type' => Application::TYPE_ITINERARY, 'status' => Application::PENDING,
            'entity_id' => $this->entity->id, 'itinerary_id' => $this->itinerary->id]);

        $this->jsonApiAs($admin, 'GET', '/api/v1/sync')->assertOk()
            ->assertJsonPath('meta.finishedTrips', [(string) $trip->id])
            ->assertJsonPath('meta.pendingApplications', ['entity' => 1, 'itinerary' => 1, 'accessRecovery' => 0]);
        $this->jsonApiAs($chief, 'GET', '/api/v1/sync')->assertOk()
            ->assertJsonPath('meta.pendingApplications', ['entity' => 0, 'itinerary' => 1, 'accessRecovery' => 0]);
        // Los contadores siguen siendo números (las apps 4.2.0 los leen así).
        $this->jsonApiAs($chief, 'GET', '/api/v1/sync')->assertJsonPath('meta.counters.applicationsToResolve', 1);
    }

    public function test_solicitud_rechazada_lleva_lo_que_muestra_la_notificacion(): void
    {
        $chief = $this->createChief($this->itinerary, $this->stops[0]);
        $member = $this->createWorker($this->entity);
        $application = Application::create(['user_id' => $member->user_id, 'type' => Application::TYPE_ITINERARY, 'status' => Application::PENDING,
            'entity_id' => $this->entity->id, 'itinerary_id' => $this->itinerary->id, 'stop_id' => $this->stops[1]]);
        $reason = \App\Models\ItineraryDenialReason::create(['name' => 'Sin plaza']);

        app(Applications::class)->reject($application, \App\Models\User::find($chief->user_id), $reason->id, null);

        $data = $this->lastData($member->user_id, 'solicitud_resuelta');
        $this->assertSame('rechazada', $data['status']);
        $this->assertSame('itinerario', $data['type']);
        $this->assertSame($this->itinerary->name, $data['itinerary']);
        $this->assertSame($this->entity->abbreviation, $data['entity']);
        $this->assertNotEmpty($data['stop']);
        $this->assertSame('Sin plaza', $data['reason']);
        $this->assertNotEmpty($data['resolvedAt']);
    }
}
