<?php

namespace App\Http\Middleware;

use App\JsonApi\JsonApiException;
use App\Models\User;
use App\Services\Passwords;
use App\Services\TokenService;
use Closure;
use Illuminate\Http\Request;

/**
 * Exige un token de acceso válido de una cuenta activa. No hace falta
 * pertenecer a ninguna Entidad (docs/11 §11.5): lo que cada uno puede ver o
 * hacer lo deciden sus permisos (App\Services\Permissions).
 *
 * Si la contraseña caducó o hay que cambiarla, solo se permite el perfil
 * propio y cerrar la sesión (403 PASSWORD_CHANGE_REQUIRED).
 */
class Authenticate
{
    /** @var TokenService */
    private $tokens;

    /** @var Passwords */
    private $passwords;

    public function __construct(TokenService $tokens, Passwords $passwords)
    {
        $this->tokens = $tokens;
        $this->passwords = $passwords;
    }

    public function handle(Request $request, Closure $next)
    {
        $token = $request->bearerToken();

        if (! $token) {
            throw new JsonApiException(401, 'UNAUTHENTICATED', 'No autenticado', 'Falta la cabecera Authorization: Bearer <token>.');
        }

        $claims = $this->tokens->decodeAccess($token);
        $user = User::find($claims['sub']);

        if (! $user) {
            throw new JsonApiException(401, 'TOKEN_REVOKED', 'Token revocado', 'La cuenta está desactivada.');
        }

        app(\App\Services\Permissions::class)->flush();
        $user->setCurrentSessionId(isset($claims['sid']) ? (int) $claims['sid'] : null);
        $this->rememberAppVersion($user, $request);
        app('auth')->guard()->setUser($user);
        $request->setUserResolver(function () use ($user) {
            return $user;
        });

        if ($this->passwords->mustChange($user) && ! $this->allowedWhileChangingPassword($request)) {
            throw new JsonApiException(403, 'PASSWORD_CHANGE_REQUIRED', 'Cambie su contraseña',
                $user->must_change_password
                    ? 'Su contraseña la puso otra persona: primero tiene que elegir una nueva.'
                    : 'Su contraseña caducó: primero tiene que elegir una nueva.');
        }

        return $next($request);
    }

    /**
     * Mientras la contraseña está pendiente de cambio solo se permite ver y
     * modificar el perfil propio, leer sus ajustes y cerrar la sesión.
     */
    private function allowedWhileChangingPassword(Request $request): bool
    {
        $path = preg_replace('#^api/v1/#', '', trim($request->path(), '/'));

        return ($path === 'me' && in_array($request->getMethod(), ['GET', 'PATCH'], true))
            || ($path === 'tokens/current' && $request->getMethod() === 'DELETE')
            || ($path === 'me/settings' && $request->getMethod() === 'GET')
            || ($path === 'password-policy' && $request->getMethod() === 'GET');
    }

    /**
     * La app envía su versión en cada petición (X-App-Version-Code); se guarda
     * para que el Administrador vea quién no ha actualizado.
     */
    private function rememberAppVersion(User $user, Request $request): void
    {
        $code = $request->header('X-App-Version-Code');

        if ($code !== null && ctype_digit($code) && (int) $code !== (int) $user->app_version_code) {
            $user->app_version_code = (int) $code;
            $user->save();
        }
    }
}
