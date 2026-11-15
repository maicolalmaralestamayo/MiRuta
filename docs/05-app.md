# 5. App móvil (Flutter, Android) — versión 4.3

La app se llama **MiRuta** (paquete `com.mitransporte.mitransporte`, versión `4.3.0+13`, Android 7.0 o superior).
Interfaz en **español**, con **trato de usted**. Funciona contra la API 4.3.0
([13-api-proxima-version.md](13-api-proxima-version.md)); lo acordado está resumido en
[12-resumen-proxima-version.md](12-resumen-proxima-version.md) y detallado en
[11-acuerdos-registro-qr.md](11-acuerdos-registro-qr.md) §11.19–§11.63 (la 4.2.0 implementa §11.61 y §11.62; la 4.3.0, §11.63). La
versión 3.0 de este documento queda en el historial de git.

## 5.1 Arquitectura

| Carpeta | Qué hay |
|---|---|
| `lib/core` | Cliente JSON:API (`dio`, renovación del token, cabecera `X-App-Version` y aviso de `426 APP_UPDATE_REQUIRED`), **caché local** (`local_cache.dart`), almacenamiento (`flutter_secure_storage` para los tokens, `shared_preferences` para lo demás), formatos («sáb. 07-11-26», 24 h) y unidades de los ajustes (`12hor30min`, `1km200m`, `10km/hor`) |
| `lib/models` | Modelos de la API: persona y pertenencias (`GET me`), Entidades, itinerarios, paradas, trabajadores, solicitudes, hijos, nomencladores, viajes, línea del recorrido, ajustes, versiones, conversaciones |
| `lib/services` | Sesión, sincronización (`GET sync?cursor=N`), notificaciones del teléfono, actualizaciones, ubicación compartida, QR (clave del teléfono MR1 y cola de «Incluir por QR» sin conexión), tema (`theme_controller.dart`) y `tracking/` (estado del trabajador y del vehículo, ventana de viaje, permisos) |
| `packages/miruta_alarm` | Paquete local (sin dependencias externas): alarma exacta que abre la ventana de viaje con la app cerrada y se reprograma al reiniciar el teléfono; en la app, `WindowAlarmReceiver.kt` arranca el servicio de ubicación |
| `lib/ui` | Pantallas por pestaña (`home`, `management`, `trips`, `profile`, `chat`, `admin`, `auth`, `shared`) y los componentes comunes (`widgets`) |

Dependencias (§11.49, solo las necesarias): `dio`, `flutter_secure_storage`, `shared_preferences`, `provider`, `intl`,
`geolocator`, `flutter_foreground_task`, `flutter_local_notifications` (+ `timezone`, `flutter_timezone`),
`workmanager`, `qr_flutter`, `mobile_scanner`, `pointycastle`, `image_picker`, `file_picker`, `share_plus`,
`path_provider`, `ota_update`, `package_info_plus`, `device_info_plus`, `url_launcher` y el paquete local
`miruta_alarm`. **Sin mapas.** La ubicación
compartida desde otras apps usa un canal propio (`mitransporte/share` en `MainActivity.kt`), sin paquetes.

## 5.2 Reglas comunes de la interfaz

- **Operaciones con el servidor** (§11.56): toda acción del usuario que se conecta al servidor muestra el spinner
  «Conectando con el servidor…» que **bloquea la app**, con **Cancelar** (corta la conexión). Al final, un mensaje
  escueto: el resultado («Itinerario creado», «Parada cambiada»…) o «Operación cancelada». Lo hace `runAction`
  (`ui/widgets/busy.dart` y `core/busy_scope.dart`: un ámbito en una zona que `ApiClient` usa en cada petición); el
  menú Acciones y los botones lo aplican solos. El spinner solo se ve mientras hay peticiones en curso.
- **Botón Actualizar:** solo las notificaciones pendientes (GET sync) y los datos de la **pantalla visible** (sus
  `DataView` se apuntan solas en el `RefreshScope` de su `AppScaffold`).
- **Notificaciones siempre en la cortina** (4.3.0): con la app abierta o cerrada; ya no hay aviso dentro de la app.
  La tarea en segundo plano no consulta mientras la app está a la vista (consulta ella).
