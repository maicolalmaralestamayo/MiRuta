<?php

/*
| MiRuta en un hospedaje compartido: punto de entrada.
|
| El código del servidor está en la subcarpeta servidor/ (protegida por su
| .htaccess) y su configuración en servidor/configuracion.php.
*/

$_ENV['PUBLIC_PATH'] = $_SERVER['PUBLIC_PATH'] = __DIR__;
putenv('PUBLIC_PATH='.__DIR__);

$app = require __DIR__.'/servidor/bootstrap/app.php';

$app->run();
