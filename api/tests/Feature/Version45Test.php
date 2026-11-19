<?php

namespace Tests\Feature;

use App\Models\Notification;
use App\Models\Scopes\NotSimulated;
use App\Models\Simulation;
use App\Models\Trip;
use App\Models\TripPassenger;
use App\Models\TripStopPass;
use App\Models\User;
use App\Models\Worker;
use App\Models\WorkerItinerary;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Versión 4.5.0 (docs/11 §11.66): simulador de trabajadores. Viaje de
 * prueba, trabajadores simulados que informan como teléfonos (sensores,
 * mayoría, pasos por parada), avance sin cron con cada petición, vehículo
 * simulado o real, aislamiento de los datos reales y «Eliminar Simulación».
 */
class Version45Test extends TestCase
{
    private $entity;
    private $itinerary;
    private array $stops;
    private User $admin;
    private Worker $real;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow(Carbon::create(2026, 11, 17, 6, 0, 0));
        $this->entity = $this->createEntity();
        $this->itinerary = $this->createItinerary($this->entity, 4);
        $this->stops = $this->itinerary->stopIds();
        $this->admin = $this->createAdmin();
        $this->real = $this->createWorker($this->entity, $this->itinerary, $this->stops[1]);
        $this->vehicleType();
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function create(array $attributes = [], ?User $who = null)
    {
        return $this->jsonApiAs($who ?? $this->admin, 'POST', '/api/v1/simulations', self::resource('simulations',
            $attributes + ['workers' => 10, 'seed' => 12345], ['itinerary' => ['itineraries', $this->itinerary->id]]));
    }

    /** La app del Administrador consulta cada 10 s durante $seconds. */
    private function poll(int $seconds, int $every = 10)
    {
        $response = null;

        for ($t = 0; $t < $seconds; $t += $every) {
            Carbon::setTestNow(Carbon::now()->addSeconds($every));
            $response = $this->jsonApiAs($this->admin, 'GET', '/api/v1/simulations')->assertOk();
        }

        return $response;
    }

    private function states(Trip $trip): array
    {
        $simulated = User::withoutGlobalScope(NotSimulated::class)->whereNotNull('simulation_id')->pluck('id');

        return TripPassenger::where('trip_id', $trip->id)->whereIn('user_id', $simulated)->pluck('state')->countBy()->all();
    }

    public function test_simulacion_con_vehiculo_simulado_de_principio_a_fin(): void
    {
        $response = $this->create()->assertCreated()
            ->assertJsonPath('data.attributes.status', 'en_curso')
            ->assertJsonPath('data.attributes.vehicleMode', 'simulado')
            ->assertJsonPath('data.attributes.normal', 70)
            ->assertJsonPath('data.attributes.behaviours.viaja', 7)
            ->assertJsonPath('data.attributes.behaviours.no_viajare', 1)
            // «Mínimo confirmaciones» = 3: tres simulados hacen de sensores.
            ->assertJsonPath('data.attributes.sensors', 3);
        $trip = Trip::findOrFail($response->json('data.relationships.trip.data.id'));
        $this->assertTrue($trip->isSimulation());

        // Solo una a la vez.
        $this->create()->assertStatus(409);

        // A media simulación: los sensores informan del vehículo y la mayoría lo sigue.
        $this->poll(190);
        $trip->refresh();
        $this->assertSame(Trip::RUNNING, $trip->status);
        $live = $this->jsonApiAs($this->admin, 'GET', "/api/v1/trips/{$trip->id}/live")->assertOk()
            ->assertJsonPath('data.attributes.simulation', true)
            // El Administrador viaja en el viaje de prueba.
            ->assertJsonPath('data.attributes.travels', true);
        $this->assertSame(3, $live->json('data.attributes.sensors'));
        $this->assertNotNull($live->json('data.attributes.vehicle.state'));

        // El Administrador informa como un trabajador más.
        $this->jsonApiAs($this->admin, 'POST', "/api/v1/trips/{$trip->id}/reports", self::resource('trip-reports', [
            'events' => [['kind' => 'worker', 'state' => 'no_viajare', 'manual' => true, 'capturedAt' => Carbon::now()->toIso8601String()]], 'gps' => true,
        ]))->assertOk()->assertJsonPath('meta.applied', true)->assertJsonPath('data.attributes.myState.state', 'no_viajare');

        // Hasta el final.
        $status = $this->poll(900);
        $trip->refresh();
        $this->assertSame(Trip::FINISHED, $trip->status);
        $this->assertSame('llegada', $trip->finish_reason);
        $status->assertJsonPath('data.0.attributes.status', 'terminada');
        $this->assertSame(4, TripStopPass::where('trip_id', $trip->id)->count(), 'Pasó por todas las paradas (por los sensores).');
        // Se detuvo en todas: Recogidas (docs/11 §11.67).
        $this->assertSame(['recogida'], TripStopPass::where('trip_id', $trip->id)->pluck('stop_state')->unique()->values()->all());

        $passes = TripStopPass::where('trip_id', $trip->id)->orderBy('route_index')->pluck('passed_at')->map(fn ($t) => Carbon::parse($t));
        for ($i = 1; $i < 4; $i++) {
            $this->assertTrue($passes[$i]->gt($passes[$i - 1]), 'Las horas de paso van en orden.');
        }

        $this->assertSame(['dejado' => 7, 'llegada_tarde' => 1, 'no_recogido' => 1, 'no_viajare' => 1], collect($this->states($trip))->sortKeys()->all());

        // Notificaciones: solo al Administrador que la inició.
        $simulated = User::withoutGlobalScope(NotSimulated::class)->whereNotNull('simulation_id')->pluck('id');
        $this->assertSame(0, Notification::whereIn('user_id', $simulated)->count());
        $this->assertSame(0, Notification::where('user_id', $this->real->user_id)->count());
        $this->assertTrue(Notification::where('user_id', $this->admin->id)->where('kind', 'viaje_creado')->exists());
    }