- **Contraseñas:** la app no propone ni sugiere contraseñas; solo comprueba los requisitos.
- **Formularios:** «Salir sin guardar» (Cancelar / Salir, `LeaveGuard`) si hay cambios; el teclado recorre todos los
  campos («Siguiente» y, en el último, «Listo»).
- **Modales:** ícono, título, pregunta y botones; el que vuelve sin hacer nada dice «Volver» cuando la acción es
  «Cancelar …» (p. ej. «Volver» / «Cancelar solicitud»).

- Barra principal **Inicio · Gestión (engranaje, con el número de solicitudes) · Viajes · Más** en todas las
  pantallas. Barra superior con el **botón Actualizar** y el **punto de conexión** (verde, rojo; gris sin servidor).
- **Tocar** una tarjeta abre su formulario; **mantenerla** la marca (check naranja arriba a la derecha); **un solo
  tipo** marcado a la vez. El botón naranja **Acciones** muestra solo lo que se puede hacer: sin nada marcado, las
  acciones generales; con algo marcado, las de lo marcado y **Marcar todo / Desmarcar todo / Invertir selección**;
  las de un solo objeto (Editar…) solo con una marcada.
- **Selectores** con ↕ que solo despliegan. **Secciones plegables** con su cantidad, que recuerdan si estaban
  plegadas, **paginadas de 5 en 5** (salvo las paradas de un itinerario elegido, que se ordenan arrastrando).
- **Formularios** con los campos propios del objeto y el interruptor **Activado**; debajo, sus **relaciones** (§11.57).
- Botones siempre con **ícono y texto**; también «Cancelar» en los diálogos. Eliminar siempre pide confirmación y
  explica qué se borra y qué se conserva.
- **Caché local** (§11.62): perfil, Entidades, itinerarios, paradas, trabajadores, hijos, solicitudes, ausencias,
  nomencladores, ajustes, viajes y la conversación se guardan en archivos del teléfono (no la línea del recorrido).
  Cada pantalla muestra al momento lo guardado («Actualizado hace …») y por detrás pregunta solo si cambió
  (`If-None-Match` → `304`); las huellas de `GET sync` (`meta.versions`) dicen qué volver a pedir. Al cerrar sesión se
  borra.
- **Sin conexión**: solo consulta, con el aviso «Sin conexión: solo consulta. Actualizado hace …»; los cambios dan
  «Sin conexión: solo se puede consultar…»; en Gestión solo queda «Incluir por QR» (con su cola sin conexión).
- **Tema** claro, oscuro o automático (por omisión): **un solo botón** con el icono del modo actual que abre un menú
  (Claro, Oscuro, Automático), en el inicio de sesión y en la barra de Inicio (4.3.0); se guarda en el teléfono.
- **Contador** junto al botón Actualizar: «↻ 7 s» dentro de la ventana de viaje (Z) o «↻ 12:34» fuera (F); al tocarlo
  conecta ya y se reinicia.
- **Sin sesión** (4.3.0): el inicio de sesión comprueba la conexión cada 30 s (además de al abrirse, al tocar el punto
  y al entrar) con su contador «↻ 23 s» junto al punto; Recuperar acceso muestra el contador de la consulta de la
  solicitud pendiente (cada 30 s).

## 5.3 Pantallas

