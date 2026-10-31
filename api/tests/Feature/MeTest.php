<?php

use App\Models\RefreshToken;
use App\Models\User;
use App\Models\Worker;
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

    private function patchMe($who, array $attributes, array $extra = [])
    {
        $document = ['data' => ['type' => 'users', 'attributes' => $attributes]];

        if (isset($extra['relationships'])) {
            $document['data']['relationships'] = $extra['relationships'];
        }

        if (isset($extra['meta'])) {
            $document['meta'] = $extra['meta'];
        }

        return $this->jsonApiAs($who, 'PATCH', '/api/v1/me', $document);
    }

    public function testMiPerfilIncluyeUsuarioPaseYJerarquia()
    {
        $worker = $this->createWorker(['pass' => 4321, 'user' => ['username' => 'maria']]);

        $this->jsonApiAs($worker, 'GET', '/api/v1/me?include=worker,worker.rank,worker.entity');

        $this->assertResponseOk();
        $json = $this->responseJson();
        $this->assertSame('users', $json['data']['type']);
        $this->assertSame('maria', $json['data']['attributes']['username']);
        $this->assertSame((string) $worker->id, $json['data']['relationships']['worker']['data']['id']);
        $included = collect($json['included'])->keyBy('type');
        $this->assertSame(4321, $included['workers']['attributes']['pass']);
        $this->assertSame('PRUEBA', $included['entities']['attributes']['abbreviation']);
        $this->assertSame('ranks', $included['ranks']['type']);
    }

    public function testCambiarNombres()
    {
        $worker = $this->createWorker();

        $this->patchMe($worker, ['firstName' => ' Ana ', 'secondSurname' => 'Díaz']);

        $this->assertResponseOk();
        $this->seeJson(['firstName' => 'Ana', 'secondSurname' => 'Díaz']);
        $this->assertSame('Ana', $this->userOf($worker)->fresh()->first_name);

        $this->patchMe($worker, ['middleName' => '  ']);
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/middleName');
    }

    public function testCambiarLaJerarquiaEnElPerfil()
    {
        $worker = $this->createWorker();
        $rank = \App\Models\Rank::where('name', 'Cabo')->first();

        $this->patchMe($worker, [], ['relationships' => ['rank' => ['data' => ['type' => 'ranks', 'id' => (string) $rank->id]]]]);

        $this->assertResponseOk();
        $this->assertSame($rank->id, (int) $worker->fresh()->rank_id);
    }

    public function testCambiarElUsuarioBloqueaElAnteriorTreintaDias()
    {
        $maria = $this->createWorker(['user' => ['username' => 'maria']]);
        $other = $this->createWorker();

        $this->patchMe($maria, ['username' => 'mariaj']);
        $this->assertResponseOk();
        $this->seeJson(['username' => 'mariaj']);

        // Nadie más puede coger "maria" en 30 días…
        $this->patchMe($other, ['username' => 'maria']);
        $this->assertJsonApiError(409, 'USERNAME_TAKEN');

        // …salvo quien lo dejó.
        $this->patchMe($maria, ['username' => 'Maria']);
        $this->assertResponseOk();

        \App\Models\ReleasedUsername::query()->update(['released_at' => \Carbon\Carbon::now()->subDays(31)]);
        $this->patchMe($maria, ['username' => 'mariajose']);
        $this->patchMe($other, ['username' => 'mariaj']);
        $this->assertResponseOk();
    }

    public function testCambiarContrasenaExigeLaActualYCierraLasOtrasSesiones()
    {
        $worker = $this->createWorker();
        app(\App\Services\TokenService::class)->issue($this->userOf($worker), 'otro');

        $this->patchMe($worker, ['password' => 'Nueva.Clave9']);
        $this->assertJsonApiError(422, 'CURRENT_PASSWORD_INVALID', '/meta/currentPassword');

        $this->patchMe($worker, ['password' => 'Nueva.Clave9'], ['meta' => ['currentPassword' => self::PASSWORD]]);

        $this->assertResponseOk();
        $this->assertTrue(Hash::check('Nueva.Clave9', $this->userOf($worker)->fresh()->password));
        $this->assertSame(0, RefreshToken::where('device_name', 'otro')->whereNull('revoked_at')->count());
        $this->assertSame(1, \App\Models\PasswordHistory::count());
    }

    /**
     * @dataProvider weakPasswords
     */
    public function testPoliticaDeContrasenas(string $password)
    {
        $worker = $this->createWorker(['user' => ['username' => 'maria', 'first_name' => 'Gertrudis']]);

        $this->patchMe($worker, ['password' => $password], ['meta' => ['currentPassword' => self::PASSWORD]]);

        $this->assertJsonApiError(422, 'PASSWORD_POLICY', '/data/attributes/password');
    }

    public function weakPasswords(): array
    {
        return [
            'corta' => ['Ab.1'],
            'un solo tipo' => ['abcdefghij'],
            'dos tipos' => ['abcdefgh12'],
            'contiene el usuario' => ['Maria.2024x'],
            'contiene un nombre' => ['Gertrudis.99'],
            'común' => ['Password123'],
            'la actual' => [self::PASSWORD],
        ];
    }

    public function testNoSePuedenRepetirLasUltimasContrasenas()
    {
        $worker = $this->createWorker();
        $current = self::PASSWORD;

        foreach (['Clave.Uno1', 'Clave.Dos2', 'Clave.Tres3'] as $password) {
            $this->patchMe($worker, ['password' => $password], ['meta' => ['currentPassword' => $current]]);
            $this->assertResponseOk();
            $current = $password;
        }

        $this->patchMe($worker, ['password' => 'Clave.Uno1'], ['meta' => ['currentPassword' => $current]]);
        $this->assertJsonApiError(422, 'PASSWORD_POLICY');

        $this->patchMe($worker, ['password' => self::PASSWORD], ['meta' => ['currentPassword' => $current]]);
        $this->assertJsonApiError(422, 'PASSWORD_POLICY');
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
        $photoPath = $this->userOf($worker)->fresh()->photo_path;
        $this->assertStringStartsWith('uploads/photos/', $photoPath);
        $this->assertFileExists(base_path('public/'.$photoPath));
        $this->assertSame(url($photoPath), $this->responseJson()['data']['attributes']['photoUrl']);

        $this->jsonApiAs($worker, 'DELETE', '/api/v1/me/photo');
        $this->assertResponseStatus(204);
        $this->assertNull($this->userOf($worker)->fresh()->photo_path);
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

    public function testElPaseLoVenSoloElTrabajadorSusJefesYElAdministrador()
    {
        $itinerary = $this->createItinerary();
        $worker = $this->joinItinerary($this->createWorker(['pass' => 77]), $itinerary);
        $peer = $this->joinItinerary($this->createWorker(), $itinerary);
        $chief = $this->createItineraryChief($itinerary);
        $transportChief = $this->createTransportChief();
        $admin = $this->createAdmin();

        foreach ([[$worker, true], [$peer, false], [$chief, true], [$transportChief, true], [$admin, true]] as list($viewer, $sees)) {
            $this->jsonApiAs($viewer, 'GET', '/api/v1/workers/'.$worker->id);
            $this->assertResponseOk();
            $this->assertSame($sees, array_key_exists('pass', $this->responseJson()['data']['attributes']));
        }

        $this->jsonApiAs($peer, 'GET', '/api/v1/workers/'.$worker->id.'?include=user');
        $user = collect($this->responseJson()['included'])->firstWhere('type', 'users');
        $this->assertArrayNotHasKey('username', $user['attributes']);
    }
}
