# 10. Traspaso de tecnología — MiRuta 2.2.0

> **Versión 3.0.0:** el modelo de datos cambió (carné, varias Entidades por persona, roles configurables, QR). Los
> pasos de puesta en marcha son los mismos, pero la base de datos de la 3.0 se instala **desde cero**: no se
> actualiza sobre una 2.x. Los nombres de archivo con «2.2.0» se refieren a la última entrega hecha.

Qué se entrega y cómo poner en marcha MiRuta en cada entorno: el hospedaje, un ordenador con Docker y un
ordenador sin Docker. Se da por hecho que Docker, Apache o nginx, PHP y MySQL/MariaDB ya están instalados.

## 10.1 Qué se entrega

```
traspaso-2.2.0/
├── 1-app/
│   ├── MiRuta-2.2.0-64bits.apk           App para casi todos los teléfonos (Android 7.0 o superior)
│   ├── MiRuta-2.2.0-32bits.apk           App para teléfonos antiguos de 32 bits
│   └── MiRuta-2.2.0-simbolos.zip         Símbolos para leer los errores de esta versión (§10.2)
├── 2-servidor-docker/
│   ├── miruta-2.2.0-imagenes.tar.gz      Imágenes para «docker load»: miruta-api:2.2.0 y mariadb:10.6
│   └── compose.yml                       Arranque de la API, la base de datos y las tareas programadas
├── 3-servidor-zip/
│   └── miruta-servidor-2.2.0.zip         Servidor para el hospedaje o para un ordenador sin Docker
└── GUIA.md                               Esta guía
```

Contenido de `miruta-servidor-2.2.0.zip`:

| Carpeta o archivo | Para qué |
|---|---|
| `htdocs/miruta/` | El servidor completo, listo para copiar dentro de la carpeta pública del sitio web |
| `htdocs/miruta/servidor/configuracion.php` | **La configuración**: base de datos, claves y carpetas. Ya trae los datos del hospedaje. |
| `htdocs/miruta/.htaccess` | Reglas para Apache: protege `servidor/` y pasa todo a la API |
| `htdocs/miruta/router.php` | Lo mismo que `.htaccess`, para el servidor web de PHP (`php -S`) |
| `htdocs/miruta/diagnostico.php` | Comprueba PHP, extensiones, carpetas y base de datos desde el navegador |
| `subida-rapida/` | Todo `htdocs/miruta` en un solo `.zip` más `desempaquetar.php`, para subir 2 archivos por FTP |
| `base-de-datos/miruta-2.2.0-inicial.sql` | La base de datos inicial vacía, por si prefiere importarla usted |
| `otros/nginx-miruta.conf` | Reglas para nginx (equivalen a `.htaccess`) |
| `CLAVE-DE-MANTENIMIENTO.txt` | La clave para instalar y mantener el servidor desde la app y para el diagnóstico |

**Guarde aparte**, además de esta entrega:

- la clave de firma de la app: `mitransporte-release.jks` y `key.properties`, entregados el 30/10;
- su `configuracion.php` una vez puesto en marcha.

Sin la clave de firma ninguna versión nueva de la app se instalará encima de esta.

## 10.2 La app

1. Copie al teléfono **`MiRuta-2.2.0-64bits.apk`**. Use la de 32 bits solo si el teléfono no admite la de 64.
   Ábrala y permita «instalar apps desconocidas».
2. La app trae puesta la dirección del hospedaje: `http://www.twintechnology.cu/miruta`. Para usar otro
   servidor, en la pantalla de inicio de sesión pulse el **botón del servidor**, elija el protocolo y escriba la
   dirección:

   | Servidor | Protocolo | Dirección |
   |---|---|---|
   | Hospedaje | http | `www.twintechnology.cu/miruta` |
   | Ordenador con Docker | http | `IP-DEL-ORDENADOR:8000` |
   | Ordenador sin Docker (Apache o nginx) | http | `IP-DEL-ORDENADOR/miruta` |
   | Ordenador sin Docker (`php -S`) | http | `IP-DEL-ORDENADOR:8080/miruta` |

   El teléfono y el ordenador tienen que estar en la misma red. La IP se ve con `ipconfig` (Windows) o
   `ip addr` (Linux).

3. En cada servidor nuevo, **la primera cuenta que se crea es la del Administrador.**

**Mantenimiento del servidor desde la app:**

- Como Administrador: *Más → Gestión → Mantenimiento del servidor*.
- Sin sesión: botón del servidor → *Mantenimiento del servidor* → clave de mantenimiento.