| Pantalla | Contenido |
|---|---|
| **Inicio de sesión** | Botón de **tema** (menú claro, oscuro, automático); botón **Servidor** (rojo sin servidor; diálogo «Falta el servidor» al intentar operar sin él), contador de la próxima comprobación (cada 30 s) y punto de conexión; usuario, contraseña, «Recordar contraseña»; **Entrar**, **Olvidé usuario/contraseña** (naranja), **Registrarme** (sin relleno). Con una **actualización obligatoria** pendiente muestra el aviso con «Descargar e instalar» y no deja entrar |
| **Inicio** (G22) | Tarjeta con los datos de la persona y sus roles; **Mi QR** (tocar = en grande); **Viajes activos** (de todos sus itinerarios); **Entidades** y sus solicitudes; **Itinerarios** y sus solicitudes (tocar una propia: «Volver» / «Cancelar solicitud»); **Paradas**; **Ausencias** en curso; **Hijos**; aviso «Permisos para sus viajes» si faltan. Acciones: Ver o editar el perfil, Solicitar Entidad, Solicitar itinerario, Cambiar de parada, Añadir hijo, Declarar ausencia, Terminar ausencia, Cerrar sesión. El botón de **tema** está en la barra. Tocar una solicitud: Aprobar / Rechazar (con motivo) a quien puede resolverla y Cancelar solicitud si es propia |
| **Declarar ausencia** | Tipo, Desde, «Hasta (opcional, vacío = indefinida)», **itinerarios afectados** (uno o varios, de cualquiera de sus Entidades) y nota |
| **Gestión** (G19, G20) | Tarjetas de las tablas con su cantidad y el número de solicitudes pendientes: **Entidades, Itinerarios, Paradas, Trabajadores** y (Administrador) los **nomencladores**. Acciones: Incluir por QR, Registrar trabajador, crear Entidad / itinerario / parada |
| **Pantalla de cada tabla** | Buscador, tarjetas de 5 en 5, marcar (mantener) con Marcar todo / Desmarcar todo / Invertir selección, Acciones según lo marcado y los **sueltos**: Entidades + **«Solicitudes»** + «Trabajadores sin Entidad»; Itinerarios + **«Solicitudes»** + «Itinerarios sin Entidad» + «Trabajadores sin itinerario»; Paradas + «Paradas sin itinerario» + «Trabajadores sin parada» |
| **Formularios con relaciones** | **Entidad:** sus itinerarios («Crear itinerario»), trabajadores («Adicionar persona»: existente o registrar) y solicitudes (aprobar / rechazar). **Itinerario:** selector de **Entidad** (con «Sin Entidad»), **paradas en orden** (arrastrar), «Adicionar parada» (existente o nueva), trabajadores («Adicionar persona», con parada opcional), solicitudes; Acciones: quitar parada, asignar o quitar Jefe. **Parada:** «Usar mi ubicación actual», sus **itinerarios** («Asociar itinerario», quitar de uno) y sus trabajadores. **Trabajador:** sus **Entidades**, cada una con sus **itinerarios y paradas** (tocar: ver, cambiar de parada, Jefe, quitar), «Añadir itinerario en X», «Asociar Entidad», y sus **hijos** («Añadir hijo») |
| **Incluir por QR** | Escanea el QR, muestra dónde está ya la persona y se elige Entidad, itinerario o parada (el itinerario de la parada, bloqueado). Sin conexión, comprueba el QR en el teléfono y lo envía al volver la conexión |
| **Ubicación compartida** | MiRuta aparece en «Compartir» (WhatsApp, Telegram, Google Maps, OsmAnd…): entiende `geo:`, enlaces de Google Maps (también los cortos, con conexión), de OpenStreetMap / OsmAnd y coordenadas escritas. Pregunta **Crear parada nueva** o **Cambiar la ubicación de una parada existente** (solo Administrador y Jefe); al guardar se cierra también esta pantalla |
| **Viajes** | Selectores Entidad e Itinerario; secciones **Planificados, En ejecución, Terminados, Cancelados** (estas dos se muestran u ocultan). Acciones: **Planificar viaje** (casillas Ida y Regreso, cada una con hora y tipo de vehículo); con un viaje marcado: editar, ver recorrido, Trabajadores, empezar, terminar, cancelar, eliminar |
| **Formulario del viaje** | Itinerario y sentido de solo lectura; fecha, hora y tipo de vehículo editables solo en Planificado; estado y ocupación prevista |
| **Línea del recorrido** | Requiere la ubicación activada solo a los trabajadores de ese viaje (el Administrador y los Jefes que no viajan la ven sin ella); si faltan «todo el tiempo» o la batería sin restricciones, aviso «Solo con la app abierta» con la pantalla **Permisos del viaje** (y el consejo de Xiaomi, Huawei, Oppo o Samsung). «Sin datos del vehículo» hasta que informan los sensores; tocar los sensores abre por qué cada uno es o no sensor («No está Viajando (está Botado)», «Sin enviar desde las 18:41», «Sin GPS»). Botados y Dormidos en la primera parada de la ida. Jefe y Administrador: «Pasó por la parada «X»» en Acciones. Paradas en el orden del recorrido, vehículo en su tramo (En movimiento, Detenido, Dejando / Recogiendo), sensores destacados, «Mi estado», cantidades sin ceros y la tarjeta «N esperando en [primera parada]» o Viajando. Opciones del trabajador: «Estoy en la parada …» (con sus hijos), «Me bajé en mi parada», «Estoy en mi parada», «Ya me recogieron», «No voy en este viaje» (en la ida pregunta «¿Tampoco irá en el regreso?») |
| **Más** | Conversaciones, Compartir la app (64 o 32 bits). Administrador: Ajustes de la app, Olvidé algo, Actualizaciones de la app (sube los APK de 64 y 32 bits y marca Obligatoria), Mantenimiento del servidor (estado, instalar o actualizar la base de datos, tareas, caché, registro de errores) |
| **Perfil, Hijo, Mi QR** | Se abren desde Inicio. Mi QR cambia cada 15 s, sin capturas de pantalla |
| **Conversación** | Con el desarrollador, estilo WhatsApp, solo texto y con motivo; se consulta cada «Frecuencia chat» |

