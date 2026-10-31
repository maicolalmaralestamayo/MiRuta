<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Services\Settings;
use App\Services\TokenService;
use App\Rules\UsernameRule;
use App\Services\Uploads;
use App\Services\WorkerRegistration;
use App\Support\Username;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class MeController extends Controller
{
    const INCLUDABLE = ['rank'];

    public function show(Request $request)
    {
        $includes = QueryParameters::readIncludes($request, self::INCLUDABLE);

        return JsonApiResponse::make((new Document($request))->resource($request->user(), $includes));
    }

    /**
     * Usuario, nombre, apellidos o contraseña. Cambiar la contraseña exige la actual
     * (meta.currentPassword) y cierra las demás sesiones.
     */
    public function update(Request $request, TokenService $tokens)
    {
        $data = $this->validateResource($request, 'workers', [
            'attributes.username' => ['sometimes', 'required', 'string', new UsernameRule()],
            'attributes.firstName' => ['sometimes', 'required', 'string', 'max:100'],
            'attributes.lastName' => ['sometimes', 'required', 'string', 'max:150'],
            'attributes.password' => ['sometimes', 'required', 'string', 'min:8', 'max:72'],
        ]);

        $worker = $request->user();
        $attributes = isset($data['attributes']) ? $data['attributes'] : [];

        foreach (['firstName' => 'first_name', 'lastName' => 'last_name'] as $field => $column) {
            if (array_key_exists($field, $attributes)) {
                $worker->{$column} = trim($attributes[$field]);
            }
        }

        if (array_key_exists('username', $attributes)) {
            $username = Username::normalize($attributes['username']);
            WorkerRegistration::ensureUsernameFree($username, $worker);
            $worker->username = $username;
        }

        if (array_key_exists('password', $attributes)) {
            $current = $request->json('meta.currentPassword');

            // Tras entrar con un código de restablecimiento no se conoce la actual.
            if (! $worker->must_change_password && (! is_string($current) || ! Hash::check($current, $worker->password))) {
                throw new JsonApiException(422, 'CURRENT_PASSWORD_INVALID', 'Contraseña actual incorrecta',
                    'Para cambiar la contraseña hay que enviar la actual en meta.currentPassword.', ['pointer' => '/meta/currentPassword']);
            }

            $worker->password = Hash::make($attributes['password']);

            if ($worker->must_change_password) {
                // La sesión actual sigue abierta; las demás ya se cerraron al usar el código.
                $worker->must_change_password = false;
            } else {
                $tokens->revokeAll($worker->id);
            }
        }

        $worker->save();

        return JsonApiResponse::make((new Document($request))->resource($worker));
    }

    public function uploadPhoto(Request $request, Settings $settings, Uploads $uploads)
    {
        $this->validate($request, [
            'photo' => ['required', 'file', 'image', 'mimes:jpeg,png', 'max:'.$settings->int('photo_max_kb')],
        ]);

        $worker = $request->user();
        $previous = $worker->photo_path;
        $worker->photo_path = $uploads->store($request->file('photo'), 'photos');
        $worker->save();
        $uploads->delete($previous);

        return JsonApiResponse::make((new Document($request))->resource($worker));
    }

    public function deletePhoto(Request $request, Uploads $uploads)
    {
        $worker = $request->user();
        $uploads->delete($worker->photo_path);
        $worker->photo_path = null;
        $worker->save();

        return response('', 204);
    }
}