    public function test_avanza_aunque_nadie_consulte_durante_un_rato(): void
    {
        $id = $this->create(['speedFactor' => 2])->assertCreated()->json('data.relationships.trip.data.id');

        // Media hora sin peticiones: la primera consulta envía todo lo pendiente con su hora de captura.
        Carbon::setTestNow(Carbon::now()->addMinutes(30));
        $this->jsonApiAs($this->admin, 'GET', '/api/v1/sync')->assertOk();
        $trip = Trip::findOrFail($id);
        $this->assertSame(Trip::FINISHED, $trip->status);
        $this->assertSame(4, TripStopPass::where('trip_id', $trip->id)->count());
        $this->assertTrue(Carbon::parse(TripStopPass::where('trip_id', $trip->id)->where('route_index', 3)->value('passed_at'))->lt(Carbon::now()->subMinutes(20)),
            'La hora de paso es la de captura, no la de la consulta.');
        $this->assertSame('terminada', Simulation::first()->status);
    }

    public function test_aislada_de_los_datos_reales(): void
    {
        $this->create()->assertCreated();
        $trip = Trip::where('simulation_id', Simulation::first()->id)->firstOrFail();
        $otherAdmin = $this->createAdmin();

        // El viaje de prueba solo lo ve quien la inició.
        $ids = fn ($who) => collect($this->jsonApiAs($who, 'GET', '/api/v1/trips')->assertOk()->json('data'))->pluck('id')->all();
        $this->assertContains((string) $trip->id, $ids($this->admin));
        $this->assertNotContains((string) $trip->id, $ids($otherAdmin));
        $this->assertNotContains((string) $trip->id, $ids($this->real));
        $this->jsonApiAs($this->real, 'GET', "/api/v1/trips/{$trip->id}/live")->assertNotFound();

        // Fuera de Gestión y de las cantidades.
        $this->jsonApiAs($this->admin, 'GET', '/api/v1/management-summary')->assertOk()->assertJsonPath('data.attributes.workers', 3);
        $users = collect($this->jsonApiAs($this->admin, 'GET', '/api/v1/users')->assertOk()->json('data'));
        $this->assertCount(3, $users);
        $this->assertCount(1, $this->jsonApiAs($this->admin, 'GET', '/api/v1/workers')->assertOk()->json('data'));
        $this->assertCount(1, $this->jsonApiAs($this->admin, 'GET', '/api/v1/worker-itineraries')->assertOk()->json('data'));
        $this->assertSame(1, WorkerItinerary::where('itinerary_id', $this->itinerary->id)->count());

        // Un viaje real del mismo itinerario y día se puede crear y no cuenta a los simulados ni al Administrador.
        $real = $this->jsonApiAs($this->admin, 'POST', '/api/v1/trips', self::resource('trips', [
            'direction' => 'ida', 'date' => Carbon::today()->toDateString(), 'departureTime' => '23:00',
        ], ['itinerary' => ['itineraries', $this->itinerary->id], 'vehicleType' => ['vehicle-types', $this->vehicleType()->id]]))->assertCreated();
        $real->assertJsonPath('data.meta.expectedPassengers', 1);
        $this->assertSame(1, Notification::where('user_id', $this->real->user_id)->count(), 'El real solo recibe la de su viaje real.');

        // Los simulados no pueden entrar.
        $this->jsonApi('POST', '/api/v1/tokens', self::resource('tokens', ['username' => 'sim'.Simulation::first()->id.'-1', 'password' => 'x']))
            ->assertStatus(401);
    }

