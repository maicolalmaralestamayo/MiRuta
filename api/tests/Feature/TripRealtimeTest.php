<?php

namespace Tests\Feature;

use App\Models\Child;
use App\Models\ChildParent;
use App\Models\Notification;
use App\Models\Trip;
use App\Models\TripStopPass;
use App\Services\Settings;
use App\Services\Trips;
use App\Support\IdentityCard;
use Carbon\Carbon;
use Tests\TestCase;

/**
 * Tiempo real (docs/11 §11.43 a §11.47): estados de los trabajadores, sensores
 * del vehículo por mayoría, estado automático del viaje y plazos.
 */
class TripRealtimeTest extends TestCase
{
    private $entity;
    private $itinerary;
    /** @var int[] paradas en orden (1.ª, 2.ª, 3.ª) */
    private array $stops;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow(Carbon::create(2026, 11, 9, 7, 0, 0));
        $this->entity = $this->createEntity();
        $this->itinerary = $this->createItinerary($this->entity, 3);
        $this->stops = $this->itinerary->stopIds();
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function trip(string $direction = 'ida', string $time = '07:00'): Trip
    {
        return Trip::create([
            'itinerary_id' => $this->itinerary->id, 'direction' => $direction, 'date' => Carbon::today(), 'departure_time' => $time,
            'departs_at' => Carbon::today()->setTimeFromTimeString($time), 'vehicle_type_id' => $this->vehicleType()->id,
            'status' => Trip::PLANNED, 'status_changed_at' => Carbon::now(),
        ]);
    }

    private function workers(array $stopIndexes): array
    {
        return array_map(fn ($i) => $this->createWorker($this->entity, $this->itinerary, $this->stops[$i]), $stopIndexes);
    }

    private function report($who, Trip $trip, array $attributes)
    {
        return $this->jsonApiAs($who, 'POST', "/api/v1/trips/{$trip->id}/reports", self::resource('trip-reports', $attributes));
    }

    public function test_ida_empieza_con_tres_viajando_y_termina_al_pasar_la_ultima_parada(): void
    {
        $trip = $this->trip();
        [$a, $b, $c, $d] = $this->workers([1, 2, 2, 1]);

        foreach ([$a, $b, $c, $d] as $w) {
            $this->report($w, $trip, ['workerState' => 'en_parada'])->assertOk()->assertJsonPath('meta.ack', true)->assertJsonPath('meta.applied', true);
        }
        $this->jsonApiAs($a, 'GET', "/api/v1/trips/{$trip->id}/live")->assertJsonPath('data.attributes.stops.0.counts.en_parada', 4);

        $this->report($a, $trip, ['workerState' => 'viajando']);
        $this->report($b, $trip, ['workerState' => 'viajando']);
        $this->assertSame(Trip::PLANNED, $trip->fresh()->status);
        $this->report($c, $trip, ['workerState' => 'viajando'])->assertJsonPath('data.attributes.status', 'en_ejecucion')
            ->assertJsonPath('data.attributes.stops.0.passed', true)->assertJsonPath('data.attributes.vehicle.nextStopIndex', 1)
            ->assertJsonPath('data.attributes.inVehicle.workers', 3)->assertJsonPath('data.attributes.sensors', 3)
            ->assertJsonPath('data.attributes.myState.sensor', true);
        $this->assertSame(1, Notification::where('user_id', $d->user_id)->where('kind', 'viaje_estado')->count());

        // Dos sensores no bastan (con 3 sensores hacen falta 3 coincidencias).
        $this->report($a, $trip, ['vehicleState' => 'en_movimiento', 'nextStopIndex' => 2]);
        $this->report($b, $trip, ['vehicleState' => 'en_movimiento', 'nextStopIndex' => 2]);
        $this->assertSame(1, $trip->fresh()->next_stop_index);
        $this->report($c, $trip, ['vehicleState' => 'en_movimiento', 'nextStopIndex' => 2])
            ->assertJsonPath('data.attributes.stops.1.passed', true)->assertJsonPath('data.attributes.vehicle.nextStopIndex', 2);

        // Se baja en la segunda parada: Dejado es definitivo.
        $this->report($a, $trip, ['workerState' => 'dejado', 'stopId' => $this->stops[1]])->assertJsonPath('data.attributes.stops.1.counts.dejado', 1);
        $this->report($a, $trip, ['workerState' => 'viajando'])->assertJsonPath('meta.applied', false)->assertJsonPath('meta.reason', 'ESTADO_FINAL');

        // Con 2 sensores basta la mayoría de los que hay (2 de 2).
        $this->report($b, $trip, ['vehicleState' => 'en_movimiento', 'nextStopIndex' => 3]);
        $this->report($c, $trip, ['vehicleState' => 'en_movimiento', 'nextStopIndex' => 3])->assertJsonPath('data.attributes.status', 'terminado');
        $trip->refresh();
        $this->assertSame('llegada', $trip->finish_reason);
        $this->assertSame(3, TripStopPass::where('trip_id', $trip->id)->count());
    }

