<?php

use App\Models\AccessRecovery;
use App\Models\Notice;
use App\Models\RefreshToken;
use Carbon\Carbon;
use Illuminate\Support\Facades\Hash;
use Laravel\Lumen\Testing\DatabaseMigrations;

/**
 * «Olvidé algo» con carné y teléfono (docs/11 §11.7).
 */
class AccessRecoveryTest extends TestCase
{
    use DatabaseMigrations;

    private $admin;
    private $worker;
    private $header;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
        $this->admin = $this->createAdmin();
        $this->worker = $this->createWorker(['user' => ['username' => 'maria', 'identity_card' => '85032002345']]);
        $this->header = $this->newInstallation();
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function newInstallation(): string
    {
        $this->jsonApi('POST', '/api/v1/installations', ['data' => ['type' => 'installations', 'attributes' => [
            'deviceModel' => 'Moto G', 'androidVersion' => '11', 'appVersionCode' => 5,
        ]]]);
        $this->assertResponseStatus(201);

        return $this->responseJson()['data']['meta']['header'];
    }

    private function requestRecovery(array $attributes = [], ?string $header = null)
    {
        return $this->jsonApi('POST', '/api/v1/guest/access-recoveries', ['data' => ['type' => 'access-recoveries', 'attributes' => array_merge([
            'forgotUsername' => true, 'forgotPassword' => true, 'identityCard' => '85032002345', 'phone' => '+53 5 123 4567',
        ], $attributes)]], ['X-Installation' => $header ?: $this->header]);
    }

    private function resolve(string $id, string $status)
    {
        return $this->jsonApiAs($this->admin, 'PATCH', '/api/v1/access-recoveries/'.$id, ['data' => ['type' => 'access-recoveries', 'id' => $id, 'attributes' => ['status' => $status]]]);
    }

    public function testFlujoCompletoConUsuarioYContrasena()
    {
        $id = $this->requestRecovery()->responseJson()['data']['id'];
        $this->assertResponseStatus(201);
        $this->assertSame('pending', $this->responseJson()['data']['attributes']['status']);
        $this->assertArrayNotHasKey('phone', $this->responseJson()['data']['attributes']);
        $this->assertTrue(Notice::where('user_id', $this->admin->id)->where('type', 'access_recovery_requested')->exists());

        $this->jsonApiAs($this->admin, 'GET', '/api/v1/access-recoveries?include=user');
        $recovery = $this->responseJson()['data'][0];
        $this->assertSame('+53 5 123 4567', $recovery['attributes']['phone']);
        $this->assertSame('85032002345', $recovery['attributes']['identityCard']);
        $this->assertTrue($recovery['attributes']['matched']);
        $this->assertSame((string) $this->worker->user_id, $recovery['relationships']['user']['data']['id']);

        // Antes de aprobarla no se ve el usuario.
        $this->jsonApi('GET', '/api/v1/guest/access-recoveries/'.$id, null, ['X-Installation' => $this->header]);
        $this->assertArrayNotHasKey('username', $this->responseJson()['data']['attributes']);
        $this->assertArrayNotHasKey('password', $this->responseJson()['data']['attributes']);

        app(\App\Services\TokenService::class)->issue($this->userOf($this->worker), 'viejo');

        // Al aprobarla se propone una contraseña nueva; el Administrador ve lo que debe comunicar.
        $this->resolve($id, 'approved');
        $this->assertResponseOk();
        $password = $this->responseJson()['data']['attributes']['password'];
        $this->assertSame('maria', $this->responseJson()['data']['attributes']['username']);
        $user = $this->userOf($this->worker)->fresh();
        $this->assertTrue(Hash::check($password, $user->password));
        $this->assertTrue($user->must_change_password);
        $this->assertSame(0, RefreshToken::where('device_name', 'viejo')->whereNull('revoked_at')->count());

        // La instalación que la pidió también lo ve, una sola vez.
        $this->jsonApi('GET', '/api/v1/guest/access-recoveries/'.$id, null, ['X-Installation' => $this->header]);
        $this->assertSame('maria', $this->responseJson()['data']['attributes']['username']);
        $this->assertSame($password, $this->responseJson()['data']['attributes']['password']);

        $recovery = AccessRecovery::find($id);
        $this->assertSame('completed', $recovery->status);
        $this->assertNull($recovery->phone_encrypted);
        $this->assertNull($recovery->password_encrypted);

        $this->jsonApi('GET', '/api/v1/guest/access-recoveries/'.$id, null, ['X-Installation' => $this->header]);
        $this->assertArrayNotHasKey('password', $this->responseJson()['data']['attributes']);

        // Al entrar con ella, debe cambiarla.
        $this->jsonApiAs($user, 'GET', '/api/v1/trips');
        $this->assertJsonApiError(403, 'PASSWORD_CHANGE_REQUIRED');
    }

