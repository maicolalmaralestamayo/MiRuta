# MiRuta — API

API JSON:API de MiRuta (antes MiTransporte), hecha con Lumen 7. La documentación funcional y técnica está en [`../docs`](../docs/README.md).

## Probar en un PC con Docker

Lo más sencillo: solo hace falta [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Windows, macOS o Linux).
No hay que instalar PHP, Composer ni MariaDB.

```bash
git clone https://github.com/maicolalmaralestamayo/MiTransporte.git
cd MiTransporte
git checkout claude/proceso-stack-discussion-idsu8k
docker compose -f docker/dev/compose.yml up --build
```

La primera vez tarda unos minutos (descarga las imágenes y las dependencias). Cuando en la consola aparece
«API lista», ya responde:

| Qué | Dónde |
|---|---|
| API | <http://localhost:8000/api/v1> |
| Documentación (Swagger) | <http://localhost:8000/docs> |
| Base de datos (MariaDB) | `localhost:3307`, base `miruta`, usuario y contraseña `miruta` |

También arranca las tareas programadas (viajes realizados, atrasos, avisos…). Las claves de
`docker/dev/compose.yml` son solo para pruebas.

**Desde el teléfono**: el PC y el teléfono en la misma red Wi-Fi. En la app, botón del servidor →
protocolo **http** y dirección `IP-DEL-PC:8000` (por ejemplo `192.168.1.20:8000`). La IP se ve con `ipconfig`
(Windows) o `ip addr` (Linux). Si no conecta, permita el puerto 8000 en el cortafuegos del PC.
La primera cuenta que se registre es la del Administrador.

Otras órdenes útiles:

```bash
docker compose -f docker/dev/compose.yml down        # parar
docker compose -f docker/dev/compose.yml down -v     # parar y BORRAR la base de datos (empezar de cero)
docker compose -f docker/dev/compose.yml exec api php artisan migrate:fresh --seed   # vaciar la base
```

El mapa necesita además el servidor de mapas (`tools/maps`); sin él, todo lo demás funciona.

## Requisitos (instalación sin Docker)

- PHP 7.2.5 o superior, con las extensiones `pdo_mysql`, `mbstring` y `openssl`.
- MariaDB 10.3 o superior.
- Composer 2.

## Instalación

```bash
cd api
composer install
cp .env.example .env
```

En `.env`, completar:

| Variable | Cómo generarla |
|---|---|
| `APP_KEY` | `php -r "echo 'base64:'.base64_encode(random_bytes(32)).PHP_EOL;"` |
| `JWT_SECRET` | `php -r "echo bin2hex(random_bytes(32)).PHP_EOL;"` (cambiarla cierra todas las sesiones) |
| `DB_*` | Base de datos y usuario de MariaDB (en el servidor, `DB_HOST=127.0.0.1`) |

> **No cambiar `APP_KEY` una vez haya datos.** Con otra `APP_KEY` no se podrían descifrar los datos cifrados guardados ni validar los códigos de activación pendientes.

Después:

```bash
php artisan migrate --seed
php -S localhost:8000 -t public
```

Con `DOCS_ENABLED=true`, Swagger UI está en <http://localhost:8000/docs>.

## Actualizaciones de la app

El Administrador publica los APK desde la app; se guardan en `public/uploads/apk/`. Como pesan decenas de MB, en `php.ini` hay que permitir subidas grandes (y el ajuste `app_max_mb` limita el tamaño, 150 MB por defecto):

```ini
upload_max_filesize = 200M
post_max_size = 200M
```

## Tareas programadas

Marcan los viajes como realizados, borran chats y aplican la baja por inactividad (ver `docs/02-procesos.md` §2.13). En el servidor hace falta una línea de `cron` que ejecute el planificador cada minuto:

```cron
* * * * * cd /ruta/a/api && php artisan schedule:run >> /dev/null 2>&1
```

**Sin cron** (hospedaje compartido): con `TASKS_ON_REQUESTS=true` la API ejecuta las tareas pendientes al terminar las peticiones, como mucho una vez por minuto; las diarias y por hora se recuperan en la primera petición posterior (`App\Services\ScheduledTasks`).

## Hospedaje compartido sin SSH

`tools/release/build-hosting-package.sh` prepara un paquete para subir por FTP (guía en `docs/10-traspaso.md`):

- la configuración va en `configuracion.php` (PHP que devuelve un arreglo con las claves de `.env`), que el servidor web nunca muestra;
- `STORAGE_PATH` saca la carpeta de trabajo de la parte pública y `TEMP_PATH` fija la carpeta temporal;
- el mantenimiento se hace desde la app: `GET /api/v1/server-status` y `POST /api/v1/maintenance-runs` (`install`, `migrate`, `run-tasks`, `clear-cache`, `log`), con la sesión del Administrador o la cabecera `X-Maintenance-Key` (`MAINTENANCE_KEY`, al menos 16 caracteres).

Se pueden lanzar a mano: `php artisan trips:auto-complete`, `trips:notify-delays`, `chats:purge-trips`, `chats:purge-expired`, `workers:inactivity`, `access-recoveries:expire` y `passwords:warn-expiry`.

## Pruebas

Con Docker, usando PHP 7.2 y MariaDB 10.6 (las versiones mínimas):

```bash
docker/test-api.sh                         # desde la raíz del repositorio
docker/test-api.sh --filter TripsTest      # una sola clase
```

Sin Docker: crear una base `mitransporte_test` y ejecutar `vendor/bin/phpunit` (los datos de conexión de pruebas están en `phpunit.xml` y se pueden sustituir con variables de entorno).

Las pruebas también se ejecutan en GitHub Actions en cada *pull request* (`.github/workflows/api.yml`).

## Estructura

```
app/
  Http/Controllers/  Controladores (uno por recurso)
  Http/Middleware/   RequireJsonApi: negociación de contenido de JSON:API
  JsonApi/           Documentos, parámetros de consulta (page, sort, filter, include) y errores
  Models/            Modelos Eloquent
  Rules/             Reglas de validación propias
  Serializers/       Capa de "vista": modelo → recurso JSON:API
  Services/          Lógica que abarca varios modelos
  Support/           Utilidades (nombres de usuario, fechas, textos de avisos, lectura del APK)
config/              mitransporte.php (claves y paginación), jsonapi.php (serializadores)
database/            Migraciones, seeders y factories
resources/lang/es/   Mensajes de validación en español
```
