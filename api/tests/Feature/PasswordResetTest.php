<?php

use App\Models\Notice;
use App\Models\PasswordReset;
use App\Models\RefreshToken;
use Carbon\Carbon;
use Illuminate\Support\Facades\Hash;
use Laravel\Lumen\Testing\DatabaseMigrations;

class PasswordResetTest extends TestCase
{
    use DatabaseMigrations;

    private $admin;
    private $worker;
    private $card;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
        $this->admin = $this->createAdmin();
        $this->card = $this->uniqueCardNumber();
        $this->worker = $this->createWorker(['card_number' => $this->card]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function requestReset(string $card, string $phone = '+53 5 123 4567')
    {
        return $this->jsonApi('POST', '/api/v1/password-resets', ['data' => ['type' => 'password-resets', 'attributes' => ['cardNumber' => $card, 'phone' => $phone]]]);
    }

    private function redeem(string $card, string $code)
    {
        return $this->jsonApi('POST', '/api/v1/tokens/reset-code', ['data' => ['type' => 'tokens', 'attributes' => ['cardNumber' => $card, 'resetCode' => $code]]]);
    }

    private function adminCode(): array
    {
        $this->jsonApiAs($this->admin, 'GET', '/api/v1/password-resets?include=worker');
        $this->assertResponseOk();

        return $this->responseJson()['data'][0];
    }

    public function testFlujoCompleto()
    {
        $this->requestReset($this->card);
        $this->assertResponseStatus(202);
        $this->assertTrue(Notice::where('worker_id', $this->admin->id)->where('type', 'password_reset_requested')->exists());

        $reset = $this->adminCode();
        $this->assertSame('+53 5 123 4567', $reset['attributes']['phone']);
        $this->assertSame(8, strlen($reset['attributes']['code']));
        $this->assertSame((string) $this->worker->id, $reset['relationships']['worker']['data']['id']);

        $this->jsonApiAs($this->admin, 'PATCH', '/api/v1/password-resets/'.$reset['id'], ['data' => ['type' => 'password-resets', 'id' => $reset['id'], 'attributes' => ['status' => 'sent']]]);
        $this->seeJson(['status' => 'sent']);

        // Se acepta en minúsculas y con guion
        $code = strtolower(substr($reset['attributes']['code'], 0, 4).'-'.substr($reset['attributes']['code'], 4));
        $this->redeem($this->card, $code);
        $this->assertResponseStatus(201);
        $access = $this->responseJson()['data']['attributes']['accessToken'];
        $this->seeJson(['mustChangePassword' => true]);

        // Teléfono y código borrados
        $stored = PasswordReset::first();
        $this->assertSame('used', $stored->status);
        $this->assertNull($stored->phone_encrypted);
        $this->assertNull($stored->code_encrypted);

        // Hasta cambiar la contraseña solo puede usar su perfil
        $auth = ['Authorization' => 'Bearer '.$access];
        $this->jsonApi('GET', '/api/v1/trips', null, $auth);
        $this->assertJsonApiError(403, 'PASSWORD_CHANGE_REQUIRED');
        $this->jsonApi('GET', '/api/v1/me', null, $auth);
        $this->seeJson(['mustChangePassword' => true]);

        $this->jsonApi('PATCH', '/api/v1/me', ['data' => ['type' => 'workers', 'attributes' => ['password' => 'nueva-clave-1']]], $auth);
        $this->assertResponseOk();
        $this->seeJson(['mustChangePassword' => false]);
        $this->assertTrue(Hash::check('nueva-clave-1', $this->worker->fresh()->password));

        $this->jsonApi('GET', '/api/v1/trips', null, $auth);
        $this->assertResponseOk();

        // El código no sirve dos veces
        $this->redeem($this->card, $code);
        $this->assertJsonApiError(401, 'RESET_CODE_INVALID');
    }

    public function testCarneDesconocidoRespondeIgual()
    {
        $this->requestReset('80010100050');

        $this->assertResponseStatus(202);
        $this->assertSame(0, PasswordReset::count());
    }

    public function testUsarElCodigoCierraLasDemasSesiones()
    {
        app(\App\Services\TokenService::class)->issue($this->worker, 'otro');
        $this->requestReset($this->card);
        $this->redeem($this->card, $this->adminCode()['attributes']['code']);

        $this->assertSame(1, RefreshToken::where('worker_id', $this->worker->id)->whereNull('revoked_at')->count());
    }

    public function testIntentosLimitadosYCaducidad()
    {
        $this->requestReset($this->card);
        $code = $this->adminCode()['attributes']['code'];

        foreach (range(1, 5) as $attempt) {
            $this->redeem($this->card, 'MALO1234');
            $this->assertJsonApiError(401, 'RESET_CODE_INVALID');
        }

        // Tras 5 fallos, ni el correcto sirve
        $this->redeem($this->card, $code);
        $this->assertJsonApiError(401, 'RESET_CODE_INVALID');
        $this->assertSame('expired', PasswordReset::first()->status);

        $this->requestReset($this->card);
        $code = $this->adminCode()['attributes']['code'];
        Carbon::setTestNow(Carbon::now()->addHours(25));
        $this->redeem($this->card, $code);
        $this->assertJsonApiError(401, 'RESET_CODE_INVALID');
    }

    public function testUnaSolicitudNuevaSustituyeALaAnterior()
    {
        $this->requestReset($this->card);
        $first = $this->adminCode()['attributes']['code'];
        $this->requestReset($this->card, '+53 5 999 9999');

        $this->redeem($this->card, $first);
        $this->assertJsonApiError(401, 'RESET_CODE_INVALID');
        $this->assertSame(1, PasswordReset::whereIn('status', ['pending', 'sent'])->count());
    }

    public function testSoloElAdministradorVeLasSolicitudes()
    {
        $this->requestReset($this->card);

        $this->jsonApiAs($this->createTransportChief(), 'GET', '/api/v1/password-resets');
        $this->assertJsonApiError(403, 'FORBIDDEN');
    }

    public function testTelefonoNoValido()
    {
        $this->requestReset($this->card, 'llámame');

        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/phone');
    }
}
