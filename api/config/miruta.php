<?php

return [

    'version' => '4.0.0',

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

    'tasks_on_requests' => (bool) env('TASKS_ON_REQUESTS', false),

    /*
    |--------------------------------------------------------------------------
    | JWT (RFC 7519, HS256)
    |--------------------------------------------------------------------------
    |
    | Cambiar la clave cierra la sesión de todos los usuarios. Las duraciones
    | son ajustes de la app («Validez acceso» y «Validez sesión»).
    |
    */

    'jwt' => [
        'secret' => env('JWT_SECRET'),
        'issuer' => env('APP_URL', 'http://localhost'),
        'audience' => 'miruta-app',
    ],

    /*
    |--------------------------------------------------------------------------
    | Archivos subidos
    |--------------------------------------------------------------------------
    |
    | Fotos, imágenes y APK. Se guardan dentro de la carpeta pública para que
    | el servidor web los sirva directamente.
    |
    */

    'uploads_directory' => 'uploads',

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
    | Documentación de la API (Swagger UI en /docs; solo desarrollo)
    |--------------------------------------------------------------------------
    */

    'docs_enabled' => (bool) env('DOCS_ENABLED', false),

    'openapi_path' => env('OPENAPI_PATH', dirname(__DIR__, 2).'/docs/openapi.yaml'),

];
