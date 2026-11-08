<?php

namespace Tests\Feature;

use App\Models\Absence;
use App\Models\AbsenceType;
use App\Models\Notification;
use App\Models\Trip;
use Carbon\Carbon;
use Tests\TestCase;

/**
 * Planificación y estados de los viajes (docs/11 §11.33, §11.43, §11.47 y §11.53).
 */
class TripsTest extends TestCase
{
    private function plan($who, $itinerary, string $direction = 'ida', ?string $date = null, string $time = '07:30')
    {
        return $this->jsonApiAs($who, 'POST', '/api/v1/trips', self::resource('trips', [
            'direction' => $direction, 'date' => $date ?? Carbon::tomorrow()->toDateString(), 'departureTime' => $time,
        ], ['itinerary' => ['itineraries', $itinerary->id], 'vehicleType' => ['vehicle-types', $this->vehicleType()->id]]));
    }

    public function test_planifican_el_administrador_y_el_jefe_de_su_itinerario(): void
    {
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);
        $other = $this->createItinerary($entity);
        $chief = $this->createChief($itinerary, $itinerary->stopIds()[0]);
        $worker = $this->createWorker($entity, $itinerary, $itinerary->stopIds()[1]);

        $this->plan($worker, $itinerary)->assertForbidden();
        $this->plan($chief, $other)->assertForbidden();
        $this->plan($chief, $itinerary)->assertCreated()->assertJsonPath('data.attributes.status', 'planificado')
            ->assertJsonPath('data.attributes.departureTime', '07:30')->assertJsonPath('data.meta.expectedPassengers', 2)
            ->assertJsonPath('data.meta.capacity', 60);
        $this->plan($chief, $itinerary)->assertStatus(409)->assertJsonPath('errors.0.code', 'TRIP_EXISTS');
        $this->plan($this->createAdmin(), $itinerary, 'regreso', null, '17:00')->assertCreated();
        $this->plan($chief, $itinerary, 'ida', Carbon::yesterday()->toDateString())->assertStatus(422)->assertJsonPath('errors.0.code', 'TRIP_IN_PAST');

