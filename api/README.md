# MiTransporte — API

API JSON:API de MiTransporte, hecha con Lumen 7. La documentación funcional y técnica está en [`../docs`](../docs/README.md).

## Requisitos

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
| `CARD_HASH_KEY` | `php -r "echo bin2hex(random_bytes(32)).PHP_EOL;"` |
| `DB_*` | Base de datos y usuario de MariaDB (en el servidor, `DB_HOST=127.0.0.1`) |

> **No cambiar `APP_KEY` ni `CARD_HASH_KEY` una vez haya datos.** Con otra `APP_KEY` no se podrían descifrar los carnés, y con otra `CARD_HASH_KEY` no se encontraría a nadie al iniciar sesión.

Después:

```bash
php artisan migrate --seed
php -S localhost:8000 -t public
```

Con `DOCS_ENABLED=true`, Swagger UI está en <http://localhost:8000/docs>.

## Tareas programadas

Marcan los viajes como realizados, borran chats y aplican la baja por inactividad (ver `docs/02-procesos.md` §2.12). En el servidor hace falta una línea de `cron` que ejecute el planificador cada minuto:

```cron
* * * * * cd /ruta/a/api && php artisan schedule:run >> /dev/null 2>&1
```

Se pueden lanzar a mano: `php artisan trips:auto-complete`, `chats:purge-trips`, `chats:purge-expired` y `workers:inactivity`.

## Pruebas

Con Docker, usando PHP 7.2 y MariaDB 10.6 (las versiones mínimas):

```bash
docker/test-api.sh                         # desde la raíz del repositorio
docker/test-api.sh --filter CardNumberTest # una sola clase
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
  Support/           Objetos de valor (CardNumber)
config/              mitransporte.php (claves y paginación), jsonapi.php (serializadores)
database/            Migraciones, seeders y factories
resources/lang/es/   Mensajes de validación en español
```
