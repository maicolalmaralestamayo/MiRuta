<?php

namespace Tests\Feature;

use App\Models\Absence;
use App\Models\AbsenceType;
use App\Models\Trip;
use App\Models\TripPassenger;
use Carbon\Carbon;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/**
 * Versión 4.2.0 (docs/11 §11.61 y §11.62): sin datos del vehículo al empezar,
 * Dormido y Botado en la ida, «Pasó por la parada» a mano, por qué un teléfono
 * no es sensor, una sola petición en la ventana de viaje, viajes propios y
 * huellas de datos en sync, consultas condicionales, ajustes de la ventana y
 * paso de las ausencias de la 4.1.0.
 */
class Version42Test extends TestCase
{
    private $entity;
    private $itinerary;
    private array $stops;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow(Carbon::create(2026, 11, 16, 7, 0, 0));
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

    private function report($who, Trip $trip, array $attributes, string $query = '')
    {
        return $this->jsonApiAs($who, 'POST', "/api/v1/trips/{$trip->id}/reports{$query}", self::resource('trip-reports', $attributes));
    }

    private function pass($who, Trip $trip, int $index)
    {
        return $this->jsonApiAs($who, 'POST', "/api/v1/trips/{$trip->id}/stop-passes", self::resource('trip-stop-passes', ['routeIndex' => $index]));
    }

    public function test_al_empezar_no_hay_datos_del_vehiculo_hasta_que_informan_los_sensores(): void
    {
        $trip = $this->trip();
        $chief = $this->createChief($this->itinerary, $this->stops[1]);

        $this->jsonApiAs($chief, 'PATCH', "/api/v1/trips/{$trip->id}", self::resource('trips', ['status' => 'en_ejecucion'], [], (string) $trip->id))
            ->assertOk()->assertJsonPath('data.attributes.vehicleState', null);
        $this->jsonApiAs($chief, 'GET', "/api/v1/trips/{$trip->id}/live")
            ->assertJsonPath('data.attributes.vehicle.state', null)->assertJsonPath('data.attributes.sensors', 0)
            ->assertJsonPath('data.attributes.canManage', true);
    }

    public function test_ida_dormidos_y_botados_en_la_primera_parada(): void
    {
        $trip = $this->trip();
        [$a, $b, $c] = array_map(fn ($i) => $this->createWorker($this->entity, $this->itinerary, $this->stops[$i]), [1, 2, 2]);

        $this->report($a, $trip, ['workerState' => 'en_parada']);
        $this->report($a, $trip, ['workerState' => 'botado'])->assertJsonPath('meta.applied', true);
        // Nombres de la 4.3.0: se guardan como No recogido y Retrasado, en su parada.
        $this->report($b, $trip, ['workerState' => 'dormido'])
            ->assertJsonPath('data.attributes.stops.1.counts.no_recogido', 1)
            ->assertJsonPath('data.attributes.stops.2.counts.retrasado', 1);

        // Un Botado al que el teléfono detecta luego en el vehículo pasa a Viajando.
        $this->report($a, $trip, ['workerState' => 'viajando'])->assertJsonPath('meta.applied', true);
        $this->report($c, $trip, ['workerState' => 'no_voy'])->assertJsonPath('data.attributes.notGoing', 1);
    }

    public function test_paso_por_la_parada_a_mano(): void
    {
        $trip = $this->trip('regreso');
        $chief = $this->createChief($this->itinerary, $this->stops[1]);
        $worker = $this->createWorker($this->entity, $this->itinerary, $this->stops[2]);

        $this->pass($worker, $trip, 0)->assertForbidden();
        $this->pass($chief, $trip, 9)->assertStatus(422)->assertJsonPath('errors.0.code', 'STOP_INDEX_INVALID');

        // La salida de un viaje Planificado lo pone En ejecución.
        $this->pass($chief, $trip, 0)->assertCreated()->assertJsonPath('data.attributes.status', 'en_ejecucion')
            ->assertJsonPath('data.attributes.stops.0.passed', true);

        // Saltar una parada: las anteriores quedan pasadas y avanza la próxima.
        $this->pass($chief, $trip, 1)->assertJsonPath('data.attributes.vehicle.nextStopIndex', 2)
            ->assertJsonPath('data.attributes.stops.1.passedManually', true)
            ->assertJsonPath('data.attributes.stops.1.latitude', fn ($v) => is_float($v));

        // La parada final termina el viaje.
        $this->pass($this->createAdmin(), $trip, 2)->assertJsonPath('data.attributes.status', 'terminado');
        $this->assertSame('llegada', $trip->fresh()->finish_reason);
        $this->pass($chief, $trip, 2)->assertStatus(409)->assertJsonPath('errors.0.code', 'TRIP_CLOSED');
    }

