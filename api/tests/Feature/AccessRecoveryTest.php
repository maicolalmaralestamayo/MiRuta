<?php

use App\Models\AccessRecovery;
use App\Models\Notice;
use App\Models\RefreshToken;
use Carbon\Carbon;
use Illuminate\Support\Facades\Hash;
use Laravel\Lumen\Testing\DatabaseMigrations;

/**
 * "No puedo entrar" (docs/08-version-2.md §8.6).
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
        $this->worker = $this->createWorker(['pass' => 321, 'user' => ['username' => 'maria']]);
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
            'forgotUsername' => true, 'forgotPassword' => true, 'entityAbbreviation' => 'prueba', 'pass' => 321, 'phone' => '+53 5 123 4567',
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

        $this->jsonApiAs($this->admin, 'GET', '/api/v1/access-recoveries?include=worker.user');
        $recovery = $this->responseJson()['data'][0];
        $this->assertSame('+53 5 123 4567', $recovery['attributes']['phone']);
        $this->assertTrue($recovery['attributes']['matched']);
        $this->assertSame((string) $this->worker->id, $recovery['relationships']['worker']['data']['id']);

        // Antes de aprobarla no se ve el usuario.
        $this->jsonApi('GET', '/api/v1/guest/access-recoveries/'.$id, null, ['X-Installation' => $this->header]);
        $this->assertArrayNotHasKey('username', $this->responseJson()['data']['attributes']);

        $this->resolve($id, 'approved');
        $this->assertResponseOk();

        $this->jsonApi('GET', '/api/v1/guest/access-recoveries/'.$id, null, ['X-Installation' => $this->header]);
        $this->assertSame('maria', $this->responseJson()['data']['attributes']['username']);

        app(\App\Services\TokenService::class)->issue($this->userOf($this->worker), 'viejo');
        $this->jsonApi('POST', '/api/v1/guest/access-recoveries/'.$id.'/password', ['data' => ['type' => 'access-recoveries', 'attributes' => ['password' => 'Nueva.Clave9']]], ['X-Installation' => $this->header]);
        $this->assertResponseStatus(201);
        $this->assertArrayHasKey('accessToken', $this->responseJson()['data']['attributes']);
        $this->assertTrue(Hash::check('Nueva.Clave9', $this->userOf($this->worker)->fresh()->password));
        $this->assertSame(0, RefreshToken::where('device_name', 'viejo')->whereNull('revoked_at')->count());

        $recovery = AccessRecovery::find($id);
        $this->assertSame('completed', $recovery->status);
        $this->assertNull($recovery->phone_encrypted);
    }

    public function testSoloElUsuarioSeCierraAlLeerlo()
    {
        $id = $this->requestRecovery(['forgotPassword' => false])->responseJson()['data']['id'];
        $this->resolve($id, 'approved');

        $this->jsonApi('GET', '/api/v1/guest/access-recoveries/'.$id, null, ['X-Installation' => $this->header]);
        $this->assertSame('maria', $this->responseJson()['data']['attributes']['username']);
        $this->assertSame('completed', AccessRecovery::find($id)->status);

        $this->jsonApi('POST', '/api/v1/guest/access-recoveries/'.$id.'/password', ['data' => ['type' => 'access-recoveries', 'attributes' => ['password' => 'Nueva.Clave9']]], ['X-Installation' => $this->header]);
        $this->assertJsonApiError(409, 'RECOVERY_NOT_APPROVED');
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
        $id = $this->requestRecovery(['pass' => 999])->responseJson()['data']['id'];
        $this->assertResponseStatus(201);

        $this->resolve($id, 'approved');
        $this->assertJsonApiError(409, 'RECOVERY_NOT_MATCHED');

        $this->resolve($id, 'rejected');
        $this->assertResponseOk();
        $this->assertNull(AccessRecovery::find($id)->phone_encrypted);
    }

    public function testHayQueOlvidarAlgo()
    {
        $this->requestRecovery(['forgotUsername' => false, 'forgotPassword' => false]);

        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/forgotUsername');
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
