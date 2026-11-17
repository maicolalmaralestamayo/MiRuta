# 5. App móvil (Flutter, Android) — versión 4.5

La app se llama **MiRuta** (paquete `com.mitransporte.mitransporte`, versión `4.5.0+15`, Android 7.0 o superior).
Interfaz en **español**, con **trato de usted**. Funciona contra la API 4.5.0
([13-api-proxima-version.md](13-api-proxima-version.md)); lo acordado está resumido en
[12-resumen-proxima-version.md](12-resumen-proxima-version.md) y detallado en
[11-acuerdos-registro-qr.md](11-acuerdos-registro-qr.md) §11.19–§11.66 (la 4.2.0 implementa §11.61 y §11.62; la 4.3.0, §11.63; la 4.4.0, §11.65; la 4.5.0, §11.66). La
versión 3.0 de este documento queda en el historial de git.

## 5.1 Arquitectura

| Carpeta | Qué hay |
|---|---|
| `lib/core` | Cliente JSON:API (`dio`, renovación del token, cabecera `X-App-Version` y aviso de `426 APP_UPDATE_REQUIRED`), **caché local** (`local_cache.dart`), almacenamiento (`flutter_secure_storage` para los tokens, `shared_preferences` para lo demás), formatos («sáb. 07-11-26», 12 h «05:00 p. m.») y unidades de los ajustes (`12hor30min`, `1km200m`, `10km/hor`) |
| `lib/models` | Modelos de la API: persona y pertenencias (`GET me`), Entidades, itinerarios, paradas, trabajadores, solicitudes, hijos, nomencladores, viajes, línea del recorrido, ajustes, versiones, conversaciones |
| `lib/services` | Sesión, sincronización (`GET sync?cursor=N&changes=M`, registro de cambios y descarga inicial en `prefetch.dart`), notificaciones del teléfono, actualizaciones, ubicación compartida, QR (clave del teléfono MR1 y cola de «Incluir por QR» sin conexión), tema (`theme_controller.dart`) y `tracking/` (estado del trabajador y del vehículo, ventana de viaje, permisos) |
| `packages/miruta_alarm` | Paquete local (sin dependencias externas): alarma exacta que abre la ventana de viaje con la app cerrada y se reprograma al reiniciar el teléfono; en la app, `WindowAlarmReceiver.kt` arranca el servicio de ubicación |
| `lib/ui` | Pantallas por pestaña (`home`, `management`, `trips`, `profile`, `chat`, `admin`, `auth`, `shared`) y los componentes comunes (`widgets`) |

Dependencias (§11.49, solo las necesarias): `dio`, `flutter_secure_storage`, `shared_preferences`, `provider`, `intl`,
`geolocator`, `flutter_foreground_task`, `flutter_local_notifications` (+ `timezone`, `flutter_timezone`),
`workmanager`, `qr_flutter`, `mobile_scanner`, `pointycastle`, `image_picker`, `file_picker`, `share_plus`,
`path_provider`, `ota_update`, `package_info_plus`, `device_info_plus`, `url_launcher` y el paquete local
`miruta_alarm`. **Sin mapas.** La ubicación
compartida desde otras apps usa un canal propio (`mitransporte/share` en `MainActivity.kt`), sin paquetes.

## 5.2 Reglas comunes de la interfaz

- **Operaciones con el servidor** (§11.56 y §11.65): toda acción que se conecta al servidor muestra un **spinner
  sobre la zona de trabajo** (fondo blanco, sin ver el formulario; siguen visibles la barra superior y la de
  navegación): «[Acción] [Objeto]» arriba («Creando Parada», «Actualizando Viaje»), el círculo en el color de acento
  (naranja) y «✕ Cancelar» gris debajo (corta la conexión; atrás también). Al terminar **no** sale ninguna cinta. Lo
  hace `runAction` (`ui/widgets/busy.dart` y `core/busy_scope.dart`); el texto sale del nombre CRUD de la acción del
  menú (`progressiveLabel`). Al cargar una pantalla sin nada guardado: «Consultando [Objeto]» con «✕ Cancelar», que
  vuelve a la pantalla anterior. En pantallas sin barras (inicio de sesión) el spinner va en un diálogo.
