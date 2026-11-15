# 10. Traspaso de tecnología — MiRuta

> **Versión 4.3.0 (docs/12 §17):** servidor **Laravel 12 con PHP 8.2** (el del hospedaje, 8.2.35) y MariaDB 10.3 o
> superior. El `.zip` del servidor trae **`vendor/` ya instalado** (sin dependencias de desarrollo y con el autoload
> optimizado): no hace falta Composer ni SSH en el hospedaje. Todo lo que hay que ejecutar en el servidor (instalar o
> actualizar la base de datos, tareas, limpiezas) se hace con los endpoints de mantenimiento de la API, desde la app
> (docs/13 §13.13). La base de datos de la 4.3.0 se instala **desde cero** (*Instalar base de datos*) o, sobre una
> 4.2.0 (o anterior, desde la 4.0.0) ya instalada, con *Actualizar base de datos*, sin perder datos: la migración
> `2026_11_16_000001_upgrade_4_3` convierte el estado «Recogido» en «Viajando» (§10.3 ter) y, si viene de una 4.1.0,
> también se aplica `2026_11_15_000001_upgrade_4_2` (§10.3 bis). No se actualiza sobre una 3.x. En esta versión no se entregan imágenes de Docker ni un SQL inicial:
> la base de datos se instala desde la app.

Qué se entrega y cómo poner en marcha MiRuta en cada entorno: el hospedaje, un ordenador con Docker y un
ordenador sin Docker. Se da por hecho que Docker, Apache o nginx, PHP y MySQL/MariaDB ya están instalados.

## 10.1 Qué se entrega

```
4.3.0/
├── miruta-4.3.0-64bits.apk               App para casi todos los teléfonos (Android 7.0 o superior)
└── miruta-4.3.0-32bits.apk               App para teléfonos antiguos de 32 bits
hosting/
├── miruta-servidor-<versión>.zip         Servidor para el hospedaje o para un ordenador sin Docker (instalación nueva)
└── miruta-actualizacion-4.3.0.zip        Actualización de un servidor ya instalado (conserva su configuracion.php)
```

En la 4.3.0 se entrega solo la **actualización** (el hospedaje ya tiene la 4.2.0). Para una instalación nueva se
genera `miruta-servidor-4.3.0.zip` con `tools/release/build-hosting-package.sh 4.3.0` (o se instala la
`miruta-servidor-4.2.0.zip` y se le aplica la actualización 4.3.0).

Contenido de `miruta-servidor-<versión>.zip`:

| Carpeta o archivo | Para qué |
|---|---|
| `htdocs/miruta/` | El servidor completo (código y `servidor/vendor/`), listo para copiar dentro de la carpeta pública del sitio web |
| `htdocs/miruta/servidor/configuracion.php` | **La configuración**: base de datos, claves y carpetas. Ya trae los datos del hospedaje. |
| `htdocs/miruta/.htaccess` | Reglas para Apache: protege `servidor/` y pasa todo a la API |
| `htdocs/miruta/router.php` | Lo mismo que `.htaccess`, para el servidor web de PHP (`php -S`) |
| `htdocs/miruta/diagnostico.php` | Comprueba PHP, extensiones, carpetas y base de datos desde el navegador |
| `subida-rapida/` | Todo `htdocs/miruta` en un solo `.zip` más `desempaquetar.php`, para subir 2 archivos por FTP |
| `otros/nginx-miruta.conf` | Reglas para nginx (equivalen a `.htaccess`) |
| `CLAVE-DE-MANTENIMIENTO.txt` | La clave para instalar y mantener el servidor desde la app y para el diagnóstico |
| `GUIA.md` | Esta guía |

**Guarde aparte**, además de esta entrega:

- la clave de firma de la app: `mitransporte-release.jks` y `key.properties`, entregados el 30/10;
- su `configuracion.php` una vez puesto en marcha.

Sin la clave de firma ninguna versión nueva de la app se instalará encima de esta.

## 10.2 La app

1. Copie al teléfono **`miruta-4.3.0-64bits.apk`**. Use la de 32 bits solo si el teléfono no admite la de 64.
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

- Como Administrador: *Más → Mantenimiento del servidor*.
- Sin sesión: botón del servidor → *Mantenimiento del servidor* → clave de mantenimiento.

