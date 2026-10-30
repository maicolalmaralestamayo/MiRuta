<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Clave para la huella del carné
    |--------------------------------------------------------------------------
    |
    | Clave secreta del HMAC-SHA256 con que se calcula la huella del carné
    | (columna card_number_hash). Permite buscar y comprobar la unicidad sin
    | descifrar. No debe cambiar una vez haya datos: las huellas dejarían de
    | coincidir.
    |
    */

    'card_hash_key' => env('CARD_HASH_KEY'),

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
