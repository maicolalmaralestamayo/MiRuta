<?php

// Solo lo que cambia respecto a la configuración por omisión de Laravel 12.
return [
    'name' => env('APP_NAME', 'MiRuta'),
    'timezone' => env('APP_TIMEZONE', 'America/Havana'),
    'locale' => env('APP_LOCALE', 'es'),
    'fallback_locale' => 'es',
    'faker_locale' => 'es_ES',
];