- **Nombres CRUD** en los menús (§11.65): Consultar, Crear, Actualizar, Eliminar + Objeto («Crear Viaje»,
  «Eliminar Parada»); las acciones con significado propio, «Actualizar Solicitud: Aprobar», «Actualizar Viaje:
  Cancelar», «Actualizar Ausencia: Terminar»… **Ningún icono** cambió.
- **Botón Actualizar:** solo las notificaciones pendientes (GET sync) y los datos de la **pantalla visible** (sus
  `DataView` se apuntan solas en el `RefreshScope` de su `AppScaffold`).
- **Notificaciones siempre en la cortina** (4.3.0): con la app abierta o cerrada; ya no hay aviso dentro de la app.
  La tarea en segundo plano no consulta mientras la app está a la vista (consulta ella).
- **Contraseñas:** la app no propone ni sugiere contraseñas; solo comprueba los requisitos.
- **Formularios:** «Salir sin guardar» si hay cambios, con **Guardar** (color principal), **Salir sin guardar** (rojo)
  y **Cancelar** (gris) (`LeaveGuard`); el teclado recorre todos los campos («Siguiente» y, en el último, «Listo»).
  En Acciones, «**Crear [Objeto]**» abre uno vacío del mismo tipo; tras guardar, el formulario sigue mostrando lo
  guardado. Las **relaciones** se eligen y se quitan en el propio formulario (al crear y al actualizar) y quedan en
  «Pendiente de guardar» (con Deshacer) hasta **Guardar**, que lo guarda todo con un solo spinner (§11.65).
- **Modales** (`AppDialog`): ícono, título, texto y los **botones a todo el ancho, uno debajo del otro**: la acción
  arriba y Cancelar abajo; **Cancelar gris**, **Eliminar rojo**, **Confirmar en el color principal**.

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
  Tras el inicio de sesión se **descarga en segundo plano** todo lo que la persona puede ver (`prefetch.dart`) y en
  cada consulta el **registro de cambios** (`meta.changes`, §11.65) pone al día lo guardado **sin avisar**: cambia
  los registros, quita los borrados y vuelve a pedir por detrás las listas con altas. Las pantallas abren con lo
  guardado y no preguntan al servidor si el registro está al día (spinner solo si aún no hay nada guardado); lo que
  no cubre el registro (resúmenes, «me») se pregunta con `If-None-Match` → `304`. Si el teléfono lleva más de
  «Conservación cambios» sin conectarse, lo descarga todo de nuevo. Al cerrar sesión se borra.
- **Sin conexión**: solo consulta, con el aviso «Sin conexión: solo consulta. Actualizado hace …»; los cambios dan
  «Sin conexión: solo se puede consultar…»; en Gestión solo queda «Incluir por QR» (con su cola sin conexión).
- **Tema** claro, oscuro o automático (por omisión): **un solo botón** con el icono del modo actual que abre un menú
  (Claro, Oscuro, Automático), en el inicio de sesión y en la barra de Inicio (4.3.0); se guarda en el teléfono.
- **Contador** junto al botón Actualizar: con la app abierta, siempre la **Frecuencia corta** («↻ 7 s»), esté o no
  en la ventana de un viaje (4.4.0); al tocarlo conecta ya y se reinicia. Con la app en recientes sigue consultando
  con la corta mientras Android la mantenga viva.
- **Sin sesión** (4.3.0): el inicio de sesión comprueba la conexión cada 30 s (además de al abrirse, al tocar el punto
  y al entrar) con su contador «↻ 23 s» junto al punto; Recuperar acceso muestra el contador de la consulta de la
  solicitud pendiente (cada 30 s).

## 5.3 Pantallas

