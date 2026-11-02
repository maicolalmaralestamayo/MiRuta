<?php

require_once __DIR__.'/../vendor/autoload.php';

/*
|--------------------------------------------------------------------------
| Configuración
|--------------------------------------------------------------------------
|
| En un hospedaje compartido la configuración va en configuracion.php (un
| archivo PHP que devuelve un arreglo con las mismas claves que .env): como
| es PHP, el servidor web nunca lo muestra aunque quede dentro de la carpeta
| pública. Si no existe, se usa .env como siempre.
|
*/

if (is_file(dirname(__DIR__).'/configuracion.php')) {
    foreach ((array) require dirname(__DIR__).'/configuracion.php' as $name => $value) {
        if (is_bool($value)) {
            $value = $value ? 'true' : 'false';
        }
        $value = (string) $value;
        putenv($name.'='.$value);
        $_ENV[$name] = $value;
        $_SERVER[$name] = $value;
    }
}

(new Laravel\Lumen\Bootstrap\LoadEnvironmentVariables(
    dirname(__DIR__)
))->bootstrap();

// Carpeta temporal propia (los hospedajes compartidos suelen exigirla).
if (env('TEMP_PATH') && is_dir(env('TEMP_PATH'))) {
    putenv('TMPDIR='.env('TEMP_PATH'));
}

date_default_timezone_set(env('APP_TIMEZONE', 'UTC'));

/*
|--------------------------------------------------------------------------
| Create The Application
|--------------------------------------------------------------------------
*/

$app = new Laravel\Lumen\Application(
    dirname(__DIR__)
);

/*
| Carpeta de trabajo (caché, registro de errores, estado de las tareas). En un
| hospedaje compartido conviene ponerla fuera de la carpeta pública, p. ej.
| en su carpeta temporal. Se crea si no existe.
*/
if (env('STORAGE_PATH')) {
    $storage = rtrim(env('STORAGE_PATH'), '/');
    foreach (['app', 'framework/cache', 'logs'] as $folder) {
        if (! is_dir($storage.'/'.$folder)) {
            @mkdir($storage.'/'.$folder, 0775, true);
        }
    }
    // Si no se puede usar, se queda la de siempre (storage/) y el estado del
    // servidor lo muestra.
    if (is_dir($storage.'/logs') && is_writable($storage.'/logs')) {
        $app->useStoragePath($storage);
    }
}

$app->withFacades();

$app->withEloquent();

/*
|--------------------------------------------------------------------------
| Register Container Bindings
|--------------------------------------------------------------------------
*/

$app->singleton(
    Illuminate\Contracts\Debug\ExceptionHandler::class,
    App\Exceptions\Handler::class
);

$app->singleton(
    Illuminate\Contracts\Console\Kernel::class,
    App\Console\Kernel::class
);

/*
|--------------------------------------------------------------------------
| Register Config Files
|--------------------------------------------------------------------------
*/

$app->configure('app');
$app->configure('mitransporte');
$app->configure('jsonapi');

/*
|--------------------------------------------------------------------------
| Register Middleware
|--------------------------------------------------------------------------
*/

$app->middleware([
    App\Http\Middleware\RunScheduledTasks::class,
]);

$app->routeMiddleware([
    'maintenance' => App\Http\Middleware\AuthenticateMaintenance::class,
    'jsonapi' => App\Http\Middleware\RequireJsonApi::class,
    'auth' => App\Http\Middleware\Authenticate::class,
    'installation' => App\Http\Middleware\AuthenticateInstallation::class,
    'auth.any' => App\Http\Middleware\AuthenticateAny::class,
]);

/*
|--------------------------------------------------------------------------
| Register Service Providers
|--------------------------------------------------------------------------
*/

$app->register(App\Providers\AppServiceProvider::class);
$app->register(App\Providers\AuthServiceProvider::class);

/*
|--------------------------------------------------------------------------
| Load The Application Routes
|--------------------------------------------------------------------------
*/

$app->router->group([
    'namespace' => 'App\Http\Controllers',
], function ($router) {
    require __DIR__.'/../routes/web.php';
});

return $app;
