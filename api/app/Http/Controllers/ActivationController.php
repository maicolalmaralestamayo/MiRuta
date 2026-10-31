<?php

namespace App\Http\Controllers;

use App\Services\Accounts;
use App\Services\TokenService;
use Illuminate\Http\Request;

/**
 * "Ya me registró un superior" (público): con la abreviatura de la Entidad,
 * el Pase y el código de activación, el trabajador elige su usuario y su
 * contraseña. Devuelve los tokens para entrar directamente.
 */
class ActivationController extends Controller
{
    public function store(Request $request, Accounts $accounts, TokenService $tokens)
    {
        $data = $this->validateResource($request, 'activations', [
            'attributes.entityAbbreviation' => ['required', 'string', 'max:15'],
            'attributes.pass' => ['required', 'integer', 'min:1', 'max:4294967295'],
            'attributes.code' => ['required', 'string', 'max:20'],
            'attributes.username' => ['required', 'string', 'max:50'],
            'attributes.password' => ['required', 'string'],
            'attributes.deviceName' => ['nullable', 'string', 'max:100'],
        ]);
        $attributes = $data['attributes'];

        $user = $accounts->activate(
            $attributes['entityAbbreviation'],
            (int) $attributes['pass'],
            $attributes['code'],
            $attributes['username'],
            $attributes['password']
        );

        if ($installation = \App\Http\Middleware\AuthenticateInstallation::resolve($request)) {
            TokenController::linkInstallation($installation, $user);
        }

        return TokenController::respond($tokens->issue($user, isset($attributes['deviceName']) ? $attributes['deviceName'] : null));
    }
}
