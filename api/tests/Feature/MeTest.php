<?php

use App\Models\RefreshToken;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Laravel\Lumen\Testing\DatabaseMigrations;

class MeTest extends TestCase
{
    use DatabaseMigrations;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
    }

    public function testMiPerfilIncluyeElCarneYLaJerarquia()
    {
        $card = $this->uniqueCardNumber();
        $worker = $this->createWorker(['card_number' => $card]);

        $this->jsonApiAs($worker, 'GET', '/api/v1/me?include=rank');

        $this->assertResponseOk();
        $json = $this->responseJson();
        $this->assertSame($card, $json['data']['attributes']['cardNumber']);
        $this->assertSame('ranks', $json['included'][0]['type']);
        $this->assertSame('Trabajador civil', $json['included'][0]['attributes']['name']);
    }

    public function testCambiarNombre()
    {
        $worker = $this->createWorker();

        $this->jsonApiAs($worker, 'PATCH', '/api/v1/me', ['data' => ['type' => 'workers', 'attributes' => ['firstName' => ' Ana ']]]);

        $this->assertResponseOk();
        $this->seeJson(['firstName' => 'Ana']);
        $this->assertSame('Ana', $worker->fresh()->first_name);
    }

    public function testCambiarContrasenaExigeLaActualYCierraLasSesiones()
    {
        $worker = $this->createWorker();
        app(\App\Services\TokenService::class)->issue($worker, 'otro');
        $document = ['data' => ['type' => 'workers', 'attributes' => ['password' => 'nueva-clave-1']]];

        $this->jsonApiAs($worker, 'PATCH', '/api/v1/me', $document);
        $this->assertJsonApiError(422, 'CURRENT_PASSWORD_INVALID', '/meta/currentPassword');

        $document['meta'] = ['currentPassword' => 'secreto123'];
        $this->jsonApiAs($worker, 'PATCH', '/api/v1/me', $document);

        $this->assertResponseOk();
        $this->assertTrue(Hash::check('nueva-clave-1', $worker->fresh()->password));
        $this->assertSame(0, RefreshToken::whereNull('revoked_at')->count());
    }

    public function testFotoDePerfil()
    {
        $worker = $this->createWorker();
        $token = $this->accessTokenFor($worker);
        $png = base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
        $path = tempnam(sys_get_temp_dir(), 'foto');
        file_put_contents($path, $png);
        $file = new UploadedFile($path, 'foto.png', 'image/png', null, true);

        $this->call('POST', '/api/v1/me/photo', [], [], ['photo' => $file], [
            'HTTP_AUTHORIZATION' => 'Bearer '.$token,
            'HTTP_ACCEPT' => 'application/vnd.api+json',
            'CONTENT_TYPE' => 'multipart/form-data; boundary=x',
        ]);

        $this->assertResponseOk();
        $photoPath = $worker->fresh()->photo_path;
        $this->assertStringStartsWith('uploads/photos/', $photoPath);
        $this->assertFileExists(base_path('public/'.$photoPath));
        $this->assertSame(url($photoPath), $this->responseJson()['data']['attributes']['photoUrl']);

        $this->jsonApiAs($worker, 'DELETE', '/api/v1/me/photo');
        $this->assertResponseStatus(204);
        $this->assertNull($worker->fresh()->photo_path);
        $this->assertFileNotExists(base_path('public/'.$photoPath));
    }

    public function testLaFotoDebeSerUnaImagen()
    {
        $worker = $this->createWorker();
        $path = tempnam(sys_get_temp_dir(), 'texto');
        file_put_contents($path, 'no soy una imagen');

        $this->call('POST', '/api/v1/me/photo', [], [], ['photo' => new UploadedFile($path, 'foto.png', 'image/png', null, true)], [
            'HTTP_AUTHORIZATION' => 'Bearer '.$this->accessTokenFor($worker),
            'CONTENT_TYPE' => 'multipart/form-data; boundary=x',
        ]);

        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/photo');
    }

    public function testOtrosNoVenMiCarneYElAdministradorSi()
    {
        $worker = $this->createWorker();
        $serializer = new \App\Serializers\WorkerSerializer();
        $request = \Illuminate\Http\Request::create('/');

        $other = $this->createWorker();
        $request->setUserResolver(function () use ($other) {
            return $other;
        });
        $this->assertArrayNotHasKey('cardNumber', $serializer->attributes($worker, $request));

        $admin = $this->createWorker(['is_admin' => true]);
        $request->setUserResolver(function () use ($admin) {
            return $admin;
        });
        $this->assertArrayHasKey('cardNumber', $serializer->attributes($worker, $request));
    }
}
