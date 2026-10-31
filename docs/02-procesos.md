# 2. Procesos y reglas de negocio

## 2.1 Registro y cuenta

1. Cualquiera puede registrarse con:
   - **carné de identidad** (11 dígitos);
   - **nombre** y **apellidos**;
   - **jerarquía** (del nomenclador);
   - **contraseña**.
2. **Validación del carné:**
   - Tiene 11 dígitos.
   - Los 6 primeros (`AAMMDD`) forman una fecha válida.
   - El siglo lo da el **7.º dígito**: 9 → 1800; 0–5 → 1900; 6–8 → 2000.
   - No puede haber otro trabajador con el mismo carné, ni siquiera inactivo.
3. **Datos que se calculan a partir del carné:**
   - **Sexo**, por el **penúltimo dígito**: par → masculino, impar → femenino. Se guarda en su propio campo.
   - **Fecha de nacimiento.** No se guarda.
4. **El primer usuario** que se registra se convierte en **Administrador**. Los demás empiezan sin itinerario y sin roles.
5. **Foto de perfil** opcional. Si no hay foto, se muestra un icono por defecto.
6. **Activo e inactivo:** un trabajador está inactivo cuando tiene borrado lógico (`deleted_at`). Reactivarlo es restaurar su fila.

### Contraseña olvidada

Sin correo ni SMS: el código lo envía el Administrador por WhatsApp.

1. En la pantalla de inicio de sesión, el trabajador pulsa **"¿Olvidaste tu contraseña?"** y escribe su **carné** y un **número de teléfono** con WhatsApp. La respuesta es la misma exista o no el carné.
2. El servidor genera un **código** de 8 caracteres y avisa a los Administradores.
3. El Administrador comprueba la solicitud y pulsa **Enviar por WhatsApp**: se abre WhatsApp con el mensaje y el código ya escritos.
4. El trabajador entra con su carné y el código. El código sirve **una sola vez**, caduca a las `password_reset_ttl_hours` horas (24 por defecto) y admite **5 intentos**.
5. Al entrar se cierran sus demás sesiones y la app le **obliga a elegir una contraseña nueva** antes de hacer cualquier otra cosa.

Una solicitud nueva cancela la anterior. El teléfono y el código se guardan cifrados, solo los ve el Administrador y **se borran** en cuanto la solicitud termina (usada, caducada o cancelada).

### Privacidad

| Dato | Quién lo ve |
|---|---|
| Nombre, apellidos, foto, jerarquía (con su icono), cantidad de hijos | Todos |
| Carné del trabajador | Solo el propio trabajador y el Administrador |
| Carné y fecha de nacimiento de sus hijos | Solo el propio trabajador y el Administrador |

- El carné se guarda **cifrado** (`card_number_encrypted`). Para iniciar sesión y comprobar que no se repite se usa su **huella** (`card_number_hash`, HMAC-SHA256 con una clave del servidor).
- La API solo devuelve el carné en `/me`, o al Administrador.

### Inicio de sesión

