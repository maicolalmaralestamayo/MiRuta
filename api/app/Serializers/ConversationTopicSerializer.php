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
        $role = $topic->role;

        return parent::attributes($topic, $request) + ['recipient' => $topic->recipient, 'roleName' => $role ? $role->name : null];
    }

    public function toOneRelationships(): array
    {
        return ['role' => ['roles', 'role_id', 'role']];
    }
}
