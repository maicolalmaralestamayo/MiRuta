<?php

namespace Tests\Feature;

use App\Models\Entity;
use App\Models\Itinerary;
use App\Models\ItineraryStop;
use App\Models\Stop;
use App\Models\User;
use App\Models\Worker;
use Tests\TestCase;

/**
 * Gestión: Entidades, itinerarios, paradas y personas (docs/11 §11.22 a §11.30).
 */
class ManagementTest extends TestCase
{
    public function test_solo_el_administrador_crea_edita_y_elimina_entidades(): void
    {
        $admin = $this->createAdmin();
        $worker = $this->createUser();

        $this->jsonApiAs($worker, 'POST', '/api/v1/entities', self::resource('entities', ['abbreviation' => 'umim', 'name' => 'Uno']))->assertForbidden();
        $id = $this->jsonApiAs($admin, 'POST', '/api/v1/entities', self::resource('entities', ['abbreviation' => 'umim', 'name' => 'Empresa UMIM', 'number' => '0001']))
            ->assertCreated()->assertJsonPath('data.attributes.abbreviation', 'UMIM')->assertJsonPath('data.attributes.active', true)->json('data.id');
        $this->jsonApiAs($admin, 'POST', '/api/v1/entities', self::resource('entities', ['abbreviation' => 'UMIM', 'name' => 'Otra']))->assertStatus(422);
        $this->jsonApiAs($admin, 'PATCH', "/api/v1/entities/{$id}", self::resource('entities', ['active' => false]))->assertOk()->assertJsonPath('data.attributes.active', false);

        // El trabajador solo ve sus Entidades activas.
        $this->createWorker(Entity::find($id), null, null, $worker);
        $this->jsonApiAs($worker, 'GET', '/api/v1/entities')->assertOk()->assertJsonCount(0, 'data');
        $this->jsonApiAs($admin, 'GET', '/api/v1/entities')->assertJsonCount(1, 'data');
    }

    public function test_buscar_una_entidad_por_abreviatura_sin_ver_la_lista(): void
    {
        $this->createEntity('DPTRANS');
        $user = $this->createUser();

        $this->jsonApiAs($user, 'GET', '/api/v1/entities/lookup?filter[abbreviation]=dptrans')->assertOk()
            ->assertJsonPath('data.attributes.name', 'Entidad DPTRANS');
        $this->jsonApiAs($user, 'GET', '/api/v1/entities/lookup?filter[abbreviation]=NADA')->assertNotFound();
    }

    public function test_al_eliminar_una_entidad_se_van_sus_itinerarios_y_las_personas_quedan_sin_ella(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity();
        $other = $this->createEntity('OTRA');
        $itinerary = $this->createItinerary($entity);
        $stopIds = $itinerary->stopIds();
        $worker = $this->createWorker($entity, $itinerary, $stopIds[1]);
        $this->createWorker($other, null, null, User::find($worker->user_id));

        $this->jsonApiAs($admin, 'DELETE', "/api/v1/entities/{$entity->id}")->assertNoContent();

        $this->assertNull(Entity::find($entity->id));
        $this->assertNull(Itinerary::find($itinerary->id));
        $this->assertNotNull(User::find($worker->user_id));
        $this->assertSame([(int) $other->id], Worker::where('user_id', $worker->user_id)->pluck('entity_id')->all());
        // Las paradas se conservan (pueden estar en otros itinerarios).
        $this->assertSame(3, Stop::whereIn('id', $stopIds)->count());
    }

    public function test_al_eliminar_un_itinerario_sus_personas_quedan_sin_itinerario_parada_ni_jefatura(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);
        $chief = $this->createChief($itinerary, $itinerary->stopIds()[0]);

