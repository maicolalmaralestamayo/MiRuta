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

    private function login(string $card, string $password = 'secreto123')
    {
        return $this->jsonApi('POST', '/api/v1/tokens', ['data' => ['type' => 'tokens', 'attributes' => [
            'cardNumber' => $card, 'password' => $password, 'deviceName' => 'Teléfono de pruebas',
        ]]]);
    }

    private function refresh(string $token)
    {
        return $this->jsonApi('POST', '/api/v1/tokens/refresh', ['data' => ['type' => 'tokens', 'attributes' => ['refreshToken' => $token]]]);
    }

    public function testInicioDeSesion()
    {
        $card = $this->uniqueCardNumber();
        $worker = $this->createWorker(['card_number' => $card]);

        $this->login($card);

        $this->assertResponseStatus(201);
        $attributes = $this->responseJson()['data']['attributes'];
        $this->assertSame('Bearer', $attributes['tokenType']);
        $this->assertSame(1800, $attributes['expiresIn']);
        $this->assertSame(90 * 86400, $attributes['refreshExpiresIn']);
        $this->assertSame((string) $worker->id, $this->responseJson()['data']['relationships']['worker']['data']['id']);
        $this->assertSame('Teléfono de pruebas', RefreshToken::first()->device_name);

        $this->jsonApi('GET', '/api/v1/me', null, ['Authorization' => 'Bearer '.$attributes['accessToken']]);
        $this->assertResponseOk();
        $this->seeJson(['cardNumber' => $card]);
    }

    /**
     * @dataProvider wrongCredentials
     */
    public function testCredencialesIncorrectas(string $card, string $password)
    {
        $this->createWorker(['card_number' => '80010100020']);

        $this->login($card, $password);

        $this->assertJsonApiError(401, 'INVALID_CREDENTIALS');
    }

    public function wrongCredentials(): array
    {
        return [
            'contraseña incorrecta' => ['80010100020', 'otra-clave'],
            'carné inexistente' => ['80010200020', 'secreto123'],
            'carné mal formado' => ['123', 'secreto123'],
        ];
    }

    public function testTrabajadorInactivoNoPuedeEntrar()
    {
        $card = $this->uniqueCardNumber();
        $this->createWorker(['card_number' => $card])->delete();

        $this->login($card);

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
        $card = $this->uniqueCardNumber();
        $this->createWorker(['card_number' => $card]);
        $refreshToken = $this->login($card)->responseJson()['data']['attributes']['refreshToken'];

        $this->jsonApi('GET', '/api/v1/me', null, ['Authorization' => 'Bearer '.$refreshToken]);

        $this->assertJsonApiError(401, 'TOKEN_INVALID');
    }

    public function testRenovacionConRotacion()
    {
        $card = $this->uniqueCardNumber();
        $this->createWorker(['card_number' => $card]);
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
        $card = $this->uniqueCardNumber();
        $this->createWorker(['card_number' => $card]);
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
        $card = $this->uniqueCardNumber();
        $this->createWorker(['card_number' => $card]);
        $token = $this->login($card)->responseJson()['data']['attributes']['refreshToken'];

        Carbon::setTestNow(Carbon::now()->addDays(91));
        $this->refresh($token);

        $this->assertJsonApiError(401, 'TOKEN_EXPIRED');
    }

    public function testCerrarSesionEnEsteDispositivo()
    {
        $card = $this->uniqueCardNumber();
        $this->createWorker(['card_number' => $card]);
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
        $card = $this->uniqueCardNumber();
        $this->createWorker(['card_number' => $card]);
        $other = $this->login($card)->responseJson()['data']['attributes'];
        $current = $this->login($card)->responseJson()['data']['attributes'];

        $this->jsonApi('DELETE', '/api/v1/tokens', null, ['Authorization' => 'Bearer '.$current['accessToken']]);
        $this->assertResponseStatus(204);

        $this->refresh($other['refreshToken']);
        $this->assertJsonApiError(401, 'TOKEN_REVOKED');
    }

    public function testTrabajadorDesactivadoConTokenValido()
    {
        $worker = $this->createWorker();
        $token = $this->accessTokenFor($worker);
        $worker->delete();

        $this->jsonApi('GET', '/api/v1/me', null, ['Authorization' => 'Bearer '.$token]);

        $this->assertJsonApiError(401, 'TOKEN_REVOKED');
    }

    public function testLaDuracionDelTokenSaleDeLosAjustes()
    {
        \App\Models\Setting::create([
            'setting_definition_id' => \App\Models\SettingDefinition::where('key', 'access_token_ttl_minutes')->value('id'),
            'value' => '10',
        ]);
        $card = $this->uniqueCardNumber();
        $this->createWorker(['card_number' => $card]);

        $this->login($card);

        $this->assertSame(600, $this->responseJson()['data']['attributes']['expiresIn']);
    }
}
