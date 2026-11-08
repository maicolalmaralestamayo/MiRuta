<?php

namespace Tests\Feature;

use App\Models\AbsenceType;
use App\Models\Trip;
use Carbon\Carbon;
use Tests\TestCase;

class NomenclatorsTest extends TestCase
{
    public function test_el_administrador_gestiona_y_el_tipo_de_vehiculo_calcula_el_total(): void
    {
        $admin = $this->createAdmin();

        $id = $this->jsonApiAs($admin, 'POST', '/api/v1/vehicle-types', self::resource('vehicle-types', ['name' => 'Ómnibus', 'seats' => 45, 'standing' => 15]))
            ->assertCreated()->assertJsonPath('data.attributes.total', 60)->assertJsonPath('data.meta.usageCount', 0)->json('data.id');

        $this->jsonApiAs($admin, 'PATCH', "/api/v1/vehicle-types/{$id}", self::resource('vehicle-types', ['standing' => 5]))
            ->assertOk()->assertJsonPath('data.attributes.total', 50);
        $this->jsonApiAs($admin, 'POST', '/api/v1/vehicle-types', self::resource('vehicle-types', ['name' => 'Ómnibus', 'seats' => 1]))
            ->assertStatus(422);

        foreach (['absence-types', 'conversation-topics', 'detention-causes'] as $type) {
            $this->jsonApiAs($admin, 'POST', "/api/v1/{$type}", self::resource($type, ['name' => 'Uno', 'description' => 'Algo']))->assertCreated();
        }

        $this->jsonApiAs($admin, 'POST', '/api/v1/denial-reasons', self::resource('denial-reasons', ['name' => 'Sin plaza', 'applicationType' => 'itinerario']))
            ->assertCreated()->assertJsonPath('data.attributes.applicationType', 'itinerario');
    }

    public function test_los_demas_solo_consultan_los_activos(): void
    {
        $worker = $this->createUser();
        AbsenceType::create(['name' => 'Vacaciones']);
        AbsenceType::create(['name' => 'Vieja', 'active' => false]);

        $this->jsonApiAs($worker, 'POST', '/api/v1/absence-types', self::resource('absence-types', ['name' => 'Otra']))->assertForbidden();
        $this->jsonApiAs($worker, 'GET', '/api/v1/absence-types')->assertOk()->assertJsonCount(1, 'data');
        $this->jsonApiAs($this->createAdmin(), 'GET', '/api/v1/absence-types')->assertJsonCount(2, 'data');
    }

    public function test_lo_que_esta_en_uso_no_se_elimina_y_se_propone_desactivarlo(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);
        $type = $this->vehicleType();
        Trip::create(['itinerary_id' => $itinerary->id, 'direction' => 'ida', 'date' => Carbon::tomorrow(), 'departure_time' => '07:00',
            'departs_at' => Carbon::tomorrow()->setTime(7, 0), 'vehicle_type_id' => $type->id, 'status' => 'planificado', 'status_changed_at' => Carbon::now()]);

        $this->jsonApiAs($admin, 'GET', "/api/v1/vehicle-types/{$type->id}")->assertJsonPath('data.meta.usageCount', 1);
        $this->jsonApiAs($admin, 'DELETE', "/api/v1/vehicle-types/{$type->id}")
            ->assertStatus(409)->assertJsonPath('errors.0.code', 'NOMENCLATOR_IN_USE')->assertJsonPath('errors.0.meta.usageCount', 1);

        $this->jsonApiAs($admin, 'PATCH', "/api/v1/vehicle-types/{$type->id}", self::resource('vehicle-types', ['active' => false]))
            ->assertOk()->assertJsonPath('data.attributes.active', false);

        $unused = AbsenceType::create(['name' => 'Libre']);
        $this->jsonApiAs($admin, 'DELETE', "/api/v1/absence-types/{$unused->id}")->assertNoContent();
    }
}
