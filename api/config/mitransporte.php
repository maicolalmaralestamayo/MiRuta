<?php

return [

    'version' => '3.0.0',

    /*
    |--------------------------------------------------------------------------
    | Mantenimiento y tareas programadas
    |--------------------------------------------------------------------------
    |
    | maintenance_key: clave para hacer el mantenimiento del servidor desde la
    | app sin iniciar sesión (instalar la base de datos, o arreglar el servidor
    | si nadie puede entrar). Vacía: solo el Administrador con su sesión.
    | tasks_on_requests: sin cron, ejecutar las tareas programadas al terminar
    | las peticiones (como mucho una vez por minuto).
    |
    */

    'maintenance_key' => env('MAINTENANCE_KEY'),

    'tasks_on_requests' => env('TASKS_ON_REQUESTS', false),

    /*
    |--------------------------------------------------------------------------
    | JWT (RFC 7519)
    |--------------------------------------------------------------------------
    |
    | Clave secreta para firmar los tokens con HS256. Cambiarla cierra la
    | sesión de todos los usuarios. Las duraciones son ajustes
    | (access_token_ttl_minutes y refresh_token_ttl_days).
    |
    */

    'jwt' => [
        'secret' => env('JWT_SECRET'),
        'issuer' => env('APP_URL', 'http://localhost'),
        'audience' => 'mitransporte-app',
    ],

    /*
    |--------------------------------------------------------------------------
    | Archivos subidos
    |--------------------------------------------------------------------------
    |
    | Fotos (personas e hijos) e imágenes (Entidades, itinerarios y paradas). Se guardan dentro de public/ para
    | que el servidor web los sirva directamente.
    |
    */

    'uploads_directory' => 'uploads',

    // Carpeta pública (donde está index.php). Por omisión, public/.
    'public_path' => env('PUBLIC_PATH'),

    /*
    |--------------------------------------------------------------------------
    | Paginación JSON:API
    |--------------------------------------------------------------------------
    */

    'pagination' => [
        'default_size' => 25,
        'max_size' => 100,
    ],

    /*
    |--------------------------------------------------------------------------
    | Documentación de la API
    |--------------------------------------------------------------------------
    |
    | Sirve Swagger UI en /docs. Solo debe activarse en desarrollo.
    |
    */

    'docs_enabled' => env('DOCS_ENABLED', false),

    'openapi_path' => env('OPENAPI_PATH', dirname(__DIR__, 2).'/docs/openapi.yaml'),

];
