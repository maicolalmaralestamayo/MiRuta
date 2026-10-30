<?php

namespace App\Serializers;

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
        $last = $conversation->messages()->max('created_at');

        return [
            'recipient' => $conversation->topic ? $conversation->topic->recipient : null,
            'createdAt' => $this->date($conversation->created_at),
            'lastMessageAt' => $last ? \Carbon\Carbon::parse($last)->toIso8601String() : null,
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'topic' => ['conversation-topics', 'conversation_topic_id', 'topic'],
            'openedBy' => ['workers', 'opened_by', 'opener'],
            'itinerary' => ['itineraries', 'itinerary_id', 'itinerary'],
        ];
    }

    public function meta(Model $conversation, Request $request): array
    {
        return ['messageCount' => $conversation->messages()->count()];
    }
}
