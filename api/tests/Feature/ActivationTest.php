<?php

use App\Models\Application;
use App\Models\Rank;
use App\Models\User;
use App\Models\Worker;
use Carbon\Carbon;
use Laravel\Lumen\Testing\DatabaseMigrations;

/**
 * Trabajadores sin teléfono: los registra un superior y activan su cuenta
 * con un código (docs/08-version-2.md §8.3).
 */
class ActivationTest extends TestCase
{
    use DatabaseMigrations;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function registerWorker($superior, array $attributes = [], array $relationships = [])
    {
        return $this->jsonApiAs($superior, 'POST', '/api/v1/workers', ['data' => [
            'type' => 'workers',
            'attributes' => array_merge([
                'firstName' => 'Pedro', 'middleName' => 'Luis', 'firstSurname' => 'Gómez', 'secondSurname' => 'Ruiz',
                'pass' => 900, 'sex' => 'M',
            ], $attributes),
            'relationships' => array_merge(['rank' => ['data' => ['type' => 'ranks', 'id' => (string) Rank::first()->id]]], $relationships),
        ]]);
    }

    private function activate(string $code, array $attributes = [])
    {
        return $this->jsonApi('POST', '/api/v1/activations', ['data' => ['type' => 'activations', 'attributes' => array_merge([
            'entityAbbreviation' => 'prueba', 'pass' => 900, 'code' => $code,
            'username' => 'pedro.gomez', 'password' => 'Clave.Segura7',
        ], $attributes)]]);
    }

    public function testElJefeDeTransporteRegistraYElTrabajadorActiva()
    {
        $chief = $this->createTransportChief();

        $this->registerWorker($chief);

        $this->assertResponseStatus(201);
        $json = $this->responseJson();
        $code = $json['data']['meta']['activationCode'];
        $this->assertRegExp('/^[A-Z2-9]{4}-[A-Z2-9]{4}$/', $code);
        $this->assertNotNull($json['data']['meta']['activationExpiresAt']);
        $this->assertSame(900, $json['data']['attributes']['pass']);
        $this->assertFalse($json['data']['attributes']['activated']);
        $worker = Worker::where('pass', 900)->first();
        $this->assertNull($worker->user->username);

        $this->activate(strtolower(str_replace('-', '', $code)));

        $this->assertResponseStatus(201);
        $this->assertArrayHasKey('accessToken', $this->responseJson()['data']['attributes']);
        $user = $worker->user->fresh();
        $this->assertSame('pedro.gomez', $user->username);
        $this->assertTrue($user->isActivated());

        // El código sirve una sola vez.
        $this->activate($code, ['username' => 'otro.nombre']);
        $this->assertJsonApiError(422, 'ACTIVATION_INVALID');

        // Ya puede entrar normalmente.
        $this->jsonApi('POST', '/api/v1/tokens', ['data' => ['type' => 'tokens', 'attributes' => ['username' => 'pedro.gomez', 'password' => 'Clave.Segura7']]]);
        $this->assertResponseStatus(201);
    }

    public function testElJefeDeItinerarioRegistraEnSuItinerario()
    {
        $itinerary = $this->createItinerary();
        $chief = $this->createItineraryChief($itinerary);
        $firstStop = $itinerary->itineraryStops()->first()->stop_id;

        $this->registerWorker($chief, [], ['stop' => ['data' => ['type' => 'stops', 'id' => (string) $firstStop]]]);

        $this->assertResponseStatus(201);
        $worker = Worker::where('pass', 900)->first();
        $this->assertSame($itinerary->id, (int) $worker->itinerary_id);
        $this->assertTrue(Application::where('worker_id', $worker->id)->where('status', 'approved')->where('created_by', $chief->user_id)->exists());

        // Sin parada no se puede.
        $this->registerWorker($chief, ['pass' => 902]);
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/relationships/stop/data/id');

        $other = $this->createItinerary('Otra ruta');
        $stop = $other->itineraryStops()->first()->stop_id;
        $this->registerWorker($chief, ['pass' => 901], [
            'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $other->id]],
            'stop' => ['data' => ['type' => 'stops', 'id' => (string) $stop]],
        ]);
        $this->assertJsonApiError(403, 'FORBIDDEN');
    }

