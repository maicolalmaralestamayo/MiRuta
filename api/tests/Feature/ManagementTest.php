<?php

namespace Tests\Feature;

use App\Models\Entity;
use App\Models\Itinerary;
use App\Models\ItineraryStop;
use App\Models\Stop;
use App\Models\User;
use App\Models\Worker;
use App\Models\WorkerItinerary;
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

    public function test_al_eliminar_una_entidad_sus_itinerarios_quedan_sin_entidad_y_las_personas_sin_ella(): void
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
        // El itinerario se conserva, suelto (docs/11 §11.58), y sin sus personas.
        $this->assertNull(Itinerary::find($itinerary->id)->entity_id);
        $this->assertSame(0, WorkerItinerary::where('itinerary_id', $itinerary->id)->count());
        $this->assertNotNull(User::find($worker->user_id));
        $this->assertSame([(int) $other->id], Worker::where('user_id', $worker->user_id)->pluck('entity_id')->all());
        $this->assertSame(3, Stop::whereIn('id', $stopIds)->count());
        $this->assertSame([(string) $itinerary->id], collect($this->jsonApiAs($admin, 'GET', '/api/v1/itineraries?filter[entity]=none')->json('data'))->pluck('id')->all());
    }

    public function test_al_eliminar_un_itinerario_sus_personas_salen_de_el_y_las_paradas_quedan_sueltas(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);
        $other = $this->createItinerary($entity);
        $chief = $this->createChief($itinerary, $itinerary->stopIds()[0]);
        $this->placeIn($chief, $other, $other->stopIds()[0]);
        $stopIds = $itinerary->stopIds();

        $this->jsonApiAs($admin, 'DELETE', "/api/v1/itineraries/{$itinerary->id}")->assertNoContent();
        $this->assertNull($this->placement($chief, $itinerary));
        $this->assertNotNull($this->placement($chief, $other), 'Conserva sus otros itinerarios.');
        $this->jsonApiAs($chief, 'GET', '/api/v1/me')->assertJsonPath('data.meta.role', 'trabajador');
        $this->assertSame(3, Stop::whereIn('id', $stopIds)->count());
        $loose = collect($this->jsonApiAs($admin, 'GET', '/api/v1/stops?filter[itinerary]=none')->json('data'))->pluck('id')->all();
        $this->assertEqualsCanonicalizing(array_map('strval', $stopIds), $loose);
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
        $this->assertNull($this->placement($a, $itinerary)->stop_id);
        $this->assertSame([$first, $third], Itinerary::find($itinerary->id)->stopIds());
        $this->assertSame([1, 2], ItineraryStop::where('itinerary_id', $itinerary->id)->orderBy('position')->pluck('position')->all());

        // Quitar la parada de su último itinerario no la elimina: queda suelta.
        $link = ItineraryStop::where('itinerary_id', $itinerary->id)->where('stop_id', $third)->first();
        $this->jsonApiAs($admin, 'DELETE', "/api/v1/itinerary-stops/{$link->id}")->assertNoContent();
        $this->assertNull($this->placement($b, $itinerary)->stop_id);
        $this->assertNotNull(Stop::find($third));
        $this->assertSame(0, ItineraryStop::where('stop_id', $third)->count());
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

    public function test_jefe_de_itinerario_lo_asigna_el_administrador_y_lo_es_de_uno_solo(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);
        $other = $this->createItinerary($entity);
        $worker = $this->createWorker($entity);

        // El Administrador lo pone en el itinerario como Jefe.
        $first = $this->jsonApiAs($admin, 'POST', '/api/v1/worker-itineraries', self::resource('worker-itineraries', ['isChief' => true],
            ['user' => ['users', $worker->user_id], 'itinerary' => ['itineraries', $itinerary->id]]))
            ->assertCreated()->assertJsonPath('data.attributes.isChief', true)->json('data.id');
        $this->jsonApiAs($worker, 'GET', '/api/v1/me')->assertJsonPath('data.meta.role', 'jefe')->assertJsonPath('data.meta.chiefItineraryId', (string) $itinerary->id);
        $this->jsonApiAs($worker, 'PATCH', "/api/v1/worker-itineraries/{$first}", self::resource('worker-itineraries', ['isChief' => false]))->assertForbidden();

        // Otro itinerario en la misma Entidad: se AÑADE; al nombrarlo Jefe de él deja de serlo del primero.
        $second = $this->jsonApiAs($admin, 'POST', '/api/v1/worker-itineraries', self::resource('worker-itineraries', [],
            ['user' => ['users', $worker->user_id], 'itinerary' => ['itineraries', $other->id], 'stop' => ['stops', $other->stopIds()[1]]]))
            ->assertCreated()->assertJsonPath('data.relationships.stop.data.id', (string) $other->stopIds()[1])->json('data.id');
        $this->assertSame(2, WorkerItinerary::where('user_id', $worker->user_id)->count());
        $this->jsonApiAs($admin, 'PATCH', "/api/v1/worker-itineraries/{$second}", self::resource('worker-itineraries', ['isChief' => true]))->assertOk();
        $this->assertFalse(WorkerItinerary::find($first)->is_chief);
        $this->jsonApiAs($worker, 'GET', '/api/v1/me')->assertJsonPath('data.meta.chiefItineraryId', (string) $other->id)
            ->assertJsonCount(1, 'data.meta.memberships')->assertJsonCount(2, 'data.meta.memberships.0.itineraries');

        // Repetir el mismo itinerario: conflicto.
        $this->jsonApiAs($admin, 'POST', '/api/v1/worker-itineraries', self::resource('worker-itineraries', [],
            ['user' => ['users', $worker->user_id], 'itinerary' => ['itineraries', $other->id]]))->assertStatus(409)->assertJsonPath('errors.0.code', 'ALREADY_IN_ITINERARY');

        // Salir del itinerario del que es Jefe quita la jefatura.
        $this->jsonApiAs($worker, 'DELETE', "/api/v1/worker-itineraries/{$second}")->assertNoContent();
        $this->jsonApiAs($worker, 'GET', '/api/v1/me')->assertJsonPath('data.meta.role', 'trabajador');
    }

    public function test_el_administrador_anade_un_itinerario_de_otra_entidad_y_la_persona_entra_en_ella(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity();
        $other = $this->createEntity('OTRA');
        $itinerary = $this->createItinerary($other);
        $worker = $this->createWorker($entity);

        $this->jsonApiAs($admin, 'POST', '/api/v1/worker-itineraries', self::resource('worker-itineraries', [],
            ['user' => ['users', $worker->user_id], 'itinerary' => ['itineraries', $itinerary->id]]))->assertCreated();
        $this->assertEqualsCanonicalizing([(int) $entity->id, (int) $other->id], Worker::where('user_id', $worker->user_id)->pluck('entity_id')->all());

        // Un itinerario sin Entidad no admite personas.
        $loose = Itinerary::create(['name' => 'Suelto']);
        $this->jsonApiAs($admin, 'POST', '/api/v1/worker-itineraries', self::resource('worker-itineraries', [],
            ['user' => ['users', $worker->user_id], 'itinerary' => ['itineraries', $loose->id]]))->assertStatus(409)->assertJsonPath('errors.0.code', 'ITINERARY_WITHOUT_ENTITY');
    }

    public function test_cada_uno_se_cambia_de_parada_y_sale_del_itinerario_pero_no_entra_en_otro(): void
    {
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);
        $other = $this->createItinerary($entity);
        [$first, $second] = $itinerary->stopIds();
        $worker = $this->createWorker($entity, $itinerary, $first);
        $placement = $this->placement($worker, $itinerary);

        $this->jsonApiAs($worker, 'PATCH', "/api/v1/worker-itineraries/{$placement->id}", self::resource('worker-itineraries', [], ['stop' => ['stops', $second]]))
            ->assertOk()->assertJsonPath('data.relationships.stop.data.id', (string) $second);
        $this->jsonApiAs($worker, 'PATCH', "/api/v1/worker-itineraries/{$placement->id}", self::resource('worker-itineraries', [], ['stop' => ['stops', $other->stopIds()[0]]]))
            ->assertStatus(422)->assertJsonPath('errors.0.code', 'STOP_NOT_IN_ITINERARY');
        $this->jsonApiAs($worker, 'PATCH', "/api/v1/worker-itineraries/{$placement->id}", self::resource('worker-itineraries', [], ['stop' => null]))
            ->assertOk()->assertJsonPath('data.relationships.stop.data', null);
        $this->jsonApiAs($worker, 'POST', '/api/v1/worker-itineraries', self::resource('worker-itineraries', [],
            ['user' => ['users', $worker->user_id], 'itinerary' => ['itineraries', $other->id]]))->assertForbidden();
        $this->jsonApiAs($worker, 'DELETE', "/api/v1/worker-itineraries/{$placement->id}")->assertNoContent();
        $this->assertSame(1, Worker::count(), 'Sigue en la Entidad.');

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

        $this->jsonApiAs($chief, 'PATCH', "/api/v1/workers/{$member->id}", self::resource('workers', ['active' => false]))
            ->assertOk()->assertJsonPath('data.attributes.active', false);
        $this->jsonApiAs($chief, 'PATCH', "/api/v1/worker-itineraries/{$this->placement($member, $itinerary)->id}",
            self::resource('worker-itineraries', [], ['stop' => ['stops', $itinerary->stopIds()[2]]]))->assertOk();
        $this->jsonApiAs($chief, 'PATCH', "/api/v1/workers/{$outsider->id}", self::resource('workers', ['active' => false]))->assertForbidden();

        // Pone en su itinerario a personas de su Entidad (sin quitarles el otro), no en otro.
        $add = fn (Worker $w, Itinerary $i) => $this->jsonApiAs($chief, 'POST', '/api/v1/worker-itineraries', self::resource('worker-itineraries', [],
            ['user' => ['users', $w->user_id], 'itinerary' => ['itineraries', $i->id]]));
        $add($outsider, $itinerary)->assertCreated();
        $this->assertNotNull($this->placement($outsider, $other));
        $add($member, $other)->assertForbidden();
        $add($foreign, $itinerary)->assertForbidden();
        $this->jsonApiAs($chief, 'DELETE', "/api/v1/worker-itineraries/{$this->placement($outsider, $other)->id}")->assertForbidden();
        $this->jsonApiAs($chief, 'DELETE', "/api/v1/worker-itineraries/{$this->placement($outsider, $itinerary)->id}")->assertNoContent();
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

    public function test_el_administrador_asocia_otra_entidad_y_elimina_a_la_persona(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity();
        $other = $this->createEntity('OTRA');
        $itinerary = $this->createItinerary($other);
        $worker = $this->createWorker($entity, null, null, null);

        // «Asociar Entidad» con un itinerario de ella: se añade sin quitar la anterior.
        $this->jsonApiAs($admin, 'POST', '/api/v1/workers', self::resource('workers', [],
            ['entity' => ['entities', $other->id], 'user' => ['users', $worker->user_id], 'itinerary' => ['itineraries', $itinerary->id], 'stop' => ['stops', $itinerary->stopIds()[0]]]))
            ->assertCreated()->assertJsonPath('data.meta.itineraries.0.stop.id', (string) $itinerary->stopIds()[0]);
        $this->jsonApiAs($admin, 'GET', "/api/v1/users/{$worker->user_id}")->assertOk()->assertJsonCount(2, 'data.meta.memberships')
            ->assertJsonPath('data.meta.memberships.1.itineraries.0.itinerary.id', (string) $itinerary->id);

        $this->jsonApiAs($admin, 'DELETE', "/api/v1/users/{$worker->user_id}")->assertNoContent();
        $this->assertSame(0, Worker::count());
        $this->assertSame(0, WorkerItinerary::count());
        $this->jsonApiAs($admin, 'DELETE', "/api/v1/users/{$admin->id}")->assertStatus(409);
    }

    public function test_itinerario_sin_entidad_y_cambio_de_entidad_con_sus_personas(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity();
        $other = $this->createEntity('OTRA');

        $id = $this->jsonApiAs($admin, 'POST', '/api/v1/itineraries', self::resource('itineraries', ['name' => 'Suelto'], ['entity' => null]))
            ->assertCreated()->assertJsonPath('data.relationships.entity.data', null)->json('data.id');
        $this->jsonApiAs($admin, 'PATCH', "/api/v1/itineraries/{$id}", self::resource('itineraries', [], ['entity' => ['entities', $entity->id]]))
            ->assertOk()->assertJsonPath('data.relationships.entity.data.id', (string) $entity->id);
        $worker = $this->createWorker($entity, Itinerary::find($id));

        // Pasa a otra Entidad: sus personas pasan con él (entran en la nueva).
        $this->jsonApiAs($admin, 'PATCH', "/api/v1/itineraries/{$id}", self::resource('itineraries', [], ['entity' => ['entities', $other->id]]))->assertOk();
        $placement = $this->placement($worker, (int) $id);
        $this->assertSame((int) $other->id, Worker::find($placement->worker_id)->entity_id);

        // Sin Entidad: salen de él.
        $this->jsonApiAs($admin, 'PATCH', "/api/v1/itineraries/{$id}", self::resource('itineraries', [], ['entity' => null]))->assertOk();
        $this->assertNull($this->placement($worker, (int) $id));

        // Sueltos y gestión.
        $this->jsonApiAs($this->createUser(), 'GET', '/api/v1/itineraries?filter[entity]=none')->assertForbidden();
        $summary = $this->jsonApiAs($admin, 'GET', '/api/v1/management-summary')->assertOk();
        $this->assertSame(1, $summary->json('data.attributes.itineraries'));
        $this->assertSame(2, $summary->json('data.attributes.entities'));
    }

    public function test_listas_de_sueltos_trabajadores_sin_itinerario_y_sin_parada(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);
        $withStop = $this->createWorker($entity, $itinerary, $itinerary->stopIds()[0]);
        $noStop = $this->createWorker($entity, $itinerary);
        $noItinerary = $this->createWorker($entity);

        $ids = fn (string $uri) => collect($this->jsonApiAs($admin, 'GET', $uri)->json('data'))->pluck('id')->all();
        $this->assertSame([(string) $noItinerary->id], $ids('/api/v1/workers?filter[itinerary]=none'));
        $this->assertSame([(string) $this->placement($noStop, $itinerary)->id], $ids('/api/v1/worker-itineraries?filter[stop]=none'));
        $this->assertCount(2, $ids("/api/v1/worker-itineraries?filter[itinerary]={$itinerary->id}"));
        $this->jsonApiAs($admin, 'GET', "/api/v1/worker-itineraries?filter[stop]={$itinerary->stopIds()[0]}")
            ->assertJsonPath('data.0.meta.itineraryName', $itinerary->name)->assertJsonPath('data.0.meta.entityAbbreviation', 'PRUEBA')
            ->assertJsonPath('data.0.relationships.user.data.id', (string) $withStop->user_id);
        $this->assertContains((string) $noItinerary->user_id, $ids('/api/v1/users?filter[itinerary]=none'));
        $this->jsonApiAs($admin, 'GET', "/api/v1/itineraries/{$itinerary->id}")->assertJsonPath('data.meta.workerCount', 2);
    }
}
