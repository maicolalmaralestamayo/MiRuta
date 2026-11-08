<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Conversation;
use App\Models\ConversationMessage;
use App\Models\ConversationTopic;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Conversaciones con el desarrollador (docs/11 §11.46 y §11.50): solo texto,
 * clasificadas por motivo. Las responde el Administrador; la respuesta llega
 * como notificación a quien abrió la conversación.
 */
class Conversations
{
    public function __construct(private Settings $settings, private Notifier $notifier)
    {
    }

    public function open(User $user, int $topicId, string $body): Conversation
    {
        $topic = ConversationTopic::find($topicId);

        if (! $topic || ! $topic->active) {
            throw new JsonApiException(422, 'TOPIC_INVALID', 'Motivo no válido', 'Elija un motivo de conversación activo.', ['pointer' => '/data/relationships/topic']);
        }

        return DB::transaction(function () use ($user, $topic, $body) {
            $conversation = Conversation::create([
                'user_id' => $user->id, 'conversation_topic_id' => $topic->id, 'last_message_at' => Carbon::now(),
                'unread_by_developer' => true, 'unread_by_user' => false,
            ]);
            $this->write($conversation, $user, $body);

            return $conversation;
        });
    }

    public function canSee(User $user, Conversation $conversation): bool
    {
        return $user->isAdmin() || (int) $conversation->user_id === (int) $user->id;
    }

    /**
     * Escribe un mensaje. Si lo escribe el Administrador en una conversación
     * ajena, es una respuesta del desarrollador.
     */
    public function write(Conversation $conversation, User $author, string $body): ConversationMessage
    {
        $body = trim($body);
        $max = $this->settings->int('longitud_mensaje');

        if ($body === '' || mb_strlen($body) > $max) {
            throw new JsonApiException(422, 'MESSAGE_INVALID', 'Mensaje no válido', "El mensaje debe tener entre 1 y {$max} caracteres.", ['pointer' => '/data/attributes/body']);
        }

        $fromDeveloper = (int) $conversation->user_id !== (int) $author->id;
        $message = ConversationMessage::create([
            'conversation_id' => $conversation->id, 'user_id' => $author->id, 'from_developer' => $fromDeveloper, 'body' => $body,
        ]);

        $conversation->forceFill([
            'last_message_at' => Carbon::now(),
            'unread_by_developer' => $fromDeveloper ? false : true,
            'unread_by_user' => $fromDeveloper ? true : $conversation->unread_by_user,
        ])->save();

        if ($fromDeveloper) {
            $this->notifier->send([(int) $conversation->user_id], Notifier::DEVELOPER_REPLY, 'Respuesta del desarrollador',
                mb_substr($body, 0, 200), ['conversationId' => (string) $conversation->id]);
        }

        return $message;
    }

    /**
     * Quien consulta los mensajes los da por leídos.
     */
    public function markRead(Conversation $conversation, User $reader): void
    {
        $column = (int) $conversation->user_id === (int) $reader->id ? 'unread_by_user' : 'unread_by_developer';

        if ($conversation->{$column}) {
            $conversation->forceFill([$column => false])->save();
        }
    }

    /**
     * Conversaciones sin leer por esa persona (y, si es Administrador, las que esperan respuesta).
     */
    public function unreadCount(User $user): int
    {
        $own = Conversation::where('user_id', $user->id)->where('unread_by_user', true)->count();

        return $user->isAdmin() ? $own + Conversation::where('user_id', '<>', $user->id)->where('unread_by_developer', true)->count() : $own;
    }

    /**
     * Borra las conversaciones sin mensajes desde hace «Conservación conversaciones».
     */
    public function purgeOld(): int
    {
        return Conversation::where('last_message_at', '<', Carbon::now()->subSeconds($this->settings->seconds('conservacion_conversaciones')))->delete();
    }
}
