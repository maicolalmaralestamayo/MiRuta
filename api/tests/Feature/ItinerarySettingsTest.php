<?php

use App\Models\EntitySetting;
use App\Models\SettingDefinition;
use App\Services\Settings;
use Laravel\Lumen\Testing\DatabaseMigrations;

/**
 * Ajustes por itinerario y por parada (docs/11 §11.17): gana el más
 * concreto, usuario → parada → itinerario → Entidad → app.
 */
class ItinerarySettingsTest extends TestCase
{
    use DatabaseMigrations;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
    }

    private function patchSetting($who, string $resource, string $filter, string $key, $value)
    {
        return $this->jsonApiAs($who, 'PATCH', "/api/v1/{$resource}/{$key}?{$filter}", ['data' => [
            'type' => $resource, 'id' => $key, 'attributes' => ['value' => $value],
        ]]);
    }

    public function testResolucionDelMasConcreto()
    {
        $itinerary = $this->createItinerary();
        $other = $this->createItinerary('Ruta Oeste');
        $stop = $itinerary->stops[1];
        $itineraryStop = $itinerary->itineraryStops()->where('stop_id', $stop->id)->first();
        $admin = $this->createAdmin();
        $settings = function () {
            return app(Settings::class);
        };
        $entityId = $this->defaultEntity()->id;

        $this->assertSame(15, $settings()->int('stop_min_dwell_seconds', null, $entityId, $itinerary->id, $stop->id));

        EntitySetting::create(['entity_id' => $entityId, 'setting_definition_id' => SettingDefinition::where('key', 'stop_min_dwell_seconds')->value('id'), 'value' => '20']);
        $this->assertSame(20, $settings()->int('stop_min_dwell_seconds', null, $entityId, $itinerary->id, $stop->id));

        $this->patchSetting($admin, 'itinerary-settings', 'filter[itinerary]='.$itinerary->id, 'stop_min_dwell_seconds', 25);
        $this->assertResponseOk();
        $this->seeJson(['value' => '25', 'inheritedValue' => '20', 'isCustom' => true, 'editable' => true]);
        $this->assertSame(25, $settings()->int('stop_min_dwell_seconds', null, $entityId, $itinerary->id, $stop->id));
        $this->assertSame(20, $settings()->int('stop_min_dwell_seconds', null, $entityId, $other->id));

        $this->patchSetting($admin, 'itinerary-stop-settings', 'filter[itineraryStop]='.$itineraryStop->id, 'stop_min_dwell_seconds', 30);
        $this->assertResponseOk();
        $this->seeJson(['value' => '30', 'inheritedValue' => '25']);
        $this->assertSame(30, $settings()->int('stop_min_dwell_seconds', null, null, $itinerary->id, $stop->id));
        $this->assertSame(25, $settings()->int('stop_min_dwell_seconds', null, null, $itinerary->id, $itinerary->stops[0]->id));

        // Quitar el de la parada vuelve al del itinerario.
        $this->jsonApiAs($admin, 'DELETE', '/api/v1/itinerary-stop-settings/stop_min_dwell_seconds?filter[itineraryStop]='.$itineraryStop->id);
        $this->assertResponseStatus(204);
        $this->assertSame(25, $settings()->int('stop_min_dwell_seconds', null, null, $itinerary->id, $stop->id));

        $this->jsonApiAs($admin, 'DELETE', '/api/v1/itinerary-settings/stop_min_dwell_seconds?filter[itinerary]='.$itinerary->id);
        $this->assertResponseStatus(204);
        $this->assertSame(20, $settings()->int('stop_min_dwell_seconds', null, null, $itinerary->id, $stop->id));
    }

    public function testListaYAjustesQueNoSonDeEseNivel()
    {
        $itinerary = $this->createItinerary();
        $member = $this->joinItinerary($this->createWorker(), $itinerary);
        $admin = $this->createAdmin();

        $this->jsonApiAs($member, 'GET', '/api/v1/itinerary-settings?filter[itinerary]='.$itinerary->id);
        $this->assertResponseOk();
        $keys = array_column($this->responseJson()['data'], 'id');
        $this->assertContains('trip_delay_tolerance_minutes', $keys);
        $this->assertContains('route_deviation_m', $keys);
        $this->assertNotContains('child_max_age', $keys);
        $this->assertFalse($this->responseJson()['data'][0]['attributes']['editable']);

        $this->jsonApiAs($member, 'GET', '/api/v1/itinerary-stop-settings?filter[itineraryStop]='.$itinerary->itineraryStops()->value('id'));
        $this->assertEqualsCanonicalizing(['stop_min_dwell_seconds', 'stop_pass_speed_kmh'], array_column($this->responseJson()['data'], 'id'));

        $this->patchSetting($admin, 'itinerary-settings', 'filter[itinerary]='.$itinerary->id, 'child_max_age', 10);
        $this->assertJsonApiError(404, 'NOT_FOUND');

        $this->patchSetting($admin, 'itinerary-settings', 'filter[itinerary]='.$itinerary->id, 'route_deviation_m', 10);
        $this->assertJsonApiError(422, 'SETTING_OUT_OF_RANGE');

        // Sin pertenecer a la Entidad no se ve.
        $this->jsonApiAs($this->createWorker([], $this->createEntity('OTRA')), 'GET', '/api/v1/itinerary-settings?filter[itinerary]='.$itinerary->id);
        $this->assertJsonApiError(404, 'NOT_FOUND');
    }

    public function testQuienLosCambia()
    {
        $itinerary = $this->createItinerary();
        $chief = $this->createItineraryChief($itinerary);

        // De partida, el Jefe de itinerario no tiene settings.itinerary.
        $this->patchSetting($chief, 'itinerary-settings', 'filter[itinerary]='.$itinerary->id, 'trip_delay_tolerance_minutes', 10);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->role('Jefe de itinerario')->permissions()->create(['operation' => 'settings.itinerary', 'scope' => 'itinerary']);
        $this->patchSetting($chief, 'itinerary-settings', 'filter[itinerary]='.$itinerary->id, 'trip_delay_tolerance_minutes', 10);
        $this->assertResponseOk();

        // En otro itinerario, no.
        $other = $this->createItinerary('Ruta Oeste');
        $this->patchSetting($chief, 'itinerary-settings', 'filter[itinerary]='.$other->id, 'trip_delay_tolerance_minutes', 10);
        $this->assertJsonApiError(403, 'FORBIDDEN');
    }

    public function testLosAjustesDeLaEntidadLosCambiaQuienTieneSettingsEntity()
    {
        $transportChief = $this->createTransportChief();
        $document = ['data' => ['type' => 'entity-settings', 'id' => 'child_max_age', 'attributes' => ['value' => 12]]];

        // De partida solo el Administrador (docs/11 §11.15).
        $this->jsonApiAs($transportChief, 'PATCH', '/api/v1/entity-settings/child_max_age', $document);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->jsonApiAs($this->createAdmin(), 'PATCH', '/api/v1/entity-settings/child_max_age?filter[entity]='.$this->defaultEntity()->id, $document);
        $this->assertResponseOk();
    }
}
