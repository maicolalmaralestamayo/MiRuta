<?php

use App\Models\Entity;
use App\Models\Rank;
use App\Models\User;
use App\Models\Worker;
use Laravel\Lumen\Testing\DatabaseMigrations;

/**
 * Registro en dos pasos (docs/08-version-2.md §8.3).
 */
class RegistrationTest extends TestCase
{
    use DatabaseMigrations;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
    }

    private function register(array $attributes = [])
    {
        return $this->jsonApi('POST', '/api/v1/users', ['data' => ['type' => 'users', 'attributes' => array_merge([
            'firstName' => 'María', 'middleName' => 'José', 'firstSurname' => 'Pérez', 'secondSurname' => 'Díaz',
            'username' => 'mjperez', 'password' => 'Clave.Segura7',
        ], $attributes)]]);
    }

    private function join($who, array $attributes = [], ?int $rankId = null)
    {
        return $this->jsonApiAs($who, 'POST', '/api/v1/me/worker', ['data' => [
            'type' => 'workers',
            'attributes' => array_merge(['entityAbbreviation' => 'prueba', 'pass' => 55, 'sex' => 'F'], $attributes),
            'relationships' => ['rank' => ['data' => ['type' => 'ranks', 'id' => (string) ($rankId ?: Rank::first()->id)]]],
        ]]);
    }

    public function testLaPrimeraCuentaEsLaDelAdministradorYNoEsTrabajador()
    {
        $this->register();

        $this->assertResponseStatus(201);
        $this->seeJson(['type' => 'users', 'isAdmin' => true, 'fullName' => 'María José Pérez Díaz']);
        $admin = User::first();
        $this->assertSame('mjperez', $admin->username);
        $this->assertNotNull($admin->password_changed_at);
        $this->assertSame(0, Worker::count());

        // El Administrador no necesita Entidad.
        $this->jsonApiAs($admin, 'GET', '/api/v1/trips');
        $this->assertResponseOk();
    }

    public function testLasSiguientesNoSonAdministradorasYDebenUnirseAUnaEntidad()
    {
        $this->createAdmin();
        $this->register();

        $this->assertResponseStatus(201);
        $this->seeJson(['isAdmin' => false]);
        $user = User::where('username', 'mjperez')->first();

        $this->jsonApiAs($user, 'GET', '/api/v1/trips');
        $this->assertJsonApiError(403, 'ENTITY_REQUIRED');

        // Sí puede ver su perfil y hablar con el desarrollador.
        $this->jsonApiAs($user, 'GET', '/api/v1/me');
        $this->assertResponseOk();
    }

    public function testLosCuatroNombresSonObligatorios()
    {
        $this->register(['middleName' => '', 'secondSurname' => null]);

        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/middleName');
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/secondSurname');
    }

    /**
     * @dataProvider invalidUsernames
     */
    public function testReglasDelUsuario(string $username)
    {
        $this->register(['username' => $username]);

        $this->assertJsonApiError(422, 'USERNAME_INVALID', '/data/attributes/username');
        $this->assertSame(0, User::count());
    }

    public function invalidUsernames(): array
    {
        return [
            'corto' => ['ana'],
            'largo' => [str_repeat('a', 21)],
            'empieza por número' => ['1maria'],
            'con tilde' => ['maría'],
            'termina en signo' => ['maria.'],
            'dos signos seguidos' => ['maria..perez'],
            'pocas letras' => ['ab123456'],
            'repetido' => ['maaaaria'],
            'reservada' => ['el_admin'],
            'reservada camuflada' => ['s0porte1'],
            'no permitida' => ['juan.puta'],
            'no permitida camuflada' => ['p3nd3jo'],
            'no permitida larga dentro' => ['elpendejo'],
        ];
    }

    public function testPalabraCortaDentroDeOtraSiSePermite()
    {
        $this->register(['username' => 'computadora']);

        $this->assertResponseStatus(201);
    }

    public function testUsuarioRepetidoSinImportarMayusculas()
    {
        $this->createUser(['username' => 'mjperez'])->delete();

        $this->register(['username' => 'MJPerez']);

        $this->assertJsonApiError(409, 'USERNAME_TAKEN', '/data/attributes/username');
    }

    public function testPoliticaDeContrasenaAlRegistrarse()
    {
        $this->register(['password' => 'mjperez2024']);

        $this->assertJsonApiError(422, 'PASSWORD_POLICY', '/data/attributes/password');
    }

    public function testUnirseALaEntidad()
    {
        $this->createAdmin();
        $user = $this->createUser();
        $entity = $this->defaultEntity();

        $this->join($user, ['entityAbbreviation' => ' prueba ']);

        $this->assertResponseStatus(201);
        $this->seeJson(['type' => 'workers', 'pass' => 55, 'sex' => 'F']);
        $this->assertSame($entity->id, (int) Worker::first()->entity_id);

        $this->jsonApiAs($user, 'GET', '/api/v1/trips');
        $this->assertResponseOk();

        $this->join($user, ['pass' => 56]);
        $this->assertJsonApiError(409, 'ALREADY_IN_ENTITY');
    }

    public function testEntidadInexistenteOPaseRepetido()
    {
        $user = $this->createUser();
        $this->createWorker(['pass' => 55]);

        $this->join($user, ['entityAbbreviation' => 'NOEXISTE']);
        $this->assertJsonApiError(422, 'ENTITY_NOT_FOUND', '/data/attributes/entityAbbreviation');

        $this->join($user);
        $this->assertJsonApiError(409, 'PASS_TAKEN', '/data/attributes/pass');

        // El mismo Pase en otra Entidad sí vale.
        $this->createEntity('OTRA');
        $this->join($user, ['entityAbbreviation' => 'otra']);
        $this->assertResponseStatus(201);
    }

    public function testElAdministradorNoSeUneAEntidades()
    {
        $this->join($this->createAdmin());

        $this->assertJsonApiError(409, 'ADMIN_HAS_NO_ENTITY');
    }

    public function testBuscarEntidadPorAbreviatura()
    {
        $user = $this->createUser();

        $this->jsonApiAs($user, 'GET', '/api/v1/entities/lookup?abbreviation=prueba');
        $this->assertJsonApiError(404, 'ENTITY_NOT_FOUND');

        $this->defaultEntity();
        $this->jsonApiAs($user, 'GET', '/api/v1/entities/lookup?abbreviation=prueba');
        $this->assertResponseOk();
        $this->seeJson(['abbreviation' => 'PRUEBA', 'name' => 'Entidad de pruebas']);

        // Sin sesión hace falta la instalación.
        $this->jsonApi('GET', '/api/v1/entities/lookup?abbreviation=prueba');
        $this->assertJsonApiError(401, 'INSTALLATION_REQUIRED');

        $header = $this->jsonApi('POST', '/api/v1/installations', ['data' => ['type' => 'installations']])->responseJson()['data']['meta']['header'];
        $this->jsonApi('GET', '/api/v1/entities/lookup?abbreviation=prueba', null, ['X-Installation' => $header]);
        $this->assertResponseOk();

        // La lista de Entidades no la ve nadie más que el Administrador.
        $worker = $this->createWorker();
        $this->createEntity('OTRA');
        $this->jsonApiAs($worker, 'GET', '/api/v1/entities');
        $this->assertSame(['PRUEBA'], array_column(array_column($this->responseJson()['data'], 'attributes'), 'abbreviation'));
        $this->jsonApiAs($this->createAdmin(), 'GET', '/api/v1/entities');
        $this->assertSame(2, $this->responseJson()['meta']['total']);
    }

    public function testPoliticaPublica()
    {
        $this->jsonApi('GET', '/api/v1/password-policy');

        $this->assertResponseOk();
        $this->seeJson(['minLength' => 8, 'requiredClasses' => 3, 'historyCount' => 5, 'usernameMinLength' => 4]);
    }
}
