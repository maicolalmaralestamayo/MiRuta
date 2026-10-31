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

        $attributes = [
            'recipient' => $conversation->topic ? $conversation->topic->recipient : null,
            'guest' => $conversation->isGuest(),
            'closed' => $conversation->isClosed(),
            'createdAt' => $this->date($conversation->created_at),
            'lastMessageAt' => $last ? \Carbon\Carbon::parse($last)->toIso8601String() : null,
        ];

        if ($conversation->isGuest()) {
            $attributes['guestName'] = $conversation->guest_name;
            $viewer = $request->user();

            // El teléfono solo lo ve el Administrador.
            if ($viewer && $viewer->isAdmin()) {
                $attributes['guestPhone'] = $conversation->guest_phone_encrypted ? \Illuminate\Support\Facades\Crypt::decryptString($conversation->guest_phone_encrypted) : null;
            }
        }

        return $attributes;
    }

    public function toOneRelationships(): array
    {
        return [
            'topic' => ['conversation-topics', 'conversation_topic_id', 'topic'],
            'openedBy' => ['users', 'opened_by', 'opener'],
            'itinerary' => ['itineraries', 'itinerary_id', 'itinerary'],
            'entity' => ['entities', 'entity_id', 'entity'],
            'installation' => ['installations', 'installation_id', 'installation'],
        ];
    }

    public function meta(Model $conversation, Request $request): array
    {
        return ['messageCount' => $conversation->messages()->count()];
    }
}
