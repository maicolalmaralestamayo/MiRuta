<?php

/*
| MiRuta en un hospedaje compartido: punto de entrada.
|
| El código del servidor (con vendor/) está en la subcarpeta servidor/
| (protegida por su .htaccess) y su configuración en servidor/configuracion.php.
*/

define('LARAVEL_START', microtime(true));

$_ENV['PUBLIC_PATH'] = $_SERVER['PUBLIC_PATH'] = __DIR__;
putenv('PUBLIC_PATH='.__DIR__);

/** @var Illuminate\Foundation\Application $app */
$app = require __DIR__.'/servidor/bootstrap/app.php';

$app->handleRequest(Illuminate\Http\Request::capture());
