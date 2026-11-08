<?php

namespace App\Http\Middleware;

use App\Http\Middleware\RequireCurrentAppVersion;
use App\JsonApi\JsonApiException;
use App\Models\RefreshToken;
use App\Models\User;
use App\Services\Access;
use App\Services\Passwords;
use App\Services\TokenService;
use Closure;
use Illuminate\Http\Request;

/**
 * Exige un token de acceso válido de una sesión abierta. No hace falta
 * pertenecer a ninguna Entidad: lo que cada uno ve o hace depende de su rol.
 *
 * Si la contraseña caducó o hay que cambiarla, solo se permite el perfil
 * propio y cerrar la sesión (403 PASSWORD_CHANGE_REQUIRED).
 */
class Authenticate
{
    public function __construct(private TokenService $tokens, private Passwords $passwords)
    {
    }

    public function handle(Request $request, Closure $next)
    {
        $token = $request->bearerToken();

        if (! $token) {
            throw new JsonApiException(401, 'UNAUTHENTICATED', 'No autenticado', 'Falta la cabecera Authorization: Bearer <token>.');
        }

        $claims = $this->tokens->decodeAccess($token);
        $user = User::find($claims['sub']);
        $sessionId = isset($claims['sid']) ? (int) $claims['sid'] : null;

        // La sesión se cerró (en este teléfono, en todos, o por una actualización obligatoria).
        $open = $sessionId !== null && RefreshToken::whereKey($sessionId)->whereNull('revoked_at')->exists();

        if (! $user || ! $open) {
            throw new JsonApiException(401, 'TOKEN_REVOKED', 'Sesión cerrada', 'La sesión se cerró. Inicie sesión de nuevo.');
        }

        app(Access::class)->flush();
        $user->setCurrentSessionId($sessionId);
        $this->rememberAppVersion($user, $request);
        $request->setUserResolver(fn () => $user);

        if ($this->passwords->mustChange($user) && ! $this->allowedWhileChangingPassword($request)) {
            throw new JsonApiException(403, 'PASSWORD_CHANGE_REQUIRED', 'Cambie su contraseña',
                $user->must_change_password
                    ? 'Su contraseña la puso otra persona: primero tiene que elegir una nueva.'
                    : 'Su contraseña caducó: primero tiene que elegir una nueva.');
        }

        return $next($request);
    }

    private function allowedWhileChangingPassword(Request $request): bool
    {
        $path = preg_replace('#^api/v1/#', '', trim($request->path(), '/'));

        return ($path === 'me' && in_array($request->getMethod(), ['GET', 'PATCH'], true))
            || (in_array($path, ['tokens/current', 'tokens'], true) && $request->getMethod() === 'DELETE')
            || ($path === 'settings' && $request->getMethod() === 'GET');
    }

    private function rememberAppVersion(User $user, Request $request): void
    {
        $code = RequireCurrentAppVersion::versionCode($request);

        if ($code !== null && $code !== (int) $user->app_version_code) {
            $user->app_version_code = $code;
            $user->save();
        }
    }
}
