<?php

use App\Models\Conversation;
use App\Models\ConversationMessage;
use App\Models\ConversationTopic;
use App\Models\ItineraryChief;
use App\Models\Trip;
use App\Models\TripMessage;
use App\Models\Vehicle;
use App\Models\VehicleType;
use Carbon\Carbon;
use Laravel\Lumen\Testing\DatabaseMigrations;

class ChatsTest extends TestCase
{
    use DatabaseMigrations;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function createTrip($itinerary, string $status = Trip::STATUS_CONFIRMED): Trip
    {
        $vehicle = $this->createVehicle(null, 10, 0);

        return Trip::create([
            'itinerary_id' => $itinerary->id, 'vehicle_id' => $vehicle->id, 'driver_id' => $this->createDriver()->id,
            'departs_at' => Carbon::now()->addDay(), 'returns_at' => Carbon::now()->addDays(2), 'status' => $status,
            'created_by' => $this->createTransportChief()->user_id,
        ]);
    }

    private function sendTripMessage($user, Trip $trip, string $body)
    {
        return $this->jsonApiAs($user, 'POST', '/api/v1/trip-messages', ['data' => ['type' => 'trip-messages',
            'attributes' => ['body' => $body],
            'relationships' => ['trip' => ['data' => ['type' => 'trips', 'id' => (string) $trip->id]]],
        ]]);
    }

    public function testChatDelViaje()
    {
        $itinerary = $this->createItinerary();
        $trip = $this->createTrip($itinerary);
        $member = $this->joinItinerary($this->createWorker(), $itinerary);
        $stranger = $this->createWorker();

        $this->sendTripMessage($member, $trip, 'Hoy voy con mi hijo');
        $this->assertResponseStatus(201);

        $this->sendTripMessage($stranger, $trip, 'Hola');
        $this->assertJsonApiError(404, 'NOT_FOUND');

        $this->jsonApiAs($member, 'GET', '/api/v1/trips/'.$trip->id.'/messages?include=author');
        $this->assertSame('Hoy voy con mi hijo', $this->responseJson()['data'][0]['attributes']['body']);

        // Desconfirmado: oculto, pero no se borra
        $trip->update(['status' => Trip::STATUS_UNCONFIRMED]);
        $this->jsonApiAs($member, 'GET', '/api/v1/trips/'.$trip->id.'/messages');
        $this->assertJsonApiError(409, 'CHAT_NOT_AVAILABLE');
        $this->assertSame(1, TripMessage::count());

        // Al cancelarse se borra
        $trip->update(['status' => Trip::STATUS_CONFIRMED]);
        $this->jsonApiAs($this->createTransportChief(), 'PATCH', '/api/v1/trips/'.$trip->id, ['data' => ['type' => 'trips', 'id' => (string) $trip->id, 'attributes' => ['status' => 'cancelled']]]);
        $this->assertResponseOk();
        $this->assertSame(0, TripMessage::count());
    }

    public function testLongitudMaximaDelMensaje()
    {
        $itinerary = $this->createItinerary();
        $trip = $this->createTrip($itinerary);

        $this->sendTripMessage($this->joinItinerary($this->createWorker(), $itinerary), $trip, str_repeat('a', 1001));

        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/body');
    }

