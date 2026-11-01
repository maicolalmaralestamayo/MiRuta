<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class NoticeSerializer extends Serializer
{
    public function type(): string
    {
        return 'notices';
    }

    public function attributes(Model $notice, Request $request): array
    {
        return [
            'type' => $notice->type,
            'message' => \App\Support\NoticeText::for($notice),
            'payload' => $notice->payload,
            'readAt' => $this->date($notice->read_at),
            'createdAt' => $this->date($notice->created_at),
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'application' => ['applications', 'application_id', 'application'],
            'trip' => ['trips', 'trip_id', 'trip'],
            'accessRecovery' => ['access-recoveries', 'access_recovery_id', 'accessRecovery'],
        ];
    }
}
