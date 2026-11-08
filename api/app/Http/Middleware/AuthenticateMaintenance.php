<?php

namespace App\Http\Middleware;

use App\JsonApi\JsonApiException;
use Closure;
use Illuminate\Http\Request;

/**
 * Mantenimiento del servidor: el Administrador con su sesión o, si aún no
 * hay base de datos o no se puede iniciar sesión, cualquiera que tenga la
 * clave de mantenimiento (MAINTENANCE_KEY) en la cabecera X-Maintenance-Key.
 */
class AuthenticateMaintenance
{
    public const MIN_KEY_LENGTH = 16;

    public function handle(Request $request, Closure $next)
    {
        $given = (string) $request->header('X-Maintenance-Key');

        if ($given !== '') {
            $key = (string) config('miruta.maintenance_key');

            if (strlen($key) < self::MIN_KEY_LENGTH || ! hash_equals($key, $given)) {
                usleep(500000);

                throw new JsonApiException(403, 'MAINTENANCE_KEY_INVALID', 'Clave incorrecta', 'La clave de mantenimiento no es correcta.');
            }

            return $next($request);
        }

        return app(Authenticate::class)->handle($request, function (Request $request) use ($next) {
            if (! $request->user()->isAdmin()) {
                throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'No tiene permiso para hacer el mantenimiento del servidor.');
            }

            return $next($request);
        });
    }
}
