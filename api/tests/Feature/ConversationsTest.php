<?php

namespace Tests\Feature;

use App\Models\Conversation;
use App\Models\ConversationTopic;
use App\Models\Notification;
use App\Services\Conversations;
use Carbon\Carbon;
use Tests\TestCase;

/**
 * Conversaciones con el desarrollador (docs/11 §11.46 y §11.50).
 */
class ConversationsTest extends TestCase
{
    public function test_conversacion_con_el_desarrollador_y_su_respuesta_notificada(): void
    {
        $admin = $this->createAdmin();
        $user = $this->createUser();
        $other = $this->createUser();
        $topic = ConversationTopic::create(['name' => 'Reportar un error']);
        $inactive = ConversationTopic::create(['name' => 'Viejo', 'active' => false]);

        $this->jsonApiAs($user, 'POST', '/api/v1/conversations', self::resource('conversations', ['body' => 'Hola'], ['topic' => ['conversation-topics', $inactive->id]]))
            ->assertStatus(422)->assertJsonPath('errors.0.code', 'TOPIC_INVALID');
        $id = $this->jsonApiAs($user, 'POST', '/api/v1/conversations', self::resource('conversations', ['body' => 'La app se cierra'], ['topic' => ['conversation-topics', $topic->id]]))
            ->assertCreated()->json('data.id');

        $this->jsonApiAs($admin, 'GET', '/api/v1/sync')->assertJsonPath('meta.counters.conversationsUnread', 1);
        $this->jsonApiAs($other, 'GET', "/api/v1/conversations/{$id}")->assertNotFound();

        $this->jsonApiAs($admin, 'POST', "/api/v1/conversations/{$id}/messages", self::resource('conversation-messages', ['body' => 'Lo reviso']))
            ->assertCreated()->assertJsonPath('data.attributes.fromDeveloper', true)->assertJsonPath('data.attributes.mine', true);
        $this->assertSame('respuesta_desarrollador', Notification::where('user_id', $user->id)->value('kind'));
        $this->jsonApiAs($admin, 'GET', '/api/v1/sync')->assertJsonPath('meta.counters.conversationsUnread', 0);

        $messages = $this->jsonApiAs($user, 'GET', "/api/v1/conversations/{$id}/messages")->assertOk()->json('data');
        $this->assertSame([true, false], array_column(array_column($messages, 'attributes'), 'mine'));
        $this->jsonApiAs($user, 'GET', "/api/v1/conversations/{$id}/messages?filter[after]=".$messages[0]['id'])->assertJsonCount(1, 'data');
        $this->jsonApiAs($user, 'GET', '/api/v1/sync')->assertJsonPath('meta.counters.conversationsUnread', 0);

        $this->jsonApiAs($user, 'POST', "/api/v1/conversations/{$id}/messages", self::resource('conversation-messages', ['body' => str_repeat('a', 1001)]))
            ->assertStatus(422)->assertJsonPath('errors.0.code', 'MESSAGE_INVALID');
    }

    public function test_se_borran_tras_su_conservacion(): void
    {
        $user = $this->createUser();
        $topic = ConversationTopic::create(['name' => 'Duda']);
        app(Conversations::class)->open($user, $topic->id, 'Una duda');

        Carbon::setTestNow(Carbon::now()->addDays(31));
        $this->assertSame(1, app(Conversations::class)->purgeOld());
        $this->assertSame(0, Conversation::count());
        Carbon::setTestNow();
    }
}
