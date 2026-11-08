# MiRuta — API

API JSON:API de MiRuta hecha con **Laravel 12** (PHP 8.2; el hospedaje tiene PHP 8.2.35). La referencia de todas las
rutas para la app está en [`docs/13-api-proxima-version.md`](../docs/13-api-proxima-version.md) y la especificación
OpenAPI en [`docs/openapi.yaml`](../docs/openapi.yaml). Los acuerdos funcionales, en `docs/11` y `docs/12`.

## Dependencias

Solo `laravel/framework` (y, para las pruebas, `phpunit/phpunit`). `composer.json` fija la plataforma a PHP 8.2.35,
así que `composer.lock` sirve para el hospedaje aunque se instale con otra versión de PHP. Sin librerías de JWT: los
tokens se firman con una implementación propia y mínima (`app/Support/Jwt.php`, HS256).

## Instalación en un PC

Requisitos: PHP 8.2 o superior con `pdo_mysql` (o `pdo_sqlite`), `mbstring`, `openssl`, `fileinfo`, `xml`, `zip`;
MariaDB 10.3 o superior; Composer 2.

```bash
cd api
composer install          # o, si no se pueden descargar los .zip de GitHub: python3 ../tools/release/vendor-desde-git.py .
cp .env.example .env      # completar APP_KEY, JWT_SECRET, MAINTENANCE_KEY y DB_*
php artisan migrate --seed
php -S 0.0.0.0:8000 -t public
```

| Variable | Cómo generarla |
|---|---|
| `APP_KEY` | `php -r "echo 'base64:'.base64_encode(random_bytes(32)).PHP_EOL;"` (no cambiarla con datos: cifra los carnés) |
| `JWT_SECRET` | `php -r "echo bin2hex(random_bytes(32)).PHP_EOL;"` (cambiarla cierra todas las sesiones) |
| `MAINTENANCE_KEY` | 16 caracteres o más: mantenimiento del servidor sin sesión |

En el hospedaje no hay `.env`: la configuración va en `configuracion.php` (un PHP que devuelve las mismas claves; lo
lee `bootstrap/app.php`). Con `STORAGE_PATH`, la caché, el registro de errores y los archivos de caché de Laravel
van a esa carpeta, fuera de la parte pública. Con `DOCS_ENABLED=true`, Swagger UI está en `/docs`.

Sin cron: con `TASKS_ON_REQUESTS=true` las tareas programadas (revisión de viajes, limpiezas) se ejecutan al terminar
las peticiones, como mucho una vez por minuto; también desde la app (`POST maintenance-runs` con `run-tasks`) o con
`php artisan miruta:tareas`.

## Pruebas

```bash
vendor/bin/phpunit                         # SQLite en memoria (rápido)
DB_CONNECTION=mysql DB_HOST=127.0.0.1 DB_DATABASE=miruta_test DB_USERNAME=miruta DB_PASSWORD=secret vendor/bin/phpunit
docker/test-api.sh                         # PHP 8.2 y MariaDB 10.3 en Docker (desde la raíz del repositorio)
```

## Paquete para el hospedaje

`tools/release/build-hosting-package.sh <versión>` genera en `entregas/hosting/` un `.zip` con el servidor y su
`vendor/` ya instalado (`--no-dev --optimize-autoloader`), listo para subir por FTP. Ver `docs/10-traspaso.md`.

## Estructura

| Carpeta | Contenido |
|---|---|
| `app/Http/Controllers` | Un controlador por recurso JSON:API (`Nomenclators/` para los nomencladores) |
| `app/Http/Middleware` | JSON:API, actualización obligatoria (`X-App-Version`), sesión, instalación, mantenimiento y tareas con las peticiones |
| `app/Services` | Reglas: `Access` (tres roles fijos), `Memberships`, `Organization` (cascadas), `Applications`, `Trips` (tiempo real), `Notifier` (notificaciones para `GET /sync`), `Settings`, `QrCodes`, `QrInclusions`, `ScheduledTasks`… |
| `app/Serializers` | Modelo → recurso JSON:API |
| `app/Support` | Carné, usuario, JWT, unidades de los ajustes (`Units`) y catálogo de ajustes (`SettingCatalog`) |
| `app/JsonApi` | Documentos, errores, parámetros de consulta y negociación de contenido |
| `database/migrations` | Esquema desde cero (MariaDB 10.3) |
| `tests` | PHPUnit 11 |