- Con **carné + contraseña**. Devuelve un token de acceso (30 min) y uno de renovación (90 días).
- Cada renovación entrega un token de renovación nuevo y revoca el anterior (**rotación**).
- Si alguien usa un token de renovación que ya se había usado, se considera robado y se revocan **todos** los tokens del trabajador (ver [07-algoritmos.md §7.4](07-algoritmos.md#74-renovación-de-tokens-con-rotación)).
- Todos los tokens de renovación de un trabajador se revocan al cerrar sesión, al cambiar la contraseña o al desactivarlo.
- Solo en el teléfono:
  - la app recuerda el último carné usado;
  - el teclado del carné es numérico;
  - el usuario puede activar un **PIN propio de la app** (4 a 6 dígitos), igual en cualquier teléfono. Si lo olvida, entra de nuevo con carné y contraseña.

## 2.2 Solicitudes

Cada solicitud tiene un **tipo** y un **estado**:

- `pending`: pendiente.
- `approved`: aprobada.
- `rejected`: rechazada.
- `cancelled`: cancelada.

Las solicitudes **no se borran**: son el historial.

| Tipo | Datos propios | Quién aprueba | Efecto al aprobarse |
|---|---|---|---|
| `itinerary_membership` | Itinerario y parada | Jefe de **ese** itinerario o Jefe de Transporte | El trabajador pasa a ese itinerario y esa parada |
| `itinerary_chief` | Itinerario y parada (no puede ser ya Jefe de otro itinerario) | Jefe de Transporte | Pasa a ser jefe de ese itinerario **y** se cambia a ese itinerario y esa parada. Las solicitudes de itinerario que tuviera pendientes se cancelan |
| `driver` | — | Jefe de Transporte | Pasa a ser chofer |
| `transport_chief` | — | Administrador | Pasa a ser Jefe de Transporte |
| `rank_change` | Jerarquía nueva | Jefe de su itinerario o Jefe de Transporte | Cambia su jerarquía |
| `child_addition` | Nombre, apellidos y carné del niño | Jefe de su itinerario o Jefe de Transporte | El niño queda declarado |
| `child_removal` | Niño | Jefe de su itinerario o Jefe de Transporte | El niño deja de estar declarado |
| `absence` | Tipo de ausencia, desde, hasta, observación | Jefe de su itinerario o Jefe de Transporte | Durante esas fechas: no cuenta como pasajero esperado, se pausa el contador de inactividad y no recibe avisos de viaje (salvo que lo active) |

**Reglas comunes:**

- El Administrador puede aprobar cualquier solicitud.
- **Nadie aprueba sus propias solicitudes.**
- Quien envió una solicitud puede **cancelarla** mientras esté pendiente.
- Al llegar una solicitud nueva, se avisa a quienes pueden aprobarla.
- Al aprobarse o rechazarse, se avisa al solicitante.
- **Mientras un cambio de itinerario está pendiente,** el trabajador sigue contando en su itinerario actual.
- **Un jefe de itinerario que se cambia a otro itinerario** sigue siendo jefe del anterior. Las jefaturas no dependen de en qué itinerario viaja.

### Bajas voluntarias

Son inmediatas, sin aprobación. Quedan registradas como solicitudes ya aprobadas, para que el historial esté completo.

| Tipo | Se avisa a | Efecto |
|---|---|---|
| `itinerary_leave` | Jefes de ese itinerario | Queda sin itinerario |
| `itinerary_chief_leave` | Jefes de Transporte | Pierde la jefatura de ese itinerario |
| `driver_leave` | Jefes de Transporte | Deja de ser chofer. Se le quita el vehículo, y sus viajes futuros se marcan **para reasignar** |
| `transport_chief_leave` | Administrador | Deja de ser Jefe de Transporte |

### Baja automática por inactividad

- Una tarea diaria del servidor da de baja de su itinerario (`itinerary_removal`, generada por el sistema) a quien **no ha subido a ningún viaje realizado de su itinerario** durante `inactivity_days` días (30 por defecto).
- Solo cuentan los días en que el itinerario **tuvo viajes realizados**.
- Los días de **ausencia aprobada** no cuentan.
- Se avisa al trabajador `inactivity_warning_days` días antes (5 por defecto).
- No afecta a sus roles.

## 2.3 Hijos

- Un trabajador puede viajar con hijos menores, **en sus piernas**. Los niños **no ocupan plaza** y no cuentan para la sobresaturación.
- Se declaran con una solicitud `child_addition`: nombre, apellidos y carné del niño. La fecha de nacimiento se calcula a partir del carné.
- **Derecho a viajar:** el niño viaja hasta el **31 de agosto siguiente** al día en que cumple `child_max_age` años (16 por defecto, lo configura el Jefe de Transporte).
  - Ejemplo con 16: si cumple 16 el 10 de marzo de 2027, viaja hasta el 31 de agosto de 2027. Si los cumple el 15 de octubre de 2027, hasta el 31 de agosto de 2028.
  - La app **no deja enviar** la solicitud si el niño ya no tiene derecho.
- **Un niño no puede declararse dos veces:** su carné es único entre los niños declarados. La app muestra además esta nota: *"Si son pareja y viajan en el mismo itinerario, solo uno de los dos debe declarar a los niños."*
- La **cantidad de hijos con derecho** es pública. Sus nombres también; su carné y su fecha de nacimiento, no.
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

### Sobresaturación

- **Pasajeros esperados** = miembros del itinerario con inscripción vigente
  − los que tienen ausencia aprobada en la fecha del viaje
  − el chofer del viaje, si es miembro de ese itinerario.
- Si los pasajeros esperados superan la **capacidad total**, el viaje está **sobresaturado**. La app lo resalta en color llamativo a los Jefes de Transporte y a los Jefes de ese itinerario.
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

- **El QR no contiene el carné.** Lleva un token temporal firmado por el servidor, válido solo para ese trayecto.
- **Niños:** cada registro indica con cuántos niños sube. Si hay varios registros, vale el último. En la subida automática se asumen todos los niños con derecho, y se puede corregir después.

### Orden de subida

1. Primero, **todos los que suben con niños** (según los declarados con derecho en la fecha del viaje).
2. Después, el resto: **mujeres** antes que **hombres**.
3. Dentro de cada grupo: por **jerarquía** (de la más alta a la más baja) y, en caso de empate, **alfabéticamente** por apellidos y nombre.

### Lista de la próxima parada

Al salir de una parada, el chofer y los Jefes de itinerario ven la lista de la siguiente:
- **En el regreso:** quiénes **suben**, en orden de subida, con su forma de marcar la subida.
- **En la salida:** quiénes **se bajan**.

## 2.10 Chats (solo texto)

| Chat | Participantes | Duración |
|---|---|---|
| **Del viaje** | Miembros del itinerario, chofer, Jefes del itinerario, Jefes de Transporte y Administrador | Visible mientras el viaje está `confirmed`. Se **borra** al pasar a `cancelled` o `completed`. Si se desconfirma, se oculta pero no se borra |
| **Con los Jefes de mi itinerario** | El trabajador y todos los Jefes de su itinerario | Se borra a los `conversation_retention_days` días del último mensaje (30 por defecto, lo configura el Administrador) |
| **Con los Jefes de Transporte** | El trabajador y todos los Jefes de Transporte | Igual |
| **Con el desarrollador** | El trabajador y el Administrador | Igual |

- Las conversaciones con jefes o con el desarrollador se abren eligiendo un **motivo** (nomenclador `conversation_topics`):
  - con los Jefes de itinerario o de Transporte: reportar un problema, reportar una queja, solicitar información;
  - con el desarrollador: dar ideas, reportar un error, solicitar información.
- Los mensajes de chat se borran **físicamente**. Es la única excepción a la regla de borrado lógico.

## 2.11 Estadísticas

- **Formato:** gráficos y tablas, exportables a **Excel** y **PDF**. Los archivos se generan en la app.
- **Periodo:** rango de fechas, fechas explícitas (días sueltos), o relativo (últimos X días, semanas, meses o años).
- **Visibilidad:** cada rol ve las que le corresponden:
  - Administrador y Jefes de Transporte: todas;
  - Jefes de itinerario: las de sus itinerarios;
  - chofer: las suyas;
  - trabajador: las propias.

| Grupo | Estadística |
|---|---|
| Viajes | Viajes por estado |
| | Puntualidad de salida y llegada (planificado frente a real) por itinerario, vehículo y chofer |
| | Duración real frente a planificada |
| | Viajes por chofer y por vehículo |
| Ocupación | Viajes sobresaturados |
| | Ocupación media por itinerario y vehículo |
| | Asistencia (subidos frente a esperados) por itinerario y parada |
| | Niños transportados |
| Trabajadores | Distribución por itinerario, parada, jerarquía y sexo |
| | Historial de viajes de cada trabajador |
| | Solicitudes por tipo y estado, y tiempo medio de aprobación |
| Paradas y recorrido | Subidas y bajadas por parada |
| | Hora real de paso por cada parada |
| | Distancia recorrida por vehículo |

## 2.12 Actualizaciones de la app

- Solo el **Administrador** publica versiones: sube el APK desde la app con su versión, su código (mayor que el anterior), las novedades y si es **obligatoria**. Los APK se guardan en el servidor (`public/uploads/apk/`).
- La app comprueba si hay una versión nueva al abrirse, desde Ajustes y en la sincronización en segundo plano (avisa una vez por versión).
- La descarga se verifica con su huella SHA-256 y después se abre el instalador de Android. La primera vez, Android pide permitir que MiTransporte instale aplicaciones.
- **Obligatoria:** si hay una versión obligatoria posterior a la instalada, la app no deja seguir (ni iniciar sesión) hasta actualizar.
- La app envía su versión en cada petición; el Administrador ve cuántos trabajadores tienen cada versión.
- Todas las versiones se firman con **la misma clave**; si no, Android no instala la actualización encima de la anterior.

## 2.13 Tareas programadas del servidor

Se ejecutan con el *scheduler* de Lumen y un `cron` cada minuto:

| Tarea | Frecuencia | Qué hace |
|---|---|---|
| `trips:auto-complete` | Cada minuto | Marca como realizados los viajes confirmados cuyo regreso ya pasó |
| `chats:purge-trips` | Cada minuto | Borra los mensajes de los viajes cancelados o realizados |
| `chats:purge-expired` | Diaria | Borra las conversaciones caducadas |
| `workers:inactivity` | Diaria | Avisa de la baja por inactividad y la aplica |
| `tokens:purge` | Diaria | Elimina los tokens de renovación caducados o revocados |
| `password-resets:expire` | Cada hora | Cierra las solicitudes de restablecimiento caducadas y borra su teléfono y código |
