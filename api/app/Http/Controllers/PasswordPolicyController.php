<?php

namespace App\Http\Controllers;

use App\JsonApi\JsonApiResponse;
use App\Services\Passwords;
use App\Support\Username;

/**
 * Requisitos de la contraseña y del usuario (público), para que la app los
 * muestre mientras se escribe. Quien decide es la API.
 */
class PasswordPolicyController extends Controller
{
    public function show(Passwords $passwords)
    {
        return JsonApiResponse::make(['data' => [
            'type' => 'password-policies',
            'id' => 'current',
            'attributes' => $passwords->policy() + [
                'usernameMinLength' => Username::MIN_LENGTH,
                'usernameMaxLength' => Username::MAX_LENGTH,
            ],
        ]]);
    }
}