| Pantalla | Contenido |
|---|---|
| **Inicio de sesión** | Botón de **tema** (menú claro, oscuro, automático); botón **Servidor** (rojo sin servidor; diálogo «Falta el servidor» al intentar operar sin él), contador de la próxima comprobación (cada 30 s) y punto de conexión; usuario, contraseña, «Recordar contraseña»; **Entrar**, **Olvidé usuario/contraseña** (naranja), **Registrarme** (sin relleno). Con una **actualización obligatoria** pendiente muestra el aviso con «Descargar e instalar» y no deja entrar |
| **Inicio** (G22) | Tarjeta con los datos de la persona y sus roles; **Mi QR** (tocar = en grande); **Viajes activos** (de todos sus itinerarios); **Entidades** y sus solicitudes; **Itinerarios** y sus solicitudes, con la opción «**Ocultar / Mostrar solicitudes aprobadas**» (ocultas por omisión, se recuerda; pendientes y rechazadas siempre); **Paradas habituales**; **Ausencias** en curso; **Hijos**; aviso «Permisos para sus viajes» si faltan. Acciones: Consultar Perfil, Crear Solicitud: Entidad / Itinerario, Actualizar Trabajador: Parada habitual, Crear Hijo, Crear Ausencia, Actualizar Ausencia: Terminar, Cerrar sesión. El botón de **tema** está en la barra. Tocar una solicitud: Actualizar Solicitud: Aprobar / Rechazar (con el motivo de su tipo) a quien puede resolverla y Eliminar Solicitud si es propia |
| **Crear Ausencia** | Tipo, Desde, «Hasta (opcional, vacío = indefinida)», **itinerarios afectados** (uno o varios, de cualquiera de sus Entidades) y nota |
| **Gestión** (G19, G20) | Tarjetas de las tablas con su cantidad y el número de solicitudes pendientes: **Entidades, Itinerarios, Paradas, Trabajadores** y (Administrador) los **nomencladores**. Acciones: Incluir por QR, Registrar trabajador, crear Entidad / itinerario / parada |
| **Pantalla de cada tabla** | Buscador, tarjetas de 5 en 5, marcar (mantener) con Marcar todo / Desmarcar todo / Invertir selección, Acciones según lo marcado y los **sueltos**: Entidades + **«Solicitudes»** + «Trabajadores sin Entidad»; Itinerarios + **«Solicitudes»** + «Itinerarios sin Entidad» + «Trabajadores sin itinerario»; Paradas + «Paradas sin itinerario» + «Trabajadores sin parada» |
| **Formularios con relaciones** | **Entidad:** sus itinerarios («Crear itinerario»), trabajadores («Adicionar persona»: existente o registrar) y solicitudes (aprobar / rechazar). **Itinerario:** selector de **Entidad** (con «Sin Entidad»), **paradas en orden** (arrastrar), «Adicionar parada» (existente o nueva), trabajadores («Adicionar persona», con parada opcional), solicitudes; Acciones: quitar parada, asignar o quitar Jefe. **Parada:** «Usar mi ubicación actual» y «**Pegar ubicación**» («lat, lng», enlaces de Google Maps, OsmAnd y OpenStreetMap, `geo:`; si no la reconoce: «No se reconoce una ubicación en lo copiado»), sus **itinerarios** («Asociar itinerario», quitar de uno) y sus trabajadores. **Trabajador:** sus **Entidades**, cada una con sus **itinerarios y paradas** (tocar: ver, cambiar de parada, Jefe, quitar), «Añadir itinerario en X», «Asociar Entidad», y sus **hijos** («Añadir hijo») |
| **Incluir por QR** | Escanea el QR, muestra dónde está ya la persona y se elige Entidad, itinerario o parada (el itinerario de la parada, bloqueado). Sin conexión, comprueba el QR en el teléfono y lo envía al volver la conexión |
| **Ubicación compartida** | MiRuta aparece en «Compartir» (WhatsApp, Telegram, Google Maps, OsmAnd…): entiende `geo:`, enlaces de Google Maps (también los cortos, con conexión), de OpenStreetMap / OsmAnd y coordenadas escritas. Pregunta **Crear parada nueva** o **Cambiar la ubicación de una parada existente** (solo Administrador y Jefe); al guardar se cierra también esta pantalla |
| **Viajes** | Selectores Entidad e Itinerario; secciones **Planificados, En ejecución, Terminados, Cancelados** (estas dos se muestran u ocultan). Acciones: **Crear Viaje**; con un viaje marcado: Consultar Viaje, Consultar Recorrido, Consultar Trabajadores, Actualizar Viaje: Iniciar / Terminar / Cancelar, Eliminar Viaje |
| **Crear Viaje** | Itinerario; **Ida** y **Regreso**, cada uno con su interruptor, **Fecha**, **Hora de salida** (12 h con a. m. / p. m., en un diálogo al tocarla) y **Tipo de vehículo**; por omisión ida hoy 05:00 p. m. y regreso mañana 06:00 a. m.; observación. Un viaje cancelado o eliminado no impide crear otro |
| **Formulario del viaje** | Itinerario y sentido de solo lectura; fecha, hora (12 h) y tipo de vehículo editables solo en Planificado; estado y ocupación prevista |
| **Línea del recorrido** («Ver recorrido») | Requiere la ubicación activada solo a los trabajadores de ese viaje (el Administrador y los Jefes que no viajan la ven sin ella); si faltan «todo el tiempo» o la batería sin restricciones, aviso con la pantalla **Permisos del viaje**. Al abrirla, si viaja en él, el viaje entra en su ventana de viaje sin esperar a la próxima consulta. Tarjetas **Sensores** («Sensor / Sensores ahora», tocar = por qué cada uno es o no sensor) y **Mi estado** (con su parada salvo en Viajando; en Dejado, donde se le dejó), **del mismo tamaño**; la **línea** de siempre con el vehículo en su tramo y, en cada parada, cuántos hay **De camino, En la parada, Retrasados, No recogidos y Dejados** (sin ceros, ida y regreso); chip «Parada habitual». Sin la tarjeta de ocupación. Acciones: Actualizar Viaje: Marcar paso por parada / Iniciar / Terminar (Jefe y Administrador); Actualizar Mi estado: En la parada / Viajando (con sus hijos) / Dejado / No voy (eligiendo la parada); Consultar Trabajadores; Consultar Viaje |
| **Más** | Conversaciones, Compartir la app (64 o 32 bits). Administrador: Ajustes de la app, Olvidé algo, Actualizaciones de la app (sube los APK de 64 y 32 bits y marca Obligatoria), Mantenimiento del servidor (estado, instalar o actualizar la base de datos, tareas, caché, registro de errores y **Simulación**) |
| **Simulación** (4.5.0, Administrador) | Más → Mantenimiento del servidor → tarjeta o acción «Consultar Simulación». Sin simulación: **itinerario**, **sentido**, **cantidad de trabajadores simulados** (1 a 60), **vehículo simulado o real**, **velocidad de la simulación** (×1, ×2, ×5, ×10; solo vehículo simulado) y **porcentajes** de comportamiento (por omisión 70 % viajan, 10 % Retrasado, 10 % No recogido, 10 % No voy; deben sumar 100), botón «Crear Simulación» (spinner «Creando Simulación»). En curso: tarjeta de la simulación (vehículo, tiempo, estado del viaje), cantidades por estado de los simulados, dónde está el vehículo simulado y «Mi estado»; botones a todo el ancho **Consultar Recorrido** (color principal) y **Eliminar Simulación** (rojo, con confirmación; spinner «Eliminando Simulación»). Se consulta cada 10 s mientras está abierta (eso hace avanzar la simulación en el servidor). El viaje de prueba sale en Viajes como «**Simulación • …**» |
| **Perfil, Hijo, Mi QR** | Se abren desde Inicio. Mi QR cambia cada 15 s, sin capturas de pantalla |
| **Conversación** | Con el desarrollador, estilo WhatsApp, solo texto y con motivo; se consulta cada «Frecuencia chat» |