**Símbolos (`MiRuta-2.2.0-simbolos.zip`).** La app va ofuscada. Si un usuario envía el texto de un error de la
versión 2.2.0, se traduce a nombres legibles con Flutter:

```bash
unzip MiRuta-2.2.0-simbolos.zip
flutter symbolize -i error.txt -d 2.2.0+8/app.android-arm64.symbols    # app de 64 bits
flutter symbolize -i error.txt -d 2.2.0+8/app.android-arm.symbols      # app de 32 bits
```

## 10.3 Entorno 1: el hospedaje (solo FTP)

Use `miruta-servidor-2.2.0.zip`. Su `configuracion.php` ya trae la base de datos, la carpeta temporal y unas
claves generadas para este servidor.

1. **Subir.** Con FileZilla (FTP explícito sobre TLS, modo pasivo, transferencia binaria, como mucho 2
   conexiones), cree `/htdocs/miruta/` y suba allí los 2 archivos de `subida-rapida/`. Después abra:
   `http://www.twintechnology.cu/miruta/desempaquetar.php?clave=CLAVE`

   El servidor desempaqueta todo y borra esos dos archivos. Si responde que falta la extensión zip, suba el
   contenido de `htdocs/miruta/` en su lugar. Incluya los archivos que empiezan por punto: en FileZilla,
   *Servidor → Forzar mostrar archivos ocultos*.
2. **Comprobar.** Abra `http://www.twintechnology.cu/miruta/diagnostico.php?clave=CLAVE`. Todo debe salir con
   ✔. Si `uploads` no se puede escribir, dele permisos 775 (o 777) con FileZilla. Compruebe también que
   `…/miruta/servidor/composer.json` responde *Forbidden*.
3. **Instalar la base de datos.** En la app: botón del servidor → *Mantenimiento del servidor* → clave →
   **Instalar base de datos**. También puede importar `base-de-datos/miruta-2.2.0-inicial.sql` con el gestor de
   la base de datos del hospedaje.
4. **Crear la cuenta del Administrador** desde la app (§10.2, paso 3).

**Particularidades del hospedaje:**

- No hay cron. Las tareas programadas se ejecutan con el uso de la app (`TASKS_ON_REQUESTS`).
- La caché y el registro de errores van a su carpeta temporal (`STORAGE_PATH`), fuera de la parte pública.
- El sitio va por http. El certificado del hospedaje es autofirmado y solo sirve para su administración.

## 10.4 Entorno 2: un ordenador con Docker

Use la carpeta `2-servidor-docker/`. No necesita Internet.

```bash
docker load -i miruta-2.2.0-imagenes.tar.gz
docker compose -f compose.yml up -d
```

La primera vez crea la base de datos y la deja lista en menos de un minuto.

| Qué | Dónde |
|---|---|
| API | `http://localhost:8000/api/v1` (desde el teléfono: `http://IP-DEL-ORDENADOR:8000`) |
| Documentación de la API (Swagger) | `http://localhost:8000/docs` |
| Base de datos | MariaDB en el puerto **3307** del ordenador; base, usuario y contraseña `miruta` |
| Clave de mantenimiento | `miruta-mantenimiento-local-1234` (en `compose.yml`) |
| Tareas programadas | Servicio `scheduler`, cada minuto |

Órdenes útiles:

```bash
docker compose -f compose.yml logs -f api      # ver lo que pasa
docker compose -f compose.yml stop             # parar (los datos se conservan)
docker compose -f compose.yml down -v          # borrar todo, también los datos, para empezar de cero
```

Los datos (base de datos, fotos y APK) se guardan en volúmenes de Docker y sobreviven a reinicios.

**Para usar Docker en un servidor real**, cambie antes en `compose.yml`:

- `APP_KEY`, `JWT_SECRET`, `MAINTENANCE_KEY` y las contraseñas de la base de datos;
- `APP_DEBUG: "false"` y `DOCS_ENABLED: "false"`;
- quite `ports` de la base de datos.

Las claves nuevas se generan con:

```bash
php -r "echo 'base64:'.base64_encode(random_bytes(32)), PHP_EOL, bin2hex(random_bytes(32)), PHP_EOL;"
```

## 10.5 Entorno 3: un ordenador sin Docker (Apache o nginx, PHP y MySQL/MariaDB)

Use `miruta-servidor-2.2.0.zip`. Hace falta:

- **PHP de 7.2.5 a 8.0**, con las extensiones `pdo_mysql`, `mbstring`, `openssl`, `json`, `fileinfo`,
  `tokenizer` y `ctype`;
