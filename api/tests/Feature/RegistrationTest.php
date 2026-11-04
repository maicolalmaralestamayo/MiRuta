<?php

use App\Models\User;
use App\Models\Worker;
use App\Services\Accounts;
use App\Support\IdentityCard;
use Laravel\Lumen\Testing\DatabaseMigrations;

/**
 * Registro (docs/11 §11.4 y §11.5): sin Entidad, con carné; el primero es
 * el Administrador; usuario y contraseña propuestos.
 */
class RegistrationTest extends TestCase
{
    use DatabaseMigrations;

    const CARD = '85032012345'; // 20/03/1985, penúltimo 4 → masculino

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
    }

    private function register(array $attributes = [])
    {
        return $this->jsonApi('POST', '/api/v1/users', ['data' => ['type' => 'users', 'attributes' => array_merge([
            'firstName' => 'María', 'middleName' => 'José', 'firstSurname' => 'Pérez', 'secondSurname' => 'Díaz',
            'identityCard' => self::CARD, 'username' => 'mjperez', 'password' => 'Clave.Segura7',
        ], $attributes)]]);
    }

    public function testLaPrimeraPersonaEsElAdministradorYQuedaSinEntidad()
    {
        $this->jsonApi('GET', '/api/v1/registration-status');
        $this->assertResponseOk();
        $this->assertFalse($this->responseJson()['data']['attributes']['adminExists']);

        $this->register();

        $this->assertResponseStatus(201);
        $this->seeJson(['type' => 'users', 'isAdmin' => true, 'fullName' => 'María José Pérez Díaz', 'entities' => []]);
        $admin = User::first();
        $this->assertSame('mjperez', $admin->username);
        $this->assertNotNull($admin->password_changed_at);
        $this->assertSame(0, Worker::count());

        $this->jsonApi('GET', '/api/v1/registration-status');
        $this->assertTrue($this->responseJson()['data']['attributes']['adminExists']);

        $this->jsonApiAs($admin, 'GET', '/api/v1/trips');
        $this->assertResponseOk();
    }

    public function testLasSiguientesNoSonAdministradorasYPuedenUsarLaAppSinEntidad()
    {
        $this->createAdmin();
        $this->register();

        $this->assertResponseStatus(201);
        $this->seeJson(['isAdmin' => false]);
        $user = User::where('username', 'mjperez')->first();

        // Sin Entidad: ve su perfil, y las listas salen vacías.
        $this->jsonApiAs($user, 'GET', '/api/v1/me');
        $this->assertResponseOk();
        $this->assertSame([], $this->responseJson()['data']['meta']['memberships']);
        $this->assertSame([], $this->responseJson()['data']['meta']['permissions']);

        $this->jsonApiAs($user, 'GET', '/api/v1/trips');
        $this->assertResponseOk();
        $this->assertSame(0, $this->responseJson()['meta']['total']);
    }

    public function testSiElAdministradorEstaDesactivadoNoHayOtroAutomatico()
    {
        $this->createAdmin()->delete();

        $this->register();

        $this->assertResponseStatus(201);
        $this->seeJson(['isAdmin' => false]);
    }

    public function testElCarneDaElSexoYLaFechaDeNacimientoYSeGuardaCifrado()
    {
        // 28/02/2001 (7.º dígito 7 → 2000), penúltimo 4 (par) → masculino.
        $this->register(['identityCard' => '01022876543']);

        $this->assertResponseStatus(201);
        $this->seeJson(['sex' => 'M', 'identityCard' => '01022876543', 'birthDate' => '2001-02-28']);
        $user = User::first();
        $this->assertSame('M', $user->sex);
        $this->assertSame('2001-02-28', $user->birth_date->toDateString());
        $this->assertNotContains('01022876543', array_map('strval', $user->getAttributes()));
        $this->assertSame(IdentityCard::hash('01022876543'), $user->identity_card_hash);
        $this->assertSame('01022876543', $user->identityCard());

        // 12/06/1895 (7.º dígito 9 → 1800), penúltimo 3 (impar) → femenino.
        $this->register(['identityCard' => '95061292531', 'username' => 'otra']);
        $this->assertResponseStatus(201);
        $this->seeJson(['sex' => 'F', 'birthDate' => '1895-06-12']);
    }

    public function testLosNombresSonObligatoriosMenosElSegundoNombre()
    {
        $this->register(['middleName' => '', 'secondSurname' => null]);

        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/secondSurname');
        $this->assertSame(1, count($this->responseJson()['errors']));

        $this->register(['middleName' => '']);
        $this->assertResponseStatus(201);
        $this->assertNull(User::first()->middle_name);
    }

    /**
     * @dataProvider invalidIdentityCards
     */
    public function testCarneNoValido(string $card)
    {
        $this->register(['identityCard' => $card]);

        $this->assertJsonApiError(422, 'IDENTITY_CARD_INVALID', '/data/attributes/identityCard');
        $this->assertSame(0, User::count());
    }

    public function invalidIdentityCards(): array
    {
        return [
            'corto' => ['8503201234'],
            'con letras' => ['8503201234A'],
            'mes 13' => ['85132012345'],
            'día 30 de febrero' => ['85023012345'],
            'futuro' => ['99123182345'], // siglo 8 → 2099
        ];
    }

    public function testCarneRepetidoConElMensajeAcordado()
    {
        $this->createUser(['identity_card' => self::CARD]);

        $this->register();

        $this->assertJsonApiError(409, 'IDENTITY_CARD_TAKEN', '/data/attributes/identityCard');
        $this->assertSame(Accounts::IDENTITY_CARD_TAKEN, $this->responseJson()['errors'][0]['detail']);
        $this->assertStringStartsWith('Alguien ya se registró con este carné de identidad. Si fue usted, emplee la opción Olvidé algo.', Accounts::IDENTITY_CARD_TAKEN);
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
            'corto' => ['a'],
            'largo' => [str_repeat('a', 51)],
            'empieza por número' => ['1maria'],
            'con tilde' => ['maría'],
            'termina en signo' => ['maria.'],
            'dos signos seguidos' => ['maria..perez'],
            'pocas letras' => ['a123456'],
            'repetido' => ['maaaaria'],
            'reservada' => ['el_admin'],
            'reservada camuflada' => ['s0porte1'],
        ];
    }

    public function testUsuarioDeDosACincuentaCaracteres()
    {
        $this->register(['username' => 'mj']);
        $this->assertResponseStatus(201);

        $this->register(['username' => str_repeat('ab', 25), 'identityCard' => $this->newIdentityCard()]);
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

    public function testUsuarioPropuesto()
    {
        $suggest = function (array $names) {
            $this->jsonApi('GET', '/api/v1/username-suggestion?'.http_build_query($names));
            $this->assertResponseOk();

            return $this->responseJson()['data']['attributes']['username'];
        };
        $names = ['firstName' => 'Maicol', 'middleName' => 'Alberto', 'firstSurname' => 'Almarales', 'secondSurname' => 'Tamayo'];

        $this->assertSame('maicol', $suggest($names));
        $this->createUser(['username' => 'maicol']);
        $this->assertSame('maicol.alberto', $suggest($names));
        $this->createUser(['username' => 'maicol.alberto']);
        $this->assertSame('maicol.alberto.almarales', $suggest($names));
        $this->createUser(['username' => 'maicol.alberto.almarales']);
        $this->assertSame('maicol.alberto.almarales.tamayo', $suggest($names));
        $this->createUser(['username' => 'maicol.alberto.almarales.tamayo']);
        $this->assertSame('maicol.alberto.almarales.tamayo.2', $suggest($names));
        $this->createUser(['username' => 'maicol.alberto.almarales.tamayo.2']);
        $this->assertSame('maicol.alberto.almarales.tamayo.3', $suggest($names));

        // Sin segundo nombre, en minúsculas, sin tildes y con la ñ como n.
        $this->assertSame('ines', $suggest(['firstName' => 'Inés', 'firstSurname' => 'Muñoz', 'secondSurname' => 'Peña']));
        $this->createUser(['username' => 'ines']);
        $this->assertSame('ines.munoz', $suggest(['firstName' => 'Inés', 'firstSurname' => 'Muñoz', 'secondSurname' => 'Peña']));

        // Las partes con palabras reservadas no se usan.
        $this->assertSame('perez', $suggest(['firstName' => 'Soporte', 'firstSurname' => 'Pérez']));
    }

    public function testContrasenaPropuestaCumpleLaPolitica()
    {
        for ($i = 0; $i < 5; $i++) {
            $this->jsonApi('GET', '/api/v1/password-suggestion');
            $this->assertResponseOk();
            $password = $this->responseJson()['data']['attributes']['password'];
            $this->assertSame([], app(\App\Services\Passwords::class)->problems($password));
        }
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

        // La lista de Entidades: cada uno ve las suyas; el Administrador, todas.
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
        $this->seeJson(['minLength' => 8, 'requiredClasses' => 3, 'historyCount' => 5, 'usernameMinLength' => 2, 'usernameMaxLength' => 50]);
    }
}
