<?php

namespace App\Serializers;

use App\Models\Worker;
use App\Services\Access;
use App\Services\Passwords;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Persona. El correo electrónico (y la fecha de nacimiento) solo los ven ella
 * misma, el Administrador y el Jefe de itinerario de sus miembros y
 * solicitantes (docs/11 §11.2 y §11.67).
 */
class UserSerializer extends Serializer
{
    public function type(): string
    {
        return 'users';
    }

    public function attributes(Model $user, Request $request): array
    {
        $access = app(Access::class);
        $viewer = $request->user();
        $attributes = [
            'firstName' => $user->first_name,
            'middleName' => $user->middle_name,
            'firstSurname' => $user->first_surname,
            'secondSurname' => $user->second_surname,
            'fullName' => $user->fullName(),
            'sex' => $user->sex,
            'photoUrl' => $this->image($user->photo_path),
            'isAdmin' => (bool) $user->is_admin,
            // Línea 2 de la tarjeta: abreviaturas de sus Entidades (vacía = «Sin Entidad»).
            'entities' => self::entityAbbreviations($user),
        ];

        if ($access->canSeeEmail($viewer, $user)) {
            $attributes['email'] = $user->email;
            $attributes['birthDate'] = $this->day($user->birth_date);
        }

        if ($viewer && ($access->isAdmin($viewer) || (int) $viewer->id === (int) $user->id)) {
            $passwords = app(Passwords::class);
            $expiresAt = $passwords->expiresAt($user);
            $attributes = ['username' => $user->username] + $attributes + [
                'mustChangePassword' => $passwords->mustChange($user),
                // Si caducó hay que dar la actual; si la puso otra persona, no.
                'currentPasswordRequired' => ! $user->must_change_password,
                'passwordExpiresAt' => $expiresAt?->toIso8601String(),
                'appVersionCode' => $user->app_version_code,
                'createdAt' => $this->date($user->created_at),
            ];
        }

        return $attributes;
    }

    /** @return string[] */
    public static function entityAbbreviations(Model $user): array
    {
        return Worker::where('workers.user_id', $user->id)
            ->join('entities', 'entities.id', '=', 'workers.entity_id')
            ->orderBy('entities.abbreviation')
            ->pluck('entities.abbreviation')->all();
    }
}
