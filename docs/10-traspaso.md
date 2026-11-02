# 10. Traspaso de tecnología: montar MiRuta desde cero

Esta guía es para quien recibe el proyecto. Dice qué hay que tener, cómo preparar el ordenador, cómo poner en
marcha el servidor y la app, y cómo mantenerlo todo después. Los detalles de cada pieza están en los documentos
que se citan.

**Orden recomendado:** §1 (lo que hay que custodiar) → §2 (preparar el ordenador) → §3 (probar en el ordenador)
→ §4 (montar el servidor) → §5 (compilar y repartir la app) → §6 (primera configuración) → §7 en adelante
(mantenimiento).

## 10.0 Cómo está hecho MiRuta

```
 Teléfonos Android ──http(s)──▶ Servidor web (Apache o nginx) ──▶ API de MiRuta (PHP) ──▶ Base de datos (MariaDB/MySQL)
  App MiRuta (Flutter)            /miruta/index.php                  Lumen 7, JSON:API, JWT
                                  /miruta/uploads/ (fotos y APK)     tareas programadas (sin cron)
                                  [/tiles/… mapa propio: opcional]
```

| Pieza | Tecnología | Dónde está en el repositorio | Documentación |
|---|---|---|---|
| App | Flutter 3.47 (Dart 3.13), Android 7.0 o superior (minSdk 24) | `app/` | `app/README.md`, `docs/05-app.md` |
| API (servidor) | Lumen 7, PHP de 7.2.5 a 8.0 | `api/` | `api/README.md`, `docs/04-api.md`, `docs/openapi.yaml` |
| Base de datos | MariaDB 10.3 o superior, o MySQL 5.7 o superior | `api/database/` (migraciones y datos iniciales) | `docs/03-datos.md` |
| Reglas de negocio | — | — | `docs/02-procesos.md`, `docs/06-ajustes.md`, `docs/07-algoritmos.md` |
| Paquetes para el servidor | scripts bash y Docker | `tools/release/` | este documento |
| Mapa propio (opcional) | Planetiler + TileServer GL | `tools/maps/` | `tools/maps/README.md` |
| Pruebas y entorno local | Docker | `docker/` | `api/README.md` |

**Repositorio:** `https://github.com/maicolalmaralestamayo/MiTransporte`. El trabajo está en la rama
`claude/proceso-stack-discussion-idsu8k`; conviene fusionarla con la rama principal (§12).

## 10.1 Lo que hay que custodiar (sin esto no se puede seguir)

Guárdelo en dos sitios distintos, por ejemplo una memoria USB y otro ordenador, nunca solo en el teléfono.
**No lo suba nunca al repositorio.**

| Qué | Para qué | Si se pierde |
|---|---|---|
| `app/android/keystore/mitransporte-release.jks` y `app/android/key.properties` (clave de firma de la app y sus contraseñas) | Firmar cada versión nueva de la app | **Ninguna versión nueva se instalará encima de la que tienen los teléfonos.** Habría que desinstalar la app en todos y empezar de cero. Es lo más importante. |
| `servidor/configuracion.php` del hospedaje (`APP_KEY`, `JWT_SECRET`, `MAINTENANCE_KEY` y datos de la base de datos) | El funcionamiento del servidor | Con claves nuevas se cierran todas las sesiones; los datos no se pierden si la base de datos sigue. |
| Clave de mantenimiento (`CLAVE-DE-MANTENIMIENTO.txt`) | Instalar o reparar el servidor desde la app sin iniciar sesión | Se cambia editando `MAINTENANCE_KEY` en `configuracion.php` (mínimo 16 caracteres). |
| Usuario y contraseña del FTP y de la base de datos del hospedaje | Subir archivos y gestionar la base de datos | Se piden al Soporte 24 horas del hospedaje. |
| Contraseña de la cuenta del Administrador de MiRuta | Gestionar la app | Si nadie puede entrar: copia de la base de datos y ayuda técnica. |
| `app/build/symbols/<versión>/` de cada versión publicada | Leer los errores que lleguen de esa versión | No se podrán interpretar los errores de esa versión. |
| Copias de la base de datos y de `uploads/` (§10.8) | Recuperarse de un desastre | Se pierden los datos. |

## 10.2 Preparar el ordenador de trabajo

Funciona en Windows, macOS o Linux. Los scripts son de `bash`: en Windows hay que usar **WSL2** (Ubuntu).