    public function testConversacionesConMotivo()
    {
        $itinerary = $this->createItinerary();
        $chief = $this->createItineraryChief($itinerary);
        $otherChief = $this->createItineraryChief($this->createItinerary('Ruta Oeste'));
        $transportChief = $this->createTransportChief();
        $admin = $this->createAdmin();
        $member = $this->joinItinerary($this->createWorker(), $itinerary);
        $complaint = ConversationTopic::where('role_id', $this->role('Jefe de itinerario')->id)->where('name', 'Reportar una queja')->first();
        $idea = ConversationTopic::where('recipient', 'developer')->where('name', 'Dar ideas')->first();

        $this->jsonApiAs($member, 'POST', '/api/v1/conversations', ['data' => ['type' => 'conversations', 'relationships' => [
            'topic' => ['data' => ['type' => 'conversation-topics', 'id' => (string) $complaint->id]],
        ]]]);
        $this->assertResponseStatus(201);
        $this->seeJson(['recipient' => 'role']);
        $conversationId = $this->responseJson()['data']['id'];
        $this->assertSame((string) $itinerary->id, $this->responseJson()['data']['relationships']['itinerary']['data']['id']);

        $this->jsonApiAs($chief, 'POST', '/api/v1/conversation-messages', ['data' => ['type' => 'conversation-messages',
            'attributes' => ['body' => 'Lo reviso'],
            'relationships' => ['conversation' => ['data' => ['type' => 'conversations', 'id' => $conversationId]]],
        ]]);
        $this->assertResponseStatus(201);

        $this->jsonApiAs($otherChief, 'GET', '/api/v1/conversations/'.$conversationId);
        $this->assertJsonApiError(404, 'NOT_FOUND');
        $this->jsonApiAs($transportChief, 'GET', '/api/v1/conversations/'.$conversationId);
        $this->assertJsonApiError(404, 'NOT_FOUND');

        // Las de los Jefes de Transporte solo las ven los de esa Entidad.
        $toTransport = ConversationTopic::where('role_id', $this->role('Jefe de Transporte')->id)->first();
        $this->jsonApiAs($member, 'POST', '/api/v1/conversations', ['data' => ['type' => 'conversations', 'relationships' => [
            'topic' => ['data' => ['type' => 'conversation-topics', 'id' => (string) $toTransport->id]],
        ]]]);
        $transportConversation = $this->responseJson()['data']['id'];
        $this->jsonApiAs($transportChief, 'GET', '/api/v1/conversations/'.$transportConversation);
        $this->assertResponseOk();
        $this->jsonApiAs($this->createTransportChief([], $this->createEntity('OTRA')), 'GET', '/api/v1/conversations/'.$transportConversation);
        $this->assertJsonApiError(404, 'NOT_FOUND');

        $this->jsonApiAs($member, 'POST', '/api/v1/conversations', ['data' => ['type' => 'conversations', 'relationships' => [
            'topic' => ['data' => ['type' => 'conversation-topics', 'id' => (string) $idea->id]],
        ]]]);
        $ideaId = $this->responseJson()['data']['id'];

        $this->jsonApiAs($admin, 'GET', '/api/v1/conversations?filter[recipient]=developer');
        $this->assertSame([$ideaId], array_column($this->responseJson()['data'], 'id'));

        $this->jsonApiAs($member, 'GET', '/api/v1/conversations/'.$conversationId.'/messages');
        $this->assertSame('Lo reviso', $this->responseJson()['data'][0]['attributes']['body']);

        // Sin itinerario no se puede escribir a los Jefes de itinerario
        $this->jsonApiAs($this->createWorker(), 'POST', '/api/v1/conversations', ['data' => ['type' => 'conversations', 'relationships' => [
            'topic' => ['data' => ['type' => 'conversation-topics', 'id' => (string) $complaint->id]],
        ]]]);
        $this->assertJsonApiError(422, 'NO_ITINERARY');

        // Una cuenta sin Entidad sí puede escribir al desarrollador.
        $this->jsonApiAs($this->createUser(), 'POST', '/api/v1/conversations', ['data' => ['type' => 'conversations', 'relationships' => [
            'topic' => ['data' => ['type' => 'conversation-topics', 'id' => (string) $idea->id]],
        ]]]);
        $this->assertResponseStatus(201);
    }

    public function testCaducidadDeLasConversaciones()
    {
        $member = $this->createWorker();
        $topic = ConversationTopic::where('recipient', 'developer')->first();
        Carbon::setTestNow(Carbon::create(2026, 10, 1, 10));
        $old = Conversation::create(['conversation_topic_id' => $topic->id, 'opened_by' => $member->user_id]);
        ConversationMessage::create(['conversation_id' => $old->id, 'user_id' => $member->user_id, 'body' => 'Viejo']);
        $active = Conversation::create(['conversation_topic_id' => $topic->id, 'opened_by' => $member->user_id]);

        Carbon::setTestNow(Carbon::create(2026, 10, 25, 10));
        ConversationMessage::create(['conversation_id' => $active->id, 'user_id' => $member->user_id, 'body' => 'Reciente']);

        Carbon::setTestNow(Carbon::create(2026, 11, 2, 10));
        $this->artisan('chats:purge-expired');

        $this->assertTrue(Conversation::withTrashed()->find($old->id)->trashed());
        $this->assertSame(0, ConversationMessage::where('conversation_id', $old->id)->count());
        $this->assertFalse($active->fresh()->trashed());
    }

    public function testCaducidadPropiaDeLasConversacionesSinCuentaYDeLosAvisosLeidos()
    {
        $member = $this->createWorker();
        $topic = ConversationTopic::where('recipient', 'developer')->first();
        $installation = \App\Models\Installation::create(['secret_hash' => str_repeat('a', 64)]);
        \App\Models\Setting::create(['setting_definition_id' => \App\Models\SettingDefinition::where('key', 'guest_conversation_retention_days')->value('id'), 'value' => '60']);

        Carbon::setTestNow(Carbon::create(2026, 10, 1, 10));
        $guest = Conversation::create(['conversation_topic_id' => $topic->id, 'installation_id' => $installation->id, 'guest_name' => 'Ana']);
        $own = Conversation::create(['conversation_topic_id' => $topic->id, 'opened_by' => $member->user_id]);
        $read = \App\Models\Notice::create(['user_id' => $member->user_id, 'type' => 'application_resolved', 'read_at' => Carbon::now()]);
        $unread = \App\Models\Notice::create(['user_id' => $member->user_id, 'type' => 'application_resolved']);

        Carbon::setTestNow(Carbon::create(2026, 11, 2, 10));
        $this->artisan('chats:purge-expired');
        $this->assertFalse($guest->fresh()->trashed(), 'sin cuenta caduca a los 60 días');
        $this->assertTrue(Conversation::withTrashed()->find($own->id)->trashed(), 'con cuenta, a los 30');

        Carbon::setTestNow(Carbon::create(2027, 1, 5, 10));
        $this->artisan('chats:purge-expired');
        $this->assertTrue(Conversation::withTrashed()->find($guest->id)->trashed());
        $this->assertTrue(\App\Models\Notice::withTrashed()->find($read->id)->trashed(), 'leído hace más de 90 días');
        $this->assertFalse($unread->fresh()->trashed(), 'los no leídos no se borran');
    }
}