**Símbolos.** La app va ofuscada. Si un usuario envía el texto de un error de la versión 4.3.0, se traduce a nombres
legibles con Flutter y los símbolos que deja la compilación en `app/build/symbols/4.3.0+13/` (guárdelos si los
necesita; no se entregan aparte):

```bash
flutter symbolize -i error.txt -d 4.3.0+13/app.android-arm64.symbols   # app de 64 bits
flutter symbolize -i error.txt -d 4.3.0+13/app.android-arm.symbols     # app de 32 bits
```

## 10.3 ter Actualizar el hospedaje de la 4.2.0 a la 4.3.0

El hospedaje ya tiene la 4.2.0 con datos. **Antes de nada, exporte la base de datos** en SQL con el gestor del
hospedaje (por si hubiera que volver atrás).

1. **Subir la actualización.** Use `miruta-actualizacion-4.3.0.zip` (no lleva `configuracion.php`) igual que en el
   paso 1 de §10.3 bis: los 2 archivos de su `subida-rapida/` a `/htdocs/miruta/` y
   `http://www.twintechnology.cu/miruta/desempaquetar.php?clave=CLAVE` con la clave de mantenimiento que ya tenía.
2. **Actualizar la base de datos.** *Más → Mantenimiento del servidor →* **Actualizar base de datos**. Aplica la
   migración `2026_11_16_000001_upgrade_4_3`: los estados «recogido» guardados pasan a «viajando» (Viajando y
   Recogido son ya un solo estado) y la columna deja de admitir «recogido». *Estado del servidor* debe mostrar la
   versión 4.3.0 y ninguna migración pendiente.
3. **Actualizar las apps.** Suba los dos APK de la 4.3.0 en *Más → Actualizaciones de la app* (puede marcarla
   Obligatoria) o instálelos a mano encima de la 4.2.0. Mientras haya teléfonos con la 4.2.0, el servidor les acepta
   «Recogido» (lo guarda como Viajando) y les sigue dando sus notificaciones de antes. Al abrir la 4.3.0 desaparecen
   los canales de notificaciones viejos y aparecen los seis nuevos (Viajes, Vehículo, Mi estado, Solicitudes,
   Mensajes, Actualizaciones), que el usuario puede ajustar en los ajustes de Android.

## 10.3 bis Actualizar el hospedaje de la 4.1.0 a la 4.2.0

El hospedaje ya tiene la 4.1.0 con datos. **Antes de nada, exporte la base de datos** en SQL con el gestor del
hospedaje (por si hubiera que volver atrás).

1. **Subir la actualización.** Use `miruta-actualizacion-4.2.0.zip`: **no lleva `configuracion.php`**, así que
   conserva la base de datos, las claves y la clave de mantenimiento del servidor. Suba a `/htdocs/miruta/` los 2
   archivos de su `subida-rapida/` y abra `http://www.twintechnology.cu/miruta/desempaquetar.php?clave=CLAVE` con la
   **clave de mantenimiento que ya tenía** (la de su `configuracion.php`). Sustituye el código y `vendor/`; no
   toca `uploads/` ni `configuracion.php`.
2. **Actualizar la base de datos.** En la app (Administrador): *Más → Mantenimiento del servidor →* **Actualizar
   base de datos** (o, sin sesión, botón del servidor → *Mantenimiento del servidor* → clave). Aplica la migración
   `2026_11_15_000001_upgrade_4_2`:
   - las ausencias de la 4.1.0 (de una Entidad) pasan a ser de la persona y a cubrir los itinerarios que tenía en
     esa Entidad; las nuevas se declaran por itinerario (uno o varios) y «Hasta» es opcional;
   - se guardan el GPS de cada informe y quién marcó a mano «Pasó por la parada»;
   - desaparece el ajuste «Frecuencia día viaje» y «Frecuencia fuera ventana» (antes «Frecuencia reposo») no admite
     menos de 15 min (si tenía menos, vuelve al valor por omisión).
   *Estado del servidor* debe mostrar la versión 4.2.0 y ninguna migración pendiente.