    public function test_informes_idempotentes_y_transiciones_no_permitidas(): void
    {
        $trip = $this->trip();
        [$a] = $this->workers([1]);
        $at = Carbon::now()->toIso8601String();

        $this->report($a, $trip, ['workerState' => 'de_camino', 'reportedAt' => $at])->assertJsonPath('meta.applied', true);
        $this->report($a, $trip, ['workerState' => 'de_camino', 'reportedAt' => $at])->assertJsonPath('meta.applied', true);
        $this->report($a, $trip, ['workerState' => 'en_parada', 'reportedAt' => Carbon::now()->subMinute()->toIso8601String()])
            ->assertJsonPath('meta.applied', false)->assertJsonPath('meta.reason', 'INFORME_ANTERIOR');
        $this->report($a, $trip, ['workerState' => 'recogido'])->assertStatus(422)->assertJsonPath('errors.0.code', 'WORKER_STATE_INVALID');

        // Con un solo trabajador esperado, basta él para empezar.
        $this->report($a, $trip, ['workerState' => 'viajando'])->assertJsonPath('data.attributes.status', 'en_ejecucion');
        // Viajando solo puede pasar a Dejado.
        $this->report($a, $trip, ['workerState' => 'no_voy'])->assertJsonPath('meta.reason', 'TRANSICION_NO_PERMITIDA');

        // Quien no es del itinerario no informa.
        $this->report($this->createWorker($this->entity), $trip, ['workerState' => 'en_parada'])->assertNotFound();
        $this->report($this->createAdmin(), $trip, ['workerState' => 'en_parada'])->assertForbidden();
    }

    public function test_hijos_que_suben_con_el_trabajador(): void
    {
        $trip = $this->trip();
        [$a, $b] = $this->workers([1, 2]);
        $card = IdentityCard::make(Carbon::now()->subYears(8)->toDateString(), 'F', 7);
        $child = Child::create(IdentityCard::columns($card) + ['first_name' => 'Niña', 'first_surname' => 'A', 'second_surname' => 'B']);
        ChildParent::create(['child_id' => $child->id, 'user_id' => $a->user_id]);
        ChildParent::create(['child_id' => $child->id, 'user_id' => $b->user_id]);

        $this->report($b, $trip, ['workerState' => 'viajando', 'childIds' => [999]])->assertStatus(422)->assertJsonPath('errors.0.code', 'CHILD_NOT_ELIGIBLE');
        $this->report($a, $trip, ['workerState' => 'viajando', 'childIds' => [$child->id]]);
        // El mismo niño cuenta una sola vez aunque lo declaren los dos padres.
        $this->report($b, $trip, ['workerState' => 'viajando', 'childIds' => [$child->id]])
            ->assertJsonPath('data.attributes.inVehicle.workers', 2)->assertJsonPath('data.attributes.inVehicle.children', 1)
            ->assertJsonPath('data.attributes.inVehicle.total', 3);
    }

