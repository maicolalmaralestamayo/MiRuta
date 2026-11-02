# Instalar el servidor de MiRuta 2.1.0 en producción

Este paquete trae la API lista para usar: el código, sus dependencias (`vendor/`) y la base de datos inicial.
No hace falta Composer ni Internet en el servidor.

## 1. Requisitos

| Qué | Versión |
|---|---|
| PHP | **7.2.5 a 7.4** (recomendado 7.4). Con PHP 8.1 o superior no funciona. |
| Extensiones de PHP | `pdo_mysql`, `mbstring`, `openssl`, `json`, `fileinfo`, `zlib` (casi siempre vienen activadas) |
| Base de datos | MariaDB 10.3 o superior (o MySQL 5.7 / 8) |
| Servidor web | Apache con `mod_rewrite` o nginx + PHP-FPM |

En `php.ini` (para poder publicar los APK de las actualizaciones):

```ini
upload_max_filesize = 200M
post_max_size = 200M
```

## 2. Copiar los archivos

1. Suba la carpeta `miruta-api` al servidor, por ejemplo a `/var/www/miruta-api`.
2. El sitio web debe apuntar a la carpeta **`public`** (no a `miruta-api`):
   - **Apache**: `DocumentRoot /var/www/miruta-api/public` y `AllowOverride All` (ya trae su `.htaccess`).
   - **nginx**: use `servidor/nginx-miruta.conf` como plantilla.
   - **Hosting con cPanel**: apunte el dominio o subdominio a `miruta-api/public`.
3. El servidor web debe poder **escribir** en `storage/` y `public/uploads/`:

   ```bash
   chown -R www-data:www-data storage public/uploads
   chmod -R 775 storage public/uploads
   ```

## 3. Base de datos

Cree una base de datos y un usuario, por ejemplo:

```sql
CREATE DATABASE miruta CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'miruta'@'localhost' IDENTIFIED BY 'una-contraseña-segura';
GRANT ALL PRIVILEGES ON miruta.* TO 'miruta'@'localhost';
```

Después cree las tablas y los datos iniciales de **una** de estas dos formas:

- **Con acceso por consola (SSH)**, desde la carpeta `miruta-api` (después del paso 4):

  ```bash
  php artisan migrate --seed --force
  ```

- **Sin consola** (phpMyAdmin u otra herramienta): importe `database/miruta-2.1.0-inicial.sql` en la base vacía.

## 4. Configuración (`.env`)

```bash
cp .env.example .env
```

Complete en `.env`:

| Variable | Valor |
|---|---|
| `APP_URL` | Dirección pública, p. ej. `https://miruta.miempresa.cu` |
| `APP_KEY` | `php -r "echo 'base64:'.base64_encode(random_bytes(32)).PHP_EOL;"` |
| `JWT_SECRET` | `php -r "echo bin2hex(random_bytes(32)).PHP_EOL;"` |
| `DB_*` | Los datos de la base del paso 3 |

> **Guarde una copia de `APP_KEY` y `JWT_SECRET`.** Si se pierde `APP_KEY` no se podrán leer los datos cifrados;
> si cambia `JWT_SECRET`, todos tendrán que volver a entrar.

Si no puede ejecutar `php` en el servidor, genere las claves en cualquier otro equipo con PHP y cópielas.

## 5. Tareas programadas

Marcan los viajes como realizados, avisan de los atrasos, borran chats antiguos, aplican la baja por
inactividad, etc. Necesitan una línea en el `cron` que se ejecute **cada minuto**:

```cron
* * * * * cd /var/www/miruta-api && php artisan schedule:run >> /dev/null 2>&1
```

En cPanel: *Trabajos de cron* → «Una vez por minuto» → la misma orden con la ruta de su cuenta.

**Si no hay cron**, ponga `TASKS_ON_REQUESTS=true` en `.env`: las tareas se ejecutan mientras la app se usa
(como mucho una vez por minuto). Para un hospedaje compartido con solo FTP use mejor el paquete de hospedaje
(`tools/release/build-hosting-package.sh`, guía en `docs/10-traspaso.md`).

## 6. Comprobar

Abra en el navegador `https://su-dominio/api/v1/password-policy`: debe responder un texto JSON que empieza por
`{"data":{"type":"password-policies"…`.

## 7. Conectar la app

En la app, botón del servidor:

- **Protocolo**: `https` si el servidor tiene certificado; si no, `http`.
- **Dirección**: el dominio o la IP (p. ej. `miruta.miempresa.cu`). Si la API está en una subcarpeta,
  inclúyala (p. ej. `miempresa.cu/miruta`). La app añade `/api/v1` sola.

**La primera cuenta que se registre es la del Administrador.** Regístrela usted antes de repartir la app.

## 8. Opcional

- **Mapa propio**: siga `servidor/mapas/README.md` (necesita Docker en el servidor).
- **HTTPS**: con un dominio, un certificado gratuito de Let's Encrypt (`certbot`) basta.
- **Documentación de la API**: `DOCS_ENABLED=true` en `.env` la publica en `/docs` (mejor dejarla desactivada en producción).

## Actualizar a una versión nueva

1. Haga una copia de seguridad de la base de datos y de `.env`, `storage/` y `public/uploads/`.
2. Sustituya los archivos por los del paquete nuevo, conservando `.env`, `storage/` y `public/uploads/`.
3. Ejecute `php artisan migrate --force` (o el script SQL de actualización que acompañe al paquete).
