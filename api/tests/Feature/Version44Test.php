<?php

namespace Tests\Feature;

use App\Models\Application;
use App\Models\EntityDenialReason;
use App\Models\ItineraryDenialReason;
use App\Models\Stop;
use App\Models\Trip;
use App\Models\TripPassenger;
use App\Models\TripStopPass;
use App\Models\VehicleType;
use App\Services\ChangeLog;
use App\Services\Settings;
use Carbon\Carbon;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Versión 4.4.0 (docs/11 §11.65): estados con parada detectada en los dos
 * sentidos (No recogido y Retrasado), cambios con hora de captura y en cola,
 * hora de paso por parada según los sensores, sensores con «Mínimo
 * confirmaciones» = 1, el servidor cubre a los teléfonos que no envían,
 * motivos de rechazo separados, «un viaje por itinerario, sentido y fecha»
 * sin contar los cancelados, frecuencias corta y larga, tipos de vehículo de
 * la instalación y registro de cambios.
 */
class Version44Test extends TestCase
{
    private $entity;
    private $itinerary;
    private array $stops;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow(Carbon::create(2026, 11, 16, 6, 50, 0));
        $this->entity = $this->createEntity();
        $this->itinerary = $this->createItinerary($this->entity, 4);
        $this->stops = $this->itinerary->stopIds();
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function trip(string $direction = 'ida', string $status = Trip::PLANNED): Trip
    {
        return Trip::create([
            'itinerary_id' => $this->itinerary->id, 'direction' => $direction, 'date' => Carbon::today(), 'departure_time' => '07:00',
            'departs_at' => Carbon::today()->setTime(7, 0), 'vehicle_type_id' => $this->vehicleType()->id,
            'status' => $status, 'status_changed_at' => Carbon::now(),
        ]);
    }

    private function send($who, Trip $trip, array $events, array $extra = [], array $headers = [])
    {
        return $this->jsonApiAs($who, 'POST', "/api/v1/trips/{$trip->id}/reports",
            self::resource('trip-reports', ['events' => $events, 'gps' => true] + $extra), $headers);
    }

    private static function worker(string $state, ?int $stopId, Carbon $at): array
    {
        return ['kind' => 'worker', 'state' => $state, 'stopId' => $stopId, 'capturedAt' => $at->toIso8601String()];
    }

    private static function vehicle(string $state, int $next, Carbon $at, bool $atStop = false): array
    {
        return ['kind' => 'vehicle', 'vehicleState' => $state, 'nextStopIndex' => $next, 'atStop' => $atStop, 'capturedAt' => $at->toIso8601String()];
    }

    private function setting(string $key, string $value): void
    {
        app(Settings::class)->set($key, $value);
    }

    public function test_un_solo_sensor_basta_con_minimo_uno_y_la_hora_de_paso_es_la_de_captura(): void
    {
        $this->setting('minimo_confirmaciones', '1');
        $trip = $this->trip();
        // Sin parada habitual: sube en la segunda parada (detectada por cercanía).
        $worker = $this->createWorker($this->entity, $this->itinerary);
        $t0 = Carbon::now()->subMinutes(5);

        // Cola guardada sin conexión: llega toda junta, desordenada; se ordena por hora de captura.
        $this->send($worker, $trip, [
            self::vehicle('en_movimiento', 2, $t0->copy()->addSeconds(40)),
            self::worker('viajando', $this->stops[1], $t0->copy()->addSeconds(20)),
            self::worker('en_parada', $this->stops[1], $t0),
        ])->assertOk()->assertJsonPath('meta.accepted', 3)
            ->assertJsonPath('data.attributes.status', 'en_ejecucion')
            ->assertJsonPath('data.attributes.sensors', 1)
            ->assertJsonPath('data.attributes.myState.sensor', true)
            ->assertJsonPath('data.attributes.vehicle.state', 'en_movimiento')
            ->assertJsonPath('data.attributes.vehicle.nextStopIndex', 2)
            ->assertJsonPath('data.attributes.stops.1.passed', true);

        $passenger = TripPassenger::where('user_id', $worker->user_id)->first();
        $this->assertSame('viajando', $passenger->state);
        $this->assertTrue($passenger->state_at->eq($t0->copy()->addSeconds(20)), 'El estado lleva la hora de captura.');
        $this->assertSame($this->stops[1], (int) $passenger->stop_id);
        // Salió cuando subió el primero y pasó por la segunda parada a la hora en que el sensor lo vio.
        $this->assertTrue(TripStopPass::where('trip_id', $trip->id)->where('route_index', 0)->value('passed_at') == $t0->copy()->addSeconds(20));
        $this->assertTrue(Carbon::parse(TripStopPass::where('trip_id', $trip->id)->where('route_index', 1)->value('passed_at'))->eq($t0->copy()->addSeconds(40)));
    }

