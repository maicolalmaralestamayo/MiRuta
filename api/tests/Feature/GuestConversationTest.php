<?php

use App\Models\Conversation;
use App\Models\ConversationTopic;
use Laravel\Lumen\Testing\DatabaseMigrations;

/**
 * Hablar con el desarrollador sin cuenta (docs/08-version-2.md §8.7).
 */
class GuestConversationTest extends TestCase
{
    use DatabaseMigrations;

    private $header;
    private $topic;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
        $this->header = $this->jsonApi('POST', '/api/v1/installations', ['data' => ['type' => 'installations', 'attributes' => ['deviceModel' => 'Moto G', 'androidVersion' => '11']]])
            ->responseJson()['data']['meta']['header'];
        $this->topic = ConversationTopic::where('recipient', 'developer')->first();
    }

    private function open(array $attributes = [], ?ConversationTopic $topic = null)
    {
        return $this->jsonApi('POST', '/api/v1/guest/conversations', ['data' => [
            'type' => 'conversations',
            'attributes' => array_merge(['guestName' => 'María', 'guestPhone' => '+53 5 123 4567', 'body' => 'No me acuerdo de mi usuario'], $attributes),
            'relationships' => ['topic' => ['data' => ['type' => 'conversation-topics', 'id' => (string) ($topic ?: $this->topic)->id]]],
        ]], ['X-Installation' => $this->header]);
    }

    public function testConversacionCompleta()
    {
        $admin = $this->createAdmin();
        $id = $this->open()->responseJson()['data']['id'];
        $this->assertResponseStatus(201);
        $this->seeJson(['guest' => true, 'guestName' => 'María']);
        $this->assertArrayNotHasKey('guestPhone', $this->responseJson()['data']['attributes']);

        // El Administrador la ve con el teléfono y los datos del teléfono.
        $this->jsonApiAs($admin, 'GET', '/api/v1/conversations?include=installation');
        $json = $this->responseJson();
        $this->assertSame($id, $json['data'][0]['id']);
        $this->assertSame('+53 5 123 4567', $json['data'][0]['attributes']['guestPhone']);
        $this->assertSame('Moto G', $json['included'][0]['attributes']['deviceModel']);

        $this->jsonApiAs($admin, 'POST', '/api/v1/conversation-messages', ['data' => ['type' => 'conversation-messages',
            'attributes' => ['body' => 'Tu usuario empieza por "ma"'],
            'relationships' => ['conversation' => ['data' => ['type' => 'conversations', 'id' => $id]]]]]);
        $this->assertResponseStatus(201);

        $this->jsonApi('GET', "/api/v1/guest/conversations/{$id}/messages", null, ['X-Installation' => $this->header]);
        $this->assertSame(['No me acuerdo de mi usuario', 'Tu usuario empieza por "ma"'], array_column(array_column($this->responseJson()['data'], 'attributes'), 'body'));

        $this->jsonApi('POST', "/api/v1/guest/conversations/{$id}/messages", ['data' => ['type' => 'conversation-messages', 'attributes' => ['body' => 'Gracias']]], ['X-Installation' => $this->header]);
        $this->assertResponseStatus(201);

        // Un trabajador cualquiera no la ve.
        $this->jsonApiAs($this->createWorker(), 'GET', '/api/v1/conversations/'.$id);
        $this->assertResponseStatus(404);
    }

    public function testSoloAlDesarrollador()
    {
        $this->open([], ConversationTopic::where('recipient', 'transport_chiefs')->first());

        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/relationships/topic');
    }

    public function testOtraInstalacionNoLaVe()
    {
        $id = $this->open()->responseJson()['data']['id'];
        $other = $this->jsonApi('POST', '/api/v1/installations', ['data' => ['type' => 'installations']])->responseJson()['data']['meta']['header'];

        $this->jsonApi('GET', "/api/v1/guest/conversations/{$id}/messages", null, ['X-Installation' => $other]);
        $this->assertJsonApiError(404, 'NOT_FOUND');

        $this->jsonApi('GET', '/api/v1/guest/conversations', null, ['X-Installation' => $other]);
        $this->assertSame([], $this->responseJson()['data']);
    }

    public function testLimiteDeMensajesPorHora()
    {
        $id = $this->open()->responseJson()['data']['id'];

        for ($i = 1; $i < 10; $i++) {
            $this->jsonApi('POST', "/api/v1/guest/conversations/{$id}/messages", ['data' => ['type' => 'conversation-messages', 'attributes' => ['body' => 'Mensaje '.$i]]], ['X-Installation' => $this->header]);
            $this->assertResponseStatus(201);
        }

        $this->jsonApi('POST', "/api/v1/guest/conversations/{$id}/messages", ['data' => ['type' => 'conversation-messages', 'attributes' => ['body' => 'Otro']]], ['X-Installation' => $this->header]);
        $this->assertJsonApiError(429, 'TOO_MANY_REQUESTS');
    }

    public function testConversacionCerradaYBloqueo()
    {
        $admin = $this->createAdmin();
        $id = $this->open()->responseJson()['data']['id'];

        $this->jsonApiAs($admin, 'PATCH', '/api/v1/conversations/'.$id, ['data' => ['type' => 'conversations', 'attributes' => ['closed' => true]]]);
        $this->assertResponseOk();
        $this->seeJson(['closed' => true]);

        $this->jsonApi('POST', "/api/v1/guest/conversations/{$id}/messages", ['data' => ['type' => 'conversation-messages', 'attributes' => ['body' => 'Hola']]], ['X-Installation' => $this->header]);
        $this->assertJsonApiError(409, 'CONVERSATION_CLOSED');

        $installation = Conversation::find($id)->installation_id;
        $this->jsonApiAs($admin, 'PATCH', '/api/v1/installations/'.$installation, ['data' => ['type' => 'installations', 'attributes' => ['blocked' => true]]]);
        $this->open();
        $this->assertJsonApiError(403, 'INSTALLATION_BLOCKED');

        // Puede seguir leyendo.
        $this->jsonApi('GET', '/api/v1/guest/conversations', null, ['X-Installation' => $this->header]);
        $this->assertResponseOk();
    }

    public function testLosMotivosSonPublicos()
    {
        $this->jsonApi('GET', '/api/v1/conversation-topics?filter[recipient]=developer');

        $this->assertResponseOk();
    }
}
