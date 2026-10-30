<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class ConversationTopicSerializer extends NomenclatorSerializer
{
    public function type(): string
    {
        return 'conversation-topics';
    }

    public function attributes(Model $topic, Request $request): array
    {
        return parent::attributes($topic, $request) + ['recipient' => $topic->recipient];
    }
}
