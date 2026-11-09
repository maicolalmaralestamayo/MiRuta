# 5. App móvil (Flutter, Android) — versión 4.0

La app se llama **MiRuta** (paquete `com.mitransporte.mitransporte`, versión `4.0.0+10`). Interfaz en **español**,
con **trato de usted**. Funciona contra la API de la versión 4.0 ([13-api-proxima-version.md](13-api-proxima-version.md));
lo acordado está resumido en [12-resumen-proxima-version.md](12-resumen-proxima-version.md) y detallado en
[11-acuerdos-registro-qr.md](11-acuerdos-registro-qr.md) §11.19–§11.55. La versión 3.0 de este documento queda en el
historial de git.

## 5.1 Arquitectura

| Carpeta | Qué hay |
|---|---|
| `lib/core` | Cliente JSON:API (`dio`, renovación del token, cabecera `X-App-Version` y aviso de `426 APP_UPDATE_REQUIRED`), almacenamiento (`flutter_secure_storage` para los tokens, `shared_preferences` para lo demás), formatos («sáb. 07-11-26», 24 h) y unidades de los ajustes (`12hor30min`, `1km200m`, `10km/hor`) |
| `lib/models` | Modelos de la API: persona y pertenencias (`GET me`), Entidades, itinerarios, paradas, trabajadores, solicitudes, hijos, nomencladores, viajes, línea del recorrido, ajustes, versiones, conversaciones |
| `lib/services` | Sesión, sincronización (`GET sync?cursor=N`), notificaciones del teléfono, actualizaciones, ubicación compartida, QR (clave del teléfono MR1 y cola de «Incluir por QR» sin conexión) y `tracking/` (estado del trabajador y del vehículo) |
| `lib/ui` | Pantallas por pestaña (`home`, `management`, `trips`, `profile`, `chat`, `admin`, `auth`, `shared`) y los componentes comunes (`widgets`) |

Dependencias (§11.49, solo las necesarias): `dio`, `flutter_secure_storage`, `shared_preferences`, `provider`, `intl`,
`geolocator`, `flutter_foreground_task`, `flutter_local_notifications` (+ `timezone`, `flutter_timezone`),
`workmanager`, `qr_flutter`, `mobile_scanner`, `pointycastle`, `image_picker`, `file_picker`, `share_plus`,
`path_provider`, `ota_update`, `package_info_plus`, `device_info_plus`, `url_launcher`. **Sin mapas.** La ubicación
compartida desde otras apps usa un canal propio (`mitransporte/share` en `MainActivity.kt`), sin paquetes.

## 5.2 Reglas comunes de la interfaz

- Barra principal **Inicio · Gestión (engranaje, con el número de solicitudes) · Viajes · Más** en todas las
  pantallas. Barra superior con el **botón Actualizar** y el **punto de conexión** (verde, rojo; gris sin servidor).
- **Tocar** una tarjeta abre su formulario; **mantenerla** la marca (check naranja arriba a la derecha); **un solo
  tipo** marcado a la vez. El botón naranja **Acciones** muestra solo lo que se puede hacer: sin nada marcado, las
  acciones generales; con algo marcado, las de lo marcado y **Marcar todo / Desmarcar todo / Invertir selección**;
  las de un solo objeto (Editar…) solo con una marcada.
- **Selectores** con ↕ que solo despliegan. **Secciones plegables** con su cantidad, que recuerdan si estaban
  plegadas, **paginadas de 5 en 5** (salvo las paradas de un itinerario elegido, que se ordenan arrastrando).
- **Formularios** con los campos propios del objeto (sin datos de otras tablas) y el interruptor **Activado**.
- Botones siempre con **ícono y texto**; también «Cancelar» en los diálogos. Eliminar siempre pide confirmación y
  explica qué se borra y qué se conserva.
- **Sin conexión**: se ve lo último cargado con el aviso «Sin conexión: datos del …»; en Gestión solo queda
  «Incluir por QR».

## 5.3 Pantallas