    public function test_regreso_empieza_con_recogidos_en_la_ultima_parada_y_termina_detenido_en_la_primera(): void
    {
        $trip = $this->trip('regreso');
        [$a, $b, $c] = $this->workers([2, 2, 2]);
        [$waiting] = $this->workers([1]);

        // El recorrido del regreso va al revés.
        $this->jsonApiAs($a, 'GET', "/api/v1/trips/{$trip->id}/live")->assertJsonPath('data.attributes.stops.0.stopId', (string) $this->stops[2]);

        $this->report($waiting, $trip, ['workerState' => 'en_parada']);
        foreach ([$a, $b, $c] as $w) {
            $response = $this->report($w, $trip, ['workerState' => 'recogido']);
        }
        $response->assertJsonPath('data.attributes.status', 'en_ejecucion')->assertJsonPath('data.attributes.stops.1.counts.en_parada', 1);

        // Detención larga: se avisa a quien está En la parada, y luego que sigue.
        foreach ([$a, $b, $c] as $w) {
            $this->report($w, $trip, ['vehicleState' => 'detenido', 'nextStopIndex' => 1]);
        }
        $this->assertSame(Trip::STOPPED, $trip->fresh()->vehicle_state);
        Carbon::setTestNow(Carbon::now()->addMinutes(6));
        foreach ([$a, $b, $c] as $w) {
            $this->report($w, $trip, ['vehicleState' => 'detenido', 'nextStopIndex' => 1]);
        }
        $this->assertSame(1, Notification::where('user_id', $waiting->user_id)->where('kind', 'vehiculo_detencion_larga')->count());

        // Causa de la detención (Administrador o Jefe).
        $cause = \App\Models\DetentionCause::create(['name' => 'Rotura']);
        $admin = $this->createAdmin();
        $this->jsonApiAs($admin, 'PATCH', "/api/v1/trips/{$trip->id}", self::resource('trips', [], ['detentionCause' => ['detention-causes', $cause->id]]))
            ->assertOk()->assertJsonPath('data.relationships.detentionCause.data.id', (string) $cause->id);

        foreach ([$a, $b, $c] as $w) {
            $this->report($w, $trip, ['vehicleState' => 'en_movimiento', 'nextStopIndex' => 1]);
        }
        $this->assertSame(1, Notification::where('user_id', $waiting->user_id)->where('kind', 'vehiculo_reanuda')->count());
        $this->assertNull($trip->fresh()->detention_cause_id);

        // Llega a la parada del que espera (Recogiendo): se le avisa.
        foreach ([$a, $b, $c] as $w) {
            $this->report($w, $trip, ['vehicleState' => 'detenido', 'atStop' => true, 'nextStopIndex' => 1]);
        }
        $this->assertSame(1, Notification::where('user_id', $waiting->user_id)->where('kind', 'vehiculo_en_parada')->count());
        $this->report($waiting, $trip, ['workerState' => 'recogido']);

        // Pasa la parada intermedia y se detiene en la primera: termina.
        foreach ([$a, $b, $c, $waiting] as $w) {
            $this->report($w, $trip, ['vehicleState' => 'en_movimiento', 'nextStopIndex' => 2]);
        }
        $this->assertSame(Trip::RUNNING, $trip->fresh()->status);
        foreach ([$a, $b, $c] as $w) {
            $response = $this->report($w, $trip, ['vehicleState' => 'detenido', 'atStop' => true, 'nextStopIndex' => 2]);
        }
        $response->assertJsonPath('data.attributes.status', 'terminado');
        $this->assertSame('llegada', $trip->fresh()->finish_reason);
    }

    public function test_un_sensor_que_no_envia_en_tres_calculos_deja_de_contar(): void
    {
        $trip = $this->trip();
        [$a, $b, $c] = $this->workers([1, 1, 2]);

        foreach ([$a, $b, $c] as $w) {
            $this->report($w, $trip, ['workerState' => 'viajando']);
        }
        $this->assertSame(3, count(app(Trips::class)->activeSensorIds($trip)));

        Carbon::setTestNow(Carbon::now()->addSeconds(31));
        $this->report($a, $trip, ['vehicleState' => 'detenido'])->assertJsonPath('data.attributes.sensors', 1)
            ->assertJsonPath('data.attributes.vehicle.state', 'detenido');
    }

    public function test_plazos_eliminacion_duracion_maxima_y_espera_cierre(): void
    {
        $trips = app(Trips::class);
        $planned = $this->trip('ida', '07:00');
        $running = $this->trip('regreso', '07:00');
        $trips->start($running);

        Carbon::setTestNow(Carbon::now()->addHours(4));
        $this->assertSame(['deleted' => 0, 'finished' => 0], $trips->review());

        // Plazo eliminación (5 h desde la salida) y Duración máxima (5 h desde que empezó).
        Carbon::setTestNow(Carbon::now()->addHours(1)->addMinute());
        $this->assertSame(['deleted' => 1, 'finished' => 1], $trips->review());
        $this->assertNull(Trip::find($planned->id));
        $this->assertSame('duracion_maxima', $running->fresh()->finish_reason);

        // Espera cierre: 2 h tras el último Dejado sin llegar a la última parada.
        app(Settings::class)->set('duracion_maxima', '2dia');
        $trip = Trip::create([
            'itinerary_id' => $this->itinerary->id, 'direction' => 'ida', 'date' => Carbon::today(), 'departure_time' => Carbon::now()->format('H:i'),
            'departs_at' => Carbon::now(), 'vehicle_type_id' => $this->vehicleType()->id, 'status' => Trip::PLANNED, 'status_changed_at' => Carbon::now(),
        ]);
        [$a] = $this->workers([1]);
        $this->report($a, $trip, ['workerState' => 'viajando']);
        $this->report($a, $trip, ['workerState' => 'dejado']);
        Carbon::setTestNow(Carbon::now()->addHours(2)->addMinute());
        $trips->review();
        $this->assertSame('espera_cierre', $trip->fresh()->finish_reason);
        $this->report($a, $trip, ['workerState' => 'dejado'])->assertJsonPath('meta.applied', false)->assertJsonPath('meta.reason', 'VIAJE_CERRADO');
    }
}
