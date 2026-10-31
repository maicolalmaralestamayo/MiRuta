<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class TripCompletionSerializer extends Serializer
{
    public function type(): string
    {
        return 'trip-completions';
    }

    public function attributes(Model $completion, Request $request): array
    {
        return [
            'role' => $completion->role,
            'createdAt' => $this->date($completion->created_at),
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'trip' => ['trips', 'trip_id', 'trip'],
            'user' => ['users', 'user_id', 'user'],
        ];
    }
}
