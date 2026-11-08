<?php

// Sin base de datos para la caché: archivos (o memoria en las pruebas).
return [
    'default' => env('CACHE_STORE', env('CACHE_DRIVER', 'file')),
];
