<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Solicitud "No puedo entrar". El Administrador ve todos los datos; la
 * instalación que la pidió ve el estado y, si se aprobó, el usuario.
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

        if ($viewer && $viewer->isAdmin()) {
            return $attributes + [
                'entityAbbreviation' => $recovery->entity_abbreviation,
                'pass' => $recovery->pass,
                'phone' => $recovery->phone(),
                'matched' => $recovery->worker_id !== null,
                'resolvedAt' => $this->date($recovery->resolved_at),
            ];
        }

        if ($recovery->status === 'approved' && $recovery->forgot_username && $recovery->worker && $recovery->worker->user) {
            $attributes['username'] = $recovery->worker->user->username;
        }

        return $attributes;
    }

    public function toOneRelationships(): array
    {
        return [
            'worker' => ['workers', 'worker_id', 'worker'],
            'installation' => ['installations', 'installation_id', 'installation'],
            'resolvedBy' => ['users', 'resolved_by', 'resolver'],
        ];
    }
}
