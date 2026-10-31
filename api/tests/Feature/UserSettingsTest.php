<?php

use App\Models\Setting;
use App\Models\SettingDefinition;
use Laravel\Lumen\Testing\DatabaseMigrations;

class UserSettingsTest extends TestCase
{
    use DatabaseMigrations;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
    }

    private function patchSetting($worker, string $key, $value)
    {
        return $this->jsonApiAs($worker, 'PATCH', '/api/v1/me/settings/'.$key, [
            'data' => ['type' => 'user-settings', 'id' => $key, 'attributes' => ['value' => $value]],
        ]);
    }

    private function setting(string $key): array
    {
        foreach ($this->responseJson()['data'] as $resource) {
            if ($resource['id'] === $key) {
                return $resource;
            }
        }

        $this->fail("No está el ajuste {$key}");
    }

    public function testListaSoloLosPersonalizables()
    {
        $worker = $this->createWorker();

        $this->jsonApiAs($worker, 'GET', '/api/v1/me/settings');

        $this->assertResponseOk();
        $keys = array_column($this->responseJson()['data'], 'id');
        $this->assertContains('departure_notice_minutes_before', $keys);
        $this->assertNotContains('child_max_age', $keys);
        $this->assertSame(['value' => '60', 'inheritedValue' => '60', 'isCustom' => false], $this->setting('departure_notice_minutes_before')['attributes']);
    }

    public function testPersonalizarYVolverAlValorGlobal()
    {
        $worker = $this->createWorker();

        $this->patchSetting($worker, 'departure_notice_minutes_before', 45);
        $this->assertResponseOk();
        $this->seeJson(['value' => '45', 'isCustom' => true]);

        $this->jsonApiAs($worker, 'DELETE', '/api/v1/me/settings/departure_notice_minutes_before');
        $this->assertResponseStatus(204);

        $this->jsonApiAs($worker, 'GET', '/api/v1/me/settings');
        $this->assertSame('60', $this->setting('departure_notice_minutes_before')['attributes']['value']);

        $this->patchSetting($worker, 'departure_notice_minutes_before', '50');
        $this->assertResponseOk();
        $this->seeJson(['value' => '50']);
    }

    /**
     * @dataProvider invalidValues
     */
    public function testValoresNoValidos(string $key, $value)
    {
        $this->patchSetting($this->createWorker(), $key, $value);

        $this->assertJsonApiError(422, 'SETTING_OUT_OF_RANGE', '/data/attributes/value');
    }

    public function invalidValues(): array
    {
        return [
            'entero fuera de rango' => ['departure_notice_minutes_before', 5000],
            'entero no numérico' => ['departure_notice_minutes_before', 'mucho'],
            'menor que el mínimo global' => ['trips_poll_background_minutes', 10],
            'hora mal formada' => ['departure_notice_fixed_time', '25:00'],
            'opción inexistente' => ['stop_notice_scope', 'algunas'],
            'booleano no válido' => ['tts_enabled', 'quizás'],
            'texto demasiado largo' => ['stop_notice_template', str_repeat('a', 501)],
        ];
    }

    public function testValoresValidosDeCadaTipo()
    {
        $worker = $this->createWorker();

        $this->patchSetting($worker, 'tts_enabled', false);
        $this->seeJson(['value' => '0']);
        $this->patchSetting($worker, 'departure_notice_fixed_time', '13:30');
        $this->seeJson(['value' => '13:30']);
        $this->patchSetting($worker, 'stop_notice_scope', 'all');
        $this->seeJson(['value' => 'all']);
        $this->patchSetting($worker, 'stop_notice_template', 'Pasó por {parada}');
        $this->seeJson(['value' => 'Pasó por {parada}']);
    }

    public function testNoSePuedenPersonalizarLosGlobales()
    {
        $this->patchSetting($this->createWorker(), 'child_max_age', 10);

        $this->assertJsonApiError(404, 'NOT_FOUND');
    }

    public function testElMinimoGlobalSubeElValorEfectivo()
    {
        $worker = $this->createWorker();
        $this->patchSetting($worker, 'trips_poll_background_minutes', 40);

        Setting::create([
            'setting_definition_id' => SettingDefinition::where('key', 'min_background_poll_minutes')->value('id'),
            'value' => '60',
        ]);

        $this->jsonApiAs($worker, 'GET', '/api/v1/me/settings');
        $this->assertSame('60', $this->setting('trips_poll_background_minutes')['attributes']['value']);
    }

    public function testDefinicionesConOpciones()
    {
        $this->jsonApiAs($this->createWorker(), 'GET', '/api/v1/setting-definitions/stop_notice_scope');

        $this->assertResponseOk();
        $attributes = $this->responseJson()['data']['attributes'];
        $this->assertSame('option', $attributes['valueType']);
        $this->assertCount(3, $attributes['options']);

        $this->jsonApiAs($this->createWorker(), 'GET', '/api/v1/setting-definitions/trips_poll_background_minutes');
        $this->assertSame('min_background_poll_minutes', $this->responseJson()['data']['attributes']['minSetting']);
    }
}
