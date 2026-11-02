<?php
/*
| MiRuta: desempaqueta miruta-servidor.zip en esta carpeta, para no tener que
| subir miles de archivos por FTP.
|
|  1. Suba este archivo y miruta-servidor.zip a /htdocs/miruta/
|  2. Abra en el navegador: http://su-dominio/miruta/desempaquetar.php?clave=CLAVE
|
| Al terminar se borran el .zip y este archivo. Escrito para PHP 5.4 o superior.
*/

header('Content-Type: text/html; charset=utf-8');
header('X-Robots-Tag: noindex');

// Si MiRuta ya está instalado (actualización), vale la clave de su configuración.
$key = '__MAINTENANCE_KEY__';
$installedConfig = __DIR__.'/servidor/configuracion.php';
if (is_file($installedConfig)) {
    $installed = (array) require $installedConfig;
    if (! empty($installed['MAINTENANCE_KEY'])) {
        $key = (string) $installed['MAINTENANCE_KEY'];
    }
}
$given = isset($_GET['clave']) ? (string) $_GET['clave'] : '';
$zipFile = __DIR__.'/miruta-servidor.zip';

function finish($message, $ok)
{
    echo '<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'
        .'<title>MiRuta · Desempaquetar</title></head><body style="font-family:system-ui,sans-serif;margin:16px">'
        .'<h1>MiRuta · Desempaquetar</h1><p style="color:'.($ok ? '#1b7f3b' : '#b3261e').'">'.$message.'</p></body></html>';
    exit;
}

if (strlen($key) < 16 || ! function_exists('hash_equals') || ! hash_equals($key, $given)) {
    http_response_code(403);
    finish('Escriba la clave de mantenimiento en la dirección: desempaquetar.php?clave=...', false);
}

if (! class_exists('ZipArchive')) {
    finish('Este PHP no tiene la extensión zip. Suba en su lugar la carpeta completa (vea LEEME.md, opción B).', false);
}

if (! is_file($zipFile)) {
    finish('No encuentro miruta-servidor.zip en esta carpeta. Súbalo con FileZilla en modo binario.', false);
}

@set_time_limit(600);
$zip = new ZipArchive();

if ($zip->open($zipFile) !== true) {
    finish('No se pudo abrir miruta-servidor.zip. Vuelva a subirlo en modo binario (puede haber llegado incompleto).', false);
}

$count = $zip->numFiles;

if (! $zip->extractTo(__DIR__)) {
    $zip->close();
    finish('No se pudo desempaquetar: compruebe que PHP puede escribir en esta carpeta (permisos 775 o 777 con FileZilla).', false);
}

$zip->close();
@unlink($zipFile);
@unlink(__FILE__);

finish('Listo: '.$count.' archivos desempaquetados. Ahora abra '
    .'<a href="diagnostico.php?clave='.htmlspecialchars($given).'">el diagnóstico</a> para comprobar el hospedaje.', true);