| Pantalla | Contenido |
|---|---|
| **Inicio de sesión** | Botón **Servidor** (rojo sin servidor; diálogo «Falta el servidor» al intentar operar sin él) y punto de conexión; usuario, contraseña, «Recordar contraseña»; **Entrar**, **Olvidé usuario/contraseña** (naranja), **Registrarme** (sin relleno). Con una **actualización obligatoria** pendiente muestra el aviso con «Descargar e instalar» y no deja entrar |
| **Inicio** | Tarjeta de la persona; **Perfil**, **Hijos**, **Mi QR**; avisos «Aún no tiene Entidad / itinerario / parada» con su botón; Entidad (selector si tiene varias), itinerario y parada, rol, próximos viajes |
| **Gestión** | Selectores Entidad → Itinerario → Parada («Todas», «Sin Entidad» solo Administrador, «Sin itinerario», «Sin parada»; recuerdan la elección), buscador de personas y secciones **Entidades, Itinerarios, Paradas, Personas, Solicitudes**. Acciones según el rol y lo marcado: registrar trabajador, crear Entidad / itinerario / parada, **Incluir por QR**, entrar en una Entidad (Administrador), solicitar Entidad o itinerario, declarar ausencia, mostrar u ocultar solicitudes aprobadas y rechazadas; editar, eliminar, salir, crear o añadir paradas, cambiar de Entidad, asignar o quitar el rol de Jefe, cambiar de itinerario o de parada, quitar del itinerario, «Cambiarme a esta parada», aprobar o rechazar (motivo del nomenclador), cancelar o eliminar las propias |
| **Formularios** | Trabajador, Entidad, itinerario y parada (con **«Usar mi ubicación actual»** y latitud y longitud de solo lectura), con imagen y «Activado» |
| **Incluir por QR** | Escanea el QR, muestra dónde está ya la persona y se elige Entidad, itinerario o parada (el itinerario de la parada, bloqueado). Sin conexión, comprueba el QR en el teléfono y lo envía al volver la conexión |
| **Ubicación compartida** | MiRuta aparece en «Compartir» (WhatsApp, Telegram, Google Maps, OsmAnd…): entiende `geo:`, enlaces de Google Maps (también los cortos, con conexión), de OpenStreetMap / OsmAnd y coordenadas escritas. Pregunta **Crear parada nueva** o **Cambiar la ubicación de una parada existente** (solo Administrador y Jefe) |
| **Viajes** | Selectores Entidad e Itinerario; secciones **Planificados, En ejecución, Terminados, Cancelados** (estas dos se muestran u ocultan). Acciones: **Planificar viaje** (casillas Ida y Regreso, cada una con hora y tipo de vehículo); con un viaje marcado: editar, ver recorrido, Trabajadores, empezar, terminar, cancelar, eliminar |
| **Formulario del viaje** | Itinerario y sentido de solo lectura; fecha, hora y tipo de vehículo editables solo en Planificado; estado y ocupación prevista |
| **Línea del recorrido** | Requiere la ubicación activada a quien viaja. Paradas en el orden del recorrido, vehículo en su tramo (En movimiento, Detenido, Dejando / Recogiendo), sensores destacados, «Mi estado», cantidades sin ceros y la tarjeta «N esperando en [primera parada]» o Viajando / Recogidos. Opciones del trabajador: «Estoy en la parada …» (con sus hijos), «Me bajé en mi parada», «Estoy en mi parada», «Ya me recogieron», «No voy en este viaje» (en la ida pregunta «¿Tampoco irá en el regreso?») |
| **Más** | Mi QR, Conversaciones, Compartir la app (64 o 32 bits), Cerrar sesión. Administrador: Nomencladores, Ajustes de la app, Olvidé algo, Actualizaciones de la app (sube los APK de 64 y 32 bits y marca Obligatoria), Mantenimiento del servidor (estado, instalar o actualizar la base de datos, tareas, caché, registro de errores) |
| **Perfil, Hijos, Mi QR** | Mismo estilo que el formulario del trabajador. Mi QR cambia cada 15 s, sin capturas de pantalla |
| **Conversación** | Con el desarrollador, estilo WhatsApp, solo texto y con motivo; se consulta cada «Frecuencia chat» |

## 5.4 Tiempo real calculado en el teléfono

`lib/services/tracking/worker_tracker.dart` (código puro, con pruebas) implementa §11.43–§11.44: con la distancia a la
parada de referencia (la primera en la ida, la suya en el regreso) en dos cálculos seguidos, **Radio parada**,
**Tolerancia GPS**, **Velocidad humana** y **Distancia abandono** deciden De camino / En la parada / No voy a viajar;
Viajando (ida) y Recogido (regreso) si sale de la parada más rápido que una persona; **Dejado** tras «Cálculos
consecutivos» a velocidad humana en el radio de alguna parada; **Botado** y **Dormido** cuando el vehículo ya pasó por
su parada, y fin del cálculo pasada la «Espera final». Viajando y Recogido hacen del teléfono un **sensor**: Detenido /
En movimiento, próxima parada (entra en su radio y sale, o la salta) y si está detenido en ella.

`tracking_service.dart` lo ejecuta en un **servicio en primer plano** (`flutter_foreground_task`) desde «Anticipación
viaje» antes de la salida hasta un estado definitivo o el fin del viaje, cada «Frecuencia cálculo»: envía
`POST trips/{id}/reports` (el cambio pendiente más antiguo y, si es sensor, el vehículo) y lo reenvía hasta recibir el
acuse. Notifica sus propios estados y, al terminar, recuerda quitar el GPS. El recordatorio de activar la ubicación lo
programa el teléfono al conocer el próximo viaje.

## 5.5 Sincronización, notificaciones y actualizaciones

- `GET sync?cursor=N` con la app abierta («Frecuencia día viaje» si hay viaje ese día, «Frecuencia reposo» si no),
  en segundo plano (`workmanager`, mínimo 15 min de Android) y con el botón Actualizar. Las notificaciones que llegan
  se muestran en el teléfono (sin pantalla de avisos); `meta.counters` da el número de Gestión; `meta.changed`, qué
  pantallas recargar; `settingsVersion`, cuándo recargar los ajustes.
- **Actualización obligatoria** (§11.54): al recibir `426` la app cierra la sesión (también en el servidor), recuerda
  la obligación sin conexión y desde el inicio de sesión obliga a descargar e instalar (`ota_update`, con SHA-256).

## 5.6 Compilar

`./build_release.sh` compila los dos APK (64 y 32 bits) por separado con el mismo `versionCode` (sin el desplazamiento
de `--split-per-abi`, que rompería la comparación de versiones de la API), firmados con la clave de
`android/key.properties` (no se sube al repositorio).
