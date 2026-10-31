<?php

namespace App\Http\Controllers;

use App\Http\Middleware\AuthenticateInstallation;
use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\Services\Accounts;
use Illuminate\Http\Request;

/**
 * Paso 1 del registro: crear la cuenta (público). La primera cuenta es la
 * del Administrador.
 */
class UserController extends Controller
{
    /** Reglas de los cuatro nombres, todos obligatorios. */
    public static function nameRules(string $prefix = 'attributes.', bool $required = true): array
    {
        $presence = $required ? ['required'] : ['sometimes', 'required'];
        $rules = [];

        foreach (['firstName', 'middleName', 'firstSurname', 'secondSurname'] as $field) {
            $key = substr($prefix, -1) === '.' ? $prefix.$field : $prefix.ucfirst($field);
            $rules[$key] = array_merge($presence, ['string', 'max:50', 'regex:/\S/']);
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
                $names[$column] = preg_replace('/\s+/u', ' ', trim($attributes[$field]));
            }
        }

        return $names;
    }

    public function store(Request $request, Accounts $accounts)
    {
        $data = $this->validateResource($request, 'users', self::nameRules() + [
            'attributes.username' => ['required', 'string', 'max:50'],
            'attributes.password' => ['required', 'string'],
        ]);
        $attributes = $data['attributes'];

        $user = $accounts->register(self::names($attributes), $attributes['username'], $attributes['password']);

        if ($installation = AuthenticateInstallation::resolve($request)) {
            TokenController::linkInstallation($installation, $user);
        }

        return JsonApiResponse::make((new Document($request))->resource($user->fresh()), 201, [
            'Location' => url('api/v1/users/'.$user->id),
        ]);
    }
}
