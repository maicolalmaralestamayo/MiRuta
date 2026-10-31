<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Services\Accounts;
use App\Services\Passwords;
use App\Services\Settings;
use App\Services\TokenService;
use App\Services\Uploads;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

/**
 * La cuenta propia (recurso "users") y su trabajador.
 */
class MeController extends Controller
{
    const INCLUDABLE = ['worker', 'worker.entity', 'worker.rank', 'worker.itinerary', 'worker.stop'];

    public function show(Request $request)
    {
        $includes = QueryParameters::readIncludes($request, self::INCLUDABLE);

        return JsonApiResponse::make((new Document($request))->resource($request->user()->refreshRoles(), $includes));
    }

    /**
     * Usuario, nombres, contraseña y jerarquía.
     *
     * Cambiar la contraseña exige la actual (meta.currentPassword), salvo
     * tras recuperar el acceso; cierra las demás sesiones.
     */
    public function update(Request $request, Accounts $accounts, Passwords $passwords, TokenService $tokens)
    {
        $data = $this->validateResource($request, 'users', UserController::nameRules('attributes.', false) + [
            'attributes.username' => ['sometimes', 'required', 'string', 'max:50'],
            'attributes.password' => ['sometimes', 'required', 'string'],
            'relationships.rank.data.type' => ['sometimes', 'in:ranks'],
            'relationships.rank.data.id' => ['sometimes', 'exists:ranks,id,deleted_at,NULL'],
        ]);

        $user = $request->user();
        $attributes = isset($data['attributes']) ? $data['attributes'] : [];
        $rankId = isset($data['relationships']['rank']['data']['id']) ? (int) $data['relationships']['rank']['data']['id'] : null;

        if ($rankId !== null && ! $user->workerModel()) {
            throw new JsonApiException(409, 'ENTITY_REQUIRED', 'Únete a tu Entidad', 'La jerarquía es del trabajador: primero únete a tu Entidad.');
        }

        DB::transaction(function () use ($request, $user, $attributes, $rankId, $accounts, $passwords, $tokens) {
            if (array_key_exists('username', $attributes)) {
                $accounts->changeUsername($user, $attributes['username']);
            }

            $user->fill(UserController::names($attributes));
            $user->save();

            if ($rankId !== null) {
                $worker = $user->workerModel();
                $worker->rank_id = $rankId;
                $worker->save();
            }

            if (array_key_exists('password', $attributes)) {
                $this->changePassword($request, $user, $attributes['password'], $passwords, $tokens);
            }
        });

        return JsonApiResponse::make((new Document($request))->resource($user->fresh()->refreshRoles()));
    }

    /**
     * Paso 2 del registro: unirse a la Entidad con su abreviatura y el Pase.
     */
    public function joinEntity(Request $request, Accounts $accounts)
    {
        $data = $this->validateResource($request, 'workers', [
            'attributes.entityAbbreviation' => ['required', 'string', 'max:15'],
            'attributes.pass' => ['required', 'integer', 'min:1', 'max:4294967295'],
            'attributes.sex' => ['required', 'in:F,M'],
            'relationships.rank.data.type' => ['required', 'in:ranks'],
            'relationships.rank.data.id' => ['required', 'exists:ranks,id,deleted_at,NULL'],
        ]);
        $attributes = $data['attributes'];

        $worker = $accounts->joinEntity(
            $request->user(),
            $attributes['entityAbbreviation'],
            (int) $attributes['pass'],
            $attributes['sex'],
            (int) $data['relationships']['rank']['data']['id']
        );

        return JsonApiResponse::make((new Document($request))->resource($worker->fresh(), ['entity', 'rank']), 201, [
            'Location' => url('api/v1/workers/'.$worker->id),
        ]);
    }

    public function uploadPhoto(Request $request, Settings $settings, Uploads $uploads)
    {
        $this->validate($request, [
            'photo' => ['required', 'file', 'image', 'mimes:jpeg,png', 'max:'.$settings->int('photo_max_kb')],
        ]);

        $user = $request->user();
        $previous = $user->photo_path;
        $user->photo_path = $uploads->store($request->file('photo'), 'photos');
        $user->save();
        $uploads->delete($previous);

        return JsonApiResponse::make((new Document($request))->resource($user));
    }

    public function deletePhoto(Request $request, Uploads $uploads)
    {
        $user = $request->user();
        $uploads->delete($user->photo_path);
        $user->photo_path = null;
        $user->save();

        return response('', 204);
    }

    private function changePassword(Request $request, $user, string $password, Passwords $passwords, TokenService $tokens): void
    {
        $recovering = (bool) $user->must_change_password;

        // Tras recuperar el acceso no se conoce la actual.
        if (! $recovering) {
            $current = $request->json('meta.currentPassword');

            if (! is_string($current) || ! $user->password || ! Hash::check($current, $user->password)) {
                throw new JsonApiException(422, 'CURRENT_PASSWORD_INVALID', 'Contraseña actual incorrecta',
                    'Para cambiar la contraseña hay que enviar la actual en meta.currentPassword.', ['pointer' => '/meta/currentPassword']);
            }
        }

        $passwords->validate($password, [$user->username, $user->first_name, $user->middle_name, $user->first_surname, $user->second_surname], $user);
        $passwords->set($user, $password);

        // La sesión actual sigue abierta; las demás se cierran.
        $current = $user->currentSessionId();
        \App\Models\RefreshToken::where('user_id', $user->id)->whereNull('revoked_at')
            ->when($current !== null, function ($query) use ($current) {
                $query->where('id', '<>', $current);
            })
            ->update(['revoked_at' => \Carbon\Carbon::now()]);
    }
}
