<?php

namespace App\Serializers;

use App\Services\Passwords;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Cuenta. El usuario y los datos de la contraseña solo los ven la propia
 * cuenta y el Administrador.
 */
class UserSerializer extends Serializer
{
    public function type(): string
    {
        return 'users';
    }

    public function attributes(Model $user, Request $request): array
    {
        $attributes = [
            'firstName' => $user->first_name,
            'middleName' => $user->middle_name,
            'firstSurname' => $user->first_surname,
            'secondSurname' => $user->second_surname,
            'fullName' => $user->fullName(),
            'photoUrl' => $user->photo_path ? url($user->photo_path) : null,
            'isAdmin' => $user->is_admin,
            'active' => ! $user->trashed(),
        ];

        if (self::isSelfOrAdmin($user, $request)) {
            $passwords = app(Passwords::class);
            $expiresAt = $passwords->expiresAt($user);
            $attributes = [
                'username' => $user->username,
                'activated' => $user->isActivated(),
            ] + $attributes + [
                'mustChangePassword' => $passwords->mustChange($user),
                // Si caducó hay que dar la actual; tras recuperar el acceso, no.
                'currentPasswordRequired' => ! $user->must_change_password,
                'passwordExpiresAt' => $expiresAt ? $expiresAt->toIso8601String() : null,
                'createdAt' => $this->date($user->created_at),
            ];
        }

        if ($request->user() && $request->user()->isAdmin()) {
            $attributes['appVersionCode'] = $user->app_version_code;
        }

        return $attributes;
    }

    public function toOneRelationships(): array
    {
        return ['worker' => ['workers', null, 'worker']];
    }

    public static function isSelfOrAdmin(Model $user, Request $request): bool
    {
        $viewer = $request->user();

        return $viewer && ($viewer->isAdmin() || (int) $viewer->id === (int) $user->id);
    }
}
