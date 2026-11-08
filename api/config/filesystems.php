<?php

// Sin las rutas storage/{path} de Laravel: los archivos subidos se sirven
// directamente desde la carpeta pública (uploads/).
return [
    'disks' => [
        'local' => [
            'driver' => 'local',
            'root' => storage_path('app/private'),
            'serve' => false,
            'throw' => false,
        ],
    ],
];
