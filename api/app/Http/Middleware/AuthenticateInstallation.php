<?php

namespace App\Http\Middleware;

use App\JsonApi\JsonApiException;
use App\Models\Installation;
use Closure;
use Illuminate\Http\Request;

/**
 * Identifica la instalación de la app sin sesión (cabecera
 * X-Installation: <id>.<secreto>). Sirve para hablar con el desarrollador y
 * recuperar el acceso sin cuenta (docs/08-version-2.md §8.6 y §8.7).
 *
 * Una instalación bloqueada por el Administrador solo puede leer.
 */
class AuthenticateInstallation
{
    public function handle(Request $request, Closure $next)
    {
        $installation = self::resolve($request);

        if (! $installation) {
            throw new JsonApiException(401, 'INSTALLATION_REQUIRED', 'Instalación no identificada',
                'Falta la cabecera X-Installation o no es válida.');
        }

        if ($installation->isBlocked() && $request->getMethod() !== 'GET') {
            throw new JsonApiException(403, 'INSTALLATION_BLOCKED', 'Bloqueado',
                'Este teléfono no puede enviar mensajes ni solicitudes. Si crees que es un error, inicia sesión y escribe al desarrollador.');
        }

        $code = $request->header('X-App-Version-Code');

        if ($code !== null && ctype_digit($code) && (int) $code !== (int) $installation->app_version_code) {
            $installation->app_version_code = (int) $code;
            $installation->save();
        }

        $request->attributes->set('installation', $installation);

        return $next($request);
    }

    public static function resolve(Request $request): ?Installation
    {
        $header = (string) $request->header('X-Installation', '');

        if (! preg_match('/^(\d+)\.([A-Za-z0-9]{20,100})$/', $header, $matches)) {
            return null;
        }

        $installation = Installation::find((int) $matches[1]);

        return $installation && hash_equals($installation->secret_hash, hash('sha256', $matches[2])) ? $installation : null;
    }
}