    public function test_estados_en_cualquier_parada_y_en_los_dos_sentidos_con_cantidades_por_parada(): void
    {
        foreach (['ida', 'regreso'] as $direction) {
            $trip = $this->trip($direction);
            $route = $trip->routeStopIds();
            [$a, $b, $c, $d] = array_map(fn () => $this->createWorker($this->entity, $this->itinerary, $this->stops[0]), range(1, 4));
            $at = Carbon::now()->subMinute();

            $this->send($a, $trip, [self::worker('en_parada', $route[2], $at)]);
            $this->send($b, $trip, [self::worker('de_camino', $route[2], $at)]);
            $this->send($c, $trip, [self::worker('en_parada', $route[1], $at)]);
            $live = $this->send($d, $trip, [self::worker('no_voy', null, $at)])->assertOk();

            // Cantidades en la parada detectada, no en la habitual; sin ceros.
            $live->assertJsonPath('data.attributes.stops.2.counts.en_parada', 1)
                ->assertJsonPath('data.attributes.stops.2.counts.de_camino', 1)
                ->assertJsonPath('data.attributes.stops.1.counts.en_parada', 1)
                ->assertJsonPath('data.attributes.stops.0.counts', [])
                ->assertJsonPath('data.attributes.notGoing', 1)
                ->assertJsonPath('data.attributes.travels', true);

            // Mi estado lleva la parada detectada con su nombre.
            $this->jsonApiAs($a, 'GET', "/api/v1/trips/{$trip->id}/live")
                ->assertJsonPath('data.attributes.myState.stopId', (string) $route[2])
                ->assertJsonPath('data.attributes.myState.stopName', Stop::find($route[2])->landmark)
                ->assertJsonPath('data.attributes.myStopId', (string) $this->stops[0]);

            // Retrasado y No recogido los calcula el teléfono, también en la ida.
            $this->send($b, $trip, [self::worker('retrasado', $route[2], $at->copy()->addSeconds(30))])->assertJsonPath('meta.applied', true)
                ->assertJsonPath('data.attributes.stops.2.counts.retrasado', 1);
            $this->send($b, $trip, [self::worker('de_camino', $route[3], $at->copy()->addSeconds(40))])
                ->assertJsonPath('meta.applied', false)->assertJsonPath('meta.reason', 'ESTADO_FINAL');

            // Viajando y luego Dejado en la parada donde se bajó (regreso incluido).
            $this->send($c, $trip, [self::worker('viajando', $route[1], $at->copy()->addSeconds(10)), self::worker('dejado', $route[3], $at->copy()->addSeconds(50))])
                ->assertJsonPath('data.attributes.stops.3.counts.dejado', 1);
            $this->jsonApiAs($c, 'GET', "/api/v1/trips/{$trip->id}/live")->assertJsonPath('data.attributes.myState.state', 'dejado')
                ->assertJsonPath('data.attributes.myState.stopName', Stop::find($route[3])->landmark);
        }
    }

    public function test_el_servidor_pone_no_recogido_y_retrasado_si_el_telefono_no_envia_y_el_telefono_manda(): void
    {
        $trip = $this->trip('ida', Trip::PLANNED);
        $chief = $this->createChief($this->itinerary, $this->stops[0]);
        $waiting = $this->createWorker($this->entity, $this->itinerary, $this->stops[1]);
        $coming = $this->createWorker($this->entity, $this->itinerary, $this->stops[1]);
        $active = $this->createWorker($this->entity, $this->itinerary, $this->stops[1]);
        $at = Carbon::now()->subMinutes(10);

        $this->send($waiting, $trip, [self::worker('en_parada', $this->stops[1], $at)]);
        $this->send($coming, $trip, [self::worker('de_camino', $this->stops[1], $at)]);
        $this->send($active, $trip, [self::worker('en_parada', $this->stops[1], $at)]);

        // Sus teléfonos dejan de enviar (salvo uno).
        Carbon::setTestNow(Carbon::now()->addMinutes(5));
        $this->send($active, $trip, []);

        $this->jsonApiAs($chief, 'POST', "/api/v1/trips/{$trip->id}/stop-passes", self::resource('trip-stop-passes', ['routeIndex' => 1]))->assertCreated()
            ->assertJsonPath('data.attributes.stops.1.counts.no_recogido', 1)
            ->assertJsonPath('data.attributes.stops.1.counts.retrasado', 1)
            ->assertJsonPath('data.attributes.stops.1.counts.en_parada', 1);
        $this->assertTrue((bool) TripPassenger::where('user_id', $waiting->user_id)->value('set_by_server'));

        // El teléfono, al volver, sabe más: iba en el vehículo.
        $this->send($waiting, $trip, [self::worker('viajando', $this->stops[1], Carbon::now()->subMinutes(4))])->assertJsonPath('meta.applied', true);
        $this->assertSame('viajando', TripPassenger::where('user_id', $waiting->user_id)->value('state'));
        // Un No recogido calculado por el teléfono que sí subió también se corrige.
        $this->send($active, $trip, [self::worker('no_recogido', $this->stops[1], Carbon::now()->subSeconds(30))]);
        $this->send($active, $trip, [self::worker('viajando', $this->stops[1], Carbon::now())])->assertJsonPath('meta.applied', true);
    }

