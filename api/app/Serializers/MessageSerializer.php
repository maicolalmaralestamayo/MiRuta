<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

abstract class MessageSerializer extends Serializer
{
    public function attributes(Model $message, Request $request): array
    {
        return [
            'body' => $message->body,
            'createdAt' => $this->date($message->created_at),
        ];
    }
}
