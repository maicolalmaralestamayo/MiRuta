<?php

namespace App\Http\Controllers;

use App\Http\Middleware\AuthenticateInstallation;
use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\Services\Accounts;
use App\Services\Passwords;
use App\Support\Username;
use Illuminate\Http\Request;

/**
 * Registro (público, docs/11 §11.5): nombres, carné, usuario y contraseña,
 * sin Entidad. Si aún no hay Administrador, quien se registra lo es.
 */
class UserController extends Controller
{
    /** Reglas de los nombres: todos obligatorios menos el segundo nombre (docs/09 §3). */
    public static function nameRules(string $prefix = 'attributes.', bool $required = true): array
    {
        $presence = $required ? ['required'] : ['sometimes', 'required'];
        $rules = [];

        foreach (['firstName', 'middleName', 'firstSurname', 'secondSurname'] as $field) {
            $key = substr($prefix, -1) === '.' ? $prefix.$field : $prefix.ucfirst($field);
            $rules[$key] = $field === 'middleName'
                ? ['sometimes', 'nullable', 'string', 'max:50']
                : array_merge($presence, ['string', 'max:50', 'regex:/\S/']);
        }

        return $rules;
    }

    /**
     * @return array [first_name, middle_name, first_surname, second_surname]
     */
    public static function names(array $attributes): array
    {
        $names = [];

        foreach (['firstName' => 'first_name', 'middleName' => 'middle_name', 'firstSurname' => 'first_surname', 'secondSurname' => 'second_surname'] as $field => $column) {
            if (array_key_exists($field, $attributes)) {
                $value = preg_replace('/\s+/u', ' ', trim((string) $attributes[$field]));
                $names[$column] = $value === '' ? null : $value;
            }
        }

        return $names;
    }

    public function store(Request $request, Accounts $accounts)
    {
        $data = $this->validateResource($request, 'users', self::nameRules() + [
            'attributes.identityCard' => ['required', 'string', 'max:20'],
            'attributes.username' => ['required', 'string', 'max:60'],
            'attributes.password' => ['required', 'string'],
        ]);
        $attributes = $data['attributes'];

        $user = $accounts->register(self::names($attributes), $attributes['identityCard'], $attributes['username'], $attributes['password']);

        if ($installation = AuthenticateInstallation::resolve($request)) {
            TokenController::linkInstallation($installation, $user);
        }

        return JsonApiResponse::make((new Document($request))->resource($user->fresh()), 201, [
            'Location' => url('api/v1/users/'.$user->id),
        ]);
    }

    /**
     * ¿Ya hay Administrador? (público; solo responde sí o no).
     */
    public function registrationStatus()
    {
        return JsonApiResponse::make(['data' => [
            'type' => 'registration-status',
            'id' => 'current',
            'attributes' => ['adminExists' => Accounts::adminExists()],
        ]]);
    }

    /**
     * Usuario propuesto a partir de los nombres (público, docs/11 §11.4).
     */
    public function usernameSuggestion(Request $request)
    {
        $this->validate($request, [
            'firstName' => ['required', 'string', 'max:50'],
            'middleName' => ['sometimes', 'nullable', 'string', 'max:50'],
            'firstSurname' => ['sometimes', 'nullable', 'string', 'max:50'],
            'secondSurname' => ['sometimes', 'nullable', 'string', 'max:50'],
        ]);
        $username = Username::suggest($request->query('firstName'), $request->query('middleName'),
            $request->query('firstSurname'), $request->query('secondSurname'));

        return JsonApiResponse::make(['data' => [
            'type' => 'username-suggestions',
            'id' => $username,
            'attributes' => ['username' => $username],
        ]]);
    }

    /**
     * Contraseña propuesta que cumple la política (público).
     */
    public function passwordSuggestion(Passwords $passwords)
    {
        return JsonApiResponse::make(['data' => [
            'type' => 'password-suggestions',
            'id' => 'current',
            'attributes' => ['password' => $passwords->suggest()],
        ]]);
    }
}