    public function test_al_llegar_quien_sigue_viajando_queda_dejado_en_la_ultima_parada(): void
    {
        $this->setting('minimo_confirmaciones', '1');
        $trip = $this->trip('regreso');
        $route = $trip->routeStopIds();
        $worker = $this->createWorker($this->entity, $this->itinerary);
        $at = Carbon::now()->subMinutes(3);

        $this->send($worker, $trip, [
            self::worker('en_parada', $route[0], $at),
            self::worker('viajando', $route[0], $at->copy()->addSeconds(10)),
            self::vehicle('detenido', 3, $at->copy()->addSeconds(60), true),
        ])->assertJsonPath('data.attributes.status', 'terminado')
            ->assertJsonPath('data.attributes.stops.3.counts.dejado', 1);
        $this->assertSame('dejado', TripPassenger::where('user_id', $worker->user_id)->value('state'));
    }

    public function test_telefonos_4_3_reciben_botado_y_dormido(): void
    {
        $trip = $this->trip();
        [$a, $b] = array_map(fn () => $this->createWorker($this->entity, $this->itinerary, $this->stops[1]), [1, 2]);

        $this->jsonApiAs($a, 'POST', "/api/v1/trips/{$trip->id}/reports", self::resource('trip-reports', ['workerState' => 'en_parada']), ['X-App-Version' => '13']);
        $this->jsonApiAs($a, 'POST', "/api/v1/trips/{$trip->id}/reports", self::resource('trip-reports', ['workerState' => 'botado']), ['X-App-Version' => '13'])
            ->assertJsonPath('data.attributes.myState.state', 'botado')
            ->assertJsonPath('data.attributes.stops.1.counts.botado', 1);
        $this->jsonApiAs($b, 'POST', "/api/v1/trips/{$trip->id}/reports", self::resource('trip-reports', ['workerState' => 'dormido']), ['X-App-Version' => '13']);

        $this->assertSame(['no_recogido', 'retrasado'], TripPassenger::orderBy('id')->pluck('state')->all());
        $this->jsonApiAs($b, 'GET', "/api/v1/trips/{$trip->id}/live", null, ['X-App-Version' => '14'])->assertJsonPath('data.attributes.myState.state', 'retrasado');
        $this->jsonApiAs($b, 'GET', '/api/v1/sync', null, ['X-App-Version' => '13'])->assertJsonPath('meta.myTrips.0.myState', 'dormido');
    }

    public function test_un_viaje_por_itinerario_sentido_y_fecha_sin_contar_los_cancelados(): void
    {
        $admin = $this->createAdmin();
        $plan = fn () => $this->jsonApiAs($admin, 'POST', '/api/v1/trips', self::resource('trips',
            ['direction' => 'ida', 'date' => Carbon::tomorrow()->toDateString(), 'departureTime' => '17:00'],
            ['itinerary' => ['itineraries', $this->itinerary->id], 'vehicleType' => ['vehicle-types', $this->vehicleType()->id]]));

        $id = $plan()->assertCreated()->json('data.id');
        $plan()->assertStatus(409)->assertJsonPath('errors.0.code', 'TRIP_EXISTS');
        $this->jsonApiAs($admin, 'PATCH', "/api/v1/trips/{$id}", self::resource('trips', ['status' => 'cancelado'], [], $id))->assertOk();
        $second = $plan()->assertCreated()->json('data.id');
        $this->jsonApiAs($admin, 'DELETE', "/api/v1/trips/{$second}")->assertNoContent();
        $plan()->assertCreated();
    }