| Herramienta | Para qué | Notas |
|---|---|---|
| **Git** | Bajar y guardar el código | — |
| **Docker Desktop** | Probar la API, pasar sus pruebas y preparar los paquetes del servidor | No hace falta instalar PHP, Composer ni MariaDB en el ordenador. |
| **Android Studio** | Trae el Android SDK (plataforma 36, build-tools 36) y Java 17 o superior | En *SDK Manager* instale también *Command-line Tools* y el NDK que pida Flutter. |
| **Flutter 3.47** (canal *stable*) | Compilar la app | `flutter doctor` debe salir sin errores de Android. |
| **Python 3** y **zip** | Los scripts de paquetes | En Linux y WSL suelen venir instalados. |
| Un teléfono Android con *Depuración USB* | Probar la app | Opcional; también sirve un emulador. |

Pasos:

```bash
git clone https://github.com/maicolalmaralestamayo/MiTransporte.git
cd MiTransporte
git checkout claude/proceso-stack-discussion-idsu8k      # o la rama principal, cuando se fusione

# Clave de firma (de su copia de seguridad, §10.1):
#   app/android/keystore/mitransporte-release.jks
#   app/android/key.properties

cd app && flutter pub get && flutter doctor
```

## 10.3 Probar todo en el ordenador

**Servidor y base de datos locales** (Docker):

```bash
docker compose -f docker/dev/compose.yml up --build
```

Cuando sale «API lista», la API responde en `http://localhost:8000/api/v1` y su documentación en
`http://localhost:8000/docs`. Las tareas programadas también funcionan.

**App contra el servidor local**: en el teléfono, en la misma Wi-Fi que el ordenador, abra el botón del servidor,
elija `http` y escriba `IP-DEL-PC:8000`. Desde el código:

```bash
cd app && flutter run
```

**Pruebas** (hay que pasarlas antes de cada entrega):

```bash
docker/test-api.sh                   # API: más de 220 pruebas con PHP 7.2 y MariaDB 10.6
cd app && flutter analyze && flutter test
```

## 10.4 Montar el servidor en el hospedaje (desde cero)

Es lo que se hizo para el hospedaje compartido (solo FTP, sin SSH ni cron). La guía completa para el
hospedaje está en `tools/release/hosting/LEEME.md`, dentro del paquete.

**1. Preparar el paquete** en el ordenador. Genera claves nuevas y deja preparada la configuración con los
datos del hospedaje:

```bash
APP_URL=http://www.twintechnology.cu/miruta \
DB_HOST=192.168.12.48 DB_DATABASE=twintechnologydb DB_USERNAME=twintechnologydbo DB_PASSWORD='…' \
TEMP_PATH=/srv/www/www.twintechnology.cu/tmp \
tools/release/build-hosting-package.sh 2.2.0
# Resultado: entregas/hosting/miruta-hosting-2.2.0.zip
```

**2. Subirlo** con FileZilla (FTP explícito sobre TLS, modo pasivo, binario, como mucho 2 conexiones):

1. Suba `subida-rapida/miruta-servidor.zip` y `subida-rapida/desempaquetar.php` a `/htdocs/miruta/`.
2. Abra `http://www.twintechnology.cu/miruta/desempaquetar.php?clave=CLAVE`.

**3. Comprobar**: abra `…/miruta/diagnostico.php?clave=CLAVE`. Todo debe salir con ✔: PHP de 7.2.5 a 8.0,
extensiones, carpetas con permiso de escritura y conexión con la base de datos. Además,
`…/miruta/servidor/composer.json` debe responder *Forbidden*.

**4. Instalar la base de datos desde la app**: en la pantalla *Servidor*, pulse *Mantenimiento del servidor*,
escriba la clave y pulse **Instalar base de datos**. También se puede importar el `.sql` de `base-de-datos/` con el
gestor del hospedaje.

**5. Crear la cuenta del Administrador**: la **primera cuenta** que se crea es la del Administrador. Créela usted
antes de dar la dirección a nadie.

**Otros tipos de servidor:**

| Si el servidor es… | Use | Guía |
|---|---|---|
| Un hospedaje compartido con solo FTP | `tools/release/build-hosting-package.sh` | `tools/release/hosting/LEEME.md` |
| Un servidor propio o VPS con SSH (Apache o nginx, cron) | `tools/release/build-api-package.sh` | `tools/release/INSTALAR.md` |
| Un servidor con Docker, también sin Internet | `docker/offline/` (imagen y `compose.yml`) | `docker/offline/compose.yml` |

## 10.5 Compilar y repartir la app

