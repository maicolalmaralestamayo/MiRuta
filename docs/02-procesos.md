# 2. Procesos y reglas de negocio

## 2.1 Entidades, cuentas y registro

### Entidades

- Una **Entidad** es una empresa que usa la app. Tiene **abreviatura** (obligatoria, única, en mayúsculas, de 2 a 15 letras y números; es lo que se muestra en toda la app), **número** (opcional, 4 dígitos, único si se pone), nombre, descripción y observación.
- Solo el **Administrador** crea, edita y desactiva Entidades.
- Cada Entidad tiene sus propios itinerarios, paradas, vehículos y trabajadores. **Cada usuario ve y actúa solo sobre su Entidad**; lo de otra responde como si no existiera. El Administrador ve todo y elige con qué Entidad trabaja.
- Dos Entidades pueden usar el mismo lugar como parada, pero cada una la registra por separado.
- Los nomencladores (jerarquías, tipos de vehículo, tipos de ausencia, motivos de conversación y palabras no permitidas) son **comunes** a todas.

### Registro en dos pasos

1. **Crear la cuenta:** primer nombre, segundo nombre, primer apellido y segundo apellido (los cuatro obligatorios), **usuario** y **contraseña**.
   - La **primera cuenta** que se crea es la del **Administrador**. No es trabajador: no tiene Entidad, Pase, jerarquía ni viajes, y termina aquí.
2. **Unirse a la Entidad** (obligatorio para los demás): **abreviatura** de la Entidad (se escribe; la app muestra el nombre para confirmar y nunca enseña la lista de Entidades), **Pase**, **sexo** y **jerarquía**.
   - El Pase es único dentro de la Entidad (también entre trabajadores inactivos).
   - Hasta completar este paso la app no deja hacer nada más (la API responde `ENTITY_REQUIRED`).

**Foto de perfil** opcional. Si no hay foto, se muestran las iniciales.

**Activo e inactivo:** una cuenta (y su trabajador) está inactiva cuando tiene borrado lógico. Solo el Administrador las activa y desactiva.

### Trabajadores sin teléfono

1. El Jefe de Transporte, el Jefe de itinerario (en su itinerario) o el Administrador lo **registran**: cuatro nombres, Pase, sexo, jerarquía y, si quieren, itinerario y parada. La cuenta queda **sin usuario ni contraseña**.
2. Se genera un **código de activación** de un solo uso que caduca a los `activation_code_ttl_days` días. Se entrega **en mano** (papel o QR) y se puede regenerar.
3. Cuando tenga teléfono, el trabajador pulsa **"Ya me registró un superior"**, escribe la abreviatura, su Pase y el código, y **elige él mismo su usuario y su contraseña**.

### Usuario

- De 4 a 20 caracteres: letras sin tilde, números, punto (`.`) y guion bajo (`_`).
- Empieza por letra; no termina en signo; sin dos signos seguidos; al menos 3 letras; ningún carácter repetido más de 3 veces seguidas.
- No puede contener **palabras reservadas** (`admin`, `soporte`, `sistema`, `mitransporte`, `desarrollador`…) ni **palabras no permitidas** (nomenclador del Administrador). Se comprueban sin tildes y con los números camuflados convertidos en letras (`p3nd3jo`). Las palabras no permitidas de 7 letras o más se buscan dentro de todo el usuario; las más cortas, solo como parte separada por punto o guion bajo (para no rechazar "computadora" por contener "puta").
- Se guarda en minúsculas y es **único en toda la app**.
- Se cambia cuando se quiera desde **Mi perfil**. El anterior queda **bloqueado** para los demás durante `username_reuse_block_days` días (30).

### Contraseñas

| Regla | Ajuste de la app | Por defecto |
|---|---|---|
| Longitud mínima | `password_min_length` | 8 |
| Tipos de carácter (mayúscula, minúscula, número, símbolo) | `password_required_classes` | 3 de 4 |
| Sin el usuario ni los nombres o apellidos | `password_forbid_personal_data` | Sí |
| Sin contraseñas comunes | `password_forbid_common` | Sí |
| Caducidad | `password_expiry_days` | 365 días |
| Aviso antes de caducar | `password_expiry_warning_days` | 15 días |
| Anteriores que no se pueden repetir | `password_history_count` | 5 |

