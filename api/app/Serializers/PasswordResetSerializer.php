<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Solo la ve el Administrador (incluye el teléfono y el código).
 */
class PasswordResetSerializer extends Serializer
{
    public function type(): string
    {
        return 'password-resets';
    }

    public function attributes(Model $reset, Request $request): array
    {
        return [
            'status' => $reset->status,
            'phone' => $reset->phone(),
            'code' => $reset->code(),
            'failedAttempts' => $reset->failed_attempts,
            'expiresAt' => $this->date($reset->expires_at),
            'sentAt' => $this->date($reset->sent_at),
            'usedAt' => $this->date($reset->used_at),
            'createdAt' => $this->date($reset->created_at),
        ];
    }

    public function toOneRelationships(): array
    {
        return ['worker' => ['workers', 'worker_id', 'worker']];
    }
}
