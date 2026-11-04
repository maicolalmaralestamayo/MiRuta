<?php

use App\Models\Child;
use App\Models\ChildParent;
use App\Support\IdentityCard;
use Carbon\Carbon;
use Carbon\CarbonImmutable;
use Illuminate\Http\UploadedFile;
use Laravel\Lumen\Testing\DatabaseMigrations;

/**
 * Hijos sin solicitudes, con carné y de varios padres (docs/11 §11.11).
 */
class ChildrenTest extends TestCase
{
    use DatabaseMigrations;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
        Carbon::setTestNow(Carbon::create(2026, 11, 2, 10));
        CarbonImmutable::setTestNow(CarbonImmutable::create(2026, 11, 2, 10));
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }

    private function addChild($parent, string $card, array $attributes = [], array $relationships = [])
    {
        $data = ['type' => 'children', 'attributes' => array_merge([
            'firstName' => 'Pepito', 'firstSurname' => 'Pérez', 'secondSurname' => 'García', 'identityCard' => $card,
        ], $attributes)];

        if ($relationships) {
            $data['relationships'] = $relationships;
        }

        return $this->jsonApiAs($parent, 'POST', '/api/v1/children', ['data' => $data]);
    }

    public function testAnadirUnHijoPorSuCarne()
    {
        $mother = $this->createWorker();
        $card = IdentityCard::make('2018-05-10', 'F', 1);

        $this->addChild($mother, $card);

        $this->assertResponseStatus(201);
        $this->seeJson(['fullName' => 'Pepito Pérez García', 'sex' => 'F', 'birthDate' => '2018-05-10', 'identityCard' => $card,
            'eligibleUntil' => '2034-08-31', 'eligible' => true, 'active' => true, 'alreadyDeclared' => false]);
        $child = Child::first();
        $this->assertSame([(int) $mother->user_id], $child->parentIds());
        $this->assertNotSame($card, $child->identity_card_encrypted);
    }

    public function testElMismoNinoLoDeclaranLosDosPadres()
    {
        $mother = $this->createWorker();
        $father = $this->createUser(); // sin Entidad
        $card = IdentityCard::make('2018-05-10', 'M', 2);

        $this->addChild($mother, $card);
        $this->addChild($father, $card, ['firstName' => 'Otro nombre']);

        $this->assertResponseStatus(201);
        $this->seeJson(['alreadyDeclared' => true]);
        $this->assertStringContainsString('ya está declarado', $this->responseJson()['meta']['notice']);
        $this->assertSame(1, Child::count());
        // Se vincula, sin cambiar sus datos.
        $this->assertSame('Pepito', Child::first()->first_name);
        $this->assertSame(2, ChildParent::count());

        // El formulario muestra quién más lo tiene declarado.
        $this->jsonApiAs($father, 'GET', '/api/v1/children/'.Child::first()->id);
        $this->assertSame(2, count($this->responseJson()['data']['meta']['parents']));

        // Si ya lo tiene declarado, no se repite.
        $this->addChild($father, $card);
        $this->assertJsonApiError(409, 'CHILD_ALREADY_DECLARED');
    }

    public function testSinDerechoNoSeDejaAnadir()
    {
        $parent = $this->createWorker();

        // Cumplió 16 en 2025: tuvo derecho hasta el 31/08/25.
        $this->addChild($parent, IdentityCard::make('2009-03-10', 'F', 3));

        $this->assertJsonApiError(422, 'CHILD_NOT_ELIGIBLE', '/data/attributes/identityCard');
        $this->assertStringContainsString('31/08/25', $this->responseJson()['errors'][0]['detail']);

        $this->addChild($parent, '1234');
        $this->assertJsonApiError(422, 'IDENTITY_CARD_INVALID');
    }

    public function testDesactivarReactivarYEditar()
    {
        $parent = $this->createWorker();
        $this->addChild($parent, IdentityCard::make('2018-05-10', 'F', 4));
        $id = $this->responseJson()['data']['id'];
        $patch = function ($who, array $attributes) use ($id) {
            return $this->jsonApiAs($who, 'PATCH', '/api/v1/children/'.$id, ['data' => ['type' => 'children', 'id' => $id, 'attributes' => $attributes]]);
        };

        $patch($parent, ['active' => false]);
        $this->assertResponseOk();
        $this->seeJson(['active' => false]);

        $patch($parent, ['active' => true, 'middleName' => 'José']);
        $this->assertResponseOk();
        $this->seeJson(['active' => true, 'fullName' => 'Pepito José Pérez García']);

        // Corregir el carné cambia el sexo y la fecha de nacimiento.
        $patch($parent, ['identityCard' => IdentityCard::make('2019-01-02', 'M', 5)]);
        $this->assertResponseOk();
        $this->seeJson(['sex' => 'M', 'birthDate' => '2019-01-02']);

        // Otra persona no puede.
        $patch($this->createWorker(), ['active' => false]);
        $this->assertJsonApiError(404, 'NOT_FOUND');

        // El Administrador sí (children.manage «all»).
        $patch($this->createAdmin(), ['active' => false]);
        $this->assertResponseOk();
    }

    public function testEliminarEsDesvincularYSinPadresSeBorra()
    {
        $mother = $this->createWorker();
        $father = $this->createWorker();
        $card = IdentityCard::make('2018-05-10', 'F', 6);
        $this->addChild($mother, $card);
        $id = $this->responseJson()['data']['id'];
        $this->addChild($father, $card);

        $this->jsonApiAs($mother, 'DELETE', '/api/v1/children/'.$id);
        $this->assertResponseStatus(204);
        $this->assertSame([(int) $father->user_id], Child::find($id)->parentIds());

        $this->jsonApiAs($mother, 'GET', '/api/v1/children?filter[parent]='.$mother->user_id);
        $this->assertSame(0, $this->responseJson()['meta']['total']);

        $this->jsonApiAs($father, 'DELETE', '/api/v1/children/'.$id);
        $this->assertResponseStatus(204);
        $this->assertTrue(Child::withTrashed()->find($id)->trashed());

        // Volver a añadirlo lo restaura.
        $this->addChild($mother, $card);
        $this->assertResponseStatus(201);
        $this->assertSame((string) $id, $this->responseJson()['data']['id']);
        $this->seeJson(['alreadyDeclared' => false]);
    }

    public function testQuienVeLosHijos()
    {
        $itinerary = $this->createItinerary();
        $parent = $this->joinItinerary($this->createWorker(), $itinerary);
        $this->addChild($parent, IdentityCard::make('2018-05-10', 'F', 7));
        $stranger = $this->createWorker();
        $admin = $this->createAdmin();

        $this->jsonApiAs($parent, 'GET', '/api/v1/children');
        $this->assertSame(1, $this->responseJson()['meta']['total']);
        $this->jsonApiAs($stranger, 'GET', '/api/v1/children');
        $this->assertSame(0, $this->responseJson()['meta']['total']);
        $this->jsonApiAs($admin, 'GET', '/api/v1/children');
        $this->assertSame(1, $this->responseJson()['meta']['total']);

        // Con children.view en su itinerario, sin ver el carné.
        $role = \App\Models\Role::create(['name' => 'Consultor de hijos']);
        $role->permissions()->create(['operation' => 'children.view', 'scope' => 'itinerary']);
        $viewer = $this->joinItinerary($this->createWorker(), $itinerary);
        $this->assignRole($viewer, 'Consultor de hijos');
        $this->jsonApiAs($viewer, 'GET', '/api/v1/children');
        $this->assertSame(1, $this->responseJson()['meta']['total']);
        $this->assertArrayNotHasKey('identityCard', $this->responseJson()['data'][0]['attributes']);
    }

    public function testElAdministradorAnadeHijosAOtraPersona()
    {
        $parent = $this->createWorker();

        $this->addChild($this->createWorker(), IdentityCard::make('2018-05-10', 'F', 8), [], ['parent' => ['data' => ['type' => 'users', 'id' => (string) $parent->user_id]]]);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->addChild($this->createAdmin(), IdentityCard::make('2018-05-10', 'F', 8), [], ['parent' => ['data' => ['type' => 'users', 'id' => (string) $parent->user_id]]]);
        $this->assertResponseStatus(201);
        $this->assertSame([(int) $parent->user_id], Child::first()->parentIds());
    }

    public function testFotoDelHijo()
    {
        $parent = $this->createWorker();
        $this->addChild($parent, IdentityCard::make('2018-05-10', 'F', 9));
        $id = $this->responseJson()['data']['id'];
        $path = tempnam(sys_get_temp_dir(), 'foto');
        file_put_contents($path, base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));

        $this->call('POST', '/api/v1/children/'.$id.'/photo', [], [], ['photo' => new UploadedFile($path, 'foto.png', 'image/png', null, true)], [
            'HTTP_AUTHORIZATION' => 'Bearer '.$this->accessTokenFor($parent),
            'HTTP_ACCEPT' => 'application/vnd.api+json',
            'CONTENT_TYPE' => 'multipart/form-data; boundary=x',
        ]);

        $this->assertResponseOk();
        $photo = Child::find($id)->photo_path;
        $this->assertStringStartsWith('uploads/children/', $photo);
        $this->assertSame(url($photo), $this->responseJson()['data']['attributes']['photoUrl']);

        $this->jsonApiAs($parent, 'DELETE', '/api/v1/children/'.$id.'/photo');
        $this->assertResponseStatus(204);
        $this->assertNull(Child::find($id)->photo_path);
        $this->assertFileNotExists(base_path('public/'.$photo));
    }
}
