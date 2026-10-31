<?php

return [

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
    | Fotos de perfil e iconos de jerarquía. Se guardan dentro de public/ para
    | que el servidor web los sirva directamente.
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
    | Documentación de la API
    |--------------------------------------------------------------------------
    |
    | Sirve Swagger UI en /docs. Solo debe activarse en desarrollo.
    |
    */

    'docs_enabled' => env('DOCS_ENABLED', false),

    'openapi_path' => env('OPENAPI_PATH', dirname(__DIR__, 2).'/docs/openapi.yaml'),

];