    public function test_motivos_de_rechazo_separados_y_la_4_3_sigue_rechazando(): void
    {
        $chief = $this->createChief($this->itinerary, $this->stops[0]);
        $admin = $this->createAdmin();
        $member = $this->createWorker($this->entity);
        $application = Application::create(['user_id' => $member->user_id, 'type' => Application::TYPE_ITINERARY, 'status' => Application::PENDING,
            'entity_id' => $this->entity->id, 'itinerary_id' => $this->itinerary->id]);
        (new DatabaseSeeder())->run();

        $this->assertSame(3, EntityDenialReason::count());
        $this->assertSame(5, ItineraryDenialReason::count());
        $this->jsonApiAs($admin, 'GET', '/api/v1/entity-denial-reasons')->assertJsonCount(3, 'data');
        // La 4.3.0 pide denial-reasons con el tipo y rechaza con ese id.
        $reasons = $this->jsonApiAs($chief, 'GET', '/api/v1/denial-reasons?filter[applicationType]=itinerario')->assertJsonCount(5, 'data')->json('data');
        $overloaded = collect($reasons)->firstWhere('attributes.name', 'El itinerario está sobrecargado');
        $this->jsonApiAs($chief, 'PATCH', "/api/v1/applications/{$application->id}?include=denialReason", self::resource('applications', ['status' => 'rechazada'],
            ['denialReason' => ['denial-reasons', $overloaded['id']]]))->assertOk()
            ->assertJsonPath('data.relationships.denialReason.data.type', 'itinerary-denial-reasons')
            ->assertJsonPath('included.0.attributes.name', 'El itinerario está sobrecargado');
    }

    public function test_la_instalacion_crea_solo_yutong_y_dongfeng(): void
    {
        (new DatabaseSeeder())->run();

        $types = VehicleType::orderBy('name')->get()->map(fn ($t) => [$t->name, (int) $t->seats, (int) $t->standing])->all();
        $this->assertSame([['Carro Dongfeng', 32, 9], ['Ómnibus Yutong', 45, 15]], $types);
    }

    public function test_la_actualizacion_desde_la_4_3(): void
    {
        $trip = $this->trip();
        $worker = $this->createWorker($this->entity, $this->itinerary, $this->stops[1]);
        $other = $this->createWorker($this->entity, $this->itinerary, $this->stops[2]);
        $now = Carbon::now();
        DB::table('trip_passengers')->insert([
            ['trip_id' => $trip->id, 'user_id' => $worker->user_id, 'stop_id' => $this->stops[1], 'state' => 'no_recogido', 'state_at' => $now, 'reported_at' => $now, 'children_count' => 0, 'created_at' => $now, 'updated_at' => $now],
            ['trip_id' => $trip->id, 'user_id' => $other->user_id, 'stop_id' => $this->stops[2], 'state' => 'retrasado', 'state_at' => $now, 'reported_at' => $now, 'children_count' => 0, 'created_at' => $now, 'updated_at' => $now],
        ]);
        // Como en una 4.3.0: estados viejos, ajustes y motivos.
        // Con MariaDB la columna ya tiene la lista nueva: se amplía como en la versión vieja.
        if (DB::getDriverName() !== 'sqlite') {
            DB::statement("ALTER TABLE trip_passengers MODIFY state ENUM('de_camino','en_parada','viajando','dejado','recogido','botado','dormido','no_recogido','retrasado','no_voy') NOT NULL");
        }
        DB::table('trip_passengers')->where('user_id', $worker->user_id)->update(['state' => 'botado']);
        DB::table('trip_passengers')->where('user_id', $other->user_id)->update(['state' => 'dormido']);
        DB::table('settings')->insert([
            ['key' => 'frecuencia_calculo', 'value' => '20seg', 'created_at' => $now, 'updated_at' => $now],
            ['key' => 'frecuencia_reposo', 'value' => '30min', 'created_at' => $now, 'updated_at' => $now],
        ]);
        $old = DB::table('denial_reasons')->insertGetId(['name' => 'Datos incorrectos', 'active' => true, 'created_at' => $now, 'updated_at' => $now]);
        $application = Application::create(['user_id' => $worker->user_id, 'type' => Application::TYPE_ENTITY, 'status' => Application::REJECTED,
            'entity_id' => $this->entity->id, 'denial_reason_id' => $old]);

        (require database_path('migrations/2026_11_16_000002_upgrade_4_4.php'))->up();

        $this->assertSame(['no_recogido', 'retrasado'], TripPassenger::orderBy('id')->pluck('state')->all());
        $this->assertSame('20seg', DB::table('settings')->where('key', 'frecuencia_corta')->value('value'));
        $this->assertSame('30min', DB::table('settings')->where('key', 'frecuencia_larga')->value('value'));
        $this->assertFalse(DB::table('settings')->where('key', 'frecuencia_calculo')->exists());
        // El motivo viejo se copia a las dos tablas y la rechazada lo conserva.
        $this->assertTrue(EntityDenialReason::where('name', 'Datos incorrectos')->exists());
        $this->assertTrue(ItineraryDenialReason::where('name', 'Datos incorrectos')->exists());
        $this->assertSame('Datos incorrectos', $application->fresh()->rejectionReason()?->name);
        $this->assertTrue(ItineraryDenialReason::where('name', 'El itinerario está sobrecargado')->exists());
    }

