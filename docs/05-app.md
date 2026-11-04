# 5. App móvil (Flutter, Android)

La app se llama **MiRuta** en todas partes (lanzador, textos, avisos y APK). Interfaz en **español**, con **trato de usted** en todos los textos (sin exagerar: las etiquetas de los campos dicen el dato a secas, "Nombre", "Teléfono"; el usted va en las frases). Las opciones de menú solo aparecen si los permisos del usuario las permiten (`GET /me` → `meta.permissions`, versión 3.0). Los acuerdos de detalle de cada pantalla están en [09-repaso-pantallas.md](09-repaso-pantallas.md).

## 5.1 Arquitectura

| Aspecto | Decisión |
|---|---|
| Estructura | Por funcionalidad (`lib/features/<funcionalidad>/{data,domain,presentation}`) |
| Cliente HTTP | `dio`, con un interceptor que añade el JWT y renueva el token automáticamente al recibir 401 |
| JSON:API | Parser propio para `data`, `included`, `relationships` y `errors` |
| Almacenamiento seguro | `flutter_secure_storage`: token de renovación, último usuario y cuándo se escribió la contraseña por última vez. **Nunca la contraseña** |
| Base local | `sqflite`: copia de los viajes para comparar cambios y trabajar sin conexión |
| Tareas en segundo plano | `workmanager` (sincronización y comprobación de actualizaciones) y servicio en primer plano para compartir ubicación |
| Notificaciones | `flutter_local_notifications` |
| Mapa | `flutter_map` con las imágenes del **servidor de mapas propio** (`GET /map`, `tools/maps`). La vista no sale de Cuba; cada imagen vista se guarda en el teléfono y se puede descargar la zona de la Entidad para usarla sin conexión. La app no crece: no lleva mapas dentro |
| Ubicación | `geolocator` |
| QR | `qr_flutter` (mostrar) y `mobile_scanner` (escanear). **3.0:** clave EC P-256 propia en el almacén seguro de Android (Keystore, no exportable), certificada por el servidor (`POST /me/qr-devices`, 30 días); QR dinámico `MR1…` firmado en el teléfono y renovado cada 15 s con `FLAG_SECURE`; verificación sin conexión con la clave del servidor (`GET /qr-public-key`) y la lista de la Entidad (`GET /entities/{id}/scan-roster`); escaneos sin conexión guardados con su hora y enviados con `POST /offline-scans`. Formato exacto: [07-algoritmos.md §7.36](07-algoritmos.md#736-código-qr-de-la-persona) |
| Voz | `flutter_tts` |
| Recordar contraseña | Sustituye al PIN propio de la app, que **se eliminó**. No se guarda la contraseña: se mantiene la sesión `remember_password_days` días (7 por defecto, con el máximo que fija el Administrador); pasado ese plazo, o si el ajuste está desactivado, se pide la contraseña al abrir la app (ver [07-algoritmos.md §7.32](07-algoritmos.md#732-recordar-contraseña-app)) |
| Servidor | La dirección **no se pide al abrir la app**: puede venir puesta al compilar (`./build_release.sh <dirección>`, opcional) y el usuario la indica en la pantalla **Servidor**, con un **selector de protocolo** (`https` por defecto o `http`). Se guarda en el teléfono. Si el servidor redirige de `http` a `https`, se guarda la dirección `https` |
| Certificados | `network_security_config`: confía en los certificados **del sistema y del usuario** (opción A del repaso), para servidores con certificados propios. Admite `http` (`usesCleartextTraffic`) |
| Ícono | El del inicio de sesión se dibuja con las mismas formas y colores que el ícono adaptable de Android (`AppIcon`), así siempre coinciden |
| Instalación | `device_info_plus`: modelo del teléfono y tipos de procesador admitidos. La instalación se registra en el servidor la primera vez que hace falta (cabecera `X-Installation`) |
| Actualizaciones | `ota_update` (descarga con verificación SHA-256 e instalación), `package_info_plus`, `file_picker` (publicar los APK), `connectivity_plus` (solo con Wi-Fi), `share_plus` (compartir la app). Comprobación periódica en segundo plano cada `update_check_hours` horas |
| Gráficos | `fl_chart` (las estadísticas no se exportan) |
| Indicador de carga | Componentes comunes (`BusyButton`, `BusyIconButton`, `BusyListTile`, `BusySwitchListTile`): mientras se espera al servidor, el control que lanzó la acción muestra el indicador y queda desactivado |

### Reglas comunes de la interfaz

| Regla | Detalle |
|---|---|
| Campos | Vacío, el campo dice el dato que pide; al tocarlo, el nombre sube al borde y dentro aparece un ejemplo. Sin ayudas fijas debajo: solo el error en rojo si incumple sus reglas (validación por campo, cuando se ha tocado). Al pulsar el botón principal se marcan los obligatorios vacíos |
| Contraseñas | La contraseña y su repetición llevan las dos el ojo para verla |
| Teléfono | Viene relleno con `+53 ` (editable) |
| Fechas | Con el día de la semana y el año de 2 dígitos: "sáb. 31/10/26 13:51". Los controles de fecha tienen el mismo aspecto que los demás campos, con ícono de calendario que abre el almanaque |
| Viajes | "Viaje de ida" / "Viaje de regreso" en lugar de "Salida" / "Regreso" en todas las interfaces |
| Botones | Ícono + texto con acción y objeto ("Guardar vehículo", "Crear viaje") |
| Eliminar | Ícono de cesto de basura en rojo, siempre con confirmación |
| Estados | Lista desplegable (p. ej. Estado: Activada / Desactivada), no botones ni íconos |
| Foto de perfil | Si no hay foto, ícono genérico de persona (no iniciales) |
| Plurales | Corregidos ("1 asiento", "1 niño", "1 trabajador esperado") |
| Hablar con el desarrollador | Botón tonal, igual en todas las pantallas donde aparece, al final |

## 5.2 Pantallas comunes

| Pantalla | Contenido |
|---|---|
| **Inicio de sesión** | Ícono, usuario (recordado en el teléfono) y contraseña. Debajo, en una línea y del mismo tamaño: **Entrar** (azul) y **Olvidé algo** (naranja). Separador; **Registrarme por primera vez** (ya no existe "Me registró un superior"). Separador; **botón de servidor** de tres estados: "Indicar servidor" (naranja, sin dirección), "Conectado al servidor" (verde) o "Desconectado del servidor" (rojo). Al final, **Hablar con el desarrollador** y, al pie, versión · arquitectura. La app **no trae dirección de servidor** por defecto |
| **Servidor** | "Elija el protocolo de conexión e indique la dirección del servidor que le facilitó el administrador de la aplicación." Selector de protocolo (`https`/`http`) y dirección en la misma línea; si se pega una URL completa, el selector toma su protocolo. La app añade `/api/v1`, comprueba que responde MiRuta y la guarda. Si falla: "Fue imposible conectarse al servidor. Revise el protocolo de conexión que seleccionó, la dirección del servidor que indicó y asegúrese de tener conexión a Internet." Si la dirección cambia, la instalación se vuelve a registrar |
| **Registrarme por primera vez** | Nombres, apellidos y **carné** (`POST /users`); usuario y contraseña ya propuestos (`GET /username-suggestion`, `GET /password-suggestion`) y modificables. `GET /registration-status` dice si será el Administrador. Carné repetido: `409 IDENTITY_CARD_TAKEN` con su texto |
| **Otros datos del registro** | Solicitar Entidad (`POST /applications` `entity_membership`; el nombre se confirma con `GET /entities/lookup`), itinerario y parada, añadir hijos (`POST /children`), solicitar roles y **Mi QR**. Sin Pase ni jerarquía |
| **Olvidé algo** | Arriba, "El Administrador comprobará sus datos…"; después, qué olvidó (usuario, contraseña o los dos), **carné** y teléfono. Luego muestra el estado; al aprobarse, solo lo pedido (usuario y/o contraseña propuesta, que habrá que cambiar al entrar) |
| **Hablar con el desarrollador (sin cuenta)** | Nombre y apellidos, teléfono, motivo y mensaje; las respuestas llegan a ese teléfono |
| **Contraseña nueva obligatoria** | Cuando caduca la contraseña (pide también la actual) o tras recuperar el acceso |
| **Contraseña** (al abrir) | Si "Recordar contraseña" está desactivado o pasaron sus días, se pide la contraseña del usuario de la sesión. Sustituye a la antigua pantalla de PIN |
| **Actualización** | Al abrir la app y periódicamente se comprueba si hay una versión nueva (notificación). Si es obligatoria, no se puede seguir sin instalarla |
| **Inicio** | Tarjeta del usuario (nombres y apellidos; abreviaturas de sus Entidades o "Sin Entidad"); seis botones **Perfil, Hijos, Entidades, Itinerario, Roles, Viajes** (3 por fila, ícono y una palabra); y, con título, Hijos con derecho, **Entidad** (tarjeta con ↕: selector de la Entidad que se ve), Itinerario y parada, Roles (Trabajador primero) y Viajes de esa Entidad. Cada tarjeta lleva a su pantalla. Detalle en [11-acuerdos-registro-qr.md §11.10](11-acuerdos-registro-qr.md) |
| **Viajes** | Selector de Entidad; viajes **En curso** y **Confirmados**; tocar uno abre su detalle |
| **Detalle del viaje** | Viaje de ida y viaje de regreso (fecha, hora y punto de salida de cada uno), vehículo (matrícula `B 123 456`, "Cap. total · Cap. sentados · Cap. de pie"), chofer, atraso, chat del viaje, **"Ya subí"**, **"Mi QR"**, **"Seguir recorrido"** |
| **Recorrido en tiempo real** | Título "Viaje de ida · X" / "Viaje de regreso · X". Cabecera con paradas pasadas, **paradas donde no se detuvo y saltadas**, atraso y sensores activos. **Línea con hitos** (línea centrada del mismo alto siempre, paradas como puntos gruesos encima, distancias proporcionales, hora de paso y km junto al nombre) o **mapa** (recorrido de referencia, si existe, y trazado real; nunca líneas rectas entre paradas). Botón **Trabajadores** |
| **Trabajadores del viaje** | Selector Viaje de ida / Viaje de regreso; por parada y alfabéticamente, con foto (o ícono de persona) y los hijos que subieron (`boardedChildIds`); al final, quienes subieron sin ser esperados (`expected: false`, `outsider`). Sin número de posición ni jerarquía |
| **Mi código QR** | Un solo QR de la persona (sin trayecto): el dinámico del teléfono, con capturas bloqueadas. Ver [07-algoritmos.md §7.36](07-algoritmos.md#736-código-qr-de-la-persona) |
| **Escanear** (chofer, quien escanea la subida o da altas con QR) | `POST /qr-scans` (o comprobación local sin conexión) → tarjeta de la persona; si es de otro itinerario o Entidad, pregunta si la deja subir (`allowOutsider`); marcar qué hijos suben (`childIds`); avisar si ya subió (QR impreso: posible copia). Alta en itinerario: elegir parada y `POST /itinerary-assignments` |
| **Perfil** | Foto, nombres, apellidos, carné y usuario editables; sexo y nacimiento de solo lectura (salen del carné). Acciones: Guardar perfil, Cambiar contraseña |
| **Hijos** y **formulario del hijo** | Con derecho a viajar y desactivados; crear, agregar ya registrado (por carné), editar, desactivar o reactivar, eliminar. En el formulario: datos del carné de solo lectura, "Derecho a viajar hasta" y quién más lo tiene declarado |
| **Entidades**, **Itinerario y parada** y **Roles** | Cada una con su selector de Entidad cuando aplica: pertenencias y solicitudes de Entidad; itinerario y parada, ausencias (sin aprobación) y solicitud de itinerario; roles (Trabajador siempre) y solicitud de los roles solicitables. Darse de baja y cancelar solicitudes desde el menú **Acciones**. La pestaña "Solicitudes" desapareció |
| **Forma común** | Barra principal (Inicio, Viajes, Mensajes, Más) en todas las pantallas y punto de conexión; tarjetas modelo sin botones dentro (tocar = editar; mantener pulsado = selección múltiple); botón naranja **Acciones** con menú flotante, acciones en gris si no aplican. Ver [11 §11.18](11-acuerdos-registro-qr.md) |
| **Conversaciones** | Con los Jefes de mi itinerario, con los Jefes de Transporte de mi Entidad y con el desarrollador. Al abrir una se elige el motivo |
| **Avisos** | Avisos del servidor con su texto concreto (`message`): "Se aprobó su solicitud de <tipo> (<detalle>). La aprobó <nombre>", "Se rechazó … Motivo: <motivo>", comienzo y atraso de viajes, caducidad de la contraseña, incidencias del recorrido (jefes) |
| **Estadísticas** | Las que le corresponden por su rol. Periodo "Últimos" o "Rango de fechas" (un día = inicio y fin iguales). Gráfico con eje en enteros y título que dice qué se mide, más tabla. No se exportan |
| **Más** | Compartir la app (sin texto de ayuda; 64 bits por defecto o 32 bits). Al pie, "MiRuta · Versión x · 64 bits" |
| **Ajustes** | Ver 5.4 |

## 5.3 Gestión (según los permisos de cada rol)

En la versión 3.0 los roles son **configurables** ([11 §11.16](11-acuerdos-registro-qr.md)): cada rol es un conjunto de
operaciones con su ámbito (propio, su itinerario, su Entidad o todas). La app muestra en **Más → Gestión** solo las
pantallas y acciones que los permisos de `GET /me` permiten, con la misma forma común y un selector de Entidad donde
aplica. Pantallas:

- **Trabajadores:** lista por Entidad (activos y desactivados), **registrar persona** (Administrador: nombres,
  apellidos, carné, ¿tiene teléfono?, usuario y contraseña propuestos que se muestran al guardar para copiarlos o
  compartirlos; si el carné ya existe se le añade la Entidad), ficha, asignar itinerario y parada o roles,
  ajustes del trabajador, **QR impreso** (compartir, imprimir, anular), desactivar, dar de baja.
- **Solicitudes por resolver:** entrada en Entidad, itinerario y parada, roles; aprobar o rechazar (motivo
  obligatorio), también varias a la vez.
- **Roles:** Administrador de solo lectura; crear y editar (nombre, ícono, solicitable, por defecto, de itinerario,
  operaciones con su ámbito, roles que aprueban); eliminar; consultar la tabla fija de operaciones.
- **Entidades, itinerarios y paradas** (con imagen), orden de paradas, recorrido de referencia.
- **Vehículos** y **planificación de viajes** (Jefe de Transporte en su Entidad, Jefe de itinerario en su
  itinerario).
- **Ajustes** de la app, de la Entidad, por itinerario y por parada.
- **Estadísticas** (incluye quienes viajan fuera de su itinerario o Entidad y los niños que viajan realmente).
- **Olvidé algo** (carné y teléfono), **actualizaciones de la app**, **mantenimiento del servidor**,
  **nomencladores** (tipos de vehículo, tipos de ausencia y motivos de conversación) y **alta en itinerario con QR**.
- **Recorrido y subida** (chofer y quien escanea): iniciar y finalizar, escanear QR (con o sin conexión), marcar qué
  hijos suben, dejar subir a quien es de fuera, corregir pasajeros, escaneos sin conexión pendientes.

## 5.4 Ajustes del usuario

Cada ajuste lleva debajo una explicación breve de **una línea** (excepción a la regla de no poner ayudas). Los valores por defecto y los límites están en [06-ajustes.md](06-ajustes.md).

| Grupo | Ajustes |
|---|---|
| **Aviso de viaje de ida** | Forma (tiempo antes u hora fija), minutos antes, hora fija, días antes, qué hacer si la hora fija ya pasó, texto |
| **Aviso de viaje de regreso** | Igual que el de ida |
| **Avisos de paso por paradas** | Alcance (ninguna, la anterior o todas las anteriores), seguir después de subir, texto |
| **Avisos de cambios y cancelaciones** | Texto |
| **Comienzo y atrasos** | Aviso de comienzo del viaje; aviso de viaje atrasado |
| **Saturación del transporte** | Recibirlos, nivel (solo sobresaturado o también saturado), de qué viajes (los míos o los que gestiono), cuándo (al cambiar, antes de la salida o las dos) y minutos antes |
| **Mensajes** | Avisos de mensajes nuevos en el chat del viaje y en las conversaciones |
| **Ausencias** | Recibir avisos de viaje durante una ausencia |
| **Seguridad** | Recordar contraseña y días para recordarla; días de aviso antes de que caduque la contraseña; recordar el usuario (solo en el teléfono) |
| **Recorrido** | Vista (mapa o línea con hitos), voz (según rol), compartir ubicación, frecuencia de envío |
| **Frecuencias** | Para cada funcionalidad, con la app abierta y en segundo plano: viajes, recorrido, chat del viaje, conversaciones, solicitudes y avisos. Activar o desactivar la sincronización en segundo plano |
| **Actualizaciones** | Cada cuántas horas comprobar si hay versión nueva; descargar solo con Wi-Fi (solo en el teléfono, desactivado por defecto); buscar ahora |
| **Mapa sin conexión** (solo en el teléfono) | Descargar la zona de la Entidad (sus paradas con unos 2 km de margen), respetando "solo con Wi-Fi"; fecha de la última descarga |

Cada ajuste vale lo que elija el usuario; si no eligió nada, lo que fije su Entidad; y si tampoco, el valor de la app.

## 5.5 Datos de la API para la app (versión 3.0)

Las pantallas de la 3.0 (tarjetas, Inicio, «Acciones») las define docs/11 §11.3, §11.10 y §11.18; aquí, solo lo que la app pide a la API. Detalle en [04-api.md](04-api.md) y `api/V3-PARTE-B.md`.

| Necesidad | API |
|---|---|
| Qué mostrar en Gestión / Más | `GET /me` → `meta.permissions` (`operation`, `scope`, `entityId`, `itineraryId`) |
| Tarjetas de Inicio (Entidades, itinerario y parada, roles) | `GET /me` → `meta.memberships` |
| Hijos | `GET/POST/PATCH/DELETE /children` (+ foto) |
| Entidades, itinerario, roles | `POST /applications` (`entity_membership`, `itinerary_membership`, `role`); bajas: `DELETE /me/entities/{id}`, `DELETE /workers/{id}/itinerary`, `DELETE /worker-roles/{id}` |
| Ausencias | `GET/POST/PATCH/DELETE /absences` (sin aprobación) |
| Mi QR | `GET /qr-public-key`, `POST /me/qr-devices` (al iniciar sesión y antes de que caduque el certificado) |
| Escanear y subir | `POST /qr-scans`, `POST /trip-boardings` (`qr`, `childIds`, `allowOutsider`, `scannedAt`), `PATCH`/`DELETE /trip-boardings/{id}` (corrección) |
| Sin conexión | `GET /entities/{id}/scan-roster` (al sincronizar), `POST /offline-scans` (al recuperar la conexión) |
| QR impreso | `GET /workers/{id}/printed-qr`, `POST /workers/{id}/printed-qr/revoke` |
| Alta con QR | `POST /itinerary-assignments` |
| Ajustes de otro trabajador | `GET/PATCH/DELETE /users/{id}/settings` (`settings.worker`) |
| Borrar mensajes | `DELETE /trip-messages/{id}`, `DELETE /conversation-messages/{id}` |
| Estadísticas nuevas | `outsider-travellers`; `children-transported` con niños que viajan realmente |
