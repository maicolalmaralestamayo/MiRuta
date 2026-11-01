<?php

use App\Models\AbsenceType;
use App\Models\Application;
use App\Models\ItineraryChief;
use App\Models\Notice;
use App\Models\User;
use App\Services\Absences;
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

    private function apply($worker, string $type, array $attributes = [], array $relationships = [])
    {
        $data = ['type' => 'applications', 'attributes' => ['type' => $type] + $attributes];
        foreach ($relationships as $name => list($jsonType, $id)) {
            $data['relationships'][$name] = ['data' => ['type' => $jsonType, 'id' => (string) $id]];
        }

        return $this->jsonApiAs($worker, 'POST', '/api/v1/applications', ['data' => $data]);
    }

    private function patchApplication($user, $id, array $attributes)
    {
        return $this->jsonApiAs($user, 'PATCH', '/api/v1/applications/'.$id, ['data' => [
            'type' => 'applications', 'id' => (string) $id, 'attributes' => $attributes,
        ]]);
    }

    private function chiefAndMember(): array
    {
        $itinerary = $this->createItinerary();
        $chief = $this->createWorker(['user' => ['first_name' => 'Teresa', 'middle_name' => null, 'first_surname' => 'Jefa', 'second_surname' => 'López']]);
        ItineraryChief::create(['itinerary_id' => $itinerary->id, 'worker_id' => $chief->id]);

        return [$chief->fresh(), $this->joinItinerary($this->createWorker(), $itinerary)];
    }

    public function testVariosHijosEnUnaMismaSolicitudYSeResuelvenPorSeparado()
    {
        list($chief, $mother) = $this->chiefAndMember();

        $this->apply($mother, 'child_addition', ['children' => [
            ['firstName' => 'Pepito', 'firstSurname' => 'Pérez', 'secondSurname' => 'García', 'birthDate' => '2015-03-05'],
            ['firstName' => 'Ana', 'middleName' => 'María', 'firstSurname' => 'Pérez', 'secondSurname' => 'García', 'birthDate' => '2018-07-16'],
        ]]);
        $this->assertResponseStatus(201);

        $applications = Application::orderBy('id')->get();
        $this->assertCount(2, $applications);
        $this->assertSame($applications[0]->id, (int) $applications[1]->group_id);
        $this->assertSame($applications[0]->id, (int) $applications[0]->group_id);
        $this->assertSame('Pepito Pérez García', $applications[0]->related_child->fullName(), 'sin segundo nombre');
        $this->assertSame(1, Notice::where('user_id', $chief->user_id)->where('type', Notice::TYPE_APPLICATION_RECEIVED)->count(), 'un solo aviso al jefe');

        // Un hijo mal escrito señala su posición en la lista.
        $this->apply($mother, 'child_addition', ['children' => [
            ['firstName' => 'Luis', 'firstSurname' => 'Pérez', 'secondSurname' => 'García', 'birthDate' => '2001-01-01'],
        ]]);
        $this->assertJsonApiError(422, 'CHILD_NOT_ELIGIBLE', '/data/attributes/children/0/birthDate');

        // Rechazar exige el motivo.
        $this->patchApplication($chief, $applications[1]->id, ['status' => 'rejected']);
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/resolutionNote');
        $this->patchApplication($chief, $applications[1]->id, ['status' => 'rejected', 'resolutionNote' => 'No es hija suya']);
        $this->assertResponseOk();
        $this->patchApplication($chief, $applications[0]->id, ['status' => 'approved']);
        $this->assertResponseOk();

        $this->jsonApiAs($mother, 'GET', '/api/v1/notices?sort=createdAt');
        $messages = array_column(array_column($this->responseJson()['data'], 'attributes'), 'message');
        $this->assertContains('Se rechazó su solicitud de Declarar hijos (Ana María Pérez García). La rechazó Teresa Jefa López. Motivo: No es hija suya', $messages);
        $this->assertContains('Se aprobó su solicitud de Declarar hijos (Pepito Pérez García). La aprobó Teresa Jefa López.', $messages);
    }

    public function testAusenciaIndefinidaYDespuesConFechas()
    {
        list($chief, $worker) = $this->chiefAndMember();
        $type = AbsenceType::where('name', 'Licencia')->first();

        $this->apply($worker, 'absence', ['indefinite' => true, 'startsOn' => '2026-11-10'], ['absenceType' => ['absence-types', $type->id]]);
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/startsOn');

        $this->apply($worker, 'absence', ['indefinite' => true], ['absenceType' => ['absence-types', $type->id]]);
        $this->assertResponseStatus(201);
        $this->seeJson(['indefinite' => true, 'startsOn' => null, 'endsOn' => null]);
        $id = $this->responseJson()['data']['id'];

        // Mientras está pendiente no cuenta; aprobada, vale para cualquier fecha.
        $absences = app(Absences::class);
        $this->assertFalse($absences->isAbsent($worker->id, Carbon::create(2027, 5, 1)));
        $this->patchApplication($chief, $id, ['status' => 'approved']);
        $this->assertTrue($absences->isAbsent($worker->id, Carbon::create(2027, 5, 1)));

        // Solo el propio trabajador le pone fechas.
        $this->patchApplication($chief, $id, ['startsOn' => '2026-11-10', 'endsOn' => '2026-11-20']);
        $this->assertJsonApiError(403, 'FORBIDDEN');
        $this->patchApplication($worker, $id, ['startsOn' => '2026-11-10', 'endsOn' => '2026-11-20']);
        $this->assertResponseOk();
        $this->seeJson(['indefinite' => false, 'startsOn' => '2026-11-10', 'endsOn' => '2026-11-20']);
        $this->assertFalse($absences->isAbsent($worker->id, Carbon::create(2027, 5, 1)));
        $this->assertTrue($absences->isAbsent($worker->id, Carbon::create(2026, 11, 15)));

        // Con fechas ya no se pueden cambiar así.
        $this->patchApplication($worker, $id, ['startsOn' => '2026-12-01', 'endsOn' => '2026-12-02']);
        $this->assertJsonApiError(409, 'ABSENCE_NOT_INDEFINITE');
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