## 5.4 Tiempo real calculado en el teléfono

`lib/services/tracking/worker_tracker.dart` (código puro, con pruebas) implementa §11.65: el trabajador sube y baja
en **cualquier parada**, en la ida y en el regreso, y la parada se **detecta por cercanía** a las del recorrido.
**De camino** hacia la parada más cercana de las que el vehículo no ha pasado (se recalcula en cada cálculo); **En la
parada** dentro de su radio; **Viajando** si se aleja de ella más rápido que una persona; **No recogido** si estaba En
la parada y el vehículo pasó sin que subiera; **Retrasado** si iba De camino y el vehículo pasó antes de que llegara;
**Dejado** tras «Cálculos consecutivos» a velocidad humana en el radio de una parada o mientras los demás sensores dicen
que el vehículo sigue (en la parada más cercana); **No voy** si lo declara o se aleja de todas las paradas más allá de
la Distancia abandono. Finales: Dejado, No recogido, Retrasado y No voy (un No recogido que sale a velocidad de
vehículo antes de la Espera final pasa a Viajando). Viajando hace del teléfono un **sensor**: Detenido / En
movimiento, próxima parada (desde la siguiente a donde subió; entra en su radio y sale, o la salta) y si está detenido
en ella.

**Ventana de viaje** (§11.62, `trip_window.dart` y `tracking_service.dart`): para cada viaje en que viaja (`meta.myTrips`)
la ventana va de **X** («Inicio ventana») antes de la salida a **Y** («Fin ventana») después de que el viaje termine
para él. Dentro, un **servicio en primer plano de ubicación** (`flutter_foreground_task`, cuya notificación fija es
**«Mi estado»**, §5.5) calcula cada «**Frecuencia corta**» y hace **una sola petición**,
`POST trips/{id}/reports?cursor=N&changes=M`: **toda la cola** de cambios del trabajador y observaciones del vehículo,
cada uno con su **hora de captura** (sin conexión se guardan; las observaciones solo cuando cambian), el GPS y, de
vuelta, la línea del recorrido y las novedades de `GET sync`. No se envían coordenadas. Lo arranca la app o, con la app cerrada, una **alarma
exacta** (`miruta_alarm`, `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`; en Android 12+ una alarma exacta permite abrir un
servicio en primer plano desde segundo plano) que se reprograma al reiniciar el teléfono. Fuera de la ventana no se
usa el GPS: con la app cerrada, `workmanager` consulta `GET sync` cada «**Frecuencia larga**» (mínimo 15 min). Con la app
abierta el servicio le pasa qué datos cambiaron y no se repiten peticiones. Con el GPS apagado el servicio arranca
igual y «Mi estado» pide activarlo; sin ningún permiso de ubicación no puede arrancar y «Mi estado» sale como
notificación normal al abrirse la ventana («Permita la ubicación todo el tiempo» o «Active la ubicación (GPS)»).

