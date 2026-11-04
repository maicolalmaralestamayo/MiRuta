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

    public function testMiPerfilConPermisosYPertenencias()
    {
        $itinerary = $this->createItinerary('Ruta Este', 2);
        $worker = $this->joinItinerary($this->createWorker(['user' => ['username' => 'maria']]), $itinerary, 2);
        $this->assignRole($worker, 'Chofer');
        $other = $this->createEntity('OTRA');
        $this->createWorker(['user_id' => $worker->user_id], $other);

        $this->jsonApiAs($worker, 'GET', '/api/v1/me');

        $this->assertResponseOk();
        $json = $this->responseJson()['data'];
        $this->assertSame('users', $json['type']);
        $this->assertSame('maria', $json['attributes']['username']);
        $this->assertSame(['OTRA', 'PRUEBA'], $json['attributes']['entities']);
        $this->assertArrayHasKey('identityCard', $json['attributes']);

        $memberships = collect($json['meta']['memberships'])->keyBy('entity.abbreviation');
        $this->assertSame('Ruta Este', $memberships['PRUEBA']['itinerary']['name']);
        $this->assertSame('Ruta Este parada 2', $memberships['PRUEBA']['stop']['landmark']);
        $this->assertSame(['Chofer', 'Trabajador'], collect($memberships['PRUEBA']['roles'])->pluck('name')->sort()->values()->all());
        $this->assertNull($memberships['OTRA']['itinerary']);
        $this->assertSame(['Trabajador'], collect($memberships['OTRA']['roles'])->pluck('name')->all());

        $permissions = collect($json['meta']['permissions']);
        $this->assertTrue($permissions->contains(['operation' => 'tracking.drive', 'scope' => 'entity', 'entityId' => (string) $this->defaultEntity()->id, 'itineraryId' => null]));
        $this->assertTrue($permissions->contains(['operation' => 'trips.view', 'scope' => 'own', 'entityId' => (string) $other->id, 'itineraryId' => null]));
        $this->assertFalse($permissions->contains(['operation' => 'tracking.drive', 'scope' => 'entity', 'entityId' => (string) $other->id, 'itineraryId' => null]));

        // El Administrador: todas con «all».
        $this->jsonApiAs($this->createAdmin(), 'GET', '/api/v1/me');
        $permissions = collect($this->responseJson()['data']['meta']['permissions']);
        $this->assertSame(count(\App\Support\Operations::CATALOG), $permissions->where('scope', 'all')->count());
    }

    public function testCambiarElCarneCambiaSexoYNacimiento()
    {
        $worker = $this->createWorker();
        $taken = $this->createUser();

        $this->patchMe($worker, ['identityCard' => '90010112361']); // penúltimo 6 → M
        $this->assertResponseOk();
        $this->seeJson(['identityCard' => '90010112361', 'birthDate' => '1990-01-01', 'sex' => 'M']);

        $this->patchMe($worker, ['identityCard' => $taken->identityCard()]);
        $this->assertJsonApiError(409, 'IDENTITY_CARD_TAKEN', '/data/attributes/identityCard');
    }

    public function testCambiarNombres()
    {
        $worker = $this->createWorker();

        $this->patchMe($worker, ['firstName' => ' Ana ', 'secondSurname' => 'Díaz']);

        $this->assertResponseOk();
        $this->seeJson(['firstName' => 'Ana', 'secondSurname' => 'Díaz']);
        $this->assertSame('Ana', $this->userOf($worker)->fresh()->first_name);

        // El segundo nombre es opcional: en blanco se queda sin él.
        $this->patchMe($worker, ['middleName' => '  ']);
        $this->assertResponseOk();
        $this->assertNull($this->userOf($worker)->fresh()->middle_name);
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

    public function testElCarneLoVenLaPersonaElAdministradorYElJefeDeSuItinerario()
    {
        $itinerary = $this->createItinerary();
        $worker = $this->joinItinerary($this->createWorker(), $itinerary);
        $peer = $this->joinItinerary($this->createWorker(), $itinerary);
        $chief = $this->createItineraryChief($itinerary);
        $otherChief = $this->createItineraryChief($this->createItinerary('Ruta Oeste'));
        $transportChief = $this->createTransportChief();
        $admin = $this->createAdmin();

        foreach ([[$worker, true], [$peer, false], [$chief, true], [$otherChief, false], [$transportChief, false], [$admin, true]] as $index => list($viewer, $sees)) {
            $this->jsonApiAs($viewer, 'GET', '/api/v1/workers/'.$worker->id.'?include=user');

            if ($viewer === $peer || $viewer === $otherChief) {
                // Sin workers.view sobre él no lo consultan.
                $this->assertResponseStatus(404);
                continue;
            }

            $this->assertResponseOk();
            $this->assertSame($sees, array_key_exists('identityCard', $this->responseJson()['data']['attributes']), "Caso {$index}");
            $user = collect($this->responseJson()['included'])->firstWhere('type', 'users');
            $this->assertSame($sees, array_key_exists('identityCard', $user['attributes']), "Caso {$index}");
        }

        // También lo ve el Jefe del itinerario que alguien solicita.
        $applicant = $this->createWorker();
        \App\Models\Application::create([
            'user_id' => $applicant->user_id, 'entity_id' => $applicant->entity_id, 'type' => 'itinerary_membership', 'status' => 'pending',
            'itinerary_id' => $itinerary->id, 'stop_id' => $itinerary->stops->first()->id, 'created_by' => $applicant->user_id,
        ]);
        $this->jsonApiAs($chief, 'GET', '/api/v1/users/'.$applicant->user_id);
        $this->assertResponseOk();
        $this->assertArrayHasKey('identityCard', $this->responseJson()['data']['attributes']);
        $this->assertArrayNotHasKey('username', $this->responseJson()['data']['attributes']);
    }
}
