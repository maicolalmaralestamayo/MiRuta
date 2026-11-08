<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class ConversationMessageSerializer extends Serializer
{
    public function type(): string
    {
        return 'conversation-messages';
    }

    public function attributes(Model $message, Request $request): array
    {
        $viewer = $request->user();

        return [
            'body' => $message->body,
            'fromDeveloper' => (bool) $message->from_developer,
            // Burbuja propia (derecha) o ajena (izquierda).
            'mine' => $viewer !== null && (int) $message->user_id === (int) $viewer->id,
            'createdAt' => $this->date($message->created_at),
        ];
    }

    public function toOneRelationships(): array
    {
        return ['conversation' => ['conversations', 'conversation_id', 'conversation']];
    }
}
