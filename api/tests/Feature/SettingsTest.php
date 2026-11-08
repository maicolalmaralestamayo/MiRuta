<?php

namespace Tests\Feature;

use App\Services\Settings;
use Tests\TestCase;

class SettingsTest extends TestCase
{
    public function test_todos_leen_los_ajustes_con_su_valor_y_su_unidad_base(): void
    {
        $response = $this->jsonApiAs($this->createUser(), 'GET', '/api/v1/settings')->assertOk();
        $settings = collect($response->json('data'))->keyBy('id');

        $this->assertSame('Radio parada', $settings['radio_parada']['attributes']['name']);
        $this->assertSame('100m', $settings['radio_parada']['attributes']['value']);
        $this->assertSame(100, $settings['radio_parada']['attributes']['base']);
        $this->assertSame(600, $settings['anticipacion_viaje']['attributes']['base']);
        $this->assertSame(3, $settings['minimo_confirmaciones']['attributes']['base']);
        $this->assertEqualsWithDelta(2.7778, $settings['velocidad_humana']['attributes']['base'], 0.001);
        $this->assertSame('m/seg', $settings['velocidad_humana']['attributes']['baseUnit']);
        $this->assertSame(18000, $settings['plazo_eliminacion']['attributes']['base']);
        $this->assertSame('Generales', $settings['radio_parada']['attributes']['groupName']);
        $this->assertNotEmpty($response->json('meta.groups'));
    }

    public function test_solo_el_administrador_los_cambia_con_unidades_combinables(): void
    {
        $admin = $this->createAdmin();
        $this->jsonApiAs($this->createUser(), 'PATCH', '/api/v1/settings/espera_cierre', self::resource('settings', ['value' => '3hor'], [], 'espera_cierre'))
            ->assertForbidden();

        $this->jsonApiAs($admin, 'PATCH', '/api/v1/settings/espera_cierre', self::resource('settings', ['value' => '2hor 30min'], [], 'espera_cierre'))
            ->assertOk()->assertJsonPath('data.attributes.value', '2hor30min')->assertJsonPath('data.attributes.base', 9000);
        $this->assertSame(9000, app(Settings::class)->seconds('espera_cierre'));

        $this->jsonApiAs($admin, 'PATCH', '/api/v1/settings/distancia_abandono', self::resource('settings', ['value' => '1km200m']))
            ->assertOk()->assertJsonPath('data.attributes.base', 1200);

        // Volver al valor por omisión.
        $this->jsonApiAs($admin, 'PATCH', '/api/v1/settings/espera_cierre', self::resource('settings', ['value' => null]))
            ->assertOk()->assertJsonPath('data.attributes.value', '2hor');
    }

    public function test_valores_no_validos_o_fuera_de_rango(): void
    {
        $admin = $this->createAdmin();

        $this->jsonApiAs($admin, 'PATCH', '/api/v1/settings/radio_parada', self::resource('settings', ['value' => '100']))
            ->assertStatus(422)->assertJsonPath('errors.0.code', 'SETTING_INVALID');
        $this->jsonApiAs($admin, 'PATCH', '/api/v1/settings/radio_parada', self::resource('settings', ['value' => '10min']))
            ->assertStatus(422);
        $this->jsonApiAs($admin, 'PATCH', '/api/v1/settings/radio_parada', self::resource('settings', ['value' => '5km']))
            ->assertStatus(422)->assertJsonPath('errors.0.detail', 'El valor no puede ser mayor que 2km.');
        $this->jsonApiAs($admin, 'PATCH', '/api/v1/settings/minimo_confirmaciones', self::resource('settings', ['value' => 0]))
            ->assertStatus(422);
        $this->jsonApiAs($admin, 'PATCH', '/api/v1/settings/minimo_confirmaciones', self::resource('settings', ['value' => 5]))
            ->assertOk()->assertJsonPath('data.attributes.value', '5');
        $this->jsonApiAs($admin, 'PATCH', '/api/v1/settings/no_existe', self::resource('settings', ['value' => '1']))
            ->assertNotFound();
    }
}
