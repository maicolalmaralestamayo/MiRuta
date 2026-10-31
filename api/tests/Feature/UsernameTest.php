<?php

use App\Models\Notice;
use App\Models\Rank;
use App\Models\Worker;
use App\Support\Username;
use Laravel\Lumen\Testing\DatabaseMigrations;

class UsernameTest extends TestCase
{
    use DatabaseMigrations;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
    }

    private function register(string $username, string $card = '92071648863')
    {
        return $this->jsonApi('POST', '/api/v1/workers', ['data' => [
            'type' => 'workers',
            'attributes' => [
                'cardNumber' => $card, 'username' => $username,
                'firstName' => 'María José', 'lastName' => 'Pérez Díaz', 'password' => 'secreto123',
            ],
            'relationships' => ['rank' => ['data' => ['type' => 'ranks', 'id' => (string) Rank::where('precedence', 17)->value('id')]]],
        ]]);
    }

    private function login(array $attributes)
    {
        return $this->jsonApi('POST', '/api/v1/tokens', ['data' => ['type' => 'tokens', 'attributes' => $attributes + ['password' => 'secreto123']]]);
    }

    public function testElRegistroGuardaElUsuarioEnMinusculas()
    {
        $this->register('  Maria.Perez ');

        $this->assertResponseStatus(201);
        $this->assertSame('maria.perez', Worker::first()->username);
    }

    public function testElUsuarioEsObligatorio()
    {
        $this->jsonApi('POST', '/api/v1/workers', ['data' => ['type' => 'workers', 'attributes' => [
            'cardNumber' => '92071648863', 'firstName' => 'A', 'lastName' => 'B', 'password' => 'secreto123',
        ], 'relationships' => ['rank' => ['data' => ['type' => 'ranks', 'id' => (string) Rank::first()->id]]]]]);

        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/username');
    }

    /**
     * @dataProvider invalidUsernames
     */
    public function testFormatoDelUsuario(string $username)
    {
        $this->register($username);

        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/username');
        $this->assertSame(0, Worker::count());
    }

    public function invalidUsernames(): array
    {
        return [
            'corto' => ['ab'],
            'empieza por número' => ['1maria'],
            'once dígitos' => ['92071648863'],
            'con tilde' => ['maría'],
            'con espacio' => ['maria perez'],
            'largo' => [str_repeat('a', 31)],
        ];
    }

    public function testUsuarioRepetidoSinImportarMayusculasNiSiEstaInactivo()
    {
        $this->createWorker(['username' => 'maria'])->delete();

        $this->register('MARIA');

        $this->assertJsonApiError(409, 'USERNAME_TAKEN', '/data/attributes/username');
    }

    public function testInicioDeSesionConUsuario()
    {
        $worker = $this->createWorker(['username' => 'maria.perez']);

        $this->login(['username' => ' Maria.Perez ']);

        $this->assertResponseStatus(201);
        $this->assertSame((string) $worker->id, $this->responseJson()['data']['relationships']['worker']['data']['id']);
    }

    public function testElCarneSigueSirviendoComoAlternativa()
    {
        $card = $this->uniqueCardNumber();
        $this->createWorker(['card_number' => $card]);

        $this->login(['username' => $card]);
        $this->assertResponseStatus(201);

        // Versiones de la app anteriores al usuario.
        $this->login(['cardNumber' => $card]);
        $this->assertResponseStatus(201);
    }

    public function testUsuarioOContrasenaIncorrectos()
    {
        $this->createWorker(['username' => 'maria']);

        $this->login(['username' => 'mario']);
        $this->assertJsonApiError(401, 'INVALID_CREDENTIALS');

        $this->login(['username' => 'maria', 'password' => 'otra-clave']);
        $this->assertJsonApiError(401, 'INVALID_CREDENTIALS');

        $this->login([]);
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/username');
    }

    public function testElTrabajadorInactivoNoEntra()
    {
        $this->createWorker(['username' => 'maria'])->delete();

        $this->login(['username' => 'maria']);

        $this->assertJsonApiError(401, 'INVALID_CREDENTIALS');
    }

    public function testCambiarElUsuarioDesdeElPerfil()
    {
        $worker = $this->createWorker(['username' => 'maria']);
        $this->createWorker(['username' => 'ocupado']);

        $this->jsonApiAs($worker, 'PATCH', '/api/v1/me', ['data' => ['type' => 'workers', 'attributes' => ['username' => 'Ocupado']]]);
        $this->assertJsonApiError(409, 'USERNAME_TAKEN');

        $this->jsonApiAs($worker, 'PATCH', '/api/v1/me', ['data' => ['type' => 'workers', 'attributes' => ['username' => 'a b']]]);
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/username');

        // Volver a guardar el suyo no es un conflicto.
        $this->jsonApiAs($worker, 'PATCH', '/api/v1/me', ['data' => ['type' => 'workers', 'attributes' => ['username' => 'MARIA']]]);
        $this->assertResponseOk();

        $this->jsonApiAs($worker, 'PATCH', '/api/v1/me', ['data' => ['type' => 'workers', 'attributes' => ['username' => 'mjose']]]);
        $this->assertResponseOk();
        $this->seeJson(['username' => 'mjose']);

        $this->login(['username' => 'mjose']);
        $this->assertResponseStatus(201);
        $this->login(['username' => 'maria']);
        $this->assertResponseStatus(401);
    }

    public function testElUsuarioSoloLoVenElPropioYElAdministrador()
    {
        $admin = $this->createAdmin();
        $worker = $this->createWorker(['username' => 'maria']);
        $other = $this->createWorker();

        $this->jsonApiAs($other, 'GET', '/api/v1/workers/'.$worker->id);
        $this->assertArrayNotHasKey('username', $this->responseJson()['data']['attributes']);

        $this->jsonApiAs($admin, 'GET', '/api/v1/workers/'.$worker->id);
        $this->assertSame('maria', $this->responseJson()['data']['attributes']['username']);

        $this->jsonApiAs($admin, 'GET', '/api/v1/workers?filter[search]=MARI');
        $this->assertSame([(string) $worker->id], array_column($this->responseJson()['data'], 'id'));
    }

    public function testRestablecerLaContrasenaConElUsuario()
    {
        $admin = $this->createAdmin();
        $worker = $this->createWorker(['username' => 'maria']);

        $this->jsonApi('POST', '/api/v1/password-resets', ['data' => ['type' => 'password-resets', 'attributes' => ['username' => 'Maria', 'phone' => '+53 5 123 4567']]]);
        $this->assertResponseStatus(202);
        $this->assertTrue(Notice::where('worker_id', $admin->id)->where('type', 'password_reset_requested')->exists());

        $this->jsonApiAs($admin, 'GET', '/api/v1/password-resets');
        $code = $this->responseJson()['data'][0]['attributes']['code'];

        $this->jsonApi('POST', '/api/v1/tokens/reset-code', ['data' => ['type' => 'tokens', 'attributes' => ['username' => 'maria', 'resetCode' => $code]]]);
        $this->assertResponseStatus(201);
        $this->assertTrue($worker->fresh()->must_change_password);
    }

    public function testPropuestaDeUsuario()
    {
        $this->assertSame('maria.perez', Username::suggest('María José', 'Pérez Díaz'));
        $this->assertSame('nunez.ibanez', Username::suggest('Núñez', 'Ibáñez'));
        $this->assertSame('usuario', Username::suggest('', ''));
        $this->assertSame('usuario2x', Username::suggest('2X', ''));

        $this->createWorker(['username' => 'maria.perez']);
        $this->createWorker(['username' => 'maria.perez2']);
        $this->assertSame('maria.perez3', Username::suggest('María', 'Pérez'));
        $this->assertTrue(Username::isValid(Username::suggest(str_repeat('a', 40), str_repeat('b', 40))));
    }
}
