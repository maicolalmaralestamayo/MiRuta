<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Instalación de la app. Solo la ve el Administrador.
 */
class InstallationSerializer extends Serializer
{
    public function type(): string
    {
        return 'installations';
    }

    public function attributes(Model $installation, Request $request): array
    {
        return [
            'deviceModel' => $installation->device_model,
            'androidVersion' => $installation->android_version,
            'appVersionCode' => $installation->app_version_code,
            'blocked' => $installation->isBlocked(),
            'createdAt' => $this->date($installation->created_at),
        ];
    }

    public function toOneRelationships(): array
    {
        return ['user' => ['users', 'user_id', 'user']];
    }
}