        $this->jsonApiAs($admin, 'DELETE', "/api/v1/itineraries/{$itinerary->id}")->assertNoContent();
        $chief->refresh();
        $this->assertNull($chief->itinerary_id);
        $this->assertNull($chief->stop_id);
        $this->assertFalse($chief->is_chief);
    }

    public function test_al_eliminar_una_parada_o_quitarla_del_itinerario_quedan_sin_parada(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity, 3);
        [$first, $second, $third] = $itinerary->stopIds();
        $a = $this->createWorker($entity, $itinerary, $second);
        $b = $this->createWorker($entity, $itinerary, $third);

        $this->jsonApiAs($admin, 'DELETE', "/api/v1/stops/{$second}")->assertNoContent();
        $this->assertNull($a->fresh()->stop_id);
        $this->assertSame((int) $itinerary->id, $a->fresh()->itinerary_id);
        $this->assertSame([$first, $third], Itinerary::find($itinerary->id)->stopIds());
        $this->assertSame([1, 2], ItineraryStop::where('itinerary_id', $itinerary->id)->orderBy('position')->pluck('position')->all());

        $link = ItineraryStop::where('itinerary_id', $itinerary->id)->where('stop_id', $third)->first();
        $this->jsonApiAs($admin, 'DELETE', "/api/v1/itinerary-stops/{$link->id}")->assertNoContent();
        $this->assertNull($b->fresh()->stop_id);
        $this->assertNotNull(Stop::find($third));
    }

    public function test_itinerarios_paradas_compartidas_y_orden(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity();
        $other = $this->createEntity('OTRA');

        $itineraryId = $this->jsonApiAs($admin, 'POST', '/api/v1/itineraries', self::resource('itineraries', ['name' => 'Ruta 1'], ['entity' => ['entities', $entity->id]]))
            ->assertCreated()->json('data.id');
        $this->jsonApiAs($admin, 'POST', '/api/v1/itineraries', self::resource('itineraries', ['name' => 'Ruta 1'], ['entity' => ['entities', $entity->id]]))
            ->assertStatus(409)->assertJsonPath('errors.0.code', 'ITINERARY_NAME_TAKEN');
        $otherItineraryId = $this->jsonApiAs($admin, 'POST', '/api/v1/itineraries', self::resource('itineraries', ['name' => 'Ruta 1'], ['entity' => ['entities', $other->id]]))
            ->assertCreated()->json('data.id');

        $stop = fn (string $name) => self::resource('stops', ['landmark' => $name, 'street' => 'Calle 23', 'latitude' => 23.13, 'longitude' => -82.38], ['itinerary' => ['itineraries', $itineraryId]]);
        $a = $this->jsonApiAs($admin, 'POST', '/api/v1/stops', $stop('Parqueo'))->assertCreated()->json('data.id');
        $b = $this->jsonApiAs($admin, 'POST', '/api/v1/stops', $stop('Coppelia'))->assertCreated()->json('data.id');
        $c = $this->jsonApiAs($admin, 'POST', '/api/v1/stops', $stop('Capitolio'))->assertCreated()->json('data.id');

        // La misma parada en un itinerario de otra Entidad.
        $this->jsonApiAs($admin, 'POST', '/api/v1/itinerary-stops', self::resource('itinerary-stops', [], ['itinerary' => ['itineraries', $otherItineraryId], 'stop' => ['stops', $b]]))
            ->assertCreated()->assertJsonPath('data.attributes.position', 1);
        $this->jsonApiAs($admin, 'GET', "/api/v1/stops/{$b}")->assertJsonCount(2, 'data.meta.itineraries');

        $ids = fn () => collect($this->jsonApiAs($admin, 'GET', "/api/v1/stops?filter[itinerary]={$itineraryId}")->json('data'))->pluck('id')->all();
        $this->assertSame([$a, $b, $c], $ids());

        $this->jsonApiAs($admin, 'PATCH', "/api/v1/itineraries/{$itineraryId}/relationships/stops", ['data' => [
            ['type' => 'stops', 'id' => $c], ['type' => 'stops', 'id' => $a], ['type' => 'stops', 'id' => $b],
        ]])->assertOk();
        $this->assertSame([$c, $a, $b], $ids());

        $this->jsonApiAs($admin, 'PATCH', "/api/v1/itineraries/{$itineraryId}/relationships/stops", ['data' => [['type' => 'stops', 'id' => $c]]])
            ->assertStatus(422)->assertJsonPath('errors.0.code', 'STOP_ORDER_INVALID');

        $link = ItineraryStop::where('itinerary_id', $itineraryId)->where('stop_id', $b)->first();
        $this->jsonApiAs($admin, 'PATCH', "/api/v1/itinerary-stops/{$link->id}", self::resource('itinerary-stops', ['position' => 1]))->assertOk();
        $this->assertSame([$b, $c, $a], $ids());

        // Paradas sin itinerario.
        $loose = $this->createStop('Suelta');
        $this->assertSame([(string) $loose->id], collect($this->jsonApiAs($admin, 'GET', '/api/v1/stops?filter[itinerary]=none')->json('data'))->pluck('id')->all());
    }

    public function test_el_jefe_gestiona_las_paradas_de_su_itinerario_pero_no_elimina_las_compartidas(): void
    {
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity, 2);
        $other = $this->createItinerary($entity, 0);
        $chief = $this->createChief($itinerary);
        [$first, $second] = $itinerary->stopIds();
        ItineraryStop::create(['itinerary_id' => $other->id, 'stop_id' => $second, 'position' => 1]);

        // Crea en su itinerario, no en otro.
        $document = fn ($itineraryId) => self::resource('stops', ['landmark' => 'Nueva', 'street' => 'Calle', 'latitude' => 23, 'longitude' => -82], ['itinerary' => ['itineraries', $itineraryId]]);
        $this->jsonApiAs($chief, 'POST', '/api/v1/stops', $document($other->id))->assertForbidden();
        $new = $this->jsonApiAs($chief, 'POST', '/api/v1/stops', $document($itinerary->id))->assertCreated()->json('data.id');

        // Edita las de su itinerario (aunque las usen otros).
        $this->jsonApiAs($chief, 'PATCH', "/api/v1/stops/{$second}", self::resource('stops', ['landmark' => 'Coppelia']))->assertOk();
        $this->jsonApiAs($chief, 'DELETE', "/api/v1/stops/{$second}")->assertStatus(409)->assertJsonPath('errors.0.code', 'STOP_SHARED');
        $this->jsonApiAs($chief, 'DELETE', "/api/v1/stops/{$new}")->assertNoContent();

        // Ordena las de su itinerario, no las de otro; no crea itinerarios.
        $this->jsonApiAs($chief, 'PATCH', "/api/v1/itineraries/{$itinerary->id}/relationships/stops", ['data' => [['type' => 'stops', 'id' => $second], ['type' => 'stops', 'id' => $first]]])->assertOk();
        $this->jsonApiAs($chief, 'PATCH', "/api/v1/itineraries/{$other->id}/relationships/stops", ['data' => [['type' => 'stops', 'id' => $second]]])->assertForbidden();
        $this->jsonApiAs($chief, 'POST', '/api/v1/itineraries', self::resource('itineraries', ['name' => 'X'], ['entity' => ['entities', $entity->id]]))->assertForbidden();

        // El trabajador no gestiona paradas.
        $worker = $this->createWorker($entity, $itinerary, $first);
        $this->jsonApiAs($worker, 'PATCH', "/api/v1/stops/{$first}", self::resource('stops', ['landmark' => 'X']))->assertForbidden();
    }

    public function test_el_administrador_registra_personas_y_si_el_carne_existe_le_anade_la_entidad(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity();
        $other = $this->createEntity('OTRA');
        $card = $this->newIdentityCard();

        $response = $this->jsonApiAs($admin, 'POST', '/api/v1/workers', self::resource('workers', [
            'firstName' => 'Ana', 'firstSurname' => 'Pérez', 'secondSurname' => 'Gil', 'identityCard' => $card,
        ], ['entity' => ['entities', $entity->id]]))->assertCreated()->assertJsonPath('meta.created', true);
        $this->assertSame('ana', $response->json('meta.username'));
        $this->assertNotEmpty($response->json('meta.password'));
        $this->assertTrue(User::where('username', 'ana')->first()->must_change_password);

        $this->jsonApiAs($admin, 'POST', '/api/v1/workers', self::resource('workers', [
            'firstName' => 'Ana', 'firstSurname' => 'Pérez', 'secondSurname' => 'Gil', 'identityCard' => $card,
        ], ['entity' => ['entities', $other->id]]))->assertCreated()->assertJsonPath('meta.created', false);
        $this->assertSame(1, User::count() - 1);
        $this->assertSame(2, Worker::count());

        // El Administrador entra en una Entidad sin solicitud.
        $this->jsonApiAs($admin, 'POST', '/api/v1/workers', self::resource('workers', [], ['entity' => ['entities', $entity->id], 'user' => ['users', $admin->id]]))->assertCreated();
        $this->jsonApiAs($this->createUser(), 'POST', '/api/v1/workers', self::resource('workers', [], ['entity' => ['entities', $entity->id]]))->assertForbidden();
    }

    public function test_jefe_de_itinerario_lo_asigna_el_administrador_y_lo_pierde_al_cambiar_de_itinerario(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);
        $other = $this->createItinerary($entity);
        $worker = $this->createWorker($entity);

        $this->jsonApiAs($worker, 'PATCH', "/api/v1/workers/{$worker->id}", self::resource('workers', ['isChief' => true]))->assertForbidden();

        // Al nombrarlo Jefe se le pone en ese itinerario.
        $this->jsonApiAs($admin, 'PATCH', "/api/v1/workers/{$worker->id}", self::resource('workers', ['isChief' => true], ['itinerary' => ['itineraries', $itinerary->id]]))
            ->assertOk()->assertJsonPath('data.attributes.isChief', true)->assertJsonPath('data.relationships.itinerary.data.id', (string) $itinerary->id);
        $this->jsonApiAs($worker, 'GET', '/api/v1/me')->assertJsonPath('data.meta.role', 'jefe')->assertJsonPath('data.meta.chiefItineraryId', (string) $itinerary->id);

        // Si se le cambia de itinerario, deja de ser Jefe.
        $this->jsonApiAs($admin, 'PATCH', "/api/v1/workers/{$worker->id}", self::resource('workers', [], ['itinerary' => ['itineraries', $other->id]]))
            ->assertOk()->assertJsonPath('data.attributes.isChief', false);
    }

    public function test_cada_uno_se_cambia_de_parada_y_sale_del_itinerario_pero_no_entra_en_otro(): void
    {
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);
        $other = $this->createItinerary($entity);
        [$first, $second] = $itinerary->stopIds();
        $worker = $this->createWorker($entity, $itinerary, $first);

        $this->jsonApiAs($worker, 'PATCH', "/api/v1/workers/{$worker->id}", self::resource('workers', [], ['stop' => ['stops', $second]]))
            ->assertOk()->assertJsonPath("data.relationships.stop.data.id", (string) $second);
        $this->jsonApiAs($worker, 'PATCH', "/api/v1/workers/{$worker->id}", self::resource('workers', [], ['stop' => ['stops', $other->stopIds()[0]]]))
            ->assertStatus(422)->assertJsonPath('errors.0.code', 'STOP_NOT_IN_ITINERARY');
        $this->jsonApiAs($worker, 'PATCH', "/api/v1/workers/{$worker->id}", self::resource('workers', [], ['itinerary' => ['itineraries', $other->id]]))
            ->assertForbidden();
        $this->jsonApiAs($worker, 'PATCH', "/api/v1/workers/{$worker->id}", self::resource('workers', [], ['itinerary' => null]))
            ->assertOk()->assertJsonPath('data.relationships.itinerary.data', null)->assertJsonPath('data.relationships.stop.data', null);

        // Salir de la Entidad.
        $this->jsonApiAs($worker, 'DELETE', "/api/v1/workers/{$worker->id}")->assertNoContent();
        $this->assertSame(0, Worker::count());
    }

    public function test_el_jefe_mueve_personas_de_su_entidad_dentro_de_su_itinerario(): void
    {
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);
        $other = $this->createItinerary($entity);
        $chief = $this->createChief($itinerary);
        $member = $this->createWorker($entity, $itinerary, $itinerary->stopIds()[0]);
        $outsider = $this->createWorker($entity, $other, $other->stopIds()[0]);
        $foreign = $this->createWorker($this->createEntity('OTRA'));

        $this->jsonApiAs($chief, 'PATCH', "/api/v1/workers/{$member->id}", self::resource('workers', ['active' => false], ['stop' => ['stops', $itinerary->stopIds()[2]]]))
            ->assertOk()->assertJsonPath('data.attributes.active', false);
        $this->jsonApiAs($chief, 'PATCH', "/api/v1/workers/{$outsider->id}", self::resource('workers', [], ['itinerary' => ['itineraries', $itinerary->id]]))->assertOk();
        $this->jsonApiAs($chief, 'PATCH', "/api/v1/workers/{$outsider->id}", self::resource('workers', [], ['itinerary' => ['itineraries', $other->id]]))->assertForbidden();
        $this->jsonApiAs($chief, 'PATCH', "/api/v1/workers/{$foreign->id}", self::resource('workers', [], ['itinerary' => ['itineraries', $itinerary->id]]))->assertNotFound();
    }

    public function test_quien_ve_que_personas_y_quien_ve_el_carne(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);
        $chief = $this->createChief($itinerary);
        $member = $this->createWorker($entity, $itinerary, $itinerary->stopIds()[0]);
        $colleague = $this->createWorker($entity);
        $inactive = $this->createWorker($entity, null, null, null, ['active' => false]);
        $foreign = $this->createWorker($this->createEntity('OTRA'));
        $loner = $this->createUser();

        $this->assertCount(3, $this->jsonApiAs($colleague, "GET", "/api/v1/workers?filter[entity]={$entity->id}")->json("data"));
        $this->assertCount(4, $this->jsonApiAs($admin, "GET", "/api/v1/workers?filter[entity]={$entity->id}")->json("data"));
        $this->jsonApiAs($colleague, 'GET', "/api/v1/users/{$foreign->user_id}")->assertNotFound();
        $this->assertArrayNotHasKey('identityCard', $this->jsonApiAs($colleague, 'GET', "/api/v1/users/{$member->user_id}")->json('data.attributes'));
        $this->assertArrayHasKey('identityCard', $this->jsonApiAs($chief, 'GET', "/api/v1/users/{$member->user_id}")->json('data.attributes'));
        $this->assertArrayNotHasKey('identityCard', $this->jsonApiAs($chief, 'GET', "/api/v1/users/{$colleague->user_id}")->json('data.attributes'));
        $this->assertArrayHasKey('identityCard', $this->jsonApiAs($admin, 'GET', "/api/v1/users/{$colleague->user_id}")->json('data.attributes'));

        // «Sin Entidad», solo el Administrador.
        $this->jsonApiAs($colleague, 'GET', '/api/v1/users?filter[entity]=none')->assertForbidden();
        $ids = collect($this->jsonApiAs($admin, 'GET', '/api/v1/users?filter[entity]=none')->json('data'))->pluck('id')->all();
        $this->assertContains((string) $loner->id, $ids);
        $this->assertContains((string) $admin->id, $ids);

        // Búsqueda por nombre, usuario o carné; filtros «Sin itinerario».
        $this->assertCount(1, $this->jsonApiAs($admin, 'GET', '/api/v1/workers?filter[search]='.User::find($member->user_id)->identityCard())->json('data'));
        $this->assertCount(2, $this->jsonApiAs($admin, 'GET', "/api/v1/workers?filter[entity]={$entity->id}&filter[itinerary]=none")->json('data'));
        $this->assertSame((string) $member->user_id, $this->jsonApiAs($admin, 'GET', "/api/v1/workers?filter[itinerary]={$itinerary->id}&filter[stop]={$itinerary->stopIds()[0]}&include=user")->json('included.0.id'));
    }

    public function test_el_administrador_cambia_a_una_persona_de_entidad_y_la_elimina(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity();
        $other = $this->createEntity('OTRA');
        $itinerary = $this->createItinerary($entity);
        $worker = $this->createWorker($entity, $itinerary, $itinerary->stopIds()[0], null, ['is_chief' => true]);

        $this->jsonApiAs($admin, 'PATCH', "/api/v1/workers/{$worker->id}", self::resource('workers', [], ['entity' => ['entities', $other->id]]))
            ->assertOk()->assertJsonPath('data.relationships.entity.data.id', (string) $other->id)
            ->assertJsonPath('data.relationships.itinerary.data', null)->assertJsonPath('data.attributes.isChief', false);

        $this->jsonApiAs($admin, 'DELETE', "/api/v1/users/{$worker->user_id}")->assertNoContent();
        $this->assertSame(0, Worker::count());
        $this->jsonApiAs($admin, 'DELETE', "/api/v1/users/{$admin->id}")->assertStatus(409);
    }
}