- Al **caducar**, la contraseña hay que cambiarla para seguir: la API solo permite el perfil propio (`PASSWORD_CHANGE_REQUIRED`) y la app muestra la pantalla de cambio obligatorio. Afecta a todos, incluido el Administrador.
- Se guardan con **bcrypt**; el historial guarda solo hashes. El teléfono **no guarda la contraseña**.

### No puedo entrar

Sustituye a la contraseña olvidada. No hay correos, SMS ni WhatsApp.

1. En el inicio de sesión, **"No puedo entrar"**: la persona marca qué olvidó (usuario, contraseña o los dos) y escribe la **abreviatura de su Entidad**, su **Pase** y un **teléfono**. La respuesta es siempre "Solicitud enviada", coincidan o no los datos.
2. El Administrador recibe un aviso. Ve los datos escritos y, si coinciden, **con quién**. Lo **verifica por su cuenta** (por ejemplo, llamándolo) y la **aprueba** o la **rechaza**.
3. Al aprobarla, **en ese mismo teléfono** (la solicitud va ligada a la instalación de la app): si olvidó el usuario, la app se lo muestra; si olvidó la contraseña, le deja elegir una nueva y entra. Las demás sesiones se cierran.
4. La solicitud caduca a las `access_recovery_ttl_hours` horas; el teléfono se borra al cerrarla. Hay un límite de solicitudes por hora desde un mismo teléfono (`access_recovery_max_per_hour`) y el Administrador puede **bloquear** un teléfono.

### Privacidad

| Dato | Quién lo ve |
|---|---|
| Nombres, foto, jerarquía (con su icono), cantidad de hijos | Todos los de su Entidad |
| Usuario | El propio trabajador y el Administrador |
| Pase | El propio trabajador, el Jefe de su itinerario (también al aprobar su entrada en el itinerario), los Jefes de Transporte de su Entidad y el Administrador |
| Fecha de nacimiento de sus hijos | El padre o la madre, sus jefes al aprobar y el Administrador |

### Inicio de sesión

