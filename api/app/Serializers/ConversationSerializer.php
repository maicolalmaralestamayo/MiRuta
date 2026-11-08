<?php

namespace App\Serializers;

use App\Models\ConversationMessage;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class ConversationSerializer extends Serializer
{
    public function type(): string
    {
        return 'conversations';
    }

    public function attributes(Model $conversation, Request $request): array
    {
        $viewer = $request->user();
        $last = ConversationMessage::where('conversation_id', $conversation->id)->orderByDesc('id')->first();
        $isOwner = $viewer && (int) $viewer->id === (int) $conversation->user_id;

        return [
            'lastMessageAt' => $this->date($conversation->last_message_at),
            'lastMessage' => $last ? mb_substr($last->body, 0, 120) : null,
            // Sin leer por quien consulta (el dueño o el desarrollador).
            'unread' => $isOwner ? (bool) $conversation->unread_by_user : (bool) $conversation->unread_by_developer,
            'createdAt' => $this->date($conversation->created_at),
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'user' => ['users', 'user_id', 'user'],
            'topic' => ['conversation-topics', 'conversation_topic_id', 'topic'],
        ];
    }
}
