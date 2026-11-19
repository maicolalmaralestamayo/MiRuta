<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\Notification;
use App\Models\Trip;
use App\Models\TripPassenger;
use App\Models\TripStopPass;
use App\Models\User;
use App\Services\Settings;
use App\Services\Trips;
use Carbon\Carbon;
use Tests\TestCase;

/**
 * Versión 5.0.0 (docs/11 §11.67): correo electrónico en lugar del carné,
 * cancelar / eliminar / podar viajes, «Plazo cancelación», estados de las
 * paradas (En espera, Recogida, Volada, Omitida), estados del trabajador de
 * la versión definitiva (también a mano), velocidad del vehículo, la salida
 * real y «Cambió la …» de la tarjeta, el círculo verde de Viajes y las horas
 * con su zona.
 */
class Version50Test extends TestCase
{
    private $entity;
    private $itinerary;
    private array $stops;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow(Carbon::create(2026, 11, 19, 10, 0, 0));
        $this->entity = $this->createEntity();
        $this->itinerary = $this->createItinerary($this->entity, 4);
        $this->stops = $this->itinerary->stopIds();
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function trip(string $direction = 'ida', string $time = '10:30', string $status = Trip::PLANNED): Trip
    {
        return Trip::create([
            'itinerary_id' => $this->itinerary->id, 'direction' => $direction, 'date' => Carbon::today(), 'departure_time' => $time,
            'departs_at' => Carbon::today()->setTimeFromTimeString($time), 'vehicle_type_id' => $this->vehicleType()->id,
            'status' => $status, 'status_changed_at' => Carbon::now(),
        ]);
    }

    private function send($who, Trip $trip, array $events)
    {
        return $this->jsonApiAs($who, 'POST', "/api/v1/trips/{$trip->id}/reports", self::resource('trip-reports', ['events' => $events, 'gps' => true]));
    }

    private static function worker(string $state, ?int $stopId, Carbon $at, bool $manual = false): array
    {
        return ['kind' => 'worker', 'state' => $state, 'stopId' => $stopId, 'capturedAt' => $at->toIso8601String()] + ($manual ? ['manual' => true] : []);
    }

    private static function vehicle(string $state, int $next, Carbon $at, bool $atStop = false, bool $inRadius = false, ?float $speed = null): array
    {
        return ['kind' => 'vehicle', 'vehicleState' => $state, 'nextStopIndex' => $next, 'atStop' => $atStop, 'inRadius' => $inRadius || $atStop,
            'speed' => $speed, 'capturedAt' => $at->toIso8601String()];
    }

    private function setting(string $key, string $value): void
    {
        app(Settings::class)->set($key, $value);
    }

    public function test_correo_en_lugar_del_carne_en_registro_perfil_busqueda_y_olvide_algo(): void
    {
        $admin = $this->createAdmin();
        $user = $this->createUser(['email' => 'maicol@correo.cu']);
        $other = $this->createUser(['email' => 'otro@correo.cu']);

        // Perfil: cambia su correo (único), sexo y nacimiento.
        $this->jsonApiAs($user, 'PATCH', '/api/v1/me', self::resource('users', ['email' => 'otro@correo.cu']))
            ->assertStatus(409)->assertJsonPath('errors.0.code', 'EMAIL_TAKEN');
        $this->jsonApiAs($user, 'PATCH', '/api/v1/me', self::resource('users', ['email' => 'no-es-correo']))
            ->assertStatus(422)->assertJsonPath('errors.0.code', 'EMAIL_INVALID');
        $this->jsonApiAs($user, 'PATCH', '/api/v1/me', self::resource('users', ['email' => 'Nuevo@Correo.cu', 'sex' => 'F', 'birthDate' => '1992-07-16']))
            ->assertOk()->assertJsonPath('data.attributes.email', 'nuevo@correo.cu')->assertJsonPath('data.attributes.sex', 'F')
            ->assertJsonPath('data.attributes.birthDate', '1992-07-16');
        $this->jsonApiAs($user, 'PATCH', '/api/v1/me', self::resource('users', ['sex' => 'X']))->assertStatus(422);

        // El Administrador lo cambia y busca por correo.
        $this->jsonApiAs($admin, 'PATCH', "/api/v1/users/{$other->id}", self::resource('users', ['email' => 'otra@correo.cu', 'sex' => 'M']))
            ->assertOk()->assertJsonPath('data.attributes.email', 'otra@correo.cu');
        $this->createWorker($this->entity, null, null, User::find($other->id));
        $this->assertCount(1, $this->jsonApiAs($admin, 'GET', '/api/v1/workers?filter[search]=otra@correo')->json('data'));

        // «Olvidé algo» con el correo.
        $header = ['X-Installation' => $this->jsonApi('POST', '/api/v1/installations', self::resource('installations', ['deviceModel' => 'X']))->json('data.meta.header')];
        $this->jsonApi('POST', '/api/v1/guest/access-recoveries', self::resource('access-recoveries', [
            'forgotUsername' => true, 'forgotPassword' => false, 'email' => 'NUEVO@correo.cu', 'phone' => '55555555',
        ]), $header)->assertCreated();
        $this->jsonApiAs($admin, 'GET', '/api/v1/access-recoveries')->assertJsonPath('data.0.attributes.email', 'nuevo@correo.cu')
            ->assertJsonPath('data.0.attributes.matched', true);
    }