## 5.4 Tiempo real calculado en el teléfono

`lib/services/tracking/worker_tracker.dart` (código puro, con pruebas) implementa §11.43–§11.44 y §11.61: con la
distancia a la parada de referencia (la primera en la ida, la suya en el regreso) en dos cálculos seguidos, **Radio
parada**, **Tolerancia GPS**, **Velocidad humana** y **Distancia abandono** deciden De camino / En la parada / No voy a
viajar; **Viajando** (ida y regreso; 4.3.0: Recogido se unificó en Viajando) si sale de la parada más rápido que una persona; **Dejado** tras «Cálculos
consecutivos» a velocidad humana en el radio de alguna parada. Cuando el vehículo pasó por la parada de referencia
(ida: salió de la primera): **Botado** si estaba En la parada y no está Viajando; **Dormido** si llega
después; luego No voy a viajar si se aleja (un Botado que sale en el vehículo pasa a Viajando) o fin del
cálculo pasada la «Espera final». Viajando hace del teléfono un **sensor**: Detenido / En movimiento,
próxima parada (entra en su radio y sale, o la salta) y si está detenido en ella.

**Ventana de viaje** (§11.62, `trip_window.dart` y `tracking_service.dart`): para cada viaje en que viaja (`meta.myTrips`)
la ventana va de **X** («Inicio ventana») antes de la salida a **Y** («Fin ventana») después de que el viaje termine
para él. Dentro, un **servicio en primer plano de ubicación** (`flutter_foreground_task`, cuya notificación fija es
**«Mi estado»**, §5.5) calcula cada **Z** («Frecuencia ventana») y hace **una sola petición**,
`POST trips/{id}/reports?cursor=N`: el cambio pendiente más antiguo (con acuse y reintento), el GPS, el sensor y, de
vuelta, la línea del recorrido y las novedades de `GET sync`. Lo arranca la app o, con la app cerrada, una **alarma
exacta** (`miruta_alarm`, `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`; en Android 12+ una alarma exacta permite abrir un
servicio en primer plano desde segundo plano) que se reprograma al reiniciar el teléfono. Fuera de la ventana no se
usa el GPS: `workmanager` consulta `GET sync` cada **F** («Frecuencia fuera ventana», mínimo 15 min). Con la app
abierta el servicio le pasa qué datos cambiaron y no se repiten peticiones. Con el GPS apagado el servicio arranca
igual y «Mi estado» pide activarlo; sin ningún permiso de ubicación no puede arrancar y «Mi estado» sale como
notificación normal al abrirse la ventana («Permita la ubicación todo el tiempo» o «Active la ubicación (GPS)»).

## 5.5 Sincronización, notificaciones y actualizaciones

