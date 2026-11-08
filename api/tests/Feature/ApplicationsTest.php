<?php

namespace Tests\Feature;

use App\Models\Application;
use App\Models\DenialReason;
use App\Models\Notification;
use App\Models\Worker;
use Tests\TestCase;

/**
 * Solicitudes de Entidad y de itinerario (docs/11 §11.23 y §11.26).
 */
class ApplicationsTest extends TestCase
{
    public function test_solicitar_entidad_la_aprueba_el_administrador(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity('UMIM');
        $user = $this->createUser();
        $chief = $this->createChief($this->createItinerary($entity));

        $id = $this->jsonApiAs($user, 'POST', '/api/v1/applications', self::resource('applications', ['type' => 'entidad', 'entityAbbreviation' => 'umim']))
            ->assertCreated()->assertJsonPath('data.attributes.status', 'pendiente')->json('data.id');
        $this->jsonApiAs($user, 'POST', '/api/v1/applications', self::resource('applications', ['type' => 'entidad'], ['entity' => ['entities', $entity->id]]))
            ->assertStatus(409)->assertJsonPath('errors.0.code', 'APPLICATION_PENDING');
        $this->assertSame(1, Notification::where('user_id', $admin->id)->where('kind', 'solicitud_recibida')->count());

        // El Jefe no resuelve solicitudes de Entidad (ni las ve).
        $this->jsonApiAs($chief, 'PATCH', "/api/v1/applications/{$id}", self::resource('applications', ['status' => 'aprobada']))->assertNotFound();

        $this->jsonApiAs($admin, 'PATCH', "/api/v1/applications/{$id}", self::resource('applications', ['status' => 'aprobada']))
            ->assertOk()->assertJsonPath('data.attributes.status', 'aprobada');
        $this->assertTrue(Worker::where('user_id', $user->id)->where('entity_id', $entity->id)->exists());
        $this->assertSame('Solicitud aprobada', Notification::where('user_id', $user->id)->value('title'));
        $this->jsonApiAs($admin, 'PATCH', "/api/v1/applications/{$id}", self::resource('applications', ['status' => 'aprobada']))
            ->assertStatus(409)->assertJsonPath('errors.0.code', 'APPLICATION_NOT_PENDING');

        $this->jsonApiAs($user, 'POST', '/api/v1/applications', self::resource('applications', ['type' => 'entidad', 'entityAbbreviation' => 'UMIM']))
            ->assertStatus(409)->assertJsonPath('errors.0.code', 'ALREADY_MEMBER');
        $this->jsonApiAs($user, 'POST', '/api/v1/applications', self::resource('applications', ['type' => 'entidad', 'entityAbbreviation' => 'NADA']))
            ->assertStatus(422)->assertJsonPath('errors.0.code', 'ENTITY_NOT_FOUND');
    }

    public function test_solicitar_itinerario_lo_resuelve_su_jefe_y_rechazar_exige_motivo(): void
    {
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);
        $other = $this->createItinerary($entity);
        $chief = $this->createChief($itinerary);
        $otherChief = $this->createChief($other);
        $worker = $this->createWorker($entity);
        $stop = $itinerary->stopIds()[1];

        $this->jsonApiAs($this->createUser(), 'POST', '/api/v1/applications', self::resource('applications', ['type' => 'itinerario'], ['itinerary' => ['itineraries', $itinerary->id]]))
            ->assertStatus(409)->assertJsonPath('errors.0.code', 'NOT_MEMBER');

        $id = $this->jsonApiAs($worker, 'POST', '/api/v1/applications', self::resource('applications', ['type' => 'itinerario'],
            ['itinerary' => ['itineraries', $itinerary->id], 'stop' => ['stops', $stop]]))->assertCreated()->json('data.id');
        $this->assertSame(1, Notification::where('user_id', $chief->user_id)->count());
        $this->assertSame(0, Notification::where('user_id', $otherChief->user_id)->count());

