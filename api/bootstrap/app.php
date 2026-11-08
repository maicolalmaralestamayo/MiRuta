<?php

require_once __DIR__.'/../vendor/autoload.php';

use App\Exceptions\JsonApiExceptionRenderer;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

/*
|--------------------------------------------------------------------------
| Configuración
|--------------------------------------------------------------------------
|
| En un hospedaje compartido la configuración va en configuracion.php (un
| archivo PHP que devuelve un arreglo con las mismas claves que .env): como
| es PHP, el servidor web nunca muestra su contenido aunque quede dentro de
| la carpeta pública. Si no existe, se usa .env como siempre (desarrollo).
|
*/

$basePath = dirname(__DIR__);

if (is_file($basePath.'/configuracion.php')) {
    foreach ((array) require $basePath.'/configuracion.php' as $name => $value) {
        if (is_bool($value)) {
            $value = $value ? 'true' : 'false';
        }
        $value = (string) $value;
        putenv($name.'='.$value);
        $_ENV[$name] = $value;
        $_SERVER[$name] = $value;
    }
}

$env = static function (string $name): ?string {
    $value = $_ENV[$name] ?? $_SERVER[$name] ?? getenv($name);

    return $value === false || $value === '' ? null : (string) $value;
};

// Carpeta temporal propia (los hospedajes compartidos suelen exigirla).
if (($temp = $env('TEMP_PATH')) && is_dir($temp)) {
    putenv('TMPDIR='.$temp);
}

/*
| Carpeta de trabajo (caché, registro de errores, estado de las tareas). En un
| hospedaje compartido conviene ponerla fuera de la carpeta pública, p. ej. en
| su carpeta temporal. Se crea si no existe. Los archivos de caché de Laravel
| (bootstrap/cache) también van ahí, para no necesitar permisos de escritura en
| la carpeta del código.
*/
$storage = null;

if ($custom = $env('STORAGE_PATH')) {
    $custom = rtrim($custom, '/');
    foreach (['app', 'framework/cache/data', 'framework/views', 'logs', 'bootstrap'] as $folder) {
        if (! is_dir($custom.'/'.$folder)) {
            @mkdir($custom.'/'.$folder, 0775, true);
        }
    }
    // Si no se puede usar, se queda la de siempre (storage/) y el estado del servidor lo muestra.
    if (is_dir($custom.'/logs') && is_writable($custom.'/logs')) {
        $storage = $custom;
        foreach (['APP_SERVICES_CACHE' => 'services.php', 'APP_PACKAGES_CACHE' => 'packages.php',
            'APP_CONFIG_CACHE' => 'config.php', 'APP_ROUTES_CACHE' => 'routes-v7.php', 'APP_EVENTS_CACHE' => 'events.php'] as $name => $file) {
            if ($env($name) === null) {
                putenv($name.'='.$storage.'/bootstrap/'.$file);
                $_ENV[$name] = $_SERVER[$name] = $storage.'/bootstrap/'.$file;
            }
        }
    }
}

$app = Application::configure(basePath: $basePath)
    ->withRouting(
        api: $basePath.'/routes/api.php',
        apiPrefix: 'api/v1',
        commands: $basePath.'/routes/console.php',
        then: function () {
            // Swagger UI (solo desarrollo, DOCS_ENABLED=true).
            if (config('miruta.docs_enabled')) {
                \Illuminate\Support\Facades\Route::get('docs', [\App\Http\Controllers\DocsController::class, 'index']);
                \Illuminate\Support\Facades\Route::get('docs/openapi.yaml', [\App\Http\Controllers\DocsController::class, 'spec']);
            }
        },
    )
    ->withMiddleware(function (Middleware $middleware) {
        // Sin cookies, sesiones ni CSRF: es una API con tokens.
        $middleware->group('api', [
            \App\Http\Middleware\RequireJsonApi::class,
            \App\Http\Middleware\RequireCurrentAppVersion::class,
        ]);
        $middleware->append(\App\Http\Middleware\RunScheduledTasks::class);
        $middleware->alias([
            'auth.token' => \App\Http\Middleware\Authenticate::class,
            'auth.any' => \App\Http\Middleware\AuthenticateAny::class,
            'installation' => \App\Http\Middleware\AuthenticateInstallation::class,
            'maintenance' => \App\Http\Middleware\AuthenticateMaintenance::class,
            'multipart' => \App\Http\Middleware\AllowMultipart::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions) {
        $exceptions->render(function (\Throwable $exception, $request) {
            return JsonApiExceptionRenderer::render($exception);
        });
        $exceptions->dontReport([\App\JsonApi\JsonApiException::class]);
    })
    ->create();

if ($storage !== null) {
    $app->useStoragePath($storage);
}

// Carpeta pública (donde está index.php). En el hospedaje es la carpeta
// superior a servidor/ (la indica index.php con PUBLIC_PATH).
if ($public = $env('PUBLIC_PATH')) {
    $app->usePublicPath($public);
}

return $app;
