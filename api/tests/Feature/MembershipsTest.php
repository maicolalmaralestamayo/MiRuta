<?php

use App\Models\Application;
use App\Models\Notice;
use App\Models\User;
use App\Models\Worker;
use App\Models\WorkerRole;
use App\Support\IdentityCard;
use Illuminate\Support\Facades\Hash;
use Laravel\Lumen\Testing\DatabaseMigrations;

/**
 * Personas y Entidades (docs/11 §11.5, §11.6 y §11.13): registro por el
 * Administrador, varias Entidades, bajas directas.
 */
class MembershipsTest extends TestCase
{
    use DatabaseMigrations;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
    }

    private function registerWorker($actor, array $attributes = [], array $relationships = [])
    {
        return $this->jsonApiAs($actor, 'POST', '/api/v1/workers', ['data' => ['type' => 'workers',
            'attributes' => array_merge([
                'firstName' => 'Maicol', 'middleName' => 'Alberto', 'firstSurname' => 'Almarales', 'secondSurname' => 'Tamayo',
                'identityCard' => '90010112361', 'hasPhone' => false,
            ], $attributes),
            'relationships' => array_merge(['entity' => ['data' => ['type' => 'entities', 'id' => (string) $this->defaultEntity()->id]]], $relationships),
        ]]);
    }

    public function testElAdministradorRegistraConUsuarioYContrasenaPropuestos()
    {
        $admin = $this->createAdmin();

        $this->registerWorker($admin);

        $this->assertResponseStatus(201);
        $meta = $this->responseJson()['data']['meta'];
        $this->assertTrue($meta['accountCreated']);
        $this->assertSame('maicol', $meta['username']);
        $this->assertSame([], app(\App\Services\Passwords::class)->problems($meta['password']));
        $user = User::where('username', 'maicol')->first();
        $this->assertTrue(Hash::check($meta['password'], $user->password));
        $this->assertTrue($user->must_change_password);
        $this->assertFalse($user->has_phone);
        $this->assertSame('M', $user->sex);
        $worker = Worker::where('user_id', $user->id)->first();
        $this->assertSame(['Trabajador'], WorkerRole::where('worker_id', $worker->id)->with('role')->get()->pluck('role.name')->all());

        // Al entrar debe cambiar la contraseña.
        $this->jsonApi('POST', '/api/v1/tokens', ['data' => ['type' => 'tokens', 'attributes' => ['username' => 'maicol', 'password' => $meta['password']]]]);
        $this->assertResponseStatus(201);
        $this->jsonApiAs($user, 'GET', '/api/v1/trips');
        $this->assertJsonApiError(403, 'PASSWORD_CHANGE_REQUIRED');
    }

    public function testUsuarioYContrasenaElegidosPorElAdministrador()
    {
        $this->registerWorker($this->createAdmin(), ['username' => 'malmarales', 'password' => 'Clave.Nueva8']);

        $this->assertResponseStatus(201);
        $this->assertSame('malmarales', $this->responseJson()['data']['meta']['username']);
        $this->assertSame('Clave.Nueva8', $this->responseJson()['data']['meta']['password']);
    }

    public function testSiElCarneYaExisteSoloAnadeLaEntidad()
    {
        $admin = $this->createAdmin();
        $person = $this->createWorker(['user' => ['identity_card' => '90010112361']], $this->createEntity('OTRA'));

        $this->registerWorker($admin);

        $this->assertResponseStatus(201);
        $meta = $this->responseJson()['data']['meta'];
        $this->assertFalse($meta['accountCreated']);
        $this->assertNull($meta['username']);
        $this->assertNull($meta['password']);
        $this->assertSame(1, User::where('identity_card_hash', IdentityCard::hash('90010112361'))->count());
        $this->assertSame(['OTRA', 'PRUEBA'], $this->userOf($person)->fresh()->workers()->with('entity')->get()->pluck('entity.abbreviation')->sort()->values()->all());
        // Tiene teléfono: se le avisa.
        $this->assertSame(1, Notice::where('user_id', $person->user_id)->where('type', 'entity_added')->count());

        $this->registerWorker($admin);
        $this->assertJsonApiError(409, 'ALREADY_MEMBER');
    }

    public function testSoloQuienTieneWorkersRegister()
    {
        $this->registerWorker($this->createTransportChief());
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->registerWorker($this->createItineraryChief($this->createItinerary()));
        $this->assertJsonApiError(403, 'FORBIDDEN');
    }

    public function testRegistrarConItinerarioYParada()
    {
        $itinerary = $this->createItinerary();

        $this->registerWorker($this->createAdmin(), [], [
            'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $itinerary->id]],
        ]);
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/relationships/stop/data/id');

        $this->registerWorker($this->createAdmin(), [], [
            'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $itinerary->id]],
            'stop' => ['data' => ['type' => 'stops', 'id' => (string) $itinerary->stops[1]->id]],
        ]);
        $this->assertResponseStatus(201);
        $this->assertSame($itinerary->stops[1]->id, (int) Worker::latest('id')->first()->stop_id);
    }

    public function testElAdministradorEntraEnEntidadesSinSolicitud()
    {
        $admin = $this->createAdmin();

        $this->jsonApiAs($admin, 'POST', '/api/v1/me/entities', ['data' => ['type' => 'workers', 'attributes' => ['entityAbbreviation' => 'prueba']]]);
        $this->assertJsonApiError(422, 'ENTITY_NOT_FOUND');

        $this->defaultEntity();
        $this->jsonApiAs($admin, 'POST', '/api/v1/me/entities', ['data' => ['type' => 'workers', 'attributes' => ['entityAbbreviation' => 'prueba']]]);
        $this->assertResponseStatus(201);
        $this->jsonApiAs($admin, 'GET', '/api/v1/me');
        $this->assertSame('PRUEBA', $this->responseJson()['data']['meta']['memberships'][0]['entity']['abbreviation']);
        $this->assertTrue($this->responseJson()['data']['attributes']['isAdmin']);

        // Los demás lo solicitan.
        $this->jsonApiAs($this->createUser(), 'POST', '/api/v1/me/entities', ['data' => ['type' => 'workers', 'attributes' => ['entityAbbreviation' => 'prueba']]]);
        $this->assertJsonApiError(403, 'FORBIDDEN');
    }

    public function testDarseDeBajaDeUnaEntidad()
    {
        $itinerary = $this->createItinerary();
        $worker = $this->joinItinerary($this->createDriver(), $itinerary);
        $vehicle = $this->createVehicle($worker);
        Application::create(['user_id' => $worker->user_id, 'entity_id' => $worker->entity_id, 'type' => 'role', 'status' => 'pending',
            'role_id' => $this->role('Jefe de Transporte')->id, 'created_by' => $worker->user_id]);

        $this->jsonApiAs($worker, 'DELETE', '/api/v1/me/entities/'.$worker->entity_id);

        $this->assertResponseStatus(204);
        $worker = Worker::withTrashed()->find($worker->id);
        $this->assertTrue($worker->trashed());
        $this->assertNull($worker->itinerary_id);
        $this->assertSame(0, WorkerRole::where('worker_id', $worker->id)->count());
        $this->assertSame('cancelled', Application::first()->status);
        $this->assertNull($vehicle->fresh()->driver_id);

        // Sin Entidad sigue teniendo su cuenta.
        $this->jsonApiAs($worker, 'GET', '/api/v1/me');
        $this->assertResponseOk();
        $this->assertSame([], $this->responseJson()['data']['meta']['memberships']);

        // Para volver lo solicita de nuevo; al aprobarse vuelve sin itinerario y con el rol por defecto.
        $this->jsonApiAs($worker, 'POST', '/api/v1/applications', ['data' => ['type' => 'applications', 'attributes' => ['type' => 'entity_membership'],
            'relationships' => ['entity' => ['data' => ['type' => 'entities', 'id' => (string) $worker->entity_id]]]]]);
        $this->jsonApiAs($this->createAdmin(), 'PATCH', '/api/v1/applications/'.$this->responseJson()['data']['id'], ['data' => ['type' => 'applications',
            'id' => $this->responseJson()['data']['id'], 'attributes' => ['status' => 'approved']]]);
        $this->assertResponseOk();
        $worker = $worker->fresh();
        $this->assertFalse($worker->trashed());
        $this->assertSame(['Trabajador'], WorkerRole::where('worker_id', $worker->id)->with('role')->get()->pluck('role.name')->all());
    }

    public function testDarseDeBajaDelItinerario()
    {
        $itinerary = $this->createItinerary();
        $worker = $this->joinItinerary($this->createWorker(), $itinerary);
        $other = $this->joinItinerary($this->createWorker(), $itinerary);

        $this->jsonApiAs($other, 'DELETE', '/api/v1/workers/'.$worker->id.'/itinerary');
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->jsonApiAs($worker, 'DELETE', '/api/v1/workers/'.$worker->id.'/itinerary');
        $this->assertResponseStatus(204);
        $this->assertNull($worker->fresh()->itinerary_id);
        $this->assertNull($worker->fresh()->stop_id);

        $this->jsonApiAs($worker, 'DELETE', '/api/v1/workers/'.$worker->id.'/itinerary');
        $this->assertJsonApiError(409, 'NO_ITINERARY');
    }

    public function testAsignarItinerarioYParadaDirectamente()
    {
        $itinerary = $this->createItinerary();
        $worker = $this->createWorker();
        $chief = $this->createItineraryChief($itinerary);
        $document = ['data' => ['type' => 'workers', 'id' => (string) $worker->id, 'relationships' => [
            'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $itinerary->id]],
            'stop' => ['data' => ['type' => 'stops', 'id' => (string) $itinerary->stops[2]->id]],
        ]]];

        // El Jefe de itinerario no asigna directamente (solo aprueba solicitudes).
        $this->jsonApiAs($chief, 'PATCH', '/api/v1/workers/'.$worker->id, $document);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->jsonApiAs($this->createAdmin(), 'PATCH', '/api/v1/workers/'.$worker->id, $document);
        $this->assertResponseOk();
        $this->assertSame($itinerary->stops[2]->id, (int) $worker->fresh()->stop_id);
        $this->assertSame(1, Notice::where('user_id', $worker->user_id)->where('type', 'itinerary_assigned')->count());
    }

    public function testDesactivarLaPertenenciaConservaItinerarioYRoles()
    {
        $itinerary = $this->createItinerary();
        $worker = $this->joinItinerary($this->createDriver(), $itinerary);
        $patch = function ($who, bool $active) use ($worker) {
            return $this->jsonApiAs($who, 'PATCH', '/api/v1/workers/'.$worker->id, ['data' => ['type' => 'workers', 'id' => (string) $worker->id, 'attributes' => ['active' => $active]]]);
        };

        $patch($this->createTransportChief(), false);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $admin = $this->createAdmin();
        $patch($admin, false);
        $this->assertResponseOk();
        $this->seeJson(['active' => false]);
        $this->assertFalse(app(\App\Services\Permissions::class)->can($this->userOf($worker), 'tracking.drive', $worker->entity_id));

        $patch($admin, true);
        $this->assertResponseOk();
        $this->assertSame($itinerary->id, (int) $worker->fresh()->itinerary_id);
        $this->assertTrue(app(\App\Services\Permissions::class)->can($this->userOf($worker)->fresh(), 'tracking.drive', $worker->entity_id));
    }

    public function testQuienVeLosTrabajadores()
    {
        $itinerary = $this->createItinerary();
        $member = $this->joinItinerary($this->createWorker(), $itinerary);
        $chief = $this->createItineraryChief($itinerary);
        $outside = $this->createWorker();
        $this->createWorker([], $this->createEntity('OTRA'));

        $this->jsonApiAs($member, 'GET', '/api/v1/workers');
        $this->assertSame([(string) $member->id], array_column($this->responseJson()['data'], 'id'));

        $this->jsonApiAs($chief, 'GET', '/api/v1/workers');
        $this->assertEqualsCanonicalizing([(string) $member->id, (string) $chief->id], array_column($this->responseJson()['data'], 'id'));

        $this->jsonApiAs($this->createTransportChief(), 'GET', '/api/v1/workers');
        $this->assertSame(4, $this->responseJson()['meta']['total']);

        $this->jsonApiAs($this->createAdmin(), 'GET', '/api/v1/workers?filter[search]='.$this->userOf($outside)->identityCard());
        $this->assertSame([(string) $outside->id], array_column($this->responseJson()['data'], 'id'));
    }
}
