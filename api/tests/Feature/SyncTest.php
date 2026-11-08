<?php

namespace Tests\Feature;

use App\Models\AppVersion;
use App\Services\Notifier;
use Carbon\Carbon;
use Tests\TestCase;

/**
 * Sincronización: GET /sync con cursor (docs/11 §11.44 y §11.47).
 */
class SyncTest extends TestCase
{
    public function test_sin_cursor_solo_da_el_cursor_y_despues_las_novedades(): void
    {
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);
        $worker = $this->createWorker($entity, $itinerary, $itinerary->stopIds()[1]);
        app(Notifier::class)->send([$worker->user_id], Notifier::TRIP_CREATED, 'Antigua', 'No se devuelve');

        $first = $this->jsonApiAs($worker, 'GET', '/api/v1/sync')->assertOk()->assertJsonCount(0, 'data')->json('meta');
        $this->assertSame([], $first['changed']);
        $this->assertNull($first['nextTrip']);

        // Nada nuevo: respuesta casi vacía con el mismo cursor.
        $this->jsonApiAs($worker, 'GET', '/api/v1/sync?cursor='.$first['cursor'])->assertJsonCount(0, 'data')->assertJsonPath('meta.cursor', $first['cursor']);

        $tripId = $this->jsonApiAs($this->createAdmin(), 'POST', '/api/v1/trips', self::resource('trips', [
            'direction' => 'ida', 'date' => Carbon::today()->toDateString(), 'departureTime' => '23:59',
        ], ['itinerary' => ['itineraries', $itinerary->id], 'vehicleType' => ['vehicle-types', $this->vehicleType()->id]]))->json('data.id');

        $response = $this->jsonApiAs($worker, 'GET', '/api/v1/sync?cursor='.$first['cursor'])->assertOk()
            ->assertJsonCount(1, 'data')->assertJsonPath('data.0.attributes.kind', 'viaje_creado')
            ->assertJsonPath('data.0.attributes.data.tripId', $tripId)
            ->assertJsonPath('meta.changed', ['trips'])
            ->assertJsonPath('meta.nextTrip.id', $tripId)->assertJsonPath('meta.nextTrip.today', true);
        $this->assertNotSame($first['cursor'], $response->json('meta.cursor'));
        $this->assertStringContainsString('Viaje planificado', $response->json('data.0.attributes.title'));

        $this->jsonApiAs($worker, 'GET', '/api/v1/sync?cursor=abc')->assertStatus(400);
    }

    public function test_avisa_de_la_ultima_version_de_la_app(): void
    {
        $user = $this->createUser();
        AppVersion::create(['version_name' => '4.1.0', 'version_code' => 41, 'mandatory' => false]);

        $this->jsonApiAs($user, 'GET', '/api/v1/sync', null, ['X-App-Version' => '40'])
            ->assertJsonPath('meta.latestAppVersion.versionCode', 41)
            ->assertJsonPath('meta.latestAppVersion.updateAvailable', true)
            ->assertJsonPath('meta.latestAppVersion.mandatory', false);
    }
}