    public function testSoloElUsuarioSeCierraAlLeerlo()
    {
        $id = $this->requestRecovery(['forgotPassword' => false])->responseJson()['data']['id'];
        $this->resolve($id, 'approved');

        // Solo lo pedido: la contraseña no cambia ni se comunica.
        $this->assertArrayNotHasKey('password', $this->responseJson()['data']['attributes']);
        $this->assertTrue(Hash::check(self::PASSWORD, $this->userOf($this->worker)->fresh()->password));

        $this->jsonApi('GET', '/api/v1/guest/access-recoveries/'.$id, null, ['X-Installation' => $this->header]);
        $this->assertSame('maria', $this->responseJson()['data']['attributes']['username']);
        $this->assertArrayNotHasKey('password', $this->responseJson()['data']['attributes']);
        $this->assertSame('completed', AccessRecovery::find($id)->status);
    }

    public function testOtraInstalacionNoVeLaSolicitud()
    {
        $id = $this->requestRecovery()->responseJson()['data']['id'];
        $this->resolve($id, 'approved');

        $this->jsonApi('GET', '/api/v1/guest/access-recoveries/'.$id, null, ['X-Installation' => $this->newInstallation()]);
        $this->assertJsonApiError(404, 'NOT_FOUND');

        $this->jsonApi('GET', '/api/v1/guest/access-recoveries/'.$id);
        $this->assertJsonApiError(401, 'INSTALLATION_REQUIRED');

        $this->jsonApi('GET', '/api/v1/guest/access-recoveries/'.$id, null, ['X-Installation' => '1.secretoequivocado1234567890']);
        $this->assertJsonApiError(401, 'INSTALLATION_REQUIRED');
    }

    public function testDatosQueNoCoincidenSoloSePuedenRechazar()
    {
        $id = $this->requestRecovery(['identityCard' => '86032002345'])->responseJson()['data']['id'];
        $this->assertResponseStatus(201);

        $this->resolve($id, 'approved');
        $this->assertJsonApiError(409, 'RECOVERY_NOT_MATCHED');

        $this->resolve($id, 'rejected');
        $this->assertResponseOk();
        $this->assertNull(AccessRecovery::find($id)->phone_encrypted);
    }

    public function testHayQueOlvidarAlgoYElCarneDebeSerValido()
    {
        $this->requestRecovery(['forgotUsername' => false, 'forgotPassword' => false]);
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/forgotUsername');

        $this->requestRecovery(['identityCard' => '123']);
        $this->assertJsonApiError(422, 'IDENTITY_CARD_INVALID', '/data/attributes/identityCard');
    }

    public function testLimiteDeSolicitudesPorHora()
    {
        for ($i = 0; $i < 3; $i++) {
            $this->requestRecovery();
            $this->assertResponseStatus(201);
        }

        $this->requestRecovery();
        $this->assertJsonApiError(429, 'TOO_MANY_REQUESTS');

        // Solo queda abierta la última.
        $this->assertSame(1, AccessRecovery::where('status', 'pending')->count());
    }

    public function testCaducan()
    {
        $id = $this->requestRecovery()->responseJson()['data']['id'];

        Carbon::setTestNow(Carbon::now()->addHours(73));
        $this->artisan('access-recoveries:expire');

        $recovery = AccessRecovery::find($id);
        $this->assertSame('expired', $recovery->status);
        $this->assertNull($recovery->phone_encrypted);
    }

    public function testSoloElAdministradorLasGestiona()
    {
        $id = $this->requestRecovery()->responseJson()['data']['id'];
        $chief = $this->createTransportChief();

        $this->jsonApiAs($chief, 'GET', '/api/v1/access-recoveries');
        $this->assertResponseStatus(403);
        $this->jsonApiAs($chief, 'PATCH', '/api/v1/access-recoveries/'.$id, ['data' => ['type' => 'access-recoveries', 'attributes' => ['status' => 'approved']]]);
        $this->assertResponseStatus(403);
    }

    public function testInstalacionBloqueada()
    {
        $installationId = (int) explode('.', $this->header)[0];

        $this->jsonApiAs($this->admin, 'PATCH', '/api/v1/installations/'.$installationId, ['data' => ['type' => 'installations', 'attributes' => ['blocked' => true]]]);
        $this->assertResponseOk();
        $this->seeJson(['blocked' => true, 'deviceModel' => 'Moto G']);

        $this->requestRecovery();
        $this->assertJsonApiError(403, 'INSTALLATION_BLOCKED');
    }
}
