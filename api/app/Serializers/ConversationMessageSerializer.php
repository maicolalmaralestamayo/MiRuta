<?php

namespace App\Serializers;

class ConversationMessageSerializer extends MessageSerializer
{
    public function type(): string
    {
        return 'conversation-messages';
    }

    public function toOneRelationships(): array
    {
        return [
            'conversation' => ['conversations', 'conversation_id', 'conversation'],
            'author' => ['users', 'user_id', 'user'],
        ];
    }
}
