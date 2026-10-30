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
        $vehicle = Vehicle::create(['vehicle_type_id' => VehicleType::first()->id, 'plate' => 'B'.rand(1000, 9999), 'seats' => 10, 'standing_capacity' => 0]);

        return Trip::create([
            'itinerary_id' => $itinerary->id, 'vehicle_id' => $vehicle->id, 'driver_id' => $this->createDriver()->driverId(),
            'departs_at' => Carbon::now()->addDay(), 'returns_at' => Carbon::now()->addDays(2), 'status' => $status,
            'created_by' => $this->createTransportChief()->id,
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

        $this->jsonApiAs($member, 'GET', '/api/v1/trips/'.$trip->id.'/messages?include=worker');
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
        $chief = $this->createWorker();
        ItineraryChief::create(['itinerary_id' => $itinerary->id, 'worker_id' => $chief->id]);
        $otherChief = $this->createWorker();
        ItineraryChief::create(['itinerary_id' => $this->createItinerary('Ruta Oeste')->id, 'worker_id' => $otherChief->id]);
        $transportChief = $this->createTransportChief();
        $admin = $this->createAdmin();
        $member = $this->joinItinerary($this->createWorker(), $itinerary);
        $complaint = ConversationTopic::where('recipient', 'itinerary_chiefs')->where('name', 'Reportar una queja')->first();
        $idea = ConversationTopic::where('recipient', 'developer')->where('name', 'Dar ideas')->first();

        $this->jsonApiAs($member, 'POST', '/api/v1/conversations', ['data' => ['type' => 'conversations', 'relationships' => [
            'topic' => ['data' => ['type' => 'conversation-topics', 'id' => (string) $complaint->id]],
        ]]]);
        $this->assertResponseStatus(201);
        $this->seeJson(['recipient' => 'itinerary_chiefs']);
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
    }

    public function testCaducidadDeLasConversaciones()
    {
        $member = $this->createWorker();
        $topic = ConversationTopic::where('recipient', 'developer')->first();
        Carbon::setTestNow(Carbon::create(2026, 10, 1, 10));
        $old = Conversation::create(['conversation_topic_id' => $topic->id, 'opened_by' => $member->id]);
        ConversationMessage::create(['conversation_id' => $old->id, 'worker_id' => $member->id, 'body' => 'Viejo']);
        $active = Conversation::create(['conversation_topic_id' => $topic->id, 'opened_by' => $member->id]);

        Carbon::setTestNow(Carbon::create(2026, 10, 25, 10));
        ConversationMessage::create(['conversation_id' => $active->id, 'worker_id' => $member->id, 'body' => 'Reciente']);

        Carbon::setTestNow(Carbon::create(2026, 11, 2, 10));
        $this->artisan('chats:purge-expired');

        $this->assertTrue(Conversation::withTrashed()->find($old->id)->trashed());
        $this->assertSame(0, ConversationMessage::where('conversation_id', $old->id)->count());
        $this->assertFalse($active->fresh()->trashed());
    }
}