        $this->jsonApiAs($otherChief, 'PATCH', "/api/v1/applications/{$id}", self::resource('applications', ['status' => 'aprobada']))->assertNotFound();
        $this->jsonApiAs($chief, 'PATCH', "/api/v1/applications/{$id}", self::resource('applications', ['status' => 'rechazada']))
            ->assertStatus(422)->assertJsonPath('errors.0.code', 'DENIAL_REASON_REQUIRED');

        $entityReason = DenialReason::create(['name' => 'No trabaja aquí', 'application_type' => 'entidad']);
        $reason = DenialReason::create(['name' => 'Sin plaza']);
        $this->jsonApiAs($chief, 'PATCH', "/api/v1/applications/{$id}", self::resource('applications', ['status' => 'rechazada'], ['denialReason' => ['denial-reasons', $entityReason->id]]))
            ->assertStatus(422)->assertJsonPath('errors.0.code', 'DENIAL_REASON_INVALID');
        $this->jsonApiAs($chief, 'PATCH', "/api/v1/applications/{$id}?include=denialReason", self::resource('applications',
            ['status' => 'rechazada', 'resolutionNote' => 'Ya va lleno'], ['denialReason' => ['denial-reasons', $reason->id]]))
            ->assertOk()->assertJsonPath('data.attributes.status', 'rechazada')->assertJsonPath('included.0.attributes.name', 'Sin plaza');

        // El trabajador ve la suya resuelta hasta que abre Solicitudes.
        $this->jsonApiAs($worker, 'GET', '/api/v1/sync')->assertJsonPath('meta.counters.applicationsResolvedUnseen', 1);
        $this->jsonApiAs($worker, 'POST', '/api/v1/me/applications-seen')->assertNoContent();
        $this->jsonApiAs($worker, 'GET', '/api/v1/sync')->assertJsonPath('meta.counters.applicationsResolvedUnseen', 0);

        // Otra vez; ahora se aprueba y queda en el itinerario con su parada.
        $id = $this->jsonApiAs($worker, 'POST', '/api/v1/applications', self::resource('applications', ['type' => 'itinerario'],
            ['itinerary' => ['itineraries', $itinerary->id], 'stop' => ['stops', $stop]]))->json('data.id');
        $this->jsonApiAs($chief, 'GET', '/api/v1/sync')->assertJsonPath('meta.counters.applicationsToResolve', 1);
        $this->jsonApiAs($chief, 'PATCH', "/api/v1/applications/{$id}", self::resource('applications', ['status' => 'aprobada']))->assertOk();
        $worker->refresh();
        $this->assertSame([(int) $itinerary->id, $stop], [$worker->itinerary_id, $worker->stop_id]);
    }

    public function test_cada_uno_ve_las_suyas_y_las_cancela_o_elimina(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity();
        $a = $this->createUser();
        $b = $this->createUser();

        $mine = $this->jsonApiAs($a, 'POST', '/api/v1/applications', self::resource('applications', ['type' => 'entidad'], ['entity' => ['entities', $entity->id]]))->json('data.id');
        $this->jsonApiAs($b, 'POST', '/api/v1/applications', self::resource('applications', ['type' => 'entidad'], ['entity' => ['entities', $entity->id]]));

        $this->jsonApiAs($a, 'GET', '/api/v1/applications')->assertJsonCount(1, 'data');
        $this->jsonApiAs($admin, 'GET', '/api/v1/applications?filter[status]=pendiente')->assertJsonCount(2, 'data');
        $this->jsonApiAs($b, 'DELETE', "/api/v1/applications/{$mine}")->assertNotFound();
        $this->jsonApiAs($admin, 'DELETE', "/api/v1/applications/{$mine}")->assertForbidden();
        $this->jsonApiAs($a, 'DELETE', "/api/v1/applications/{$mine}")->assertNoContent();
        $this->assertSame(1, Application::count());
    }
}