    public function test_eliminar_simulacion_lo_borra_todo(): void
    {
        $id = $this->create()->assertCreated()->json('data.id');
        $tripId = Simulation::findOrFail($id)->trip_id;
        $this->poll(200);
        $this->assertGreaterThan(0, TripPassenger::where('trip_id', $tripId)->count());

        $this->jsonApiAs($this->createUser(), 'DELETE', "/api/v1/simulations/{$id}")->assertForbidden();
        $this->jsonApiAs($this->admin, 'DELETE', "/api/v1/simulations/{$id}")->assertNoContent();

        $this->assertSame(0, Simulation::count());
        $this->assertNull(Trip::find($tripId));
        $this->assertSame(0, TripPassenger::where('trip_id', $tripId)->count());
        $this->assertSame(0, DB::table('users')->whereNotNull('simulation_id')->count());
        $this->assertSame(0, DB::table('workers')->whereNotNull('simulation_id')->count());
        $this->assertSame(0, DB::table('worker_itineraries')->whereNotNull('simulation_id')->count());
        // Lo real sigue.
        $this->assertNotNull(WorkerItinerary::where('user_id', $this->real->user_id)->first());
        // Las eliminaciones no se avisan (docs/11 §11.67): al Administrador no le queda nada de ese viaje.
        $this->assertSame([], Notification::where('user_id', $this->admin->id)->pluck('kind')->all());
        $this->jsonApiAs($this->admin, 'GET', '/api/v1/simulations')->assertOk()->assertJsonPath('meta.total', 0);
    }

    public function test_con_vehiculo_real_los_simulados_siguen_lo_que_informan_los_telefonos(): void
    {
        $id = $this->create(['vehicleMode' => 'real', 'workers' => 12])->assertCreated()
            ->assertJsonPath('data.attributes.sensors', 0)->json('data.id');
        $trip = Trip::findOrFail(Simulation::findOrFail($id)->trip_id);
        $this->poll(180);
        $this->assertSame(Trip::PLANNED, $trip->fresh()->status, 'Sin vehículo real no pasa nada.');

        // El Administrador marca el paso por cada parada (como lo harían los sensores reales).
        for ($i = 0; $i < 3; $i++) {
            $this->jsonApiAs($this->admin, 'POST', "/api/v1/trips/{$trip->id}/stop-passes", self::resource('trip-stop-passes', ['routeIndex' => $i]))->assertCreated();
            $this->poll(30);
        }

        $plan = Simulation::findOrFail($id)->planData();
        $states = TripPassenger::where('trip_id', $trip->id)->get()->keyBy('user_id');

        foreach ($plan['workers'] as $w) {
            $state = $states[$w['userId']]->state ?? null;
            $expected = match ($w['behaviour']) {
                'viaja' => $w['drop'] <= 2 ? 'dejado' : 'viajando',
                'llegada_tarde' => 'llegada_tarde',
                'no_recogido' => 'no_recogido',
                default => 'no_viajare',
            };
            $this->assertSame($expected, $state, "Trabajador {$w['n']} ({$w['behaviour']}, sube en {$w['board']})");
        }

        // Llega a la última: termina y los que seguían viajando quedan Dejados.
        $this->jsonApiAs($this->admin, 'POST', "/api/v1/trips/{$trip->id}/stop-passes", self::resource('trip-stop-passes', ['routeIndex' => 3]))->assertCreated();
        $this->poll(10)->assertJsonPath('data.0.attributes.status', 'terminada');
        $this->assertArrayNotHasKey('viajando', $this->states($trip));
    }

    public function test_solo_el_administrador_y_validaciones(): void
    {
        $this->create([], $this->createUser())->assertForbidden();
        $this->create(['normal' => 50])->assertStatus(422);
        $this->create(['workers' => 0])->assertStatus(422);
        $this->assertSame(0, Simulation::count());
    }
}
