<?php

namespace Tests\Feature;

use App\Models\AppVersion;
use App\Models\AppVersionFile;
use App\Models\RefreshToken;
use Illuminate\Http\UploadedFile;
use Tests\TestCase;

/**
 * Actualizaciones de la app y actualización obligatoria (docs/11 §11.54).
 */
class AppVersionsTest extends TestCase
{
    protected function tearDown(): void
    {
        foreach (AppVersionFile::pluck('apk_path') as $path) {
            @unlink(public_path($path));
        }

        parent::tearDown();
    }

    private function apk(string $content = "PK\x03\x04contenido"): UploadedFile
    {
        $path = tempnam(sys_get_temp_dir(), 'apk');
        file_put_contents($path, $content);

        return new UploadedFile($path, 'miruta.apk', 'application/vnd.android.package-archive', null, true);
    }

    private function publish($admin, int $code, bool $mandatory, ?array $files = null)
    {
        $files ??= ['apkArm64' => $this->apk("PK\x03\x04arm64"), 'apkArm32' => $this->apk("PK\x03\x04arm32")];

        return $this->call('POST', '/api/v1/app-versions', ['versionName' => '4.'.$code.'.0', 'versionCode' => $code, 'mandatory' => $mandatory ? '1' : '0'],
            [], $files, ['HTTP_ACCEPT' => 'application/vnd.api+json', 'HTTP_AUTHORIZATION' => 'Bearer '.$this->tokenFor($admin)]);
    }

    public function test_el_administrador_publica_los_apk_de_64_y_32_bits(): void
    {
        $admin = $this->createAdmin();

        $this->publish($this->createUser(), 2, false)->assertForbidden();
        $files = collect($this->publish($admin, 2, false)->assertCreated()->json('data.attributes.files'))->keyBy('abi');
        $this->assertStringEndsWith('.apk', $files['armeabi-v7a']['downloadUrl']);
        $this->assertFileExists(public_path(AppVersionFile::where('abi', 'arm64-v8a')->value('apk_path')));
        $this->publish($admin, 2, false)->assertStatus(422)->assertJsonPath('errors.0.code', 'VERSION_CODE_TOO_LOW');
        $this->publish($admin, 3, false, ['apkArm64' => $this->apk('no es un apk')])->assertStatus(422)->assertJsonPath('errors.0.code', 'APK_INVALID');

        // La versión se lee del propio APK cuando se puede.
        $path = tempnam(sys_get_temp_dir(), 'apk');
        copy(base_path('tests/fixtures/version-2.0.1.apk'), $path);
        $this->call('POST', '/api/v1/app-versions', ['notes' => 'Novedades'], [], ['apkUniversal' => new UploadedFile($path, 'v.apk', null, null, true)],
            ['HTTP_ACCEPT' => 'application/vnd.api+json', 'HTTP_AUTHORIZATION' => 'Bearer '.$this->tokenFor($admin)])
            ->assertCreated()->assertJsonPath('data.attributes.versionName', '2.0.1')->assertJsonPath('data.attributes.versionCode', 6);

        $this->jsonApi('GET', '/api/v1/app-versions/latest?filter[currentVersionCode]=1&filter[abis]=armeabi-v7a')
            ->assertOk()->assertJsonPath('meta.updateAvailable', true)->assertJsonPath('meta.file.abi', 'universal');

        $id = AppVersion::where('version_code', 2)->value('id');
        $this->jsonApiAs($admin, 'PATCH', "/api/v1/app-versions/{$id}", self::resource('app-versions', ['mandatory' => true]))
            ->assertOk()->assertJsonPath('data.attributes.mandatory', true);
    }

    public function test_actualizacion_obligatoria_cierra_la_sesion_y_bloquea_el_inicio_de_sesion(): void
    {
        $user = $this->createUser(['username' => 'pepe']);
        $token = $this->tokenFor($user);
        AppVersion::create(['version_name' => '4.1.0', 'version_code' => 41, 'mandatory' => true]);
        AppVersion::create(['version_name' => '4.2.0', 'version_code' => 42, 'mandatory' => false]);

        // Con la versión al día no pasa nada; sin cabecera, tampoco.
        $this->jsonApi('GET', '/api/v1/me', null, ['Authorization' => 'Bearer '.$token, 'X-App-Version' => '41'])->assertOk();
        $this->jsonApi('GET', '/api/v1/me', null, ['Authorization' => 'Bearer '.$token])->assertOk();

        // Con una versión anterior a la obligatoria: 426 y la sesión queda cerrada.
        $this->jsonApi('GET', '/api/v1/me', null, ['Authorization' => 'Bearer '.$token, 'X-App-Version' => '40'])
            ->assertStatus(426)->assertJsonPath('errors.0.code', 'APP_UPDATE_REQUIRED')
            ->assertJsonPath('errors.0.meta.mandatoryVersionCode', 41)->assertJsonPath('errors.0.meta.latestVersionCode', 42);
        $this->assertSame(0, RefreshToken::where('user_id', $user->id)->whereNull('revoked_at')->count());
        $this->jsonApi('GET', '/api/v1/me', null, ['Authorization' => 'Bearer '.$token, 'X-App-Version' => '41'])->assertStatus(401);

        // El inicio de sesión también se rechaza.
        $this->jsonApi('POST', '/api/v1/tokens', self::resource('tokens', ['username' => 'pepe', 'password' => self::PASSWORD]), ['X-App-Version' => '40'])
            ->assertStatus(426)->assertJsonPath('errors.0.code', 'APP_UPDATE_REQUIRED');

        // Se permiten: comprobar la versión, cerrar la sesión y «Olvidé algo».
        $this->jsonApi('GET', '/api/v1/app-versions/latest?filter[currentVersionCode]=40', null, ['X-App-Version' => '40'])
            ->assertOk()->assertJsonPath('meta.mandatory', true);
        $this->jsonApi('DELETE', '/api/v1/tokens/current', null, ['Authorization' => 'Bearer '.$this->tokenFor($user), 'X-App-Version' => '40'])->assertNoContent();
        $this->jsonApi('POST', '/api/v1/installations', self::resource('installations', ['deviceModel' => 'X']), ['X-App-Version' => '40'])->assertCreated();
    }
}