- **MariaDB 10.3+** o **MySQL 5.7+**.

1. **Copiar.** Copie la carpeta `htdocs/miruta` dentro de la carpeta pública de su servidor web: por ejemplo
   `C:\xampp\htdocs\miruta` o `/var/www/html/miruta`.
2. **Crear la base de datos** vacía, con `utf8mb4`, y un usuario con todos los permisos sobre ella.
3. **Configurar.** Edite `miruta/servidor/configuracion.php`:
   - `APP_URL`: `http://localhost/miruta`, o la dirección con que se entrará;
   - `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME` y `DB_PASSWORD`: los de su base de datos;
   - **borre las líneas `STORAGE_PATH` y `TEMP_PATH`**, que son del hospedaje; la carpeta de trabajo pasa a ser
     `miruta/servidor/storage`;
   - si quiere, ponga `'APP_DEBUG' => true` para ver los errores mientras prueba.
4. **Permisos.** El usuario del servidor web (`www-data`, `apache`…) tiene que poder escribir en
   `miruta/uploads/` y en `miruta/servidor/storage/`. En Linux:

   ```bash
   chown -R www-data miruta/uploads miruta/servidor/storage
   ```

   En Windows con XAMPP no hace falta.
5. **Instalar la base de datos.** Elija una de estas formas:
   - en la consola: `php miruta/servidor/artisan migrate --seed --force`;
   - desde la app, con la clave de mantenimiento;
   - importando `base-de-datos/miruta-2.2.0-inicial.sql`.
6. **Servidor web.** Elija uno:
   - **Apache** (también XAMPP o WAMP): active `mod_rewrite` y `AllowOverride All` para esa carpeta. El
     `.htaccess` ya hace el resto.
   - **nginx con PHP-FPM**: copie el contenido de `otros/nginx-miruta.conf` dentro del `server { }` de su sitio,
     con `root` en la carpeta que contiene `miruta/`. Ajuste `fastcgi_pass` a su PHP-FPM y recargue nginx.
   - **Servidor web de PHP** (solo para probar):

     ```bash
     cd /carpeta/que/contiene/miruta
     php -S 0.0.0.0:8080 miruta/router.php
     ```

7. **Comprobar.** Abra `http://localhost/miruta/api/v1/password-policy` (o `:8080/miruta/…` con `php -S`).
   Debe responder un JSON que empieza por `{"data":{"type":"password-policies"…`. El diagnóstico está en
   `…/miruta/diagnostico.php?clave=CLAVE`, y `…/miruta/servidor/composer.json` debe responder *Forbidden*.
8. **Tareas programadas.** Hay dos formas:
   - con `'TASKS_ON_REQUESTS' => true` (como viene), se ejecutan con el uso de la app;
   - con cron, ponga `false` y añada:

     ```cron
     * * * * * php /ruta/a/miruta/servidor/artisan schedule:run >/dev/null 2>&1
     ```

## 10.6 Versiones futuras

Desde el repositorio (`https://github.com/maicolalmaralestamayo/MiRuta`):

| Qué | Cómo |
|---|---|
| App | Suba la versión en `app/pubspec.yaml`, compile con `app/build_release.sh <dirección-del-servidor>/api/v1` (necesita la clave de firma en `app/android/`) y publíquela en *Gestión → Actualizaciones de la app*. Guarde `app/build/symbols/<versión>`. |
| Servidor para el hospedaje (primera vez) | `tools/release/build-hosting-package.sh <versión>` con `APP_URL`, `DB_*` y `TEMP_PATH`; genera claves nuevas. |
| Servidor para actualizar uno instalado | `ACTUALIZACION=1 tools/release/build-hosting-package.sh <versión>`: no lleva `configuracion.php`, así que conserva sus claves y datos. Después, en la app: *Mantenimiento del servidor → Actualizar base de datos*. |
| Imagen Docker | `docker build -f docker/offline/Dockerfile -t miruta-api:<versión> .` y `docker save miruta-api:<versión> mariadb:10.6 \| gzip > miruta-<versión>-imagenes.tar.gz` |

Actualice siempre primero el servidor y después la app.

## 10.7 Copias de seguridad

- **Base de datos:** expórtela en SQL con el gestor del hospedaje, semanalmente y antes de cada actualización.
- **Fotos y APK:** copie `miruta/uploads/`.
- **Configuración:** guarde `miruta/servidor/configuracion.php`.

Para restaurar, monte el servidor con su `configuracion.php`, importe la base de datos y vuelva a copiar
`uploads/`.