        // Se notifica la creación a los trabajadores del itinerario.
        $this->assertSame(2, Notification::where('user_id', $worker->user_id)->where('kind', 'viaje_creado')->count());
    }

    public function test_quien_ve_los_viajes(): void
    {
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);
        $admin = $this->createAdmin();
        $id = $this->plan($admin, $itinerary)->json('data.id');
        $withStop = $this->createWorker($entity, $itinerary, $itinerary->stopIds()[1]);
        $withoutStop = $this->createWorker($entity, $itinerary);
        $outsider = $this->createWorker($entity);

        $this->jsonApiAs($withStop, 'GET', '/api/v1/trips')->assertJsonCount(1, 'data');
        $this->jsonApiAs($withoutStop, 'GET', '/api/v1/trips')->assertJsonCount(0, 'data');
        $this->jsonApiAs($outsider, 'GET', "/api/v1/trips/{$id}")->assertNotFound();
        $this->jsonApiAs($admin, 'GET', '/api/v1/trips?filter[status]=planificado,en_ejecucion&include=itinerary,vehicleType')
            ->assertJsonCount(1, 'data')->assertJsonCount(2, 'included');
    }

    public function test_solo_se_edita_planificado_y_se_notifica_el_cambio(): void
    {
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);
        $chief = $this->createChief($itinerary, $itinerary->stopIds()[0]);
        $worker = $this->createWorker($entity, $itinerary, $itinerary->stopIds()[1]);
        $id = $this->plan($chief, $itinerary)->json('data.id');

        $this->jsonApiAs($chief, 'PATCH', "/api/v1/trips/{$id}", self::resource('trips', ['departureTime' => '08:00']))
            ->assertOk()->assertJsonPath('data.attributes.departureTime', '08:00');
        $this->assertSame(1, Notification::where('user_id', $worker->user_id)->where('kind', 'viaje_modificado')->count());

        $this->jsonApiAs($chief, 'PATCH', "/api/v1/trips/{$id}", self::resource('trips', ['status' => 'en_ejecucion']))
            ->assertOk()->assertJsonPath('data.attributes.status', 'en_ejecucion')->assertJsonPath('data.attributes.editable', false);
        $this->jsonApiAs($chief, 'PATCH', "/api/v1/trips/{$id}", self::resource('trips', ['departureTime' => '09:00']))
            ->assertStatus(409)->assertJsonPath('errors.0.code', 'TRIP_NOT_EDITABLE');
        $this->jsonApiAs($chief, 'PATCH', "/api/v1/trips/{$id}", self::resource('trips', ['status' => 'cancelado']))
            ->assertStatus(409)->assertJsonPath('errors.0.code', 'TRIP_TRANSITION_INVALID');
        $this->jsonApiAs($chief, 'DELETE', "/api/v1/trips/{$id}")->assertStatus(409);

        $this->jsonApiAs($chief, 'PATCH', "/api/v1/trips/{$id}", self::resource('trips', ['status' => 'terminado']))
            ->assertOk()->assertJsonPath('data.attributes.finishReason', 'manual');
        // La terminación no se notifica; el comienzo sí.
        $this->assertSame(1, Notification::where('user_id', $worker->user_id)->where('kind', 'viaje_estado')->count());
        $this->jsonApiAs($worker, 'PATCH', "/api/v1/trips/{$id}", self::resource('trips', ['status' => 'planificado']))->assertForbidden();
    }

    public function test_cancelan_el_administrador_o_el_jefe_que_lo_planifico(): void
    {
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);
        $admin = $this->createAdmin();
        $chief = $this->createChief($itinerary);
        $otherChief = $this->createChief($itinerary);
        $byAdmin = $this->plan($admin, $itinerary)->json('data.id');
        $byChief = $this->plan($chief, $itinerary, 'regreso')->json('data.id');

        $this->jsonApiAs($chief, 'PATCH', "/api/v1/trips/{$byAdmin}", self::resource('trips', ['status' => 'cancelado']))->assertForbidden();
        $this->jsonApiAs($otherChief, 'PATCH', "/api/v1/trips/{$byChief}", self::resource('trips', ['status' => 'cancelado']))->assertForbidden();
        $this->jsonApiAs($chief, 'PATCH', "/api/v1/trips/{$byChief}", self::resource('trips', ['status' => 'cancelado']))
            ->assertOk()->assertJsonPath('data.attributes.status', 'cancelado');
        $this->jsonApiAs($admin, 'PATCH', "/api/v1/trips/{$byAdmin}", self::resource('trips', ['status' => 'cancelado']))->assertOk();
    }

    public function test_los_ausentes_no_son_pasajeros_esperados_y_trabajadores_del_viaje(): void
    {
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);
        $admin = $this->createAdmin();
        $a = $this->createWorker($entity, $itinerary, $itinerary->stopIds()[1]);
        $b = $this->createWorker($entity, $itinerary, $itinerary->stopIds()[2]);
        $type = AbsenceType::create(['name' => 'Vacaciones']);

        $this->jsonApiAs($a, 'POST', '/api/v1/absences', self::resource('absences', ['startsOn' => Carbon::today()->toDateString()],
            ['worker' => ['workers', $a->id], 'absenceType' => ['absence-types', $type->id]]))->assertCreated()->assertJsonPath('data.attributes.indefinite', true);
        $this->jsonApiAs($b, 'POST', '/api/v1/absences', self::resource('absences', ['startsOn' => Carbon::today()->toDateString()],
            ['worker' => ['workers', $a->id], 'absenceType' => ['absence-types', $type->id]]))->assertForbidden();
        $this->assertSame(1, Absence::count());

        $id = $this->plan($admin, $itinerary)->assertJsonPath('data.meta.expectedPassengers', 1)->json('data.id');
        $this->jsonApiAs($admin, 'GET', "/api/v1/trips/{$id}/passengers")->assertOk()->assertJsonPath('meta.total', 1)
            ->assertJsonPath('data.0.relationships.user.data.id', (string) $b->user_id);
    }
}
