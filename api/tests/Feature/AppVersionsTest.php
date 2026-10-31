<?php

use App\Models\AppVersion;
use App\Models\AppVersionFile;
use Illuminate\Http\UploadedFile;
use Laravel\Lumen\Testing\DatabaseMigrations;

class AppVersionsTest extends TestCase
{
    use DatabaseMigrations;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
    }

    private function apk(string $content = "PK\x03\x04contenido"): UploadedFile
    {
        $path = tempnam(sys_get_temp_dir(), 'apk');
        file_put_contents($path, $content);

        return new UploadedFile($path, 'mitransporte.apk', 'application/vnd.android.package-archive', null, true);
    }

    /**
     * @param array $files [campo => UploadedFile]; por defecto 64 y 32 bits
     */
    private function publish($user, int $code, bool $mandatory = false, ?array $files = null)
    {
        $files = $files === null ? ['apkArm64' => $this->apk("PK\x03\x04arm64"), 'apkArm32' => $this->apk("PK\x03\x04arm32")] : $files;
        $this->call('POST', '/api/v1/app-versions', [
            'versionName' => "1.{$code}.0", 'versionCode' => (string) $code, 'notes' => 'Novedades', 'mandatory' => $mandatory ? '1' : '0',
        ], [], $files, [
            'HTTP_AUTHORIZATION' => 'Bearer '.$this->accessTokenFor($user),
            'HTTP_ACCEPT' => 'application/vnd.api+json',
            'CONTENT_TYPE' => 'multipart/form-data; boundary=x',
        ]);

        return $this;
    }

    public function testSoloElAdministradorPublicaUnApkPorProcesador()
    {
        $this->publish($this->createTransportChief(), 2);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->publish($this->createAdmin(), 2);
        $this->assertResponseStatus(201);
        $attributes = $this->responseJson()['data']['attributes'];
        $this->assertSame(2, $attributes['versionCode']);
        $files = collect($attributes['files'])->keyBy('abi');
        $this->assertSame(['arm64-v8a', 'armeabi-v7a'], $files->keys()->sort()->values()->all());
        $this->assertSame(hash('sha256', "PK\x03\x04arm64"), $files['arm64-v8a']['sha256']);
        $this->assertStringEndsWith('.apk', $files['armeabi-v7a']['downloadUrl']);
        $this->assertFileExists(base_path('public/'.AppVersionFile::first()->apk_path));
    }

    public function testValidaciones()
    {
        $admin = $this->createAdmin();

        $this->publish($admin, 2, false, ['apkArm64' => $this->apk('no es un apk')]);
        $this->assertJsonApiError(422, 'APK_INVALID', '/apkArm64');

        $this->publish($admin, 2, false, []);
        $this->assertJsonApiError(422, 'APK_REQUIRED');

        $this->publish($admin, 5);
        $this->publish($admin, 5);
        $this->assertJsonApiError(422, 'VERSION_CODE_TOO_LOW');
    }

    public function testUltimaVersionPublicaYObligatoriedad()
    {
        $admin = $this->createAdmin();

        $this->jsonApi('GET', '/api/v1/app-versions/latest?filter[currentVersionCode]=1');
        $this->assertResponseOk();
        $this->assertNull($this->responseJson()['data']);
        $this->assertFalse($this->responseJson()['meta']['updateAvailable']);

        $this->publish($admin, 2, true);
        $this->publish($admin, 3, false);

        $this->jsonApi('GET', '/api/v1/app-versions/latest?filter[currentVersionCode]=1');
        $this->assertSame(3, $this->responseJson()['data']['attributes']['versionCode']);
        $this->assertSame(['updateAvailable' => true, 'mandatory' => true], $this->responseJson()['meta']);

        $this->jsonApi('GET', '/api/v1/app-versions/latest?filter[currentVersionCode]=2');
        $this->assertSame(['updateAvailable' => true, 'mandatory' => false], $this->responseJson()['meta']);

        $this->jsonApi('GET', '/api/v1/app-versions/latest?filter[currentVersionCode]=3');
        $this->assertSame(['updateAvailable' => false, 'mandatory' => false], $this->responseJson()['meta']);
    }

    public function testCadaTelefonoRecibeSuApk()
    {
        $admin = $this->createAdmin();
        $this->publish($admin, 2);

        // Un teléfono de 64 bits prefiere el suyo.
        $this->jsonApi('GET', '/api/v1/app-versions/latest?filter[abis]=arm64-v8a,armeabi-v7a');
        $this->assertSame('arm64-v8a', $this->responseJson()['meta']['file']['abi']);
        $this->assertSame(hash('sha256', "PK\x03\x04arm64"), $this->responseJson()['meta']['file']['sha256']);

        // Uno con Android de 32 bits recibe el de 32.
        $this->jsonApi('GET', '/api/v1/app-versions/latest?filter[abis]=armeabi-v7a,armeabi');
        $this->assertSame('armeabi-v7a', $this->responseJson()['meta']['file']['abi']);

        // Uno que no admite ninguno no recibe nada.
        $this->jsonApi('GET', '/api/v1/app-versions/latest?filter[abis]=x86_64');
        $this->assertNull($this->responseJson()['meta']['file']);

        // Con un solo APK, todos reciben ese.
        $this->publish($admin, 3, false, ['apkArm64' => $this->apk()]);
        $this->jsonApi('GET', '/api/v1/app-versions/latest?filter[abis]=armeabi-v7a');
        $this->assertSame('arm64-v8a', $this->responseJson()['meta']['file']['abi']);

        // El universal sirve para cualquiera.
        $this->publish($admin, 4, false, ['apkArm64' => $this->apk(), 'apkUniversal' => $this->apk()]);
        $this->jsonApi('GET', '/api/v1/app-versions/latest?filter[abis]=armeabi-v7a');
        $this->assertSame('universal', $this->responseJson()['meta']['file']['abi']);
    }

    public function testVersionInstaladaYRetirada()
    {
        $admin = $this->createAdmin();
        $worker = $this->createWorker();
        $this->publish($admin, 2);
        $id = $this->responseJson()['data']['id'];

        $this->jsonApiAs($worker, 'GET', '/api/v1/me', null, ['X-App-Version-Code' => '2']);
        $this->assertSame(2, (int) $this->userOf($worker)->fresh()->app_version_code);

        $this->jsonApiAs($admin, 'GET', '/api/v1/app-versions');
        $this->assertSame(1, $this->responseJson()['data'][0]['meta']['installedCount']);

        $this->jsonApiAs($worker, 'GET', '/api/v1/app-versions');
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $paths = AppVersionFile::pluck('apk_path')->all();
        $this->jsonApiAs($admin, 'DELETE', '/api/v1/app-versions/'.$id);
        $this->assertResponseStatus(204);

        foreach ($paths as $path) {
            $this->assertFileNotExists(base_path('public/'.$path));
        }

        $this->jsonApi('GET', '/api/v1/app-versions/latest');
        $this->assertNull($this->responseJson()['data']);
    }
}