3. **Revisar los ajustes** (*Más → Ajustes de la app → Ventana viaje*): Inicio ventana (X, `10min`), Fin ventana
   (Y, `5min`), Frecuencia ventana (Z, `10seg`) y Frecuencia fuera ventana (F, `15min`).
4. **Actualizar las apps.** Suba los dos APK en *Más → Actualizaciones de la app* (puede marcarla Obligatoria) o
   instálelos a mano encima de la 4.1.0 (misma clave de firma). Al abrir la 4.2.0 en un viaje, cada trabajador verá la
   pantalla de **permisos del viaje** (ubicación «Permitir todo el tiempo», batería sin restricciones, alarmas).

## 10.3 Entorno 1: el hospedaje (solo FTP)

Use `miruta-servidor-4.2.0.zip`. Su `configuracion.php` ya trae la base de datos, la carpeta temporal y unas
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
   **Instalar base de datos**.
4. **Crear la cuenta del Administrador** desde la app (§10.2, paso 3).

**Particularidades del hospedaje:**

- No hay cron. Las tareas programadas se ejecutan con el uso de la app (`TASKS_ON_REQUESTS`).
- La caché y el registro de errores van a su carpeta temporal (`STORAGE_PATH`), fuera de la parte pública.
- El sitio va por http. El certificado del hospedaje es autofirmado y solo sirve para su administración.

## 10.4 Entorno 2: un ordenador con Docker

En esta versión no se entregan imágenes de Docker (docs/11 §11.55); para generarlas, vea §10.6. Con ellas no hace
falta Internet.

```bash
docker load -i miruta-4.2.0-imagenes.tar.gz
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

Use `miruta-servidor-4.2.0.zip`. Hace falta:

- **PHP 8.2 o superior**, con las extensiones `pdo_mysql`, `mbstring`, `openssl`, `fileinfo`, `tokenizer`,
  `ctype`, `xml` y `dom` (y `zip` para la subida rápida);
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
   - desde la app (*Mantenimiento del servidor → Instalar base de datos*), que usa `POST maintenance-runs`;
   - en la consola, si la hay: `php miruta/servidor/artisan migrate --seed --force`;
   - desde la app, con la clave de mantenimiento.
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
     * * * * * php /ruta/a/miruta/servidor/artisan miruta:tareas >/dev/null 2>&1
     ```

## 10.6 Versiones futuras

Desde el repositorio (`https://github.com/maicolalmaralestamayo/MiRuta`):

| Qué | Cómo |
|---|---|
| App | Suba la versión en `app/pubspec.yaml`, compile con `app/build_release.sh <dirección-del-servidor>/api/v1` (necesita la clave de firma en `app/android/`) y publíquela en *Gestión → Actualizaciones de la app*. Guarde `app/build/symbols/<versión>`. |
| Servidor para el hospedaje (primera vez) | `tools/release/build-hosting-package.sh <versión>` con `APP_URL`, `DB_*` y `TEMP_PATH`; genera claves nuevas e instala `vendor/` con `composer install --no-dev --optimize-autoloader` (o, sin acceso a los `.zip` de GitHub, `VENDOR_METODO=git`). Con `GENERAR_SQL=1` añade el SQL inicial. Queda en `entregas/hosting/`. |
| Servidor para actualizar uno instalado | `ACTUALIZACION=1 tools/release/build-hosting-package.sh <versión>`: no lleva `configuracion.php`, así que conserva sus claves y datos. Después, en la app: *Mantenimiento del servidor → Actualizar base de datos*. |
| Imagen Docker | Por ahora no se entrega (docs/11 §11.55). Si hace falta: `docker build -f docker/offline/Dockerfile -t miruta-api:<versión> .` y `docker save miruta-api:<versión> mariadb:10.3 \| gzip > miruta-<versión>-imagenes.tar.gz` |

Actualice siempre primero el servidor y después la app.

## 10.7 Copias de seguridad

- **Base de datos:** expórtela en SQL con el gestor del hospedaje, semanalmente y antes de cada actualización.
- **Fotos y APK:** copie `miruta/uploads/`.
- **Configuración:** guarde `miruta/servidor/configuracion.php`.

Para restaurar, monte el servidor con su `configuracion.php`, importe la base de datos y vuelva a copiar
`uploads/`.