    public function test_registro_de_cambios(): void
    {
        $admin = $this->createAdmin();
        $worker = $this->createWorker($this->entity, $this->itinerary, $this->stops[1]);
        $other = $this->createEntity('OTRA');

        // Sin cursor: hay que descargarlo todo.
        $first = $this->jsonApiAs($worker, 'GET', '/api/v1/sync?changes=')->assertOk()->assertJsonPath('meta.changes.full', true);
        $cursor = $first->json('meta.changes.cursor');

        // Cambia una parada que ve, se crea otra Entidad y se borra un itinerario.
        $this->jsonApiAs($admin, 'PATCH', "/api/v1/stops/{$this->stops[1]}", self::resource('stops', ['landmark' => 'Coppelia'], [], (string) $this->stops[1]))->assertOk();
        $doomed = $this->createItinerary($this->entity, 2, 'Borrar');
        $doomedStops = $doomed->stopIds();
        $this->jsonApiAs($admin, 'DELETE', "/api/v1/itineraries/{$doomed->id}")->assertNoContent();

        $changes = $this->jsonApiAs($worker, 'GET', '/api/v1/sync?changes='.$cursor)->assertOk()->assertJsonPath('meta.changes.full', false)->json('meta.changes');
        $stop = collect($changes['data'])->first(fn ($r) => $r['type'] === 'stops' && $r['id'] === (string) $this->stops[1]);
        $this->assertSame('Coppelia', $stop['attributes']['landmark']);
        $this->assertContains((string) $doomed->id, $changes['deleted']['itineraries']);
        // Las relaciones borradas en cascada también.
        $this->assertNotEmpty($changes['deleted']['itinerary-stops'] ?? []);
        $this->assertContains('stops', $changes['changed']);

        // Al día: nada nuevo.
        $this->jsonApiAs($worker, 'GET', '/api/v1/sync?changes='.$changes['cursor'])->assertJsonPath('meta.changes.data', [])
            ->assertJsonPath('meta.changes.cursor', $changes['cursor']);

        // Poda: lo más viejo que «Conservación cambios» se borra y ese teléfono lo descarga todo.
        Carbon::setTestNow(Carbon::now()->addMonths(2));
        $other->update(['name' => 'Otra entidad']);
        $this->assertGreaterThan(0, app(ChangeLog::class)->prune());
        $this->jsonApiAs($worker, 'GET', '/api/v1/sync?changes='.$cursor)->assertJsonPath('meta.changes.full', true);
        $this->jsonApiAs($worker, 'GET', '/api/v1/sync?changes='.$changes['cursor'])->assertJsonPath('meta.changes.full', false);
        // Las apps 4.3.0 siguen recibiendo meta.versions.
        $this->jsonApiAs($worker, 'GET', '/api/v1/sync')->assertJsonPath('meta.versions.stops', fn ($v) => is_string($v));
        $this->assertNotNull($doomedStops);
    }

    public function test_frecuencias_corta_y_larga(): void
    {
        $admin = $this->createAdmin();
        $settings = collect($this->jsonApiAs($admin, 'GET', '/api/v1/settings')->json('data'))->keyBy('id');

        $this->assertSame('Frecuencia corta', $settings['frecuencia_corta']['attributes']['name']);
        $this->assertSame('10seg', $settings['frecuencia_corta']['attributes']['value']);
        $this->assertSame('Frecuencia larga', $settings['frecuencia_larga']['attributes']['name']);
        $this->assertSame('1mes', $settings['conservacion_cambios']['attributes']['value']);
        $this->assertFalse($settings->has('frecuencia_calculo'));
    }
}
