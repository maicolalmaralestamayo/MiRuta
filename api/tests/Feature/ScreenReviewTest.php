<?php

use App\Models\Notice;
use App\Models\User;
use App\Support\ApkInfo;
use Carbon\Carbon;
use Carbon\CarbonImmutable;
use Illuminate\Http\UploadedFile;
use Laravel\Lumen\Testing\DatabaseMigrations;

/**
 * Cambios del servidor acordados en el repaso de pantallas (docs/09-repaso-pantallas.md).
 */
class ScreenReviewTest extends TestCase
{
    use DatabaseMigrations;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
        Carbon::setTestNow(Carbon::create(2026, 11, 2, 10));
        CarbonImmutable::setTestNow(CarbonImmutable::create(2026, 11, 2, 10));
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }

    public function testMatriculaConLaNomenclaturaCubana()
    {
        $chief = $this->createTransportChief();
        $type = \App\Models\VehicleType::first();
        $create = function (string $plate) use ($chief, $type) {
            return $this->jsonApiAs($chief, 'POST', '/api/v1/vehicles', ['data' => ['type' => 'vehicles',
                'attributes' => ['plate' => $plate, 'seats' => 40, 'standingCapacity' => 10],
                'relationships' => ['vehicleType' => ['data' => ['type' => 'vehicle-types', 'id' => (string) $type->id]], 'driver' => ['data' => null]],
            ]]);
        };

        $create('b 123 456');
        $this->assertResponseStatus(201);
        $this->seeJson(['plate' => 'B123456']);

        foreach (['X123456', 'B12345', 'B1234567', 'BB12345'] as $plate) {
            $create($plate);
            $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/plate');
        }

        // Las letras son un ajuste de la app.
        $admin = $this->createAdmin();
        $this->jsonApiAs($admin, 'PATCH', '/api/v1/settings/plate_letters', ['data' => ['type' => 'settings', 'id' => 'plate_letters', 'attributes' => ['value' => 'B,P,T,X']]]);
        $this->assertResponseOk();
        $create('X123456');
        $this->assertResponseStatus(201);
    }

    public function testAvisoDiarioDeCaducidadDeLaContrasenaConLosDiasDeCadaUsuario()
    {
        $user = $this->createUser(['password_changed_at' => Carbon::now()->subDays(355)]); // caduca en 10 días
        $other = $this->createUser(['password_changed_at' => Carbon::now()->subDays(355)]);
        $this->jsonApiAs($other, 'PATCH', '/api/v1/me/settings/password_expiry_notice_days', [
            'data' => ['type' => 'user-settings', 'id' => 'password_expiry_notice_days', 'attributes' => ['value' => 5]],
        ]);
        $this->assertResponseOk();

        $this->artisan('passwords:warn-expiry');
        $this->artisan('passwords:warn-expiry');
        $this->assertSame(1, Notice::where('user_id', $user->id)->count(), 'una vez al día');
        $this->assertSame(0, Notice::where('user_id', $other->id)->count(), 'a este le faltan más de 5 días');

        Carbon::setTestNow(Carbon::create(2026, 11, 3, 10));
        $this->artisan('passwords:warn-expiry');
        $this->assertSame(2, Notice::where('user_id', $user->id)->count(), 'y otra al día siguiente');

        $this->jsonApiAs($user, 'GET', '/api/v1/notices');
        $this->seeJson(['message' => 'Su contraseña caduca el jue. 12/11/26. Cámbiela en Mi perfil.']);
    }

    public function testDiasParaRecordarLaContrasenaConMaximoDeLaApp()
    {
        $worker = $this->createWorker();
        $patch = function ($value) use ($worker) {
            return $this->jsonApiAs($worker, 'PATCH', '/api/v1/me/settings/remember_password_days', [
                'data' => ['type' => 'user-settings', 'id' => 'remember_password_days', 'attributes' => ['value' => $value]],
            ]);
        };

        $patch(31);
        $this->assertJsonApiError(422, 'SETTING_OUT_OF_RANGE');
        $patch(30);
        $this->assertResponseOk();

        // Si el Administrador baja el máximo, el valor efectivo se ajusta.
        $this->jsonApiAs($this->createAdmin(), 'PATCH', '/api/v1/settings/remember_password_max_days', ['data' => ['type' => 'settings', 'id' => 'remember_password_max_days', 'attributes' => ['value' => 10]]]);
        $this->assertResponseOk();
        $this->assertSame(10, app(\App\Services\Settings::class)->int('remember_password_days', User::find($worker->user_id)));
    }

    public function testLaVersionSeLeeDelPropioApk()
    {
        $fixture = __DIR__.'/../fixtures/version-2.0.1.apk';
        $this->assertSame(['versionName' => '2.0.1', 'versionCode' => 6], ApkInfo::read($fixture));
        $this->assertNull(ApkInfo::read(__FILE__));

        $path = tempnam(sys_get_temp_dir(), 'apk');
        copy($fixture, $path);
        $this->call('POST', '/api/v1/app-versions', ['notes' => 'Novedades'], [], [
            'apkArm64' => new UploadedFile($path, 'miruta.apk', 'application/vnd.android.package-archive', null, true),
        ], [
            'HTTP_AUTHORIZATION' => 'Bearer '.$this->accessTokenFor($this->createAdmin()),
            'HTTP_ACCEPT' => 'application/vnd.api+json',
            'CONTENT_TYPE' => 'multipart/form-data; boundary=x',
        ]);
        $this->assertResponseStatus(201);
        $this->seeJson(['versionName' => '2.0.1', 'versionCode' => 6]);
    }

    public function testConfiguracionDelMapaConLaZonaDeLaEntidad()
    {
        $worker = $this->createWorker();
        $this->createStop('Empresa', null, 23.10);
        $this->createStop('Hospital', null, 23.12);
        $this->createStop('Otra', $this->createEntity('OTRA'), 21.0);

        $this->jsonApiAs($worker, 'GET', '/api/v1/map');
        $this->assertResponseOk();
        $map = $this->responseJson()['data']['attributes'];
        $this->assertSame('/tiles/{z}/{x}/{y}.png', $map['tilesUrl']);
        $this->assertSame(19.6, $map['bounds']['south']);
        $this->assertEqualsWithDelta(23.08, $map['area']['south'], 0.0001, 'solo las paradas de su Entidad');
        $this->assertEqualsWithDelta(23.14, $map['area']['north'], 0.0001);
    }
}
