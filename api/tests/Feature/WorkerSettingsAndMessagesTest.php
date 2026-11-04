<?php

use App\Models\ConversationMessage;
use App\Models\ConversationTopic;
use App\Models\Role;
use App\Models\RolePermission;
use App\Models\Trip;
use App\Models\TripMessage;
use Carbon\Carbon;
use Laravel\Lumen\Testing\DatabaseMigrations;

/**
 * Ajustes de un trabajador (settings.worker) y borrar mensajes de otros
 * (chat.delete_messages).
 */
class WorkerSettingsAndMessagesTest extends TestCase
{
    use DatabaseMigrations;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
    }

    private function roleWith(string $name, array $permissions): Role
    {
        $this->role('Trabajador');
        $role = Role::create(['name' => $name, 'requestable' => false, 'is_default' => false, 'itinerary_scoped' => false]);

        foreach ($permissions as $operation => $scope) {
            RolePermission::create(['role_id' => $role->id, 'operation' => $operation, 'scope' => $scope]);
        }

        return $role;
    }

    public function testAjustesDeUnTrabajador()
    {
        $itinerary = $this->createItinerary();
        $worker = $this->joinItinerary($this->createWorker(), $itinerary);
        $outside = $this->createWorker();
        $manager = $this->joinItinerary($this->createWorker(), $itinerary);
        $this->assignRole($manager, $this->roleWith('Gestor de ajustes', ['settings.worker' => 'itinerary'])->name);
        $url = '/api/v1/users/'.$worker->user_id.'/settings';
        $patch = ['data' => ['type' => 'user-settings', 'id' => 'departure_notice_minutes_before', 'attributes' => ['value' => 30]]];

        $this->jsonApiAs($outside, 'GET', $url);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->jsonApiAs($manager, 'PATCH', $url.'/departure_notice_minutes_before', $patch);
        $this->assertResponseOk();
        $this->seeJson(['value' => '30', 'isCustom' => true]);

        $this->jsonApiAs($worker, 'GET', '/api/v1/me/settings');
        $this->seeJson(['value' => '30']);

        // Fuera de su itinerario, no.
        $this->jsonApiAs($manager, 'PATCH', '/api/v1/users/'.$outside->user_id.'/settings/departure_notice_minutes_before', $patch);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->jsonApiAs($this->createAdmin(), 'DELETE', $url.'/departure_notice_minutes_before');
        $this->assertResponseStatus(204);
    }

    public function testBorrarMensajesDeOtros()
    {
        Carbon::setTestNow(Carbon::create(2026, 11, 3, 12));
        $itinerary = $this->createItinerary();
        $trip = Trip::create([
            'itinerary_id' => $itinerary->id, 'vehicle_id' => $this->createVehicle()->id, 'driver_id' => $this->createDriver()->id,
            'departs_at' => Carbon::now()->addDay(), 'returns_at' => Carbon::now()->addDays(2), 'status' => Trip::STATUS_CONFIRMED,
            'created_by' => $this->createTransportChief()->user_id,
        ]);
        $author = $this->joinItinerary($this->createWorker(), $itinerary);
        $other = $this->joinItinerary($this->createWorker(), $itinerary);
        $moderator = $this->joinItinerary($this->createWorker(), $itinerary);
        $this->assignRole($moderator, $this->roleWith('Moderador', ['chat.delete_messages' => 'itinerary'])->name);

        $first = TripMessage::create(['trip_id' => $trip->id, 'user_id' => $author->user_id, 'body' => 'Hola']);
        $second = TripMessage::create(['trip_id' => $trip->id, 'user_id' => $author->user_id, 'body' => 'Algo feo']);

        $this->jsonApiAs($other, 'DELETE', '/api/v1/trip-messages/'.$first->id);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->jsonApiAs($author, 'DELETE', '/api/v1/trip-messages/'.$first->id);
        $this->assertResponseStatus(204);

        $this->jsonApiAs($moderator, 'DELETE', '/api/v1/trip-messages/'.$second->id);
        $this->assertResponseStatus(204);
        $this->assertSame(0, TripMessage::count());

        // Conversación dirigida al Jefe de itinerario.
        $chief = $this->createItineraryChief($itinerary);
        $topic = ConversationTopic::where('role_id', $this->role('Jefe de itinerario')->id)->first();
        $this->jsonApiAs($author, 'POST', '/api/v1/conversations', ['data' => ['type' => 'conversations', 'relationships' => [
            'topic' => ['data' => ['type' => 'conversation-topics', 'id' => (string) $topic->id]],
        ]]]);
        $conversationId = $this->responseJson()['data']['id'];
        $message = ConversationMessage::create(['conversation_id' => $conversationId, 'user_id' => $author->user_id, 'body' => 'Queja']);

        // El Jefe de itinerario de partida no tiene chat.delete_messages.
        $this->jsonApiAs($chief, 'DELETE', '/api/v1/conversation-messages/'.$message->id);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->jsonApiAs($this->createAdmin(), 'DELETE', '/api/v1/conversation-messages/'.$message->id);
        $this->assertResponseStatus(204);
        Carbon::setTestNow();
    }
}
