<?php

use App\Models\RefreshToken;
use Carbon\Carbon;
use Laravel\Lumen\Testing\DatabaseMigrations;

class AuthTest extends TestCase
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

    private function login(string $username, string $password = self::PASSWORD)
    {
        return $this->jsonApi('POST', '/api/v1/tokens', ['data' => ['type' => 'tokens', 'attributes' => [
            'username' => $username, 'password' => $password, 'deviceName' => 'Teléfono de pruebas',
        ]]]);
    }

    private function refresh(string $token)
    {
        return $this->jsonApi('POST', '/api/v1/tokens/refresh', ['data' => ['type' => 'tokens', 'attributes' => ['refreshToken' => $token]]]);
    }

    public function testInicioDeSesion()
    {
        $worker = $this->createWorker(['user' => ['username' => 'maria.perez']]);

        $this->login('Maria.Perez');

        $this->assertResponseStatus(201);
        $attributes = $this->responseJson()['data']['attributes'];
        $this->assertSame('Bearer', $attributes['tokenType']);
        $this->assertSame(1800, $attributes['expiresIn']);
        $this->assertSame(90 * 86400, $attributes['refreshExpiresIn']);
        $this->assertSame((string) $worker->user_id, $this->responseJson()['data']['relationships']['user']['data']['id']);
        $this->assertSame('Teléfono de pruebas', RefreshToken::first()->device_name);

        $this->jsonApi('GET', '/api/v1/me', null, ['Authorization' => 'Bearer '.$attributes['accessToken']]);
        $this->assertResponseOk();
        $this->seeJson(['username' => 'maria.perez']);
    }

    /**
     * @dataProvider wrongCredentials
     */
    public function testCredencialesIncorrectas(string $username, string $password)
    {
        $this->createWorker(['user' => ['username' => 'maria']]);

        $this->login($username, $password);

        $this->assertJsonApiError(401, 'INVALID_CREDENTIALS');
    }

    public function wrongCredentials(): array
    {
        return [
            'contraseña incorrecta' => ['maria', 'Otra.Clave1'],
            'usuario inexistente' => ['mario', self::PASSWORD],
            'usuario mal formado' => ['1', self::PASSWORD],
        ];
    }

    public function testTrabajadorInactivoNoPuedeEntrar()
    {
        $worker = $this->createWorker(['user' => ['username' => 'maria']]);
        $this->userOf($worker)->delete();

        $this->login('maria');

        $this->assertJsonApiError(401, 'INVALID_CREDENTIALS');
    }

    public function testRutaProtegidaSinToken()
    {
        $this->jsonApi('GET', '/api/v1/me');

        $this->assertJsonApiError(401, 'UNAUTHENTICATED');
    }

    public function testTokenManipulado()
    {
        $token = $this->accessTokenFor($this->createWorker());
        $parts = explode('.', $token);
        $parts[1] = rtrim(strtr(base64_encode(json_encode(['sub' => 999, 'exp' => time() + 999, 'typ' => 'access'])), '+/', '-_'), '=');

        $this->jsonApi('GET', '/api/v1/me', null, ['Authorization' => 'Bearer '.implode('.', $parts)]);

        $this->assertJsonApiError(401, 'TOKEN_INVALID');
    }

    public function testTokenDeAccesoCaducado()
    {
        $worker = $this->createWorker();
        $token = $this->accessTokenFor($worker);

        Carbon::setTestNow(Carbon::now()->addMinutes(31));
        $this->jsonApi('GET', '/api/v1/me', null, ['Authorization' => 'Bearer '.$token]);

        $this->assertJsonApiError(401, 'TOKEN_EXPIRED');
    }

    public function testElTokenDeRenovacionNoSirveComoAcceso()
    {
        $card = 'maria';
        $this->createWorker(['user' => ['username' => $card]]);
        $refreshToken = $this->login($card)->responseJson()['data']['attributes']['refreshToken'];

        $this->jsonApi('GET', '/api/v1/me', null, ['Authorization' => 'Bearer '.$refreshToken]);

        $this->assertJsonApiError(401, 'TOKEN_INVALID');
    }

    public function testRenovacionConRotacion()
    {
        $card = 'maria';
        $this->createWorker(['user' => ['username' => $card]]);
        $first = $this->login($card)->responseJson()['data']['attributes']['refreshToken'];

        $this->refresh($first);
        $this->assertResponseStatus(201);
        $second = $this->responseJson()['data']['attributes']['refreshToken'];
        $this->assertNotSame($first, $second);

        $old = RefreshToken::orderBy('id')->first();
        $this->assertNotNull($old->revoked_at);
        $this->assertSame(RefreshToken::orderBy('id', 'desc')->value('id'), (int) $old->replaced_by_id);
        $this->assertSame('Teléfono de pruebas', RefreshToken::orderBy('id', 'desc')->value('device_name'));
    }

    public function testReutilizarUnTokenDeRenovacionRevocaTodasLasSesiones()
    {
        $card = 'maria';
        $this->createWorker(['user' => ['username' => $card]]);
        $otherDevice = $this->login($card)->responseJson()['data']['attributes']['refreshToken'];
        $stolen = $this->login($card)->responseJson()['data']['attributes']['refreshToken'];
        $this->refresh($stolen);
        $legitimate = $this->responseJson()['data']['attributes']['refreshToken'];

        $this->refresh($stolen);
        $this->assertJsonApiError(401, 'TOKEN_REVOKED');

        $this->refresh($legitimate);
        $this->assertJsonApiError(401, 'TOKEN_REVOKED');
        $this->refresh($otherDevice);
        $this->assertJsonApiError(401, 'TOKEN_REVOKED');
    }

    public function testTokenDeRenovacionCaducado()
    {
        $card = 'maria';
        $this->createWorker(['user' => ['username' => $card]]);
        $token = $this->login($card)->responseJson()['data']['attributes']['refreshToken'];

        Carbon::setTestNow(Carbon::now()->addDays(91));
        $this->refresh($token);

        $this->assertJsonApiError(401, 'TOKEN_EXPIRED');
    }

    public function testCerrarSesionEnEsteDispositivo()
    {
        $card = 'maria';
        $this->createWorker(['user' => ['username' => $card]]);
        $other = $this->login($card)->responseJson()['data']['attributes'];
        $current = $this->login($card)->responseJson()['data']['attributes'];

        $this->jsonApi('DELETE', '/api/v1/tokens/current', null, ['Authorization' => 'Bearer '.$current['accessToken']]);
        $this->assertResponseStatus(204);

        $this->refresh($current['refreshToken']);
        $this->assertJsonApiError(401, 'TOKEN_REVOKED');
        $this->refresh($other['refreshToken']);
        $this->assertResponseStatus(201);
    }

    public function testCerrarSesionEnTodosLosDispositivos()
    {
        $card = 'maria';
        $this->createWorker(['user' => ['username' => $card]]);
        $other = $this->login($card)->responseJson()['data']['attributes'];
        $current = $this->login($card)->responseJson()['data']['attributes'];

        $this->jsonApi('DELETE', '/api/v1/tokens', null, ['Authorization' => 'Bearer '.$current['accessToken']]);
        $this->assertResponseStatus(204);

        $this->refresh($other['refreshToken']);
        $this->assertJsonApiError(401, 'TOKEN_REVOKED');
    }

    public function testCuentaDesactivadaConTokenValido()
    {
        $worker = $this->createWorker();
        $token = $this->accessTokenFor($worker);
        $this->userOf($worker)->delete();

        $this->jsonApi('GET', '/api/v1/me', null, ['Authorization' => 'Bearer '.$token]);

        $this->assertJsonApiError(401, 'TOKEN_REVOKED');
    }

    public function testLaDuracionDelTokenSaleDeLosAjustes()
    {
        \App\Models\Setting::create([
            'setting_definition_id' => \App\Models\SettingDefinition::where('key', 'access_token_ttl_minutes')->value('id'),
            'value' => '10',
        ]);
        $card = 'maria';
        $this->createWorker(['user' => ['username' => $card]]);

        $this->login($card);

        $this->assertSame(600, $this->responseJson()['data']['attributes']['expiresIn']);
    }

    public function testCuentaDesactivadaNoPuedeEntrar()
    {
        $this->createWorker(['user' => ['username' => 'inactiva']]);
        \App\Models\User::where('username', 'inactiva')->first()->delete();

        $this->login('inactiva');

        $this->assertJsonApiError(401, 'INVALID_CREDENTIALS');
    }

    public function testContrasenaCaducadaObligaACambiarla()
    {
        $worker = $this->createWorker(['user' => ['password_changed_at' => Carbon::now()->subDays(366)]]);

        $this->jsonApiAs($worker, 'GET', '/api/v1/trips');
        $this->assertJsonApiError(403, 'PASSWORD_CHANGE_REQUIRED');

        $this->jsonApiAs($worker, 'GET', '/api/v1/me');
        $this->assertResponseOk();
        $this->assertTrue($this->responseJson()['data']['attributes']['mustChangePassword']);

        $this->jsonApiAs($worker, 'PATCH', '/api/v1/me', ['data' => ['type' => 'users', 'attributes' => ['password' => 'Nueva.Clave9']], 'meta' => ['currentPassword' => self::PASSWORD]]);
        $this->assertResponseOk();

        $this->jsonApiAs($worker, 'GET', '/api/v1/trips');
        $this->assertResponseOk();
    }

    public function testElLoginEnlazaLaInstalacionYSusConversacionesSinCuenta()
    {
        $this->createWorker(['user' => ['username' => 'maria']]);
        $installation = $this->jsonApi('POST', '/api/v1/installations', ['data' => ['type' => 'installations', 'attributes' => ['deviceModel' => 'Moto G']]])
            ->responseJson()['data'];
        $header = $installation['meta']['header'];
        $topic = \App\Models\ConversationTopic::where('recipient', 'developer')->first();
        $this->jsonApi('POST', '/api/v1/guest/conversations', ['data' => ['type' => 'conversations',
            'attributes' => ['guestName' => 'María', 'guestPhone' => '+53 5 123 4567', 'body' => 'Hola'],
            'relationships' => ['topic' => ['data' => ['type' => 'conversation-topics', 'id' => (string) $topic->id]]]]], ['X-Installation' => $header]);
        $this->assertResponseStatus(201);

        $this->jsonApi('POST', '/api/v1/tokens', ['data' => ['type' => 'tokens', 'attributes' => ['username' => 'maria', 'password' => self::PASSWORD]]], ['X-Installation' => $header]);
        $this->assertResponseStatus(201);

        $user = \App\Models\User::where('username', 'maria')->first();
        $this->assertSame($user->id, (int) \App\Models\Installation::find($installation['id'])->user_id);
        $this->assertSame($user->id, (int) \App\Models\Conversation::first()->opened_by);
    }
}
