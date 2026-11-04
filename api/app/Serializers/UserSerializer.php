<?php

namespace App\Serializers;

use App\Models\Application;
use App\Models\Worker;
use App\Services\Passwords;
use App\Services\Permissions;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * La persona. El usuario y los datos de la contraseña los ven ella misma y
 * el Administrador. El carné (docs/11 §11.2), ella misma, el Administrador
 * y quien tenga workers.view_identity_card sobre alguna de sus pertenencias
 * o sobre el itinerario que solicita.
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
            'sex' => $user->sex,
            'photoUrl' => $user->photo_path ? url($user->photo_path) : null,
            'isAdmin' => $user->is_admin,
            'hasPhone' => (bool) $user->has_phone,
            'active' => ! $user->trashed(),
            // Abreviaturas de sus Entidades (línea 2 de la tarjeta, docs/11 §11.3).
            'entities' => self::entityAbbreviations($user),
        ];

        if (self::canSeeIdentityCard($user, $request)) {
            $attributes['identityCard'] = $user->identityCard();
            $attributes['birthDate'] = $user->birth_date ? $user->birth_date->toDateString() : null;
        }

        if (self::isSelfOrAdmin($user, $request)) {
            $passwords = app(Passwords::class);
            $expiresAt = $passwords->expiresAt($user);
            $attributes = ['username' => $user->username] + $attributes + [
                'mustChangePassword' => $passwords->mustChange($user),
                // Si caducó hay que dar la actual; si la puso otra persona, no.
                'currentPasswordRequired' => ! $user->must_change_password,
                'passwordExpiresAt' => $expiresAt ? $expiresAt->toIso8601String() : null,
                'printedQrVersion' => (int) $user->printed_qr_version,
                'createdAt' => $this->date($user->created_at),
            ];
        }

        if ($request->user() && $request->user()->isAdmin()) {
            $attributes['appVersionCode'] = $user->app_version_code;
        }

        return $attributes;
    }

    public static function isSelfOrAdmin(Model $user, Request $request): bool
    {
        $viewer = $request->user();

        return $viewer && ($viewer->isAdmin() || (int) $viewer->id === (int) $user->id);
    }

    public static function canSeeIdentityCard(Model $user, Request $request): bool
    {
        if (self::isSelfOrAdmin($user, $request)) {
            return true;
        }

        $viewer = $request->user();

        if (! $viewer) {
            return false;
        }

        $permissions = app(Permissions::class);

        if (! $permissions->canAnywhere($viewer, 'workers.view_identity_card')) {
            return false;
        }

        foreach (Worker::where('user_id', $user->id)->get() as $worker) {
            if ($permissions->can($viewer, 'workers.view_identity_card', (int) $worker->entity_id, $worker->itinerary_id ? (int) $worker->itinerary_id : null)) {
                return true;
            }
        }

        // Quien solicita entrar en un itinerario de su ámbito.
        foreach (Application::where('user_id', $user->id)->where('type', Application::TYPE_ITINERARY_MEMBERSHIP)
            ->where('status', Application::STATUS_PENDING)->get() as $application) {
            if ($permissions->can($viewer, 'workers.view_identity_card', (int) $application->entity_id, (int) $application->itinerary_id)) {
                return true;
            }
        }

        return false;
    }

    /**
     * @return string[]
     */
    public static function entityAbbreviations(Model $user): array
    {
        return Worker::where('workers.user_id', $user->id)
            ->join('entities', 'entities.id', '=', 'workers.entity_id')
            ->whereNull('entities.deleted_at')
            ->orderBy('entities.abbreviation')
            ->pluck('entities.abbreviation')->all();
    }
}