- Con **usuario + contraseña**. Devuelve un token de acceso (30 min) y uno de renovación (90 días).
- Cada renovación entrega un token de renovación nuevo y revoca el anterior (**rotación**).
- Si alguien usa un token de renovación que ya se había usado, se considera robado y se revocan **todos** los tokens de la cuenta (ver [07-algoritmos.md §7.4](07-algoritmos.md#74-renovación-de-tokens-con-rotación)).
- Todos los tokens de renovación se revocan al cerrar sesión en todos los dispositivos o al desactivar la cuenta. Al cambiar la contraseña se cierran las **demás** sesiones.
- Solo en el teléfono:
  - la app recuerda el último usuario (se puede desactivar en los ajustes);
  - el usuario puede activar un **PIN propio de la app** (4 a 6 dígitos), guardado como hash **PBKDF2** con sal. Si lo olvida, entra de nuevo con usuario y contraseña.

### Hablar con el desarrollador sin cuenta

- En el inicio de sesión, al crear la cuenta y al unirse a la Entidad hay un botón **"Hablar con el desarrollador"**.
- Sin cuenta se escribe nombre, teléfono, motivo y mensaje. Cada conversación lleva un identificador de la **instalación** de la app, su versión, el modelo del teléfono y la versión de Android.
- El Administrador la ve como **"Sin cuenta"** y responde dentro de la app; la respuesta llega a ese teléfono. Si después se crea una cuenta en ese teléfono, la conversación pasa a la cuenta.
- Límite de mensajes por hora (`guest_messages_max_per_hour`); el Administrador puede cerrar conversaciones y bloquear instalaciones.

## 2.2 Solicitudes

Cada solicitud tiene un **tipo** y un **estado**:

- `pending`: pendiente.
- `approved`: aprobada.
- `rejected`: rechazada.
- `cancelled`: cancelada.

Las solicitudes **no se borran**: son el historial.

| Tipo | Datos propios | Quién aprueba | Efecto al aprobarse |
|---|---|---|---|
| `itinerary_membership` | Itinerario y parada (de su Entidad) | Jefe de **ese** itinerario o Jefe de Transporte de la Entidad | El trabajador pasa a ese itinerario y esa parada |
| `itinerary_chief` | Itinerario y parada (no puede ser ya Jefe de otro itinerario) | Jefe de Transporte de la Entidad | Pasa a ser jefe de ese itinerario **y** se cambia a ese itinerario y esa parada. Las solicitudes de itinerario que tuviera pendientes se cancelan |
| `driver` | — | Jefe de Transporte de la Entidad | Pasa a ser chofer |
| `transport_chief` | — | Administrador | Pasa a ser Jefe de Transporte |
| `child_addition` | Cuatro nombres y fecha de nacimiento del niño | Jefe de su itinerario o Jefe de Transporte | El niño queda declarado |
| `child_removal` | Niño | Jefe de su itinerario o Jefe de Transporte | El niño deja de estar declarado |
| `absence` | Tipo de ausencia, desde, hasta, observación | Jefe de su itinerario o Jefe de Transporte | Durante esas fechas: no cuenta como pasajero esperado, se pausa el contador de inactividad y no recibe avisos de viaje (salvo que lo active) |

La **jerarquía** ya no necesita solicitud: cada uno la cambia en su perfil (solo sirve para las estadísticas).

**Reglas comunes:**

- El Administrador puede aprobar cualquier solicitud; un Jefe de Transporte, solo las de su Entidad.
- **Nadie aprueba sus propias solicitudes.**
- Quien envió una solicitud puede **cancelarla** mientras esté pendiente.
- Al llegar una solicitud nueva, se avisa a quienes pueden aprobarla.
- Al aprobarse o rechazarse, se avisa al solicitante.
- **Mientras un cambio de itinerario está pendiente,** el trabajador sigue contando en su itinerario actual.
- **Un jefe de itinerario que se cambia a otro itinerario** sigue siendo jefe del anterior. Las jefaturas no dependen de en qué itinerario viaja.

### Asignaciones y retiradas directas

Los superiores pueden asignar y quitar sin esperar una solicitud, a usuarios ya registrados de su Entidad:

| Quién | Qué puede asignar o quitar |
|---|---|
| Administrador | Jefe de Transporte de cualquier Entidad, y todo lo demás |
| Jefe de Transporte | Jefe de itinerario y chofer en su Entidad; itinerario y parada de sus trabajadores |
| Jefe de itinerario | Itinerario y parada, solo en su itinerario |

Cada asignación queda como una solicitud **creada por el superior y ya aprobada**; cada retirada, como la baja correspondiente. El trabajador recibe un aviso (`role_assigned` o `role_removed`) y puede darse de baja de un rol cuando quiera.

### Bajas voluntarias

Son inmediatas, sin aprobación. Quedan registradas como solicitudes ya aprobadas, para que el historial esté completo.

| Tipo | Se avisa a | Efecto |
|---|---|---|
| `itinerary_leave` | Jefes de ese itinerario | Queda sin itinerario |
| `itinerary_chief_leave` | Jefes de Transporte | Pierde la jefatura de ese itinerario |
| `driver_leave` | Jefes de Transporte | Deja de ser chofer. Se le quita el vehículo, y sus viajes futuros se marcan **para reasignar** |
| `transport_chief_leave` | Administrador | Deja de ser Jefe de Transporte |

### Baja automática por inactividad

- Una tarea diaria del servidor da de baja de su itinerario (`itinerary_removal`, generada por el sistema) a quien **no ha subido a ningún viaje realizado de su itinerario** durante `inactivity_days` días (30 por defecto; ajuste de cada Entidad).
- Cuenta como actividad que el chofer o el Jefe de itinerario marquen que subió, o que el sistema lo detecte. **Conducir un viaje realizado también cuenta.**
- Solo cuentan los días en que el itinerario **tuvo viajes realizados**.
- Los días de **ausencia aprobada** no cuentan.
- Se avisa al trabajador `inactivity_warning_days` días antes (5 por defecto).
- No afecta a sus roles.

## 2.3 Hijos

- Un trabajador puede viajar con hijos menores, **en sus piernas**. Los niños **no ocupan plaza** y no cuentan para la saturación, pero sus números siempre se muestran.
- Se declaran con una solicitud `child_addition`: los cuatro nombres (obligatorios) y la **fecha de nacimiento** del niño.
- **Derecho a viajar:** el niño viaja hasta el **31 de agosto siguiente** al día en que cumple `child_max_age` años (16 por defecto; ajuste de cada Entidad, lo configura su Jefe de Transporte).
  - Ejemplo con 16: si cumple 16 el 10 de marzo de 2027, viaja hasta el 31 de agosto de 2027. Si los cumple el 15 de octubre de 2027, hasta el 31 de agosto de 2028.
  - La app **no deja enviar** la solicitud si el niño ya no tiene derecho.
- **Posible duplicado:** sin carné no se puede saber con certeza si dos padres declaran al mismo niño. Si en la misma Entidad ya hay uno con la misma fecha de nacimiento, primer nombre y primer apellido, se **avisa** a quien aprueba, sin bloquear. La app muestra además esta nota: *"Si son pareja y viajan en el mismo itinerario, solo uno de los dos debe declarar a los niños."*
- La **cantidad de hijos con derecho** es pública. Sus nombres también; su fecha de nacimiento, no.
- **Al subir,** se indica con cuántos niños sube (de 0 a los que tiene con derecho).

## 2.4 Vehículos y choferes

- Solo los Jefes de Transporte (y el Administrador) crean y gestionan vehículos.
- Datos del vehículo: **tipo** (nomenclador), **matrícula** (única), **asientos** (sin el del chofer) y **capacidad de pie**.
- **Capacidad total = asientos + capacidad de pie.** Se calcula.
- El Jefe de Transporte asigna a cada vehículo su **chofer habitual**, que debe ser un trabajador con rol de chofer. Al crear un viaje se propone ese chofer.
- No se guarda historial de asignaciones: lo que quedó en cada **viaje** ya registra qué chofer condujo qué vehículo.

## 2.5 Itinerarios y paradas

- **Itinerario:** nombre, descripción y observación, más una **lista ordenada de paradas**.
- **Parada:** punto de referencia, calle, entrecalle 1, entrecalle 2, latitud y longitud. Puede estar en varios itinerarios.
- El **punto de salida** de un viaje es la **primera** parada del itinerario, y el **punto de regreso**, la **última**.
  - Para cambiarlos hay que editar el itinerario: crear la parada y moverla al principio o al final.
  - Esto afecta a todos los viajes pendientes de ese itinerario, que se marcan como modificados para que las apps lo detecten al sincronizar.
- **Trayecto de salida:** recorre las paradas en orden. **Trayecto de regreso:** en orden inverso.
- No se puede quitar de un itinerario una parada en la que hay miembros. Primero hay que cambiarles la parada.

## 2.6 Viajes

### Datos

- Itinerario, vehículo y chofer.
- Fecha y hora de **salida**.
- Fecha y hora de **regreso**, posterior a la salida y elegida explícitamente.
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

### Planificación por rango de fechas

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
- **Solo cuentan los trabajadores.** Los niños van cargados y no ocupan plaza, pero sus números se muestran siempre: "35 trabajadores (+10 niños) · capacidad 40".
- Tres niveles:

  | Estado | Cuándo | Color |
  |---|---|---|
  | Normal | Trabajadores ≤ asientos | Sin marca |
  | **Saturado** | Más que asientos, pero caben de pie | Naranja |
  | **Sobresaturado** | Más que asientos + capacidad de pie | Rojo |

- La app lo resalta a los Jefes de Transporte y a los Jefes de ese itinerario.
- **Avisos de saturación**, configurables por cada usuario: recibirlos o no; nivel (solo sobresaturado, o también saturado); de qué viajes (los suyos, o los que gestiona: su itinerario o su Entidad); cuándo (al cambiar el estado, X minutos antes de la salida o las dos). Por defecto: sobresaturado, activado; saturado, desactivado. Se calculan en el teléfono al sincronizar.
- No se planifica un segundo vehículo: **un viaje = un vehículo**.

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

### Aviso de salida y aviso de regreso

- **Contenido:**
  - tipo de vehículo y matrícula;
  - chofer;
  - capacidad total;
  - fecha, hora y punto de salida;
  - fecha, hora y punto de regreso.
- **Cuándo,** a elección de cada usuario y por separado para salida y regreso:
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

### Avisos a superiores

Reciben un aviso:
- quienes pueden aprobar una solicitud, cuando llega una nueva;
- el solicitante, cuando su solicitud se resuelve;
- los superiores, cuando alguien se da de baja (ver 2.2).

Estos avisos se guardan en la tabla `notifications` del servidor y la app los recoge al sincronizar.

## 2.8 Recorrido en tiempo real

### Inicio y fin de cada trayecto

- El chofer, un Jefe del itinerario o un Jefe de Transporte pulsa **"Iniciar recorrido"**. Se hace por separado para la salida y para el regreso.
- El trayecto termina al pasar por la última parada o al pulsar **"Finalizar recorrido"**, lo que ocurra primero.

### Sensores

- Puede enviar su ubicación el chofer del viaje o cualquier miembro del itinerario. Cada uno decide si la comparte y cada cuánto (por defecto, cada 10 segundos).
- Android muestra una notificación fija mientras se comparte la ubicación.
- Sin cobertura, las posiciones se guardan en el teléfono y se envían después.
- **Combinación en el servidor:** se toma la mediana de las posiciones recientes de los sensores activos. Se descartan los que están a más de `sensor_outlier_distance_m` metros del grupo.
- Todos ven **cuántos sensores** hay activos.
- Un trabajador deja de enviar automáticamente al pasar por su parada de bajada.

### Paso por paradas

- El servidor registra el paso cuando la posición combinada entra en un radio de `stop_detection_radius_m` metros alrededor de la parada (100 m por defecto).
- Con esos registros la app avisa del paso por paradas y muestra la voz y la lista de la próxima parada.

### Vista del recorrido

Cada usuario elige entre:
- **Mapa:** itinerario, paradas, ruta seguida y posición actual.
- **Línea con hitos:** las distancias entre paradas son **proporcionales** a la distancia real. Al principio se usa la distancia en línea recta; cuando haya trayectos registrados, la distancia realmente recorrida.

### Voz

Disponible para el chofer, los Jefes de itinerario, los Jefes de Transporte y el Administrador, si la activan. Anuncia:
- *"Comenzando viaje"*
- *"Saliendo de parada X, próxima parada Y"*
- *"Llegando a parada Y"*
- *"Terminando viaje"*

### Estadísticas del viaje en marcha

- Pasajeros a bordo frente a la capacidad, y niños a bordo.
- Subidos frente a esperados, por parada y en total.
- Paradas pasadas y restantes.
- Adelanto o retraso respecto a lo planificado.
- Distancia recorrida y restante.
- Sensores activos.

## 2.9 Subida al transporte

### Formas de registrar la subida

Se guardan todas en `trip_boardings`:

| Forma | Cómo funciona |
|---|---|
| `automatic` | El teléfono del trabajador se mueve junto con el vehículo. Solo funciona si el trabajador comparte su ubicación (ver [07-algoritmos.md §7.23](07-algoritmos.md#723-subida-automática)) |
| `self` | El trabajador pulsa **"Ya subí"** |
| `qr` | El trabajador muestra su código QR y el chofer o un Jefe de itinerario lo escanea |
| `manual` | El chofer o un Jefe de itinerario marca a la persona en la lista |

- **El QR no lleva datos personales** (ni usuario ni Pase): es un token temporal firmado por el servidor, válido solo para ese trayecto.
- **Niños:** cada registro indica con cuántos niños sube. Si hay varios registros, vale el último. En la subida automática se asumen todos los niños con derecho, y se puede corregir después.

### Lista de pasajeros

No hay orden de subida. La lista va **por parada** (en el orden del itinerario) y, dentro de cada parada, **alfabéticamente** por apellidos y nombres. Muestra cuántos niños con derecho lleva cada uno.

### Lista de la próxima parada

Al salir de una parada, el chofer y los Jefes de itinerario ven la lista de la siguiente:
- **En el regreso:** quiénes **suben**, con su forma de marcar la subida.
- **En la salida:** quiénes **se bajan**.

## 2.10 Chats (solo texto)

| Chat | Participantes | Duración |
|---|---|---|
| **Del viaje** | Miembros del itinerario, chofer, Jefes del itinerario, Jefes de Transporte y Administrador | Visible mientras el viaje está `confirmed`. Se **borra** al pasar a `cancelled` o `completed` (o `trip_chat_retention_days` días después del regreso). Si se desconfirma, se oculta pero no se borra |
| **Con los Jefes de mi itinerario** | El trabajador y todos los Jefes de su itinerario | Se borra a los `conversation_retention_days` días del último mensaje (30 por defecto, lo configura el Administrador) |
| **Con los Jefes de Transporte** | El trabajador y los Jefes de Transporte **de su Entidad** | Igual |
| **Con el desarrollador** | La cuenta (aunque aún no se haya unido a una Entidad) y el Administrador | Igual |
| **Con el desarrollador, sin cuenta** | Quien escribe desde el inicio de sesión, la creación de la cuenta o la unión a la Entidad, y el Administrador (ver §2.1) | `guest_conversation_retention_days` días desde el último mensaje |

- Las conversaciones con jefes o con el desarrollador se abren eligiendo un **motivo** (nomenclador `conversation_topics`):
  - con los Jefes de itinerario o de Transporte: reportar un problema, reportar una queja, solicitar información;
  - con el desarrollador: dar ideas, reportar un error, solicitar información.
- Las conversaciones se pueden **cerrar** (y reabrir): cerradas, no admiten mensajes.
- Todas las caducidades de los chats son ajustes **de la app** (los fija el Administrador).
- Los mensajes de chat se borran **físicamente**. Es la única excepción a la regla de borrado lógico.

## 2.11 Estadísticas

- **Formato:** gráficos y tablas. Solo se ven en la app: no se exportan.
- **Periodo:** rango de fechas, fechas explícitas (días sueltos), o relativo (últimos X días, semanas, meses o años).
- **Visibilidad:** cada rol ve las que le corresponden:
  - Administrador: todas, de todas las Entidades (o de una);
  - Jefes de Transporte: todas, de su Entidad;
  - Jefes de itinerario: las de sus itinerarios;
  - chofer: las suyas;
  - trabajador: las propias.

| Grupo | Estadística |
|---|---|
| Viajes | Viajes por estado |
| | Puntualidad de salida y llegada (planificado frente a real) por itinerario, vehículo y chofer |
| | Duración real frente a planificada |
| | Viajes por chofer y por vehículo |
| Ocupación | Viajes saturados y sobresaturados (con trabajadores, niños, asientos, de pie y los que no caben) |
| | Ocupación media por itinerario y vehículo |
| | Asistencia (subidos frente a esperados) por itinerario y parada |
| | Niños transportados |
| Trabajadores | Distribución por itinerario, parada, jerarquía y sexo (la jerarquía solo sirve para esto) |
| | Historial de viajes de cada trabajador |
| | Solicitudes por tipo y estado, y tiempo medio de aprobación |
| Paradas y recorrido | Subidas y bajadas por parada |
| | Hora real de paso por cada parada |
| | Distancia recorrida por vehículo |

## 2.12 Actualizaciones de la app

- Solo el **Administrador** publica versiones: sube **un APK por tipo de procesador** (64 bits, 32 bits y, si quiere, uno universal) con su versión, su código (mayor que el anterior), las novedades y si es **obligatoria**. Los APK se guardan en el servidor (`public/uploads/apk/`).
- **Cada teléfono descarga el suyo:** la app pregunta a Android qué tipos admite. Si una versión tiene un solo APK, todos reciben ese.
- **Solo con Wi-Fi:** ajuste del teléfono, desactivado por defecto. Si está activado y hay datos móviles, la app avisa del tamaño y deja descargar igualmente. Las obligatorias se descargan siempre, avisando del tamaño.
- **Compartir la app:** desde **Más**, se envía el APK (por WhatsApp, Bluetooth, Quick Share…), eligiendo para qué tipo de teléfono (64 bits por defecto, o 32 bits). Si es del mismo tipo que el instalado, se comparte el del teléfono sin gastar datos. El mensaje lleva la dirección del servidor, que quien la instala pone con el botón **Servidor** de la bienvenida.
- La app comprueba si hay una versión nueva al abrirse, desde Ajustes y en la sincronización en segundo plano (avisa una vez por versión).
- La descarga se verifica con su huella SHA-256 y después se abre el instalador de Android. La primera vez, Android pide permitir que MiTransporte instale aplicaciones.
- **Obligatoria:** si hay una versión obligatoria posterior a la instalada, la app no deja seguir (ni iniciar sesión) hasta actualizar.
- La app envía su versión en cada petición; el Administrador ve cuántas cuentas tienen cada versión.
- Todas las versiones se firman con **la misma clave**; si no, Android no instala la actualización encima de la anterior.

## 2.13 Tareas programadas del servidor

Se ejecutan con el *scheduler* de Lumen y un `cron` cada minuto:

| Tarea | Frecuencia | Qué hace |
|---|---|---|
| `trips:auto-complete` | Cada minuto | Marca como realizados los viajes confirmados cuyo regreso ya pasó |
| `chats:purge-trips` | Cada minuto | Borra los mensajes de los viajes cancelados o realizados (pasados `trip_chat_retention_days` días) |
| `chats:purge-expired` | Diaria | Borra las conversaciones caducadas |
| `workers:inactivity` | Diaria | Avisa de la baja por inactividad y la aplica |
| `tokens:purge` | Diaria | Elimina los tokens de renovación caducados o revocados |
| `access-recoveries:expire` | Cada hora | Cierra las solicitudes "No puedo entrar" caducadas y borra su teléfono |
| `passwords:warn-expiry` | Diaria | Avisa a quien tiene la contraseña a punto de caducar |
