<?php
/*
| MiRuta con el servidor web de PHP (solo para un entorno local o de pruebas):
|
|   cd htdocs
|   php -S 0.0.0.0:8080 miruta/router.php
|
| Hace lo mismo que .htaccess en Apache: no sirve el código (servidor/) ni los
| archivos ocultos, sirve tal cual los archivos que existen (fotos, APK) y
| manda todo lo demás a index.php.
*/

$path = rawurldecode((string) parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH));
$base = '/'.basename(__DIR__);

if ($path !== $base && strpos($path, $base.'/') !== 0) {
    http_response_code(404);
    echo 'MiRuta está en '.$base.'/';
    return true;
}

$relative = (string) substr($path, strlen($base));

if (preg_match('#^/servidor(/|$)#', $relative) || strpos($relative, '/.') !== false) {
    http_response_code(403);
    echo 'Forbidden';
    return true;
}

if ($relative !== '' && $relative !== '/' && is_file(__DIR__.$relative) && substr($relative, -4) !== '.php') {
    return false;
}

if (in_array($relative, array('/diagnostico.php', '/desempaquetar.php'), true) && is_file(__DIR__.$relative)) {
    require __DIR__.$relative;
    return true;
}

$_SERVER['SCRIPT_NAME'] = $base.'/index.php';
$_SERVER['SCRIPT_FILENAME'] = __DIR__.'/index.php';
$_SERVER['PHP_SELF'] = $base.'/index.php';

require __DIR__.'/index.php';