1. Suba la versión en `app/pubspec.yaml`. Por ejemplo, de `2.2.0+8` a `2.3.0+9`: el número de detrás del `+`
   tiene que ser **siempre mayor** que el anterior.
2. Compile la app con la dirección del servidor ya puesta. El usuario la puede cambiar después.

   ```bash
   cd app && ./build_release.sh http://www.twintechnology.cu/miruta/api/v1
   # Resultado: build/release/<versión>/MiRuta-<versión>-64bits.apk y -32bits.apk
   ```

3. Guarde `build/symbols/<versión>/` (§10.1).
4. **Primera vez:** reparta los APK por WhatsApp, Telegram, memoria USB, etc. Casi todos los teléfonos
   modernos usan el de **64 bits**; el de 32 bits es para teléfonos antiguos. Al instalar, Android pide permitir
   «instalar apps desconocidas».
5. **Versiones siguientes:** como Administrador, entre en *Más → Gestión → Actualizaciones de la app → Publicar
   versión*. Suba los dos APK, escriba las novedades y elija si es obligatoria. Los teléfonos la detectan solos y
   la descargan desde su servidor.

## 10.6 Primera configuración de la app (orden recomendado)

Como Administrador:

1. **Ajustes de la app** (*Gestión → Ajustes de la app*): contraseñas, caducidades, letras de matrícula, etc.
   Cada ajuste tiene su explicación (`docs/06-ajustes.md`).
2. **Nomencladores**: jerarquías (con su ícono y orden), tipos de vehículo, tipos de ausencia y motivos de
   conversación. Ya vienen unos iniciales.
3. **Entidades**: cree cada empresa con su **abreviatura**, que los trabajadores escribirán al unirse.
4. **Jefes de Transporte**: cada uno crea su cuenta, se une a su Entidad (abreviatura y Pase) y pide el rol
   *Jefe de Transporte*. El Administrador aprueba la solicitud en *Solicitudes*.

Después, cada Jefe de Transporte, en su Entidad:

5. **Vehículos y choferes**: los choferes piden su rol y el Jefe de Transporte lo aprueba. Luego registra los
   vehículos, con matrícula y capacidades, y asigna su chofer habitual.
6. **Itinerarios y paradas**: crea las paradas sobre el mapa y las ordena. La primera parada es la salida y la
   última, el regreso.
7. **Trabajadores**: se registran ellos mismos o, si no tienen teléfono, los registra un jefe y les entrega un
   código de activación. Piden su itinerario y su parada, y el jefe aprueba la solicitud.
8. **Jefes de itinerario** (opcional): piden el rol y el Jefe de Transporte lo aprueba.
9. **Planificación de viajes**: *Gestión → Planificación de viajes*.

Los procesos completos están en `docs/02-procesos.md`.

## 10.7 Publicar una versión nueva (servidor y app)

1. Haga los cambios y pase las pruebas (§10.3).
2. Suba la versión en `app/pubspec.yaml` y en `api/config/mitransporte.php` (`'version'`).
3. **Servidor:** prepare el paquete de actualización, que no lleva configuración y conserva claves y datos:

   ```bash
   ACTUALIZACION=1 tools/release/build-hosting-package.sh 2.3.0
   # Resultado: entregas/hosting/miruta-actualizacion-2.3.0.zip
   ```

   Súbalo y desempaquételo como en §10.4, con la clave de siempre. Después, en la app: *Gestión →
   Mantenimiento del servidor → **Actualizar base de datos***.
4. **App:** compile y publíquela como en §10.5.
5. Guarde el código en el repositorio con `git commit` y `git push`.

**Regla de oro:** primero el servidor y después la app. Una app nueva puede necesitar cosas que un servidor
antiguo no tiene; un servidor nuevo sigue funcionando con las apps anteriores.

## 10.8 Copias de seguridad

| Qué | Cómo | Cada cuánto |
|---|---|---|
| Base de datos | Gestor de la base de datos del Servicio de Utilidades (`https://unixweb.nauta.cu/`) → exportar en SQL | Semanal, y antes de cada actualización |
| Fotos y APK subidos | Con FileZilla, descargar `/htdocs/miruta/uploads/` | Mensual |
| `servidor/configuracion.php` | Con FileZilla, descargarlo | Al instalar y cuando cambie |
| Clave de firma de la app | Copia en dos sitios (§10.1) | Una vez; comprobar que sigue ahí |

**Restaurar:**