    public function test_cancelar_solo_planificado_eliminar_solo_cancelado_o_terminado(): void
    {
        $admin = $this->createAdmin();
        $worker = $this->createWorker($this->entity, $this->itinerary, $this->stops[1]);
        $planned = $this->trip();
        $patch = fn (Trip $t, string $status) => $this->jsonApiAs($admin, 'PATCH', "/api/v1/trips/{$t->id}", self::resource('trips', ['status' => $status], [], (string) $t->id));

        $this->jsonApiAs($admin, 'DELETE', "/api/v1/trips/{$planned->id}")->assertStatus(409)->assertJsonPath('errors.0.code', 'TRIP_NOT_DELETABLE');
        $patch($planned, 'en_ejecucion')->assertOk();
        $patch($planned, 'cancelado')->assertStatus(409)->assertJsonPath('errors.0.code', 'TRIP_TRANSITION_INVALID');
        $this->jsonApiAs($admin, 'DELETE', "/api/v1/trips/{$planned->id}")->assertStatus(409);
        $patch($planned, 'terminado')->assertOk();
        $this->jsonApiAs($admin, 'DELETE', "/api/v1/trips/{$planned->id}")->assertNoContent();

        $cancelled = $this->trip('regreso');
        $patch($cancelled, 'cancelado')->assertOk()->assertJsonPath('data.attributes.status', 'cancelado');
        $this->assertSame('manual', $cancelled->fresh()->finish_reason);
        $this->jsonApiAs($admin, 'DELETE', "/api/v1/trips/{$cancelled->id}")->assertNoContent();

        // Las eliminaciones no se avisan.
        $this->assertSame(0, Notification::where('user_id', $worker->user_id)->where('kind', 'viaje_eliminado')->count());
    }

    public function test_plazo_cancelacion_y_poda_por_conservacion_viajes(): void
    {
        $trips = app(Trips::class);
        $planned = $this->trip('ida', '10:30');
        $worker = $this->createWorker($this->entity, $this->itinerary, $this->stops[1]);

        Carbon::setTestNow(Carbon::create(2026, 11, 19, 15, 29));
        $this->assertSame(['cancelled' => 0, 'finished' => 0], $trips->review());
        Carbon::setTestNow(Carbon::create(2026, 11, 19, 15, 31));
        $this->assertSame(['cancelled' => 1, 'finished' => 0], $trips->review());
        $this->assertSame(Trip::CANCELLED, $planned->fresh()->status);
        $this->assertSame('plazo_cancelacion', $planned->fresh()->finish_reason);
        $this->assertTrue(Notification::where('user_id', $worker->user_id)->where('title', 'Viaje cancelado')->exists());

        // Poda: los Cancelados y Terminados de hace más de «Conservación viajes» (30 días).
        $finished = $this->trip('regreso', '11:00', Trip::FINISHED);
        $future = Trip::create([
            'itinerary_id' => $this->itinerary->id, 'direction' => 'ida', 'date' => Carbon::today()->addDays(40), 'departure_time' => '10:30',
            'departs_at' => Carbon::today()->addDays(40)->setTime(10, 30), 'vehicle_type_id' => $this->vehicleType()->id,
            'status' => Trip::PLANNED, 'status_changed_at' => Carbon::now(),
        ]);
        Carbon::setTestNow(Carbon::now()->addDays(29));
        $this->assertSame(0, $trips->prune());
        Carbon::setTestNow(Carbon::now()->addDays(2));
        $this->assertSame(2, $trips->prune());
        $this->assertNull(Trip::find($planned->id));
        $this->assertNull(Trip::find($finished->id));
        $this->assertNotNull(Trip::find($future->id), 'Un Planificado nunca se poda.');
        $this->assertArrayHasKey('viajes:podar', \App\Services\ScheduledTasks::TASKS);
    }

