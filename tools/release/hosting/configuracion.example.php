<?php

/*
| Configuración de MiRuta en el hospedaje.
|
| Es un archivo PHP: el servidor web nunca muestra su contenido. Edítelo con
| FileZilla (botón derecho > Ver/Editar) y vuelva a subirlo.
|
| IMPORTANTE: guarde una copia de APP_KEY, JWT_SECRET y MAINTENANCE_KEY. Si
| cambian, se cierran todas las sesiones (APP_KEY y JWT_SECRET) o deja de
| servir la clave de mantenimiento.
*/

return [
    'APP_NAME' => 'MiRuta',
    'APP_ENV' => 'production',
    'APP_DEBUG' => false,
    'APP_URL' => '__APP_URL__',
    'APP_TIMEZONE' => 'America/Havana',
    'APP_LOCALE' => 'es',

    // Claves secretas (generadas al preparar el paquete).
    'APP_KEY' => '__APP_KEY__',
    'JWT_SECRET' => '__JWT_SECRET__',

    // Clave de mantenimiento: para instalar o actualizar la base de datos
    // desde la app (Servidor > Mantenimiento) sin iniciar sesión.
    'MAINTENANCE_KEY' => '__MAINTENANCE_KEY__',

    // Base de datos (MySQL o MariaDB).
    'DB_CONNECTION' => 'mysql',
    'DB_HOST' => '__DB_HOST__',
    'DB_PORT' => '3306',
    'DB_DATABASE' => '__DB_DATABASE__',
    'DB_USERNAME' => '__DB_USERNAME__',
    'DB_PASSWORD' => '__DB_PASSWORD__',

    // Carpeta de trabajo (caché, registro de errores) fuera de la parte
    // pública, y carpeta temporal del hospedaje.
    'STORAGE_PATH' => '__TEMP_PATH__/miruta',
    'TEMP_PATH' => '__TEMP_PATH__',

    // Sin cron: las tareas programadas se ejecutan con las peticiones.
    'TASKS_ON_REQUESTS' => true,

    'CACHE_DRIVER' => 'file',
    'QUEUE_CONNECTION' => 'sync',
    'LOG_CHANNEL' => 'stack',
    'DOCS_ENABLED' => false,
];