1. Monte el servidor como en §10.4, pero ponga su `configuracion.php` guardado en lugar del nuevo.
2. Importe la copia de la base de datos en lugar de *Instalar base de datos*.
3. Vuelva a subir `uploads/`.

## 10.9 Mantenimiento diario y problemas frecuentes

El Administrador tiene en *Gestión → Mantenimiento del servidor* el estado del servidor y los botones:
actualizar la base de datos, ejecutar tareas, limpiar la caché y ver el **registro de errores**
(`docs/02-procesos.md` §2.15).

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| La app dice «Fue imposible conectarse al servidor» | Protocolo o dirección mal escritos, sin Internet, o el hospedaje caído | Revise `http` y `www.twintechnology.cu/miruta`. Abra `…/miruta/api/v1/password-policy` en el navegador. |
| «En esa dirección no hay un servidor de MiRuta» | La dirección apunta a otra web | Revise que termine en `/miruta`. |
| Error 500 o pantalla de error | PHP incompatible, base de datos caída o un fallo | Abra el diagnóstico y el registro de errores. |
| No se pueden subir fotos o APK | Permisos de `uploads/` o límite de subida | Diagnóstico: permisos 775/777 en `uploads/`; pida al Soporte 64 MB de subida. |
| No llegan los avisos de retraso | Nadie usa la app (las tareas van con el uso) o una tarea falla | *Mantenimiento → Tareas programadas*: vea la última ejecución y el error. |
| Después de subir archivos nuevos falla todo | Falta *Actualizar base de datos*, o se sobrescribió `configuracion.php` | Pulse *Actualizar base de datos*; si se sobrescribió, vuelva a subir el suyo. |
| Nadie puede iniciar sesión | Cambiaron `APP_KEY` o `JWT_SECRET` | Restaure su `configuracion.php`; todos vuelven a entrar con su contraseña. |
| Un teléfono no instala la versión nueva («conflicto con un paquete existente») | La APK se firmó con otra clave | Compile con la clave original (§10.1). |

## 10.10 El mapa

La app pide las imágenes del mapa a **su propio servidor de mapas** (`tools/maps`): datos de Cuba, con calles,
edificios y puntos de interés. Ese servidor necesita **Docker** y unos GB de disco, y **no cabe en el hospedaje
compartido**. Hasta montarlo, el mapa (paradas, recorrido en tiempo real) sale sin fondo.

Opciones, por decidir:

1. Montar `tools/maps` en otro servidor con Docker (un VPS o un ordenador de la empresa con dirección pública) y
   poner su dirección en el ajuste de la app *Dirección de las imágenes del mapa* (`map_tiles_url`).
2. Generar las imágenes por adelantado solo para la zona de las Entidades y subirlas por FTP a `/htdocs/miruta/tiles/`.

## 10.11 Dónde está cada cosa

| Necesito… | Documento |
|---|---|
| Entender qué hace la app y para quién | `docs/01-vision.md` |
| Reglas: solicitudes, viajes, avisos, tareas | `docs/02-procesos.md` |
| Tablas de la base de datos | `docs/03-datos.md` |
| La API (rutas, permisos, errores) | `docs/04-api.md` y `docs/openapi.yaml` (también en `/docs` del servidor local) |
| Las pantallas de la app | `docs/05-app.md` y `docs/09-repaso-pantallas.md` |
| Los ajustes | `docs/06-ajustes.md` |
| Cálculos (ocupación, retrasos, paradas, desvíos) | `docs/07-algoritmos.md` |
| Historia de las versiones | `docs/08-version-2.md` |
| Backlog y planificación (Scrum) | `docs/scrum/` |

## 10.12 Pendientes conocidos al hacer el traspaso

- **Probar en el hospedaje real y en teléfonos reales.** Se probó con un Apache que imita el hospedaje (PHP 7.4,
  `open_basedir`, carpeta `tmp`) y con pruebas automáticas en PHP 7.2 y 8.0, pero no en el hospedaje ni en
  teléfonos.
- **Confirmar con el hospedaje:** que la base de datos sea MySQL o MariaDB, la versión de PHP, que `.htaccess`
  funcione (`AllowOverride`) y el límite de subida (64 MB).
- **Cambiar la contraseña de la base de datos**, que es igual al usuario, y ponerla en `configuracion.php`.
- **Fusionar la rama** `claude/proceso-stack-discussion-idsu8k` con la rama principal del repositorio.
- **Mapa:** decidir la opción de §10.10.
- **HTTPS:** con un certificado oficial instalado por el hospedaje, cambiar en la app el protocolo a `https`.
