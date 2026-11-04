# 2. Procesos y reglas de negocio

## 2.1 Entidades, cuentas y registro

### Entidades

- Una **Entidad** es una empresa que usa la app. Tiene **abreviatura** (obligatoria, única, en mayúsculas, de 2 a 15 letras y números; es lo que se muestra en toda la app), **número** (opcional), nombre, descripción, observación e **imagen** (opcional).
- Cada Entidad tiene sus propios itinerarios, paradas y vehículos. Dos Entidades pueden usar el mismo lugar como parada, pero cada una la registra por separado.
- **Una persona puede pertenecer a varias Entidades** (docs/11 §11.6): la cuenta, los nombres, el carné, los hijos y el QR son de la persona; en cada Entidad tiene su itinerario y parada y sus roles. Está activa a la vez en todas.
- Los nomencladores (tipos de vehículo, tipos de ausencia, motivos de conversación) son **comunes**. **Ya no hay Pase ni jerarquía** (versión 3.0).

### La persona y su carné

- La persona se identifica por su **carné de identidad** (11 dígitos), único en toda la app. De él salen la **fecha de nacimiento** y el **sexo** (no se escriben). Se guarda cifrado, con una huella para buscarlo ([07-algoritmos.md §7.37](07-algoritmos.md#737-carné-de-identidad)).
- Lo ven la propia persona, el Administrador y quien tenga `workers.view_identity_card` (por defecto, el Jefe de itinerario, de los miembros de su itinerario y de quienes solicitan entrar).

### Registro

1. **Registro:** nombres y apellidos (segundo nombre opcional), carné, **usuario** y **contraseña** ya propuestos por el sistema y modificables. **Sin Entidad.** Si el carné ya existe: `IDENTITY_CARD_TAKEN` con el texto de docs/11 §11.5.
   - Si aún no hay **Administrador**, quien se registra lo es (el servidor lo garantiza aunque dos lo intenten a la vez).
2. **Otros datos del registro** (ya con la sesión iniciada): solicitar entrar en una Entidad (por su abreviatura), solicitar itinerario y parada (una vez aprobada la Entidad), añadir hijos, solicitar roles y ver **Mi QR**.

- El **Administrador** entra en las Entidades que quiera sin solicitud («Unirme a una Entidad»).
- **Foto de perfil** opcional (sin foto, un ícono genérico).
- **Activo e inactivo:** la cuenta inactiva tiene borrado lógico (`workers.delete`). Una pertenencia se puede **desactivar** (`workers.deactivate`) o darse de **baja** (la persona o `entities.assign_members`).

### Registro por el Administrador (también sin teléfono)

- Lo hace quien tenga `workers.register` (por defecto, el Administrador) en la Entidad que elija: nombres, apellidos, carné y si **tiene teléfono**. El sistema propone usuario y contraseña; se muestran una vez para copiarlos y compartirlos. Al entrar por primera vez, debe cambiar la contraseña.
- **Si el carné ya existe**, no se crea otra cuenta: se le añade esa Entidad, aprobada (con aviso si tiene teléfono).
- **Sin teléfono:** usa un **QR impreso** (§2.16). Cuando entra por primera vez en la app con un teléfono, el impreso se anula.
- Desaparecen «Me registró un superior» y los códigos de activación.

### Usuario

- De **2 a 50** caracteres: letras sin tilde, números, punto (`.`) y guion bajo (`_`).
- Empieza por letra; no termina en signo; sin dos signos seguidos; al menos **2 letras**; ningún carácter repetido más de 3 veces seguidas.
- **Usuario propuesto:** primer nombre → +.segundo nombre → +.primer apellido → +.segundo apellido → +.2, .3… (minúsculas, sin tildes), mientras esté ocupado o no sea válido. También se propone una contraseña.
- No puede contener **palabras reservadas** (`admin`, `soporte`, `sistema`, `miruta`, `mitransporte`, `desarrollador`…). Se comprueban sin tildes y con los números camuflados convertidos en letras (`4dm1n`).
- En la versión 2.1 se **eliminó por completo** el nomenclador de palabras prohibidas en los usuarios (pantalla, API, tabla y datos iniciales): quedan solo las reglas de formación y las palabras reservadas.
- Se guarda en minúsculas y es **único en toda la app**.
- Se cambia cuando se quiera desde **Mi perfil**. El anterior queda **bloqueado** para los demás durante `username_reuse_block_days` días (30).

### Contraseñas

| Regla | Ajuste de la app | Por defecto |
|---|---|---|
| Longitud mínima | `password_min_length` | 8 |
| Tipos de carácter (mayúscula, minúscula, número, símbolo) | `password_required_classes` | 3 de 4 |
| Caducidad | `password_expiry_days` | 365 días |
| Anteriores que no se pueden repetir (historial) | `password_history_count` | 5 |

- Se **quitaron** en la versión 2.1 la lista de contraseñas comunes y la regla de no contener el usuario ni los nombres (y sus ajustes `password_forbid_common` y `password_forbid_personal_data`).
- **Aviso de caducidad:** cada día, durante los últimos `password_expiry_notice_days` días (15 por defecto; **ajuste de cada usuario**, 0 = sin avisos), el servidor crea un aviso `password_expiring`: *"Su contraseña caduca el sáb. 14/03/26. Cámbiela en Mi perfil."* En Mi perfil la fila Contraseña muestra "caduca el <día> dd/mm/aa".

- Al **caducar**, la contraseña hay que cambiarla para seguir: la API solo permite el perfil propio (`PASSWORD_CHANGE_REQUIRED`) y la app muestra la pantalla de cambio obligatorio. Afecta a todos, incluido el Administrador.
- Se guardan con **bcrypt**; el historial guarda solo hashes. El teléfono **no guarda la contraseña** (ni siquiera con "Recordar contraseña").

### Olvidé algo

La app no envía correos, SMS ni WhatsApp por su cuenta.

1. En el inicio de sesión, **«Olvidé algo»**: la persona marca qué olvidó (usuario, contraseña o los dos) y escribe su **carné** y un **teléfono** (sin Entidad ni Pase). La respuesta es siempre «Solicitud enviada».
2. Solo el **Administrador** (`access_recoveries.manage`) la aprueba, tras verificar los datos y confirmarlo por una tercera vía (llamada o WhatsApp).
3. Al aprobarla, el sistema propone una contraseña nueva. Se comunica **solo lo que se olvidó** (usuario, contraseña o ambos), por esa tercera vía o en el teléfono que hizo la solicitud. Al entrar con la contraseña nueva, debe cambiarla.
4. La solicitud caduca a las `access_recovery_ttl_hours` horas; el teléfono se borra al cerrarla. Hay un límite por hora desde un mismo teléfono y el Administrador puede **bloquear** un teléfono.

### Privacidad

| Dato | Quién lo ve |
|---|---|
| Nombres, foto, sexo y Entidades (tarjeta) | Quien puede ver a la persona |
| Usuario | La propia persona y el Administrador |
| Carné y fecha de nacimiento | La propia persona, el Administrador y `workers.view_identity_card` en su ámbito |
| Carné de los hijos | Sus padres y el Administrador |
| QR | No lleva datos personales: solo el identificador de la persona y firmas |

### Inicio de sesión

- Con **usuario + contraseña**. Devuelve un token de acceso (30 min) y uno de renovación (90 días).
- Cada renovación entrega un token de renovación nuevo y revoca el anterior (**rotación**).
- Si alguien usa un token de renovación que ya se había usado, se considera robado y se revocan **todos** los tokens de la cuenta (ver [07-algoritmos.md §7.4](07-algoritmos.md#74-renovación-de-tokens-con-rotación)).
- Todos los tokens de renovación se revocan al cerrar sesión en todos los dispositivos o al desactivar la cuenta. Al cambiar la contraseña se cierran las **demás** sesiones.
- Solo en el teléfono, la app recuerda el último usuario (se puede desactivar en los ajustes).

### Recordar contraseña

Sustituye al PIN propio de la app, que se **eliminó por completo** en la versión 2.1.

- Dos ajustes del usuario: **"Recordar contraseña"** (`remember_password`, activado por defecto) y **"Días para recordar la contraseña"** (`remember_password_days`, 7 por defecto). El máximo de días lo fija el Administrador (`remember_password_max_days`, 30 por defecto).
- **La contraseña no se guarda.** La app anota en el teléfono cuándo se escribió por última vez y mantiene la sesión (los tokens) durante esos días.
- Al abrir la app, si el ajuste está desactivado o ya pasaron los días, se pide de nuevo la contraseña. La sesión no se cierra mientras tanto: los avisos siguen llegando.
- Ver [07-algoritmos.md §7.32](07-algoritmos.md#732-recordar-contraseña-app).

### Servidor y conexión

- La dirección del servidor se indica en la pantalla **Servidor**, con un **selector de protocolo** (`https`, por defecto, o `http`) y la dirección en la misma línea. No se prueban protocolos automáticamente; si se pega una URL completa, el selector toma su protocolo.
- En el inicio de sesión, el botón de servidor tiene **tres estados**: "Indicar servidor" (naranja, sin dirección), "Conectado al servidor" (verde, responde) y "Desconectado del servidor" (rojo, no responde). Se comprueba al abrir y al volver de Servidor.
- La app confía en los **certificados del sistema y en los instalados por el usuario** (`network_security_config`). Si el servidor redirige de `http` a `https`, la app guarda la dirección `https`.

### Hablar con el desarrollador sin cuenta

- En el inicio de sesión, al registrarse y en "Otros datos del registro" hay un botón **"Hablar con el desarrollador"** (tonal, al final de la pantalla).
- Sin cuenta se escribe nombre y apellidos, teléfono (con `+53 ` puesto por defecto), motivo y mensaje. Cada conversación lleva un identificador de la **instalación** de la app, su versión, el modelo del teléfono y la versión de Android.
- El Administrador la ve como **"Sin cuenta"** y responde dentro de la app; la respuesta llega a ese teléfono. Si después se crea una cuenta en ese teléfono, la conversación pasa a la cuenta.
- Límite de mensajes por hora (`guest_messages_max_per_hour`); el Administrador puede cerrar conversaciones y bloquear instalaciones.

## 2.2 Solicitudes, roles y asignaciones

Cada solicitud tiene un **tipo** y un **estado** (`pending`, `approved`, `rejected`, `cancelled`). No se borran: son el historial.

| Tipo | Datos | Quién aprueba (por defecto) | Efecto |
|---|---|---|---|
| `entity_membership` | Abreviatura de la Entidad | `entities.approve_membership` (Administrador) | Pertenece a la Entidad, con el **rol por defecto** |
| `itinerary_membership` | Itinerario y parada (siempre juntos) | `members.approve` sobre ese itinerario (Jefe de ese itinerario y Administrador) | Pasa a ese itinerario y parada en esa Entidad (pierde el anterior; no pierde jefaturas) |
| `role` | Rol (+ itinerario si es por itinerario) | Los roles aprobadores con `roles.approve` en la Entidad (Chofer → Jefe de Transporte) y el Administrador | Tiene el rol en esa Entidad |

- **Nadie aprueba sus propias solicitudes.** El solicitante puede cancelarlas mientras estén pendientes. **Al rechazar, el motivo es obligatorio.**
- Se avisa a quienes pueden resolverla al llegar y al solicitante al resolverse.
- **Desaparecen** las solicitudes de hijos, de ausencias y de bajas.

### Roles configurables

- Un **rol** es un conjunto de **operaciones** (catálogo fijo, `GET /operations`) con su **ámbito**: propio, su itinerario, su Entidad o todas. El Administrador crea, edita y elimina roles, elige el **rol por defecto** y qué roles aprueban las solicitudes de cada uno (docs/11 §11.16).
- Roles de partida (editables): **Trabajador** (por defecto), **Chofer**, **Jefe de itinerario** (por itinerario: uno por Entidad) y **Jefe de Transporte** (docs/11 §11.15).
- El **Administrador** es un rol fijo con todas las operaciones en todas las Entidades; siempre hay al menos uno.
- Eliminar un rol lo quita a quien lo tenga (aviso `role_removed`).

### Asignaciones directas

| Qué | Operación | Por defecto |
|---|---|---|
| Entidad | `entities.assign_members` | Administrador |
| Itinerario y parada | `members.assign` | Administrador |
| Itinerario y parada **escaneando el QR** | `members.assign_by_qr` | Administrador (§2.16) |
| Roles | `roles.assign` + ser rol aprobador de ese rol | Administrador; Jefe de Transporte, solo Chofer |

### Bajas

Son acciones directas, con confirmación en la app: darse de baja de una Entidad (se borran su itinerario, su parada y sus roles allí; para volver hay que solicitarlo), del itinerario o de un rol. Si deja de poder conducir, sus viajes futuros quedan para reasignar.

### Ausencias

- **Sin aprobación:** las declara la propia persona (tipo, desde y hasta, o indefinida) y las edita o quita cuando quiera. También `absences.manage`.
- Efectos: durante la ausencia **no cuenta como pasajero esperado** y se **pausa la baja automática por inactividad**.

### Baja automática por inactividad

- Una tarea diaria del servidor quita su itinerario a quien **no ha subido a ningún viaje realizado de su itinerario** durante `inactivity_days` días (30 por defecto; ajuste de cada Entidad).
- Cuenta como actividad que el chofer o el Jefe de itinerario marquen que subió, o que el sistema lo detecte. **Conducir un viaje realizado también cuenta.**
- Solo cuentan los días en que el itinerario **tuvo viajes realizados**.
- Los días de **ausencia** no cuentan.
- Se avisa al trabajador `inactivity_warning_days` días antes (5 por defecto).
- No afecta a sus roles.

## 2.3 Hijos

- Los hijos son **de la persona** (no de una Entidad) y se identifican por su **carné**: nombres, apellidos y carné; la fecha de nacimiento y el sexo salen del carné. Foto opcional.
- **Sin solicitudes:** los padres los añaden, corrigen, desactivan y quitan directamente. Si el niño ya está registrado (lo declaró el otro padre), se avisa de que ya está declarado y se le asigna igualmente.
- **Derecho a viajar:** hasta el **31 de agosto siguiente** al cumpleaños en que alcanza `child_max_age` (16 por defecto; el de la Entidad si sus padres pertenecen a una sola, si no el de la app). Sin derecho no se puede añadir; cuando lo pierde, deja de mostrarse.
- **En la planificación no se espera a ningún niño:** los pasajeros esperados son solo trabajadores y la ocupación prevista no suma niños.
- **Al subir** se marcan **qué hijos suben** con el trabajador. Cada niño cuenta **una sola vez por trayecto**, aunque lo tengan declarado los dos padres.
- **Estadísticas:** hijos con derecho declarados y niños que viajan realmente (§2.11).

## 2.4 Vehículos y choferes

- Gestionan los vehículos quienes tienen `vehicles.manage` (por defecto, el Jefe de Transporte de la Entidad y el Administrador).
- Datos del vehículo: **tipo** (nomenclador), **matrícula** (única en la Entidad), **capacidad sentados** y **capacidad de pie**.
- **Matrícula cubana:** una letra de las permitidas (ajuste de la app `plate_letters`, `B,P,T` por defecto; lo edita el Administrador) seguida de 6 dígitos. Se escribe y se guarda junta y en mayúsculas (`B123456`; la API quita espacios y guiones) y la app la muestra con los dígitos separados (`B 123 456`).
- **Capacidad total = capacidad sentados + capacidad de pie.** Se calcula y se muestra de solo lectura.
- Quien tiene `vehicles.assign_driver` asigna a cada vehículo su **chofer habitual**, una pertenencia con `tracking.drive` (rol Chofer). Al crear un viaje se propone ese chofer.
- No se guarda historial de asignaciones: lo que quedó en cada **viaje** ya registra qué chofer condujo qué vehículo.

## 2.5 Itinerarios y paradas

- **Itinerario:** nombre, descripción y observación, más una **lista ordenada de paradas**.
- **Parada:** punto de referencia, calle, entrecalle 1, entrecalle 2, latitud y longitud. Puede estar en varios itinerarios.
- El **punto de salida** de un viaje es la **primera** parada del itinerario, y el **punto de regreso**, la **última**.
  - Para cambiarlos hay que editar el itinerario: crear la parada y moverla al principio o al final.
  - Esto afecta a todos los viajes pendientes de ese itinerario, que se marcan como modificados para que las apps lo detecten al sincronizar.
- **Viaje de ida:** recorre las paradas en orden. **Viaje de regreso:** en orden inverso.
- Itinerarios y paradas se gestionan juntos ("Itinerarios y paradas"): desde la ficha del itinerario se añaden paradas existentes o se crean nuevas con el mapa.
- **Recorrido de referencia:** el Jefe de ese itinerario o un Jefe de Transporte marca un viaje de ida y otro de regreso **ya terminados** de ese itinerario como trazado habitual (`referenceOutboundLeg`, `referenceReturnLeg`). Sirve para detectar desvíos (§2.8) y para dibujar el recorrido en el mapa. El Jefe de itinerario solo puede cambiar eso de la ficha.
- No se puede quitar de un itinerario una parada en la que hay miembros. Primero hay que cambiarles la parada.

## 2.6 Viajes

### Datos

- Itinerario, vehículo y chofer.
- Fecha y hora del **viaje de ida** (en la app: "Viaje de ida", con el punto de salida).
- Fecha y hora del **viaje de regreso**, posterior a la ida.
- Estado.

### Estados

| Estado | Significado |
|---|---|
| `unconfirmed` | No confirmado. Las apps no lo notifican |
| `confirmed` | Confirmado. Se notifica y tiene chat |
| `completed` | Realizado |
| `cancelled` | Cancelado. No se borra, queda como historial |

Solo hay **dos reglas** de transición:

1. Se puede pasar a `cancelled` si el viaje **no** está `completed`.
2. Se puede pasar a `completed` si el viaje **no** está `cancelled`.

Todo lo demás está permitido. Por ejemplo, un viaje confirmado se puede desconfirmar y volver a confirmar.

### Solapamiento

- Al pasar un viaje a `confirmed`, se comprueba que **ni el vehículo ni el chofer** tengan otro viaje `confirmed` cuyo intervalo `[salida, regreso]` se solape con el suyo.
- Si se solapa, se rechaza indicando con qué viaje choca.
- Los viajes no confirmados pueden solaparse entre sí.

### Planificación de varios días e itinerarios

- En **Nuevo viaje** el itinerario es de selección múltiple y las fechas se marcan en un almanaque (uno o varios días). Las horas de ida y de regreso se aplican a cada día marcado (el regreso puede caer al día siguiente).
- Se crean días × itinerarios viajes; cada itinerario lleva su vehículo y su chofer (los habituales por defecto). Antes de crear se muestra "Se crearán N viajes" y se señalan los solapes o faltantes en su fila.

### Planificación por rango de fechas (copia)

- Se crea un viaje y se **copia** a cada fecha de un rango. En cada copia todo es igual menos las fechas:
  - la salida pasa a cada día del rango, con la misma hora;
  - el regreso mantiene la misma distancia de tiempo respecto a la salida que en el original.
- Las copias se crean `confirmed` o `unconfirmed`, según elija quien planifica.
- La operación es **atómica**: si alguna copia confirmada se solapa, no se crea ninguna y se indican los días que chocan.
- **Confirmación y desconfirmación:** individual o masiva.

### Ocupación: saturación y sobresaturación

- **Trabajadores esperados** = miembros del itinerario con inscripción vigente
  − los que tienen ausencia aprobada en la fecha del viaje
  − el chofer del viaje, si es miembro de ese itinerario.
- **Solo cuentan los trabajadores.** **No se espera a ningún niño** (versión 3.0): "35 trabajadores · capacidad 40". Los niños que viajan se ven al subir.
- Tres niveles:

  | Estado | Cuándo | Color |
  |---|---|---|
  | Normal | Trabajadores ≤ capacidad sentados | Sin marca |
  | **Saturado** | Más que sentados, pero caben de pie | Naranja |
  | **Sobresaturado** | Más que sentados + capacidad de pie | Rojo |

- La app lo resalta a los Jefes de Transporte y a los Jefes de ese itinerario.
- **Avisos de saturación**, configurables por cada usuario: recibirlos o no; nivel (solo sobresaturado, o también saturado); de qué viajes (los suyos, o los que gestiona: su itinerario o su Entidad); cuándo (al cambiar el estado, X minutos antes de la salida o las dos). Por defecto: sobresaturado, activado; saturado, desactivado. Se calculan en el teléfono al sincronizar.
- No se planifica un segundo vehículo: **un viaje = un vehículo**.

### Viajes atrasados

- Un viaje de ida o de regreso **confirmado** está **atrasado** si no ha comenzado y ya pasó su hora más la tolerancia de la Entidad (`trip_delay_tolerance_minutes`, 5 min por defecto).
- La API lo indica en cada viaje (`outboundDelayed`, `returnDelayed`) junto con los minutos de atraso (`outboundDelayMinutes`, `returnDelayMinutes`: al comenzar, o hasta ahora si sigue sin comenzar). La app lo muestra como "Atrasado" en tarjetas, detalle y recorrido.
- Ver [07-algoritmos.md §7.31](07-algoritmos.md#731-viajes-atrasados-y-aviso-de-comienzo).

### Marcar como realizado

- Pueden marcarlo:
  - el **chofer de ese viaje**;
  - los **Jefes del itinerario de ese viaje**;
  - cualquier **Jefe de Transporte** y el **Administrador**;
  - el **servidor**, con una tarea programada, cuando un viaje `confirmed` llega a su hora de regreso más `trip_auto_complete_delay_minutes`.
- Cada marca se guarda en `trip_completions` (quién, con qué rol y cuándo). El viaje pasa a `completed` con la primera marca; las siguientes se añaden a la lista.
- Si el viaje deja de estar realizado (por ejemplo, porque se marcó por error), sus marcas **se conservan** con borrado lógico.

## 2.7 Notificaciones

Todas son **locales**: la app las programa en el teléfono a partir de los datos que sincroniza. Solo se notifican viajes `confirmed`.

### Aviso de viaje de ida y aviso de viaje de regreso

- **Contenido:**
  - tipo de vehículo y matrícula;
  - chofer;
  - capacidad total;
  - fecha, hora y punto de salida;
  - fecha, hora y punto de regreso.
- **Cuándo,** a elección de cada usuario y por separado para la ida y el regreso:
  - **tiempo antes** (por defecto, 60 minutos); o
  - **hora fija** de ese día o de N días antes (por ejemplo, a las 23:00 del día anterior).
- **Hora fija que no sirve:** si cae después del momento del viaje, el usuario decide si se usa el aviso por defecto o no se avisa.

### Avisos de cambios

Al sincronizar, la app compara cada viaje con su copia local y avisa en el momento si:
- se canceló;
- se desconfirmó ("pendiente de confirmación");
- cambió el chofer, el vehículo, alguna fecha u hora, o el punto de salida o de regreso.

Después reprograma los avisos.

### Avisos de paso por paradas

Cada usuario elige:
- **qué paradas le avisan:** ninguna, solo la anterior a la suya, o todas las anteriores;
- **si sigue recibiendo avisos después de subir**, de las paradas posteriores.

### Texto de los avisos

Cada usuario puede personalizar el texto de cada tipo de aviso, usando variables que la app rellena:

| Variable | Contenido |
|---|---|
| `{itinerario}` | Nombre del itinerario |
| `{tipo}` | Tipo de vehículo |
| `{matricula}` | Matrícula |
| `{chofer}` | Nombre y apellidos del chofer |
| `{capacidad}` | Capacidad total |
| `{fecha_salida}`, `{hora_salida}`, `{punto_salida}` | Datos de la salida |
| `{fecha_regreso}`, `{hora_regreso}`, `{punto_regreso}` | Datos del regreso |
| `{parada}` | Parada por la que acaba de pasar |
| `{hora}` | Hora del paso |
| `{paradas_restantes}` | Paradas que faltan hasta la suya |
| `{cambios}` | Lista de lo que cambió |

### Avisos de mensajes nuevos

Notificación al llegar un mensaje al chat del viaje (`trip_chat_notice_enabled`) o una respuesta en las conversaciones (`conversation_notice_enabled`). Los dos se activan o desactivan en los Ajustes del usuario (activados por defecto).

### Avisos del servidor

Reciben un aviso:
- quienes pueden aprobar una solicitud, cuando llega una nueva;
- el solicitante, cuando su solicitud se resuelve;
- los superiores, cuando alguien se da de baja (ver 2.2);
- el usuario, cada día de los últimos `password_expiry_notice_days` antes de que caduque su contraseña;
- los pasajeros esperados, el chofer y los Jefes del itinerario, cuando un viaje **comienza** (a tiempo o con atraso; `trip_start_notice_enabled`) y cuando se **atrasa** (una sola vez por viaje de ida o de regreso; `trip_delay_notice_enabled`). Se respeta `notify_during_absence`;
- quienes tienen `trips.edit` sobre el itinerario, cuando hay una **incidencia del recorrido** (§2.8). A los pasajeros no se les avisa.

Estos avisos se guardan en la tabla `notices` del servidor y la app los recoge al sincronizar. **El texto lo da la API** (`message`), con lo concreto: qué solicitud fue, quién la resolvió y, si se rechazó, el motivo. Además, `payload` lleva los datos del aviso (sentido del viaje, minutos de atraso, tipo de incidencia, parada). Ejemplos:

| Tipo | Texto |
|---|---|
| `application_received` | *Pepito Pérez García envió una solicitud de Declarar hijos (Juan Pérez López).* |
| `application_resolved` (aprobada) | *Se aprobó su solicitud de Itinerario y parada (Ruta Este · Parque). La aprobó Ana Gómez Ruiz.* |
| `application_resolved` (rechazada) | *Se rechazó su solicitud de Ausencia temporal (Vacaciones · indefinida). La rechazó Ana Gómez Ruiz. Motivo: …* |
| `password_expiring` | *Su contraseña caduca el sáb. 14/03/26. Cámbiela en Mi perfil.* |
| `trip_started` | *Comenzó el viaje de ida de Ruta Este (12 min de atraso).* / *… a tiempo.* |
| `trip_delayed` | *El viaje de regreso de Ruta Este está atrasado: debía comenzar a las 17:00.* |
| `trip_incident` | *Viaje de ida de Ruta Este: no se detuvo en la parada Parque.* / *se saltó la parada …* / *se desvió del recorrido.* |

## 2.8 Recorrido en tiempo real

### Inicio y fin de cada trayecto

- El chofer, un Jefe del itinerario o un Jefe de Transporte pulsa **"Iniciar viaje de ida"** o **"Iniciar viaje de regreso"**. Al iniciarlo se envía el aviso de comienzo.
- El trayecto termina al pasar por la última parada o al pulsar **"Finalizar recorrido"**, lo que ocurra primero.

### Sensores

- Puede enviar su ubicación el chofer del viaje o cualquier miembro del itinerario. Cada uno decide si la comparte y cada cuánto (por defecto, cada 10 segundos).
- Android muestra una notificación fija mientras se comparte la ubicación.
- Sin cobertura, las posiciones se guardan en el teléfono y se envían después.
- **Combinación en el servidor:** se toma la mediana de las posiciones recientes de los sensores activos. Se descartan los que están a más de `sensor_outlier_distance_m` metros del grupo.
- Todos ven **cuántos sensores** hay activos.
- Un trabajador deja de enviar automáticamente al pasar por su parada de bajada.

### Paso por paradas

- El servidor registra la **llegada** cuando la posición combinada entra en un radio de `stop_detection_radius_m` metros alrededor de la parada (100 m por defecto), y la **salida** cuando deja ese radio.
- Con esos registros la app avisa del paso por paradas y muestra la voz y la lista de la próxima parada.

### Paradas no realizadas y desvíos

| Incidencia | Cuándo | Ajuste de la Entidad |
|---|---|---|
| **No se detuvo** (pasó de largo) | Entró en el radio de la parada y salió estando menos de N segundos y sin bajar de V km/h | `stop_min_dwell_seconds` (15 s), `stop_pass_speed_kmh` (5 km/h) |
| **Se saltó la parada** | Llegó a una parada posterior sin haber pasado por esta | — |
| **Desvío** | Se alejó del recorrido de referencia más de X metros (se cierra al volver) | `route_deviation_m` (300 m) |

- La parada de salida no cuenta para estas incidencias; la última se da por detenida al llegar (termina el trayecto).
- El desvío solo se vigila si el itinerario tiene **recorrido de referencia** en ese sentido (§2.5).
- Cada incidencia queda registrada en el viaje (`trip_leg_incidents`) para las estadísticas, y se avisa a quienes tienen `trips.edit` sobre el itinerario. **A los pasajeros no se les avisa.**
- La app las muestra en la cabecera del recorrido en tiempo real y en el detalle del viaje.
- Ver [07-algoritmos.md §7.18](07-algoritmos.md#718-paso-por-paradas-paradas-no-realizadas-y-fin-del-trayecto) y [§7.33](07-algoritmos.md#733-desvío-del-recorrido-de-referencia).

### Vista del recorrido

Cada usuario elige entre:
- **Mapa:** paradas, recorrido de referencia (si existe), trazado real recorrido y posición actual. Nunca líneas rectas entre paradas. El mapa es el propio (§2.14).
- **Línea con hitos:** línea centrada que ocupa siempre el mismo alto; las paradas son puntos gruesos encima de la línea, a distancias **proporcionales** a la distancia real, con la hora de paso y los km al lado del nombre. Al principio se usa la distancia en línea recta; cuando haya trayectos registrados, la distancia realmente recorrida.

### Voz

Disponible para el chofer, los Jefes de itinerario, los Jefes de Transporte y el Administrador, si la activan. Anuncia:
- *"Comenzando viaje"*
- *"Saliendo de parada X, próxima parada Y"*
- *"Llegando a parada Y"*
- *"Terminando viaje"*

### Estadísticas del viaje en marcha

- Pasajeros a bordo frente a la capacidad, y niños a bordo.
- Subidos frente a esperados, por parada y en total.
- Paradas pasadas y restantes, paradas donde no se detuvo y paradas saltadas.
- Atraso al comenzar.
- Adelanto o retraso respecto a lo planificado.
- Distancia recorrida y restante.
- Sensores activos.

## 2.9 Subida al transporte

### Formas de registrar la subida

Una sola subida por persona y trayecto (`trip_boardings`):

| Forma | Cómo funciona |
|---|---|
| `automatic` | El teléfono del trabajador se mueve junto con el vehículo (si comparte su ubicación; [07-algoritmos.md §7.23](07-algoritmos.md#723-subida-automática)). No marca hijos |
| `self` | El trabajador pulsa **«Ya subí»** (solo miembros del itinerario) y marca qué hijos suben |
| `qr` | El chofer o quien tenga `tracking.scan_boarding` escanea el **QR de la persona** (§2.16) |
| `manual` | El chofer o quien escanea marca a la persona en la lista |

- **Hijos:** al subir se marca qué hijos suben (solo los activos con derecho). Cada niño, una vez por trayecto.
- **Alguien de otro itinerario o de otra Entidad:** se avisa a quien escanea, que decide si lo deja subir (necesita `tracking.allow_outsiders`). Si lo deja, se registra como `outsider` y **cuenta como pasajero**.
- **Una sola subida por trayecto:** un segundo escaneo de la misma persona se rechaza; con un QR impreso, se avisa de que puede ser una copia.
- **Corrección de pasajeros** (`tracking.fix_passengers`): quitar subidas, cambiar los hijos y añadir subidas después del trayecto.
- **Sin conexión:** las subidas se guardan en el teléfono con la hora del escaneo y se envían al recuperarla; el servidor revalida el QR y descarta los repetidos.

### Trabajadores del viaje (lista de pasajeros)

No hay orden de subida. La lista va **por parada** (en el orden del itinerario) y, dentro de cada parada, **alfabéticamente** por apellidos y nombres, con su subida y los hijos que subieron. Al final, quienes subieron sin ser esperados (de otro itinerario o Entidad).

### Lista de la próxima parada

Al salir de una parada, el chofer y los Jefes de itinerario ven la lista de la siguiente:
- **En el viaje de regreso:** quiénes **suben**, con su forma de marcar la subida.
- **En el viaje de ida:** quiénes **se bajan**.

## 2.10 Chats (solo texto)

| Chat | Participantes | Duración |
|---|---|---|
| **Del viaje** | Miembros del itinerario, chofer, Jefes del itinerario, Jefes de Transporte y Administrador | Visible mientras el viaje está `confirmed`. Se **borra** al pasar a `cancelled` o `completed` (o `trip_chat_retention_days` días después del regreso). Si se desconfirma, se oculta pero no se borra |
| **Dirigida a un rol** (p. ej. Jefe de itinerario, Jefe de Transporte) | La persona y quienes tienen ese rol en su Entidad (y en su itinerario, si es por itinerario) con `chat.role_conversations` | Se borra a los `conversation_retention_days` días del último mensaje |
| **Con el desarrollador** | La cuenta (aunque aún no se haya unido a una Entidad) y el Administrador | Igual |
| **Con el desarrollador, sin cuenta** | Quien escribe desde el inicio de sesión, la creación de la cuenta o la unión a la Entidad, y el Administrador (ver §2.1) | `guest_conversation_retention_days` días desde el último mensaje |

- Las conversaciones con jefes o con el desarrollador se abren eligiendo un **motivo** (nomenclador `conversation_topics`):
  - con los Jefes de itinerario o de Transporte: reportar un problema, reportar una queja, solicitar información;
  - con el desarrollador: dar ideas, reportar un error, solicitar información.
- Las conversaciones se pueden **cerrar** (y reabrir): cerradas, no admiten mensajes.
- Todas las caducidades de los chats son ajustes **de la app** (los fija el Administrador).
- Los mensajes de chat se borran **físicamente**. Es la única excepción a la regla de borrado lógico.
- Cada uno puede **borrar sus mensajes**; los de otros, quien tenga `chat.delete_messages` (en el itinerario del viaje o en la Entidad de la conversación).

## 2.11 Estadísticas

- **Formato:** gráficos y tablas. Solo se ven en la app: no se exportan.
- **Periodo:** «Últimos» (X días, semanas, meses o años) o «Rango de fechas».
- **Visibilidad:** `statistics.view` con su ámbito (su itinerario, su Entidad o todas; por defecto, Jefe de itinerario, Jefe de Transporte y Administrador). Sin él, el chofer ve las de sus viajes y cada trabajador las propias.

| Grupo | Estadística |
|---|---|
| Viajes | Viajes por estado; puntualidad; duración; viajes por chofer y por vehículo |
| Ocupación | Viajes saturados y sobresaturados (solo trabajadores); ocupación media; asistencia por itinerario y parada |
| Niños | **Niños que viajan realmente** (marcados al subir), niños distintos e hijos con derecho declarados |
| Trabajadores | Distribución por itinerario, parada y sexo (sin jerarquía); historial de viajes; solicitudes por tipo y estado |
| | **Trabajadores que viajan fuera de su itinerario o de su Entidad** (`outsider-travellers`) |
| Paradas y recorrido | Subidas y bajadas por parada; hora real de paso; distancia; incidencias del recorrido |

## 2.12 Actualizaciones de la app

- Solo el **Administrador** publica versiones: sube **un APK por tipo de procesador** (64 bits, 32 bits y, si quiere, uno universal), las novedades y si es **obligatoria**. Los APK se guardan en el servidor (`public/uploads/apk/`).
- **La versión y el código se leen del propio APK** (`AndroidManifest.xml`) y se muestran de solo lectura; todos los APK de una versión deben coincidir (`APK_VERSION_MISMATCH`) y el código debe ser mayor que el de la última versión. Solo si no se pueden leer se piden a mano.
- **Cada teléfono descarga el suyo:** la app pregunta a Android qué tipos admite. Si una versión tiene un solo APK, todos reciben ese.
- **Solo con Wi-Fi:** ajuste del teléfono, desactivado por defecto. Si está activado y hay datos móviles, la app avisa del tamaño y deja descargar igualmente. Las obligatorias se descargan siempre, avisando del tamaño.
- **Compartir la app:** desde **Más**, se envía el APK (por WhatsApp, Bluetooth, Quick Share…), eligiendo para qué tipo de teléfono (64 bits por defecto, o 32 bits). Si es del mismo tipo que el instalado, se comparte el del teléfono sin gastar datos. El mensaje lleva la dirección del servidor, que quien la instala pone con el botón de servidor del inicio de sesión.
- La app comprueba si hay una versión nueva al abrirse, desde Ajustes y **periódicamente en segundo plano**, cada `update_check_hours` horas (24 por defecto, ajustable por el usuario), y muestra una notificación cuando hay versión nueva (una vez por versión).
- La descarga se verifica con su huella SHA-256 y después se abre el instalador de Android. La primera vez, Android pide permitir que MiRuta instale aplicaciones.
- **Obligatoria:** si hay una versión obligatoria posterior a la instalada, la app no deja seguir (ni iniciar sesión) hasta actualizar.
- La app envía su versión en cada petición; el Administrador ve cuántas cuentas tienen cada versión.
- Todas las versiones se firman con **la misma clave**; si no, Android no instala la actualización encima de la anterior.

## 2.13 Tareas programadas del servidor

Se ejecutan con el *scheduler* de Lumen y un `cron` cada minuto o, en un hospedaje sin cron
(`TASKS_ON_REQUESTS=true`), al terminar las peticiones de la app, como mucho una vez por minuto; las diarias y por
hora que no tocaron por falta de uso se ejecutan en la primera petición posterior. El Administrador ve cuándo se
ejecutó cada una, y las lanza a mano, en *Gestión → Mantenimiento del servidor* (§2.15).

| Tarea | Frecuencia | Qué hace |
|---|---|---|
| `trips:auto-complete` | Cada minuto | Marca como realizados los viajes confirmados cuyo regreso ya pasó |
| `chats:purge-trips` | Cada minuto | Borra los mensajes de los viajes cancelados o realizados (pasados `trip_chat_retention_days` días) |
| `chats:purge-expired` | Diaria | Borra las conversaciones caducadas |
| `workers:inactivity` | Diaria | Avisa de la baja por inactividad y la aplica |
| `tokens:purge` | Diaria | Elimina los tokens de renovación caducados o revocados |
| `access-recoveries:expire` | Cada hora | Cierra las solicitudes "Olvidé algo" caducadas y borra su teléfono |
| `passwords:warn-expiry` | Diaria | Avisa cada día, durante los últimos `password_expiry_notice_days` días de cada usuario, a quien tiene la contraseña a punto de caducar |
| `trips:notify-delays` | Cada minuto | Avisa de los viajes de ida o de regreso atrasados (una vez por cada uno) |
| `qr:purge-nonces` | Cada hora | Borra los códigos QR ya usados que caducaron (7 días después de su hora) |

## 2.14 Mapa propio

- La app **no lleva mapas** ni usa los servidores públicos de OpenStreetMap: pide las imágenes al **servidor de mapas propio**, que guarda los datos de Cuba y las dibuja con un estilo sencillo (calles con sus nombres, edificios y PDI). Se prepara con los scripts de `tools/maps` (ver `tools/maps/README.md`).
- `GET /map` da la plantilla de las imágenes (ajuste de la app `map_tiles_url`, `/tiles/{z}/{x}/{y}.png` por defecto, relativa a la dirección del servidor), los niveles de zoom, los **límites de Cuba** y la **zona de la Entidad** (sus paradas con unos 2 km de margen).
- La vista **no sale de Cuba**. Las zonas vistas **se guardan en el teléfono**: no se vuelven a descargar y funcionan sin Internet.
- **Descarga sin conexión** de la zona de la Entidad cuando el usuario quiera (Ajustes → Mapa sin conexión), respetando "solo con Wi-Fi".

## 2.15 Mantenimiento del servidor desde la app

Para hospedajes sin SSH (solo FTP), lo que antes eran comandos se hace desde la app:

- **Quién**: el Administrador con su sesión (*Gestión → Mantenimiento del servidor*) o, sin sesión, quien tenga la
  **clave de mantenimiento** del servidor (`MAINTENANCE_KEY`): pantalla *Servidor → Mantenimiento del servidor*.
  La clave sirve para instalar el servidor y para arreglarlo si nadie puede entrar.
- **Estado**: versión de PHP y extensiones, límites de subida, conexión con la base de datos, si está instalada y
  los cambios pendientes, carpetas con permiso de escritura y la última ejecución de cada tarea programada.
- **Órdenes** (solo estas, nunca una orden libre): *Instalar base de datos* (solo si está vacía), *Actualizar base
  de datos* (cambios de una versión nueva y ajustes nuevos), *Ejecutar tareas pendientes*, *Limpiar caché* y *Ver
  registro de errores*.
- Si el servidor responde pero con error (p. ej. aún sin base de datos), la app acepta igualmente la dirección,
  para poder hacer el mantenimiento.

## 2.16 Código QR de la persona

**Un solo QR por persona para toda la app** (docs/11 §11.8 y §11.9). Identifica a la persona, no una Entidad, y **no lleva datos personales**. Formato y verificación: [07-algoritmos.md §7.36](07-algoritmos.md#736-código-qr-de-la-persona).

- **Con teléfono (QR dinámico):** al iniciar sesión, el teléfono crea una clave propia en el almacén seguro de Android y el servidor la certifica (30 días). El teléfono genera el QR **sin conexión** firmando la persona, la hora y un número aleatorio, y lo **renueva cada 15 s**. La pantalla no admite capturas. Cada código vale **una sola vez** y ±2 minutos.
- **Sin teléfono (QR impreso):** fijo, no caduca; lo ven, reimprimen y anulan el Administrador y el Jefe de su itinerario (`workers.printed_qr`). Se imprime junto a nombres, apellidos y sexo. Anularlo invalida las copias. Una sola subida por trayecto: si el mismo QR se usa dos veces en un viaje, se avisa. Al entrar por primera vez con teléfono, se anula solo.
- **Usos:** subir al transporte (§2.9) y **alta directa en un itinerario** (`members.assign_by_qr`, por defecto solo el Administrador): solo si la persona pertenece a esa Entidad; quien escanea elige la parada; pierde su itinerario anterior en esa Entidad pero no sus jefaturas.
- **Sin conexión en ambos teléfonos:** quien escanea guarda la clave del servidor y la lista de la Entidad (trabajadores con su versión del impreso e hijos con derecho), comprueba las firmas sin conexión, muestra la tarjeta de la lista y guarda las subidas y altas para enviarlas al recuperar la conexión.