    public function test_por_que_un_telefono_no_es_sensor(): void
    {
        $trip = $this->trip();
        [$a, $b, $c, $d] = array_map(fn ($i) => $this->createWorker($this->entity, $this->itinerary, $this->stops[$i]), [1, 1, 2, 2]);

        $this->report($a, $trip, ['workerState' => 'viajando', 'gps' => true]);
        $this->report($b, $trip, ['workerState' => 'viajando', 'gps' => false]);
        $this->report($c, $trip, ['workerState' => 'en_parada']);
        $this->report($d, $trip, ['workerState' => 'viajando']);
        Carbon::setTestNow(Carbon::now()->addSeconds(25));
        $this->report($a, $trip, ['gps' => true]);
        $this->report($b, $trip, ['gps' => false]);
        Carbon::setTestNow(Carbon::now()->addSeconds(10));

        $rows = collect($this->jsonApiAs($a, 'GET', "/api/v1/trips/{$trip->id}/passengers")->assertOk()->json('data'))
            ->keyBy(fn ($row) => $row['relationships']['user']['data']['id']);
        $this->assertSame(['sensor', true], [$rows[(string) $a->user_id]['attributes']['sensorReason'], $rows[(string) $a->user_id]['attributes']['sensor']]);
        $this->assertSame('sin_gps', $rows[(string) $b->user_id]['attributes']['sensorReason']);
        $this->assertSame('no_en_vehiculo', $rows[(string) $c->user_id]['attributes']['sensorReason']);
        $this->assertSame('sin_enviar', $rows[(string) $d->user_id]['attributes']['sensorReason']);
        $this->assertNotNull($rows[(string) $d->user_id]['attributes']['lastSeenAt']);
        $this->jsonApiAs($a, 'GET', "/api/v1/trips/{$trip->id}/live")->assertJsonPath('data.attributes.sensors', 1);
    }

    public function test_una_sola_peticion_envia_y_recibe_y_sync_trae_mis_viajes(): void
    {
        $trip = $this->trip();
        $worker = $this->createWorker($this->entity, $this->itinerary, $this->stops[1]);
        $other = $this->createWorker($this->entity, $this->itinerary);

        $cursor = $this->jsonApiAs($worker, 'GET', '/api/v1/sync')->assertOk()
            ->assertJsonPath('meta.myTrips.0.id', (string) $trip->id)
            ->assertJsonPath('meta.myTrips.0.myStopId', (string) $this->stops[1])
            ->assertJsonPath('meta.versions.trips', fn ($v) => is_string($v) && strlen($v) === 12)
            ->json('meta.cursor');
        // Sin parada habitual también viaja (docs/11 §11.65).
        $this->jsonApiAs($other, 'GET', '/api/v1/sync')->assertJsonCount(1, 'meta.myTrips');

        $this->report($worker, $trip, ['workerState' => 'en_parada', 'gps' => true], '?cursor='.$cursor)
            ->assertJsonPath('meta.ack', true)->assertJsonPath('meta.sync.meta.cursor', $cursor)
            ->assertJsonPath('meta.sync.meta.myTrips.0.myState', 'en_parada');
        $this->report($worker, $trip, ['gps' => true])->assertJsonMissingPath('meta.sync');

        // La huella cambia cuando cambian los datos.
        $before = $this->jsonApiAs($worker, 'GET', '/api/v1/sync')->json('meta.versions.entities');
        Cache::forget('sync.versions');
        $this->createEntity('NUEVA');
        $this->assertNotSame($before, $this->jsonApiAs($worker, 'GET', '/api/v1/sync')->json('meta.versions.entities'));
    }

    public function test_consulta_condicional_con_etag(): void
    {
        $worker = $this->createWorker($this->entity, $this->itinerary, $this->stops[1]);
        $etag = $this->jsonApiAs($worker, 'GET', '/api/v1/itineraries')->assertOk()->headers->get('ETag');
        $this->assertNotEmpty($etag);

        $this->jsonApiAs($worker, 'GET', '/api/v1/itineraries', null, ['If-None-Match' => $etag])->assertStatus(304);
        $this->jsonApiAs($worker, 'GET', '/api/v1/itineraries', null, ['If-None-Match' => '"otra"'])->assertOk();
    }

