<?php
/*
| MiRuta: diagnóstico del hospedaje.
|
| No usa el resto del servidor, así que funciona aunque la API no arranque
| (por ejemplo, con una versión de PHP que no sirve). Ábralo en el navegador:
|   http://su-dominio/miruta/diagnostico.php?clave=CLAVE_DE_MANTENIMIENTO
| Escrito para que funcione con cualquier PHP desde 5.4.
*/

header('Content-Type: text/html; charset=utf-8');
header('X-Robots-Tag: noindex');

$configFile = __DIR__.'/servidor/configuracion.php';
$config = is_file($configFile) ? (array) require $configFile : array();
$key = isset($config['MAINTENANCE_KEY']) ? (string) $config['MAINTENANCE_KEY'] : '';
$given = isset($_GET['clave']) ? (string) $_GET['clave'] : '';

if (strlen($key) < 16 || ! function_exists('hash_equals') || ! hash_equals($key, $given)) {
    http_response_code(403);
    echo '<p>Escriba la clave de mantenimiento en la dirección: diagnostico.php?clave=...</p>';
    exit;
}

$rows = array();

function row(&$rows, $label, $ok, $value)
{
    $rows[] = array($label, $ok, $value);
}

// PHP
$version = PHP_VERSION;
$phpOk = version_compare($version, '7.2.5', '>=') && version_compare($version, '8.1.0', '<');
row($rows, 'Versión de PHP', $phpOk, $version.($phpOk ? '' : ' (hace falta de 7.2.5 a 8.0)'));

foreach (array('pdo_mysql', 'mbstring', 'openssl', 'json', 'fileinfo', 'tokenizer', 'ctype', 'zip', 'gd') as $extension) {
    $optional = in_array($extension, array('zip', 'gd'), true);
    $loaded = extension_loaded($extension);
    row($rows, 'Extensión '.$extension, $loaded ? true : ($optional ? null : false), $loaded ? 'sí' : ($optional ? 'no (opcional)' : 'no'));
}

foreach (array('upload_max_filesize', 'post_max_size', 'memory_limit', 'max_execution_time', 'open_basedir', 'disable_functions') as $setting) {
    $value = ini_get($setting);
    row($rows, $setting, null, $value === '' || $value === false ? '(sin valor)' : $value);
}
row($rows, 'Servidor web', null, isset($_SERVER['SERVER_SOFTWARE']) ? $_SERVER['SERVER_SOFTWARE'] : '?');
row($rows, 'PHP corre como', null, PHP_SAPI);

// Configuración
row($rows, 'servidor/configuracion.php', is_file($configFile), is_file($configFile) ? 'encontrado' : 'falta');
foreach (array('APP_KEY', 'JWT_SECRET') as $name) {
    $set = isset($config[$name]) && strlen($config[$name]) >= 32 && strpos($config[$name], '__') === false;
    row($rows, $name, $set, $set ? 'puesta' : 'falta o es demasiado corta');
}
row($rows, 'Código del servidor (vendor/)', is_file(__DIR__.'/servidor/vendor/autoload.php'), is_file(__DIR__.'/servidor/vendor/autoload.php') ? 'completo' : 'falta: suba la carpeta servidor/vendor completa');

// Carpetas
$folders = array(
    'Carpeta de archivos subidos (uploads)' => __DIR__.'/uploads',
    'Carpeta de trabajo (STORAGE_PATH)' => isset($config['STORAGE_PATH']) ? $config['STORAGE_PATH'] : '',
    'Carpeta temporal (TEMP_PATH)' => isset($config['TEMP_PATH']) ? $config['TEMP_PATH'] : '',
);
// Si la carpeta de trabajo no sirve, se usa servidor/storage.
$storage = isset($config['STORAGE_PATH']) ? $config['STORAGE_PATH'] : '';
if ($storage === '' || ! (is_dir($storage) || @mkdir($storage, 0775, true)) || ! is_writable($storage)) {
    $folders['Carpeta de trabajo de respaldo (servidor/storage)'] = __DIR__.'/servidor/storage';
}
foreach ($folders as $label => $path) {
    if ($path === '') {
        continue;
    }
    if (! is_dir($path)) {
        @mkdir($path, 0775, true);
    }
    $writable = is_dir($path) && is_writable($path);
    row($rows, $label, $writable, $path.($writable ? ' (se puede escribir)' : (is_dir($path) ? ' (NO se puede escribir: dé permisos 775 o 777 con FileZilla)' : ' (no existe y no se pudo crear)')));
}

// Base de datos
if (! empty($config['DB_HOST'])) {
    $dsn = 'mysql:host='.$config['DB_HOST'].';port='.(isset($config['DB_PORT']) ? $config['DB_PORT'] : '3306').';dbname='.$config['DB_DATABASE'].';charset=utf8mb4';
    try {
        $pdo = new PDO($dsn, $config['DB_USERNAME'], $config['DB_PASSWORD'], array(PDO::ATTR_TIMEOUT => 5, PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION));
        $server = $pdo->query('SELECT VERSION()')->fetchColumn();
        row($rows, 'Base de datos', true, 'conecta ('.$server.')');
        $tables = $pdo->query("SHOW TABLES LIKE 'users'")->fetchColumn();
        row($rows, 'Tablas de MiRuta', $tables ? true : null, $tables ? 'instaladas' : 'aún no: instálelas desde la app (Mantenimiento del servidor)');
    } catch (Exception $e) {
        row($rows, 'Base de datos', false, $e->getMessage());
        foreach (array(3306 => 'MySQL/MariaDB', 5432 => 'PostgreSQL') as $port => $engine) {
            $socket = @fsockopen($config['DB_HOST'], $port, $errno, $errstr, 3);
            row($rows, 'Puerto '.$port.' ('.$engine.')', null, $socket ? 'abierto' : 'cerrado');
            if ($socket) {
                fclose($socket);
            }
        }
    }
}

?><!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>MiRuta · Diagnóstico</title>
<style>
body{font-family:system-ui,sans-serif;margin:16px;color:#1b2a41}
table{border-collapse:collapse;width:100%;max-width:900px}
td{border-bottom:1px solid #ddd;padding:6px 8px;vertical-align:top;word-break:break-word}
.ok{color:#1b7f3b}.mal{color:#b3261e;font-weight:bold}.info{color:#555}
</style></head><body>
<h1>MiRuta · Diagnóstico del hospedaje</h1>
<table>
<?php foreach ($rows as $r): ?>
<tr><td><?php echo htmlspecialchars($r[0]); ?></td>
<td class="<?php echo $r[1] === true ? 'ok' : ($r[1] === false ? 'mal' : 'info'); ?>"><?php echo $r[1] === true ? '✔' : ($r[1] === false ? '✘' : '·'); ?> <?php echo htmlspecialchars((string) $r[2]); ?></td></tr>
<?php endforeach; ?>
</table>
<p>Compruebe también que el código está protegido: al abrir <code>servidor/composer.json</code> en el navegador debe salir «Forbidden» (prohibido).</p>
</body></html>