    public function test_estados_de_las_paradas_recogida_volada_y_omitida_con_sensores(): void
    {
        $this->setting('minimo_confirmaciones', '1');
        $trip = $this->trip();
        $sensor = $this->createWorker($this->entity, $this->itinerary, $this->stops[0]);
        $t0 = Carbon::now()->subMinutes(10);

        $live = $this->send($sensor, $trip, [
            self::worker('en_parada', $this->stops[0], $t0),
            self::worker('viajando', $this->stops[0], $t0->copy()->addSeconds(10)),
            // Se detiene en la segunda: Recogida al detenerse.
            self::vehicle('detenido', 1, $t0->copy()->addSeconds(60), true, true, 0),
        ])->assertOk();
        $live->assertJsonPath('data.attributes.status', 'en_ejecucion')
            ->assertJsonPath('data.attributes.stops.0.state', 'recogida')->assertJsonPath('data.attributes.stops.0.left', true)
            ->assertJsonPath('data.attributes.stops.1.state', 'recogida')->assertJsonPath('data.attributes.stops.1.left', false)
            ->assertJsonPath('data.attributes.stops.2.state', 'en_espera');

        // Pasa por el radio de la tercera sin detenerse (Volada) y luego va hacia el final sin
        // entrar en el radio de la cuarta (Omitida).
        $this->send($sensor, $trip, [
            self::vehicle('en_movimiento', 2, $t0->copy()->addSeconds(120), false, false, 32),
            self::vehicle('en_movimiento', 2, $t0->copy()->addSeconds(150), false, true, 30),
            self::vehicle('en_movimiento', 3, $t0->copy()->addSeconds(180), false, false, 40),
        ])->assertJsonPath('data.attributes.stops.1.left', true)
            ->assertJsonPath('data.attributes.stops.2.state', 'volada')
            ->assertJsonPath('data.attributes.vehicle.speed', 40);
        $live = $this->send($sensor, $trip, [self::vehicle('en_movimiento', 4, $t0->copy()->addSeconds(240), false, false, 45)]);
        $live->assertJsonPath('data.attributes.status', 'terminado')->assertJsonPath('data.attributes.stops.3.state', 'omitida');
        $this->assertSame(['recogida', 'recogida', 'volada', 'omitida'], TripStopPass::where('trip_id', $trip->id)->orderBy('route_index')->pluck('stop_state')->all());
    }

    public function test_marcar_paso_recogida_omitidas_y_el_servidor_pone_no_recogido_y_llegada_tarde(): void
    {
        $trip = $this->trip();
        $chief = $this->createChief($this->itinerary, $this->stops[0]);
        $waiting = $this->createWorker($this->entity, $this->itinerary, $this->stops[2]);
        $approaching = $this->createWorker($this->entity, $this->itinerary, $this->stops[2]);
        $away = $this->createWorker($this->entity, $this->itinerary, $this->stops[2]);
        $at = Carbon::now()->subMinutes(10);

        $this->send($waiting, $trip, [self::worker('en_parada', $this->stops[2], $at)]);
        $this->send($approaching, $trip, [self::worker('acercandose', $this->stops[2], $at)]);
        $this->send($away, $trip, [self::worker('alejandose', $this->stops[2], $at)]);
        Carbon::setTestNow(Carbon::now()->addMinutes(5));

        // Marca la tercera: empieza, la primera Recogida, la segunda Omitida, la tercera Recogida (a mano).
        $live = $this->jsonApiAs($chief, 'POST', "/api/v1/trips/{$trip->id}/stop-passes", self::resource('trip-stop-passes', ['routeIndex' => 2]))->assertCreated();
        $live->assertJsonPath('data.attributes.status', 'en_ejecucion')
            ->assertJsonPath('data.attributes.stops.0.state', 'recogida')
            ->assertJsonPath('data.attributes.stops.1.state', 'omitida')
            ->assertJsonPath('data.attributes.stops.2.state', 'recogida')->assertJsonPath('data.attributes.stops.2.passedManually', true)
            ->assertJsonPath('data.attributes.stops.2.counts.no_recogido', 1)
            ->assertJsonPath('data.attributes.stops.2.counts.llegada_tarde', 2)
            ->assertJsonPath('data.attributes.stops.3.state', 'en_espera');
        $this->assertTrue((bool) TripPassenger::where('user_id', $waiting->user_id)->value('set_by_server'));
        $this->assertNotNull($trip->fresh()->started_at);
    }

