<?php

namespace App\Http\Middleware;

use App\JsonApi\JsonApiException;
use App\Models\Worker;
use App\Services\TokenService;
use Closure;
use Illuminate\Http\Request;

/**
 * Exige un token de acceso válido de un trabajador activo.
 */
class Authenticate
{
    /** @var TokenService */
    private $tokens;

    public function __construct(TokenService $tokens)
    {
        $this->tokens = $tokens;
    }

    public function handle(Request $request, Closure $next)
    {
        $token = $request->bearerToken();

        if (! $token) {
            throw new JsonApiException(401, 'UNAUTHENTICATED', 'No autenticado', 'Falta la cabecera Authorization: Bearer <token>.');
        }

        $claims = $this->tokens->decodeAccess($token);
        $worker = Worker::find($claims['sub']);

        if (! $worker) {
            throw new JsonApiException(401, 'TOKEN_REVOKED', 'Token revocado', 'La cuenta está desactivada.');
        }

        $worker->setCurrentSessionId(isset($claims['sid']) ? (int) $claims['sid'] : null);
        $this->rememberAppVersion($worker, $request);
        app('auth')->guard()->setUser($worker);
        $request->setUserResolver(function () use ($worker) {
            return $worker;
        });

        if ($worker->must_change_password && ! $this->allowedWhileChangingPassword($request)) {
            throw new JsonApiException(403, 'PASSWORD_CHANGE_REQUIRED', 'Cambia tu contraseña',
                'Entraste con un código de restablecimiento: primero tienes que elegir una contraseña nueva.');
        }

        return $next($request);
    }

    /**
     * Mientras la contraseña está pendiente de cambio solo se permite ver y
     * modificar el perfil propio y cerrar la sesión.
     */
    private function allowedWhileChangingPassword(Request $request): bool
    {
        $path = preg_replace('#^api/v1/#', '', trim($request->path(), '/'));

        return ($path === 'me' && in_array($request->getMethod(), ['GET', 'PATCH'], true))
            || ($path === 'tokens/current' && $request->getMethod() === 'DELETE')
            || ($path === 'me/settings' && $request->getMethod() === 'GET');
    }

    /**
     * La app envía su versión en cada petición (X-App-Version-Code); se guarda
     * para que el Administrador vea quién no ha actualizado.
     */
    private function rememberAppVersion(Worker $worker, Request $request): void
    {
        $code = $request->header('X-App-Version-Code');

        if ($code !== null && ctype_digit($code) && (int) $code !== (int) $worker->app_version_code) {
            $worker->app_version_code = (int) $code;
            $worker->save();
        }
    }
}