    public function testUnTrabajadorNormalNoRegistraANadie()
    {
        $this->registerWorker($this->createWorker());

        $this->assertResponseStatus(403);
    }

    public function testElAdministradorIndicaLaEntidad()
    {
        $entity = $this->createEntity('OTRA');

        $this->registerWorker($this->createAdmin());
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/relationships/entity/data/id');

        $this->registerWorker($this->createAdmin(), [], ['entity' => ['data' => ['type' => 'entities', 'id' => (string) $entity->id]]]);
        $this->assertResponseStatus(201);
        $this->assertSame($entity->id, (int) Worker::where('pass', 900)->value('entity_id'));
    }

    public function testPaseRepetidoEnLaEntidad()
    {
        $this->createWorker(['pass' => 900]);

        $this->registerWorker($this->createTransportChief());

        $this->assertJsonApiError(409, 'PASS_TAKEN');
    }

    public function testRegenerarElCodigoAnulaElAnterior()
    {
        $chief = $this->createTransportChief();
        $first = $this->registerWorker($chief)->responseJson()['data']['meta']['activationCode'];
        $worker = Worker::where('pass', 900)->first();

        $this->jsonApiAs($chief, 'POST', '/api/v1/workers/'.$worker->id.'/activation-codes', ['meta' => []]);
        $this->assertResponseStatus(201);
        $second = $this->responseJson()['data']['meta']['activationCode'];
        $this->assertNotSame($first, $second);

        $this->activate($first);
        $this->assertJsonApiError(422, 'ACTIVATION_INVALID');
        $this->activate($second);
        $this->assertResponseStatus(201);

        $this->jsonApiAs($chief, 'POST', '/api/v1/workers/'.$worker->id.'/activation-codes', ['meta' => []]);
        $this->assertJsonApiError(409, 'ALREADY_ACTIVATED');
    }

    public function testCodigoCaducadoOConDemasiadosIntentos()
    {
        $chief = $this->createTransportChief();
        $code = $this->registerWorker($chief)->responseJson()['data']['meta']['activationCode'];

        for ($i = 0; $i < 5; $i++) {
            $this->activate('AAAA-AAAA');
            $this->assertJsonApiError(422, 'ACTIVATION_INVALID');
        }

        // Tras 5 fallos, ni el correcto sirve.
        $this->activate($code);
        $this->assertJsonApiError(422, 'ACTIVATION_INVALID');

        $worker = Worker::where('pass', 900)->first();
        $this->jsonApiAs($chief, 'POST', '/api/v1/workers/'.$worker->id.'/activation-codes', ['meta' => []]);
        $code = $this->responseJson()['data']['meta']['activationCode'];

        Carbon::setTestNow(Carbon::now()->addDays(8));
        $this->activate($code);
        $this->assertJsonApiError(422, 'ACTIVATION_INVALID');
    }

    public function testAlActivarSeAplicanLasReglasDeUsuarioYContrasena()
    {
        $code = $this->registerWorker($this->createTransportChief())->responseJson()['data']['meta']['activationCode'];

        $this->activate($code, ['username' => 'admin.pedro']);
        $this->assertJsonApiError(422, 'USERNAME_INVALID');

        $this->activate($code, ['password' => 'pedro123']);
        $this->assertJsonApiError(422, 'PASSWORD_POLICY');

        $this->activate($code);
        $this->assertResponseStatus(201);
    }

    public function testListadoDeTrabajadoresSinActivar()
    {
        $chief = $this->createTransportChief();
        $this->registerWorker($chief);

        $this->jsonApiAs($chief, 'GET', '/api/v1/workers?filter[activated]=false');

        $this->assertResponseOk();
        $this->assertSame(1, $this->responseJson()['meta']['total']);
    }
}