    public function test_cualquier_estado_a_mano_y_estados_sin_parada(): void
    {
        $trip = $this->trip('regreso');
        $worker = $this->createWorker($this->entity, $this->itinerary, $this->stops[1]);
        $at = Carbon::now()->subMinutes(5);

        $this->send($worker, $trip, [self::worker('fuera_itinerario', $this->stops[1], $at)])
            ->assertJsonPath('data.attributes.myState.state', 'fuera_itinerario')->assertJsonPath('data.attributes.myState.stopId', null)
            ->assertJsonPath('data.attributes.myState.manual', false);
        $this->send($worker, $trip, [self::worker('dejado', $this->stops[2], $at->copy()->addSeconds(10), true)])
            ->assertJsonPath('meta.applied', true)->assertJsonPath('data.attributes.myState.manual', true);
        // De un estado final a otro, a mano: también.
        $this->send($worker, $trip, [self::worker('en_parada', $this->stops[3], $at->copy()->addSeconds(20), true)])
            ->assertJsonPath('meta.applied', true)->assertJsonPath('data.attributes.myState.state', 'en_parada');
        // En la línea no cuentan los Viajando (la app quita además Dejados en la ida y En Parada en el regreso).
        $this->send($worker, $trip, [self::worker('viajando', $this->stops[3], $at->copy()->addSeconds(30))])
            ->assertJsonPath('data.attributes.stops.0.counts', [])->assertJsonPath('data.attributes.myState.sensor', true);

        $this->jsonApiAs($worker, 'POST', "/api/v1/trips/{$trip->id}/reports", self::resource('trip-reports', ['events' => [
            ['kind' => 'worker', 'state' => 'no_voy', 'capturedAt' => Carbon::now()->toIso8601String()],
        ]]))->assertStatus(422)->assertJsonPath('errors.0.code', 'WORKER_STATE_INVALID');
        $this->assertCount(9, TripPassenger::STATES);
    }

    public function test_tarjeta_cambio_la_salida_real_y_circulo_verde_de_viajes(): void
    {
        $admin = $this->createAdmin();
        $worker = $this->createWorker($this->entity, $this->itinerary, $this->stops[1]);
        $trip = $this->trip();
        $this->trip('regreso', '18:00', Trip::FINISHED);

        $this->jsonApiAs($admin, 'PATCH', "/api/v1/trips/{$trip->id}", self::resource('trips', ['departureTime' => '10:45'], [], (string) $trip->id))
            ->assertOk()->assertJsonPath('data.attributes.changes', ['hora'])->assertJsonPath('data.attributes.startedAt', null);
        $this->jsonApiAs($worker, 'GET', '/api/v1/sync')->assertJsonPath('meta.counters.activeTrips', 1);

        Carbon::setTestNow(Carbon::now()->addMinutes(50));
        $this->jsonApiAs($admin, 'PATCH', "/api/v1/trips/{$trip->id}", self::resource('trips', ['status' => 'en_ejecucion'], [], (string) $trip->id))
            ->assertOk()->assertJsonPath('data.attributes.changes', [])
            ->assertJsonPath('data.attributes.startedAt', Carbon::now()->toIso8601String());
        $this->jsonApiAs($worker, 'GET', '/api/v1/sync')->assertJsonPath('meta.counters.activeTrips', 1);
    }

    public function test_horas_con_zona_la_salida_y_el_paso_por_la_primera_son_la_misma(): void
    {
        $this->setting('minimo_confirmaciones', '1');
        $trip = $this->trip();
        $worker = $this->createWorker($this->entity, $this->itinerary, $this->stops[0]);
        // El teléfono envía la hora de captura en UTC (5.0.0): 14:55Z = 09:55 en La Habana.
        $live = $this->send($worker, $trip, [
            ['kind' => 'worker', 'state' => 'viajando', 'stopId' => $this->stops[0], 'capturedAt' => '2026-11-19T14:55:00.000Z'],
        ])->assertOk();

        $this->assertSame('2026-11-19T09:55:00-05:00', $live->json('data.attributes.startedAt'));
        $this->assertSame('2026-11-19T09:55:00-05:00', $live->json('data.attributes.stops.0.passedAt'));
        $trip = $this->jsonApiAs($worker, 'GET', "/api/v1/trips/{$trip->id}")->json('data.attributes');
        $this->assertSame($trip['startedAt'], $live->json('data.attributes.stops.0.passedAt'));
        $this->assertSame('2026-11-19T10:00:00-05:00', $this->jsonApiAs($worker, 'GET', '/api/v1/sync')->json('meta.serverTime'));
    }

    public function test_hijos_sin_carne(): void
    {
        $parent = $this->createUser();
        $this->jsonApiAs($parent, 'POST', '/api/v1/children', self::resource('children', [
            'firstName' => 'Lía', 'firstSurname' => 'A', 'secondSurname' => 'B', 'birthDate' => Carbon::now()->subYears(5)->toDateString(),
        ]))->assertCreated()->assertJsonPath('data.attributes.sex', 'M')->assertJsonPath('data.attributes.eligible', true);
        $this->jsonApiAs($parent, 'POST', '/api/v1/children', self::resource('children', [
            'firstName' => 'Lía', 'firstSurname' => 'A', 'secondSurname' => 'B', 'birthDate' => Carbon::now()->addDay()->toDateString(),
        ]))->assertStatus(422);
        $this->assertSame(1, Child::count());
    }
}
