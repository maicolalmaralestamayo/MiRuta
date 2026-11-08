<?php

namespace App\Http\Middleware;

use App\JsonApi\JsonApiException;
use App\Models\AppVersion;
use App\Services\TokenService;
use Closure;
use Illuminate\Http\Request;

/**
 * Actualización obligatoria (docs/11 §11.54). La app envía su versión
 * (versionCode de Android) en cada petición, en la cabecera X-App-Version.
 * Si hay una versión obligatoria posterior, se rechaza todo con 426
 * APP_UPDATE_REQUIRED (también el inicio de sesión) y se cierra la sesión de
 * esa petición en el servidor, salvo:
 *
 * - comprobar la última versión (GET app-versions/latest);
 * - cerrar la sesión (DELETE tokens/current y DELETE tokens);
 * - «Olvidé algo» sin cuenta (guest/…) y registrar la instalación;
 * - el mantenimiento del servidor.
 *
 * Las APK se descargan como archivos (uploads/apk/…), sin pasar por la API.
 * Sin la cabecera no se comprueba nada.
 */
class RequireCurrentAppVersion
{
    public const HEADER = 'X-App-Version';

    /** Rutas permitidas: [método, ruta sin el prefijo api/v1/] (con * al final = prefijo). */
    public const ALLOWED = [
        ['GET', 'app-versions/latest'],
        ['DELETE', 'tokens/current'],
        ['DELETE', 'tokens'],
        ['*', 'guest/*'],
        ['POST', 'installations'],
        ['GET', 'server-status'],
        ['POST', 'maintenance-runs'],
    ];

    public function handle(Request $request, Closure $next)
    {
        $code = self::versionCode($request);

        if ($code === null || $this->allowed($request)) {
            return $next($request);
        }

        $mandatory = AppVersion::where('version_code', '>', $code)->where('mandatory', true)->orderByDesc('version_code')->first();

        if (! $mandatory) {
            return $next($request);
        }

        $this->closeSession($request);
        $latest = AppVersion::latest();

        throw new JsonApiException(426, 'APP_UPDATE_REQUIRED', 'Actualización obligatoria',
            'Hay una versión nueva de MiRuta que es obligatoria. Descárguela e instálela para seguir usando la app.', [], [
                'installedVersionCode' => $code,
                'mandatoryVersionCode' => $mandatory->version_code,
                'latestVersionCode' => $latest?->version_code,
                'latestVersionName' => $latest?->version_name,
                'latestVersionUrl' => url('api/v1/app-versions/latest'),
            ]);
    }

    public static function versionCode(Request $request): ?int
    {
        $value = $request->header(self::HEADER, $request->header('X-App-Version-Code'));

        return is_string($value) && ctype_digit(trim($value)) ? (int) trim($value) : null;
    }

    private function allowed(Request $request): bool
    {
        $path = preg_replace('#^api/v1/?#', '', trim($request->path(), '/'));

        foreach (self::ALLOWED as [$method, $pattern]) {
            if ($method !== '*' && $method !== $request->getMethod()) {
                continue;
            }

            if (str_ends_with($pattern, '*') ? str_starts_with($path, rtrim($pattern, '*')) : $path === $pattern) {
                return true;
            }
        }

        return false;
    }

    /**
     * Anula la sesión de la petición (si trae un token válido).
     */
    private function closeSession(Request $request): void
    {
        $token = $request->bearerToken();

        if (! $token) {
            return;
        }

        try {
            $claims = app(TokenService::class)->decodeAccess($token);

            if (isset($claims['sid'])) {
                app(TokenService::class)->revoke((int) $claims['sid']);
            }
        } catch (\Throwable $e) {
            // Token no válido o caducado: no hay sesión que cerrar.
        }
    }
}