- `GET sync?cursor=N` fuera de la ventana de viaje cada F (con la app abierta y en segundo plano con `workmanager`,
  mínimo 15 min de Android) y con el botón Actualizar; dentro de la ventana, en la petición del servicio cada Z. Las notificaciones que llegan
  se muestran en el teléfono (sin pantalla de avisos); `meta.counters` da el número de Gestión; `meta.changed`, qué
  pantallas recargar; `settingsVersion`, cuándo recargar los ajustes; `myTrips`, la ventana de viaje; `versions`, qué datos guardados
  volver a pedir; `finishedTrips` y `pendingApplications`, qué notificaciones quitar o actualizar.
- **Notificaciones** (4.3.0, §11.63; textos en `notification_texts.dart`, código puro con pruebas; muestra
  `notifications.dart`). Seis canales y cada notificación con título, líneas (estilo de texto largo, todas a la vista)
  y una última línea **destacada en naranja** (formato HTML de Android; donde no se aplique el color queda como la
  última línea). Se actualizan en su sitio (id estable):

  | Canal | Notificación |
  |---|---|
  | Viajes | Una por viaje: «Viaje planificado / cambiado / en ejecución / cancelado / eliminado», «[Itinerario] • ida», «Lun. 16/11/26 07:00», «[Parada de salida] • [Tipo de vehículo]»; en «cambiado», destacada «Cambió la fecha, hora y …» (solo lo que cambió). Se quita al terminar el viaje (`finishedTrips`); cancelado o eliminado, al pasar la hora de salida |
  | Vehículo | Una por viaje en ejecución, compuesta en el teléfono por el servicio de ubicación con la línea del recorrido: «[Tipo] • en movimiento / detenido», itinerario, «Anterior» / «Próxima»; destacadas «Primera parada», «Última parada», «Recogiendo en …» (regreso) / «Dejando en …» (ida) o, sin sensores, solo el tipo y «Sin datos» con los últimos datos. Se quita al llegar él a un estado definitivo (Dejado, Botado, Dormido, No voy; Viajando en el regreso) y al terminar el viaje |
  | Mi estado | La fija del servicio de ubicación: estado, «[Itinerario] • ida», «Mi parada: …»; destacadas «Llegó tarde a la parada» (Dormido), «El vehículo pasó sin recogerle» (Botado), «Ya puede quitar la ubicación» (terminó para él). Sin GPS solo «Active la ubicación (GPS)» (tocar: ajustes de ubicación); sin «Permitir todo el tiempo», solo «Permita la ubicación todo el tiempo» (tocar: permisos de MiRuta) |
  | Solicitudes | Una de «N solicitudes pendientes» (Administrador y Jefe) con los tipos que tengan alguna («Entidad: 1 • Itinerario: 2 • Olvidé algo: 1»); se quita cuando no queda ninguna. Una por cada solicitud propia respondida («Solicitud aprobada / rechazada», Entidad o Itinerario • Entidad + Parada, fecha; destacada «Motivo: …» si se rechaza); se quitan al verlas en Inicio |
  | Mensajes | «Respuesta del desarrollador»: el último mensaje, su fecha y, con más de uno, «N mensajes sin leer»; tocar abre la conversación; se quita al leerla |
  | Actualizaciones | «Actualización disponible / obligatoria», «Versión 4.3.0», «Tamaño: 13.6 MB» (APK de este teléfono); destacada «Instálela para seguir usando MiRuta» si es obligatoria; tocar abre Más y empieza la descarga; se quita al instalarla |

  Al abrirse, la app crea los canales y borra los de la 4.2.0 (`viajes`, `ubicacion`, `mi_estado`, `general`,
  `recorrido`) y los recordatorios «Active la ubicación» que esta programó.
- **Actualización obligatoria** (§11.54): al recibir `426` la app cierra la sesión (también en el servidor), recuerda
  la obligación sin conexión y desde el inicio de sesión obliga a descargar e instalar (`ota_update`, con SHA-256).

## 5.6 Compilar

`./build_release.sh` compila los dos APK (64 y 32 bits; se entregan como `miruta-4.3.0-64bits.apk` y `miruta-4.3.0-32bits.apk`) por separado con el mismo `versionCode` (sin el desplazamiento
de `--split-per-abi`, que rompería la comparación de versiones de la API), firmados con la clave de
`android/key.properties` (no se sube al repositorio).