## 5.5 Sincronización, notificaciones y actualizaciones

- `GET sync?cursor=N&changes=M` con la app abierta cada «Frecuencia corta», con la app cerrada fuera de la ventana cada
  «Frecuencia larga» (`workmanager`, mínimo 15 min de Android) y con el botón Actualizar; dentro de la ventana, en la
  petición del servicio cada «Frecuencia corta». Las notificaciones que llegan
  se muestran en el teléfono (sin pantalla de avisos); `meta.counters` da el número de Gestión; `meta.changed`, qué
  pantallas recargar; `settingsVersion`, cuándo recargar los ajustes; `myTrips`, la ventana de viaje; `changes`, el registro de cambios
  (§5.2, caché local); `finishedTrips` y `pendingApplications`, qué notificaciones quitar o actualizar.
- **Notificaciones** (4.3.0, §11.63; textos en `notification_texts.dart`, código puro con pruebas; muestra
  `notifications.dart`). Seis canales y cada notificación con título, líneas (estilo de texto largo, todas a la vista)
  y una última línea **destacada en naranja** (formato HTML de Android; donde no se aplique el color queda como la
  última línea). Se actualizan en su sitio (id estable):

  | Canal | Notificación |
  |---|---|
  | Viajes | Una por viaje: «Viaje planificado / cambiado / en ejecución / cancelado / eliminado», «[Itinerario] • ida», «Lun. 16/11/26 07:00», «[Parada de salida] • [Tipo de vehículo]»; en «cambiado», destacada «Cambió la fecha, hora y …» (solo lo que cambió). Se quita al terminar el viaje (`finishedTrips`); cancelado o eliminado, al pasar la hora de salida |
  | Vehículo | Una por viaje en ejecución, compuesta en el teléfono por el servicio de ubicación con la línea del recorrido: «[Tipo] • en movimiento / detenido», itinerario, «Anterior» / «Próxima»; destacadas «Primera parada», «Última parada», «Recogiendo en …» (regreso) / «Dejando en …» (ida) o, sin sensores, solo el tipo y «Sin datos» con los últimos datos. Se quita al llegar él a un estado final (Dejado, No recogido, Retrasado, No voy) y al terminar el viaje |
  | Mi estado | La fija del servicio de ubicación: estado (De camino, En la parada, Viajando, Dejado, No recogido, Retrasado, No voy), «[Itinerario] • ida», «Mi parada: …» (la detectada; no en Viajando); destacadas «Llegó tarde a la parada» (Retrasado), «El vehículo pasó sin recogerle» (No recogido), «Ya puede quitar la ubicación» (terminó para él). Sin GPS solo «Active la ubicación (GPS)» (tocar: ajustes de ubicación); sin «Permitir todo el tiempo», solo «Permita la ubicación todo el tiempo» (tocar: permisos de MiRuta) |
  | Solicitudes | Una de «N solicitudes pendientes» (Administrador y Jefe) con los tipos que tengan alguna («Entidad: 1 • Itinerario: 2 • Olvidé algo: 1»); se quita cuando no queda ninguna. Una por cada solicitud propia respondida («Solicitud aprobada / rechazada», Entidad o Itinerario • Entidad + Parada, fecha; destacada «Motivo: …» si se rechaza); se quitan al verlas en Inicio |
  | Mensajes | «Respuesta del desarrollador»: el último mensaje, su fecha y, con más de uno, «N mensajes sin leer»; tocar abre la conversación; se quita al leerla |
  | Actualizaciones | «Actualización disponible / obligatoria», «Versión 4.3.0», «Tamaño: 13.6 MB» (APK de este teléfono); destacada «Instálela para seguir usando MiRuta» si es obligatoria; tocar abre Más y empieza la descarga; se quita al instalarla |

  Al abrirse, la app crea los canales y borra los de la 4.2.0 (`viajes`, `ubicacion`, `mi_estado`, `general`,
  `recorrido`) y los recordatorios «Active la ubicación» que esta programó.
- **Actualización obligatoria** (§11.54): al recibir `426` la app cierra la sesión (también en el servidor), recuerda
  la obligación sin conexión y desde el inicio de sesión obliga a descargar e instalar (`ota_update`, con SHA-256).

## 5.6 Compilar

`./build_release.sh` compila los dos APK (64 y 32 bits; desde la 4.3.0 se entrega solo el de 32 bits,
`miruta-4.5.0-32bits.apk`, que se compila solo con `SOLO_32=1 ./build_release.sh`) por separado con el mismo `versionCode` (sin el desplazamiento
de `--split-per-abi`, que rompería la comparación de versiones de la API), firmados con la clave de
`android/key.properties` (no se sube al repositorio).
