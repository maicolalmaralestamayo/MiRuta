<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Solicitud «Olvidé algo». Quien la gestiona ve todos los datos; la
 * instalación que la pidió ve el estado y, si se aprobó, lo que pidió
 * (usuario y contraseña propuesta).
 */
class AccessRecoverySerializer extends Serializer
{
    public function type(): string
    {
        return 'access-recoveries';
    }

    public function attributes(Model $recovery, Request $request): array
    {
        $attributes = [
            'forgotUsername' => $recovery->forgot_username,
            'forgotPassword' => $recovery->forgot_password,
            'status' => $recovery->status,
            'expiresAt' => $this->date($recovery->expires_at),
            'createdAt' => $this->date($recovery->created_at),
        ];

        $viewer = $request->user();
        $approved = $recovery->status === 'approved';
        // Solo lo que se pidió, mientras está aprobada (docs/11 §11.7).
        $granted = [];

        if ($approved && $recovery->forgot_username && $recovery->user) {
            $granted['username'] = $recovery->user->username;
        }

        if ($approved && $recovery->forgot_password && ($password = $recovery->proposedPassword())) {
            $granted['password'] = $password;
        }

        if ($viewer && app(\App\Services\Permissions::class)->can($viewer, 'access_recoveries.manage')) {
            return $attributes + [
                'identityCard' => $recovery->identityCard(),
                'phone' => $recovery->phone(),
                'matched' => $recovery->user_id !== null,
                'resolvedAt' => $this->date($recovery->resolved_at),
            ] + $granted;
        }

        return $attributes + $granted;
    }

    public function toOneRelationships(): array
    {
        return [
            'user' => ['users', 'user_id', 'user'],
            'installation' => ['installations', 'installation_id', 'installation'],
            'resolvedBy' => ['users', 'resolved_by', 'resolver'],
        ];
    }
}