    public function test_ajustes_de_la_ventana_de_viaje(): void
    {
        $admin = $this->createAdmin();
        $settings = collect($this->jsonApiAs($admin, 'GET', '/api/v1/settings')->assertOk()->json('data'))->keyBy('id');

        $this->assertSame('Ventana viaje', $settings['fin_ventana']['attributes']['groupName']);
        // Desde la 4.4.0, «Frecuencia larga» (docs/11 §11.65).
        $this->assertSame('Frecuencia larga', $settings['frecuencia_larga']['attributes']['name']);
        $this->assertSame('15min', $settings['frecuencia_larga']['attributes']['value']);
        $this->assertFalse($settings->has('frecuencia_dia_viaje'));

        $this->jsonApiAs($admin, 'PATCH', '/api/v1/settings/frecuencia_larga', self::resource('settings', ['value' => '10min'], [], 'frecuencia_larga'))
            ->assertStatus(422)->assertJsonPath('errors.0.code', 'SETTING_INVALID');
        $this->jsonApiAs($admin, 'PATCH', '/api/v1/settings/frecuencia_larga', self::resource('settings', ['value' => '30min'], [], 'frecuencia_larga'))->assertOk();
    }

    public function test_jefe_declara_ausencia_solo_en_su_itinerario(): void
    {
        $other = $this->createItinerary($this->entity, 2, 'Otra');
        $chief = $this->createChief($this->itinerary, $this->stops[0]);
        $worker = $this->createWorker($this->entity, $this->itinerary, $this->stops[1]);
        $this->placeIn($worker, $other, $other->stopIds()[0]);
        $type = AbsenceType::create(['name' => 'Enfermedad']);
        $document = fn (array $itineraries) => ['data' => ['type' => 'absences', 'attributes' => ['startsOn' => Carbon::today()->toDateString(), 'endsOn' => null], 'relationships' => [
            'user' => ['data' => ['type' => 'users', 'id' => (string) $worker->user_id]],
            'absenceType' => ['data' => ['type' => 'absence-types', 'id' => (string) $type->id]],
            'itineraries' => ['data' => array_map(fn ($id) => ['type' => 'itineraries', 'id' => (string) $id], $itineraries)],
        ]]];

        $this->jsonApiAs($chief, 'POST', '/api/v1/absences', $document([$this->itinerary->id, $other->id]))->assertForbidden();
        $id = $this->jsonApiAs($chief, 'POST', '/api/v1/absences', $document([$this->itinerary->id]))->assertCreated()
            ->assertJsonPath('data.attributes.indefinite', true)->json('data.id');
        $this->jsonApiAs($worker, 'GET', '/api/v1/absences?filter[current]=true')->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $id);
        $this->jsonApiAs($worker, 'POST', '/api/v1/absences', $document([]))->assertStatus(422)->assertJsonPath('errors.0.code', 'ABSENCE_WITHOUT_ITINERARY');
    }

    public function test_actualizar_base_de_datos_pasa_las_ausencias_de_la_4_1(): void
    {
        // Esquema de la 4.1.0: sin user_id ni absence_itinerary.
        Schema::dropIfExists('absence_itinerary');
        Schema::table('absences', fn ($t) => $t->dropConstrainedForeignId('user_id'));
        $other = $this->createItinerary($this->entity, 2, 'Otra');
        $worker = $this->createWorker($this->entity, $this->itinerary, $this->stops[1]);
        $this->placeIn($worker, $other, $other->stopIds()[0]);
        $type = AbsenceType::create(['name' => 'Vacaciones']);
        DB::table('absences')->insert(['worker_id' => $worker->id, 'absence_type_id' => $type->id, 'starts_on' => Carbon::today()->toDateString(),
            'created_at' => Carbon::now(), 'updated_at' => Carbon::now()]);
        DB::table('settings')->insert(['key' => 'frecuencia_dia_viaje', 'value' => '15min', 'created_at' => Carbon::now(), 'updated_at' => Carbon::now()]);
        DB::table('settings')->insert(['key' => 'frecuencia_reposo', 'value' => '5min', 'created_at' => Carbon::now(), 'updated_at' => Carbon::now()]);

        (require database_path('migrations/2026_11_15_000001_upgrade_4_2.php'))->up();

        $absence = Absence::first();
        $this->assertSame((int) $worker->user_id, $absence->user_id);
        $this->assertEqualsCanonicalizing([$this->itinerary->id, $other->id], $absence->itineraryIds());
        $this->assertSame(0, DB::table('settings')->count());
        $this->assertTrue(Schema::hasColumn('trip_passengers', 'gps_ok'));

        // Se puede volver a ejecutar sin efecto.
        (require database_path('migrations/2026_11_15_000001_upgrade_4_2.php'))->up();
        $this->assertSame(2, DB::table('absence_itinerary')->count());
        $this->assertSame(0, TripPassenger::count());
    }
}
