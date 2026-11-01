# 7. Algoritmos

Diagramas de flujo de los algoritmos que van más allá de crear, leer, modificar o borrar filas. Están ordenados por área.

**Dónde se ejecuta cada uno:**

| Algoritmo | API | App | Tarea programada |
|---|:-:|:-:|:-:|
| 7.1 Usuario y contraseña | ✔ | ✔ | |
| 7.2 Registro en dos pasos y activación | ✔ | | |
| 7.3 Inicio de sesión | ✔ | | |
| 7.4 Renovación de tokens con rotación | ✔ | | |
| 7.5 Valor efectivo de un ajuste | ✔ | ✔ | |
| 7.6 Permiso para resolver una solicitud | ✔ | | |
| 7.7 Efectos de aprobar una solicitud | ✔ | | |
| 7.8 Bajas voluntarias | ✔ | | |
| 7.9 Derecho a viajar de un niño | ✔ | ✔ | |
| 7.10 Copia de un viaje a un rango de fechas | ✔ | ✔ | |
| 7.11 Cambio de estado de un viaje | ✔ | | |
| 7.12 Solapamiento de viajes | ✔ | | |
| 7.13 Trabajadores esperados y ocupación | ✔ | ✔ | |
| 7.14 Marcar un viaje como realizado | ✔ | | ✔ |
| 7.15 Sincronización y detección de cambios | | ✔ | |
| 7.16 Programación de avisos de viaje de ida y de regreso | | ✔ | |
| 7.17 Combinación de sensores | ✔ | | |
| 7.18 Paso por paradas, paradas no realizadas y fin del trayecto | ✔ | | |
| 7.19 Eventos del recorrido: voz y lista de la próxima parada | | ✔ | |
| 7.20 Avisos de paso por paradas | | ✔ | |
| 7.21 Lista de pasajeros | ✔ | | |
| 7.22 Registro de subida | ✔ | | |
| 7.23 Subida automática | ✔ | | |
| 7.24 Parada automática del sensor | | ✔ | |
| 7.25 Línea con hitos proporcional | | ✔ | |
| 7.26 Baja automática por inactividad | | | ✔ |
| 7.27 Borrado de chats | | | ✔ |
| 7.28 Periodo de una estadística | ✔ | ✔ | |
| 7.29 Olvidé algo | ✔ | ✔ | ✔ |
| 7.30 Compartimentación por Entidad | ✔ | | |
| 7.31 Viajes atrasados y aviso de comienzo | ✔ | ✔ | ✔ |
| 7.32 Recordar contraseña | | ✔ | |
| 7.33 Desvío del recorrido de referencia | ✔ | | |
| 7.34 Lectura de la versión del APK y comprobación de actualizaciones | ✔ | ✔ | |
| 7.35 Aviso diario de caducidad de la contraseña | | | ✔ |

---

## 7.1 Usuario y contraseña

```mermaid
flowchart TD
    A(["Inicio: usuario U, contraseña P"]) --> B["u = U en minúsculas, sin espacios"]
    B --> C{"¿4 a 20 caracteres de a-z, 0-9, punto y guion bajo; empieza por letra; no termina en signo; sin dos signos seguidos; al menos 3 letras; sin un carácter repetido 4 veces?"}
    C -->|No| X1["422 USERNAME_INVALID"]
    C -->|Sí| D["plano = u sin signos, con los números camuflados convertidos en letras"]
    D --> E{"¿plano contiene una palabra reservada (admin, soporte, miruta, mitransporte…)?"}
    E -->|Sí| X1
    E -->|No| G{"¿Otra cuenta usa u, o la dejó hace menos de username_reuse_block_days días?"}
    G -->|Sí| X2["409 USERNAME_TAKEN"]
    G -->|No| H{"¿P cumple la longitud mínima y los tipos de carácter exigidos, y no es una de las password_history_count anteriores?"}
    H -->|No| X3["422 PASSWORD_POLICY con todos los motivos"]
    H -->|Sí| Z(["Fin: se guarda u y el hash bcrypt de P; la anterior pasa al historial; password_changed_at = ahora"])
```

**Caducidad:** la contraseña caduca a los `password_expiry_days` días de `password_changed_at`. A partir de ahí, y tras recuperar el acceso, la API solo permite el perfil propio (`PASSWORD_CHANGE_REQUIRED`). La tarea `passwords:warn-expiry` avisa cada día durante los últimos `password_expiry_notice_days` días de cada usuario (7.35).

**Desde la versión 2.1** ya no se comprueban palabras no permitidas en el usuario, ni contraseñas comunes, ni que la contraseña contenga el usuario o los nombres. Los mensajes de error tratan de usted.

## 7.2 Registro en dos pasos y activación

```mermaid
flowchart TD
    A(["Inicio: nombres (segundo nombre opcional), usuario, contraseña"]) --> B["Validar usuario y contraseña (7.1)"]
    B --> C["Abrir transacción y bloquear la tabla users para el conteo"]
    C --> D{"¿Hay alguna cuenta?"}
    D -->|No| E["is_admin = verdadero: es el Administrador, sin trabajador"]
    D -->|Sí| F["is_admin = falso"]
    E --> G["Guardar la cuenta"]
    F --> G
    G --> H(["Fin del paso 1: 201 con la cuenta; la app inicia sesión"])
    H --> I{"¿Es el Administrador?"}
    I -->|Sí| Z(["Fin"])
    I -->|No| J(["Paso 2: abreviatura, Pase, sexo, jerarquía"])
    J --> K{"¿Existe una Entidad activa con esa abreviatura (sin distinguir mayúsculas)?"}
    K -->|No| X1["422 ENTITY_NOT_FOUND"]
    K -->|Sí| L{"¿Ya hay un trabajador con ese Pase en la Entidad, aunque esté inactivo?"}
    L -->|Sí| X2["409 PASS_TAKEN"]
    L -->|No| M["Crear el trabajador de la cuenta en esa Entidad"]
    M --> Z
```

**Registro por un superior** (trabajador sin teléfono): se crea la cuenta **sin usuario ni contraseña** y su trabajador, y un **código de activación** (8 caracteres sin los que se confunden, guardado como HMAC) que caduca a los `activation_code_ttl_days` días. Generar otro anula el anterior.

**Activación** ("Me registró un superior"): se busca el trabajador por Entidad y Pase; su cuenta tiene que estar sin activar y su último código, vigente, con menos de 5 intentos fallidos. Si el código no coincide se suma un intento. Si todo es correcto, se validan usuario y contraseña (7.1), se guardan, se marca el código como usado y se devuelven los tokens. Cualquier dato incorrecto responde igual: `422 ACTIVATION_INVALID`.

## 7.3 Inicio de sesión

```mermaid
flowchart TD
    A(["Inicio: usuario, contraseña, nombre del dispositivo"]) --> B["Buscar la cuenta activa por usuario en minúsculas"]
    B --> C{"¿Existe y tiene contraseña?"}
    C -->|No| D["Verificar la contraseña contra un hash ficticio, para igualar el tiempo de respuesta"]
    D --> X["401 INVALID_CREDENTIALS"]
    C -->|Sí| E{"¿La contraseña coincide con bcrypt?"}
    E -->|No| X
    E -->|Sí| F["Token de acceso: JWT HS256 con sub, iat, exp = ahora + access_token_ttl_minutes, jti"]
    F --> G["Token de renovación: JWT con jti propio y exp = ahora + refresh_token_ttl_days"]
    G --> H["Guardar en refresh_tokens la huella SHA-256 del jti, el dispositivo y la caducidad"]
    H --> Z(["Fin: 201 con los dos tokens"])
```

Si la petición trae `X-Installation`, la instalación pasa a ser de esa cuenta, y sus conversaciones sin cuenta, también.

## 7.4 Renovación de tokens con rotación

Si alguien reutiliza un token de renovación ya usado, es señal de que fue robado: se revocan **todos** los tokens de la cuenta.

```mermaid
flowchart TD
    A(["Inicio: token de renovación"]) --> B{"¿Firma válida y no caducado?"}
    B -->|No| X1["401 TOKEN_EXPIRED"]
    B -->|Sí| C["Buscar en refresh_tokens por la huella del jti"]
    C --> D{"¿Existe?"}
    D -->|No| X2["401 TOKEN_REVOKED"]
    D -->|Sí| E{"¿Está revocado?"}
    E -->|Sí| F{"¿Tiene replaced_by_id, es decir, ya se usó?"}
    F -->|Sí| G["Reutilización detectada: revocar todos los tokens de la cuenta"]
    G --> X2
    F -->|No| X2
    E -->|No| H{"¿La cuenta está activa?"}
    H -->|No| X2
    H -->|Sí| I["Emitir un nuevo par de tokens (7.3, pasos F a H)"]
    I --> J["Revocar el token usado y apuntar su replaced_by_id al nuevo"]
    J --> Z(["Fin: 201 con los dos tokens nuevos"])
```

## 7.5 Valor efectivo de un ajuste

```mermaid
flowchart TD
    A(["Inicio: clave del ajuste, cuenta U (opcional), Entidad E (la de U si no se indica)"]) --> B["Leer setting_definitions por clave"]
    B --> C{"¿user_overridable y hay fila en user_settings para U?"}
    C -->|Sí| D["valor = user_settings.value"]
    C -->|No| E{"¿level = entity y hay fila en entity_settings para E?"}
    E -->|Sí| E2["valor = entity_settings.value"]
    E -->|No| F{"¿Hay fila en settings (valor de la app)?"}
    F -->|Sí| F2["valor = settings.value"]
    F -->|No| G["valor = default_value"]
    D --> H{"¿Tiene un ajuste mínimo asociado, p. ej. min_background_poll_minutes?"}
    E2 --> H
    F2 --> H
    G --> H
    H -->|Sí| I["valor = máximo entre valor y el mínimo"]
    H -->|No| H2{"¿Tiene un ajuste máximo asociado, p. ej. remember_password_max_days?"}
    I --> H2
    H2 -->|Sí| I2["valor = mínimo entre valor y el máximo"]
    H2 -->|No| J["Convertir según value_type"]
    I2 --> J
    J --> Z(["Fin: valor"])
```

**Al guardar un ajuste** se valida que el valor sea del tipo correcto y esté entre `min_value` y `max_value` (o en `setting_options`); si tiene ajuste máximo asociado, tampoco puede superar su valor actual. Los valores de la app (`settings`) solo los cambia el Administrador; los de una Entidad (`entity_settings`), su Jefe de Transporte o el Administrador. Si no, `SETTING_OUT_OF_RANGE` o `FORBIDDEN`.

## 7.6 Permiso para resolver o asignar una solicitud

```mermaid
flowchart TD
    A(["Inicio: cuenta U, solicitud S del trabajador W"]) --> B{"¿S está pendiente?"}
    B -->|No| X1["409 APPLICATION_NOT_PENDING"]
    B -->|Sí| C{"¿W es el trabajador de U?"}
    C -->|Sí| X2["403 SELF_APPROVAL"]
    C -->|No| D{"¿U es Administrador?"}
    D -->|Sí| OK(["Fin: puede resolver"])
    D -->|No| D2{"¿W es de la Entidad de U?"}
    D2 -->|No| X3["403 FORBIDDEN"]
    D2 -->|Sí| E{"¿Tipo de S?"}
    E -->|transport_chief| X3
    E -->|"itinerary_chief o driver"| F{"¿U es Jefe de Transporte?"}
    E -->|itinerary_membership| G{"¿U es Jefe del itinerario pedido? (el Jefe de Transporte lo es de todos los de su Entidad)"}
    E -->|"child_addition, child_removal o absence"| H{"¿U es Jefe del itinerario actual de W?"}
    F -->|Sí| OK
    F -->|No| X3
    G -->|Sí| OK
    G -->|No| X3
    H -->|Sí| OK
    H -->|No| X3
```

La **bandeja de solicitudes** (`filter[toResolve]=true`) aplica este mismo algoritmo como filtro de la consulta.

**Asignación directa:** si un superior crea una solicitud para **otro** trabajador (relación `worker`), se crea con `created_by` = el superior, se comprueba este mismo permiso y, si lo tiene, se aprueba al instante (7.7) y se avisa al trabajador con `role_assigned`. Solo se pueden asignar `itinerary_membership`, `itinerary_chief`, `driver` y `transport_chief`.

## 7.7 Efectos de aprobar una solicitud

Todo se hace dentro de una transacción. Si algún paso falla, no se aplica nada.

```mermaid
flowchart TD
    A(["Inicio: solicitud S aprobada por U"]) --> B["S.status = approved, resolved_by = U, resolved_at = ahora"]
    B --> C{"¿Tipo de S?"}
    C -->|itinerary_membership| D["Trabajador: itinerary_id y stop_id = los de S"]
    C -->|itinerary_chief| E["Crear o restaurar itinerary_chiefs (itinerario, trabajador)"]
    E --> E2{"¿El itinerario o la parada de S son distintos de los actuales?"}
    E2 -->|Sí| E3["Trabajador: itinerary_id y stop_id = los de S"]
    E2 -->|No| E4["Sin cambio de itinerario"]
    E3 --> E5["Cancelar sus solicitudes itinerary_membership pendientes"]
    E4 --> E5
    C -->|driver| F["Crear o restaurar drivers (trabajador)"]
    C -->|transport_chief| G["Crear o restaurar transport_chiefs (trabajador)"]
    C -->|child_addition| I["El niño queda declarado (se deriva de la solicitud aprobada)"]
    C -->|child_removal| J["Borrado lógico del niño"]
    C -->|absence| K["Sin cambios en tablas: la ausencia aprobada se consulta por fechas (sin fechas = indefinida, cubre todos los días)"]
    D --> N["Crear notice application_resolved para la cuenta del trabajador (role_assigned si fue una asignación)"]
    E5 --> N
    F --> N
    G --> N
    I --> N
    J --> N
    K --> N
    N --> Z(["Fin"])
```

**Al rechazar:** el motivo (`resolution_note`) es obligatorio; se cambia el estado y se avisa al solicitante con el motivo. **Al cancelar:** solo se cambia el estado. Una solicitud `child_addition` rechazada o cancelada aplica además borrado lógico al niño, para que pueda volver a declararse.

**Al crear una solicitud** se buscan todos los usuarios que podrían resolverla (7.6) y se crea un `notice` `application_received` para cada uno.

**Varios hijos a la vez** (`children[]`): dentro de una transacción se crea una solicitud `child_addition` por hijo; la primera toma su propio id como `group_id` y las demás, el de la primera. Cada hijo se valida (7.9); si uno falla, no se crea ninguna y el error apunta a ese hijo. Se envía un único `application_received` (el de la primera). Después cada solicitud se aprueba o se rechaza por separado.

**Ausencia indefinida:** se crea sin `starts_on` ni `ends_on`. Una vez aprobada, solo el propio trabajador puede ponerle fechas (`PATCH` sin `status`); se guardan sin nueva aprobación. Si la ausencia no es indefinida o no está aprobada: `409 ABSENCE_NOT_INDEFINITE`.

## 7.8 Bajas y retiradas

Las bajas las pide el propio trabajador; las **retiradas** las hace un superior: el Administrador cualquiera; el Jefe de Transporte, en su Entidad, `itinerary_chief_leave`, `driver_leave` e `itinerary_leave`; el Jefe de itinerario, `itinerary_leave` de los de su itinerario. En una retirada, `created_by` y `resolved_by` son el superior y el trabajador recibe `role_removed`.

```mermaid
flowchart TD
    A(["Inicio: baja de tipo B del trabajador T, la pida él o un superior"]) --> B["Crear solicitud B, ya aprobada"]
    B --> C{"¿Tipo B?"}
    C -->|itinerary_leave| D["Guardar el itinerario y la parada actuales en itinerary_applications"]
    D --> D2["T: itinerary_id y stop_id = vacíos"]
    D2 --> D3["Avisar a los Jefes de ese itinerario"]
    C -->|itinerary_chief_leave| E["Borrado lógico de itinerary_chiefs de ese itinerario"]
    E --> E2["Avisar a los Jefes de Transporte de su Entidad"]
    C -->|driver_leave| F["Borrado lógico de drivers"]
    F --> F2["Quitar a T como chofer habitual de los vehículos"]
    F2 --> F3["Buscar viajes futuros no cancelados con T de chofer"]
    F3 --> F4["Avisar a los Jefes de Transporte de su Entidad: trip_needs_reassignment por cada viaje"]
    F4 --> F5["Avisarles también: resignation"]
    C -->|transport_chief_leave| G["Borrado lógico de transport_chiefs"]
    G --> G2["Avisar al Administrador"]
    D3 --> Z(["Fin"])
    E2 --> Z
    F5 --> Z
    G2 --> Z
```

## 7.9 Derecho a viajar de un niño

```mermaid
flowchart TD
    A(["Inicio: fecha de nacimiento N del niño, Entidad de su padre o madre, fecha D a evaluar"]) --> C["E = child_max_age de esa Entidad (7.5)"]
    C --> D["Cumpleaños límite L = N + E años. Si N es 29 de febrero y el año no es bisiesto, L = 28 de febrero"]
    D --> F{"¿L es anterior o igual al 31 de agosto de su año?"}
    F -->|Sí| G["Fecha límite F = 31 de agosto del año de L"]
    F -->|No| H["Fecha límite F = 31 de agosto del año siguiente a L"]
    G --> I{"¿D es anterior o igual a F?"}
    H --> I
    I -->|Sí| J(["Fin: tiene derecho hasta F"])
    I -->|No| K(["Fin: no tiene derecho"])
```

**Ejemplos con E = 16:**
- Nacido el 10/03/2011 → L = 10/03/2027 → F = 31/08/2027.
- Nacido el 15/10/2011 → L = 15/10/2027 → F = 31/08/2028.

**Al declarar un hijo:**
1. La fecha de nacimiento no puede ser futura.
2. Se comprueba el derecho con D = hoy. Si no lo tiene: `CHILD_NOT_ELIGIBLE`.
3. **Posible duplicado:** mientras la solicitud está pendiente, si en la misma Entidad hay otro niño declarado o pendiente con la misma fecha de nacimiento, primer nombre y primer apellido, la solicitud se muestra con `possibleDuplicate = true` a quien la aprueba. No se bloquea.

## 7.10 Copia de un viaje a un rango de fechas

La app genera las operaciones y la API las ejecuta todas o ninguna.

```mermaid
flowchart TD
    A(["Inicio: viaje base (salida S0, regreso R0), desde Fd, hasta Fh, estado E"]) --> B{"¿Fd es anterior o igual a Fh?"}
    B -->|No| X["Error de validación"]
    B -->|Sí| C["duración = R0 - S0"]
    C --> D["d = Fd, operaciones = lista vacía"]
    D --> E{"¿d es posterior a Fh?"}
    E -->|No| F["salida = fecha d + hora de S0"]
    F --> G["regreso = salida + duración"]
    G --> H["Añadir operación add de trips con itinerario, vehículo, chofer, salida, regreso y E"]
    H --> I["d = d + 1 día"]
    I --> E
    E -->|Sí| J["POST /operations con todas las operaciones"]
    J --> K["API: abrir transacción"]
    K --> L["Para cada operación: validar regreso posterior a la salida"]
    L --> M{"¿E = confirmed?"}
    M -->|Sí| N["Comprobar solapamiento (7.12) contra la base de datos y contra las copias anteriores del mismo lote"]
    M -->|No| O["Insertar"]
    N --> P{"¿Hay solapamiento?"}
    P -->|Sí| Q["Anotar el día que choca y seguir comprobando"]
    P -->|No| O
    O --> R{"¿Quedan operaciones?"}
    Q --> R
    R -->|Sí| L
    R -->|No| S{"¿Algún día chocó?"}
    S -->|Sí| T["Deshacer la transacción y devolver 409 TRIP_OVERLAP con la lista de días"]
    S -->|No| U["Confirmar la transacción"]
    U --> Z(["Fin: viajes creados"])
```

La comprobación **dentro del mismo lote** importa cuando la duración supera un día: las copias de días consecutivos podrían solaparse entre sí.

## 7.11 Cambio de estado de un viaje

```mermaid
flowchart TD
    A(["Inicio: viaje V, estado nuevo N"]) --> B{"¿N = cancelled y V está completed?"}
    B -->|Sí| X["409 TRIP_TRANSITION_NOT_ALLOWED"]
    B -->|No| C{"¿N = completed y V está cancelled?"}
    C -->|Sí| X
    C -->|No| D{"¿N = confirmed?"}
    D -->|Sí| E["Comprobar solapamiento (7.12)"]
    E --> F{"¿Hay solapamiento?"}
    F -->|Sí| X2["409 TRIP_OVERLAP con conflictingTripId"]
    F -->|No| G
    D -->|No| G{"¿V estaba completed y N es distinto de completed?"}
    G -->|Sí| H["Borrado lógico de sus trip_completions"]
    G -->|No| I
    H --> I{"¿N = completed y no viene de una marca (7.14)?"}
    I -->|Sí| J["Registrar la marca del usuario (7.14)"]
    I -->|No| K
    J --> K{"¿N es cancelled o completed?"}
    K -->|Sí| L["Borrar físicamente los mensajes del chat del viaje"]
    K -->|No| M
    L --> M["Guardar estado; updated_at = ahora (las apps lo detectan al sincronizar)"]
    M --> Z(["Fin"])
```

## 7.12 Solapamiento de viajes

Dos intervalos `[S1, R1]` y `[S2, R2]` se solapan si **S1 < R2** y **S2 < R1**.

```mermaid
flowchart TD
    A(["Inicio: viaje V con vehículo, chofer, salida S y regreso R"]) --> B["Buscar viajes W con: id distinto de V, estado confirmed y sin borrar"]
    B --> C["Filtrar: W.vehículo = V.vehículo o W.chofer = V.chofer"]
    C --> D["Filtrar: W.salida menor que R y S menor que W.regreso"]
    D --> E{"¿Queda algún W?"}
    E -->|Sí| F(["Fin: solapa con W (se indica si es por vehículo o por chofer)"])
    E -->|No| G(["Fin: no solapa"])
```

Se ejecuta con una sola consulta, apoyada en los índices `(vehicle_id, status, departs_at, returns_at)` y `(driver_id, status, departs_at, returns_at)`.

## 7.13 Trabajadores esperados y ocupación

```mermaid
flowchart TD
    A(["Inicio: viaje V"]) --> B["M = trabajadores activos con itinerary_id = V.itinerario"]
    B --> C["Quitar de M a quienes tienen una ausencia aprobada que incluye la fecha de salida de V"]
    C --> D{"¿El chofer de V está en M?"}
    D -->|Sí| E["Quitar al chofer de M"]
    D -->|No| F
    E --> F["esperados = tamaño de M"]
    F --> G["niños esperados = suma de hijos con derecho en la fecha de V (7.9) de cada miembro de M; no cuentan para la ocupación"]
    G --> H["asientos = asientos del vehículo; capacidad = asientos + capacidad de pie"]
    H --> I{"¿esperados es mayor que capacidad?"}
    I -->|Sí| J["nivel = overloaded (sobresaturado)"]
    I -->|No| K{"¿esperados es mayor que asientos?"}
    K -->|Sí| L["nivel = saturated (saturado: van de pie)"]
    K -->|No| N["nivel = normal"]
    J --> Z(["Fin: esperados, niños esperados, asientos, capacidad, nivel"])
    L --> Z
    N --> Z
```

**Avisos de saturación (app):** al sincronizar, para cada viaje pendiente y futuro del alcance elegido (los suyos, o los que gestiona), si el nivel alcanza el elegido (`overloaded`, o también `saturated`): con "al cambiar", se muestra un aviso cuando el nivel cambia respecto al guardado en el teléfono; con "antes de la salida", se programa uno `saturation_notice_minutes_before` minutos antes. Si deja de cumplirse, el aviso programado se cancela.

## 7.14 Marcar un viaje como realizado

```mermaid
flowchart TD
    A(["Inicio: viaje V, usuario U (o sistema)"]) --> B{"¿V está cancelled?"}
    B -->|Sí| X["409 TRIP_TRANSITION_NOT_ALLOWED"]
    B -->|No| C{"¿Quién marca?"}
    C -->|Sistema| R["rol = system, trabajador vacío"]
    C -->|Usuario| D{"¿U es Administrador?"}
    D -->|Sí| R1["rol = administrator"]
    D -->|No| E{"¿U es Jefe de Transporte?"}
    E -->|Sí| R2["rol = transport_chief"]
    E -->|No| F{"¿U es el chofer de V?"}
    F -->|Sí| R3["rol = driver"]
    F -->|No| G{"¿U es Jefe del itinerario de V?"}
    G -->|Sí| R4["rol = itinerary_chief"]
    G -->|No| X2["403 FORBIDDEN"]
    R --> H
    R1 --> H
    R2 --> H
    R3 --> H
    R4 --> H{"¿Existe una marca de U en V, aunque esté borrada?"}
    H -->|"Sí, activa"| I["No se duplica"]
    H -->|"Sí, borrada"| J["Restaurarla"]
    H -->|No| K["Crear trip_completions"]
    I --> L
    J --> L
    K --> L{"¿V está completed?"}
    L -->|No| M["V.status = completed y aplicar efectos de 7.11"]
    L -->|Sí| Z
    M --> Z(["Fin"])
```

**Tarea `trips:auto-complete`** (cada minuto): busca los viajes `confirmed` con `returns_at + trip_auto_complete_delay_minutes` anterior o igual a ahora, y aplica este algoritmo con quien marca = sistema.

## 7.15 Sincronización y detección de cambios (app)

```mermaid
flowchart TD
    A(["Inicio: sincronización"]) --> B["GET /trips?filter[updatedSince]=última sincronización y filter[itinerary]=el mío"]
    B --> C["Para cada viaje recibido V"]
    C --> D["L = copia local de V"]
    D --> E{"¿Existe L?"}
    E -->|No| F{"¿V está confirmed?"}
    F -->|Sí| G["Programar avisos (7.16)"]
    F -->|No| P
    G --> P
    E -->|Sí| H{"¿Cambió el estado?"}
    H -->|"confirmed a cancelled"| I["Aviso de cancelación y quitar los avisos programados"]
    H -->|"confirmed a unconfirmed"| J["Aviso: pendiente de confirmación, y quitar los avisos programados"]
    H -->|"otro a confirmed"| K["Programar avisos (7.16)"]
    H -->|No| M{"¿V está confirmed?"}
    M -->|Sí| N["cambios = campos distintos entre V y L: chofer, vehículo, salida, regreso, punto de salida, punto de regreso"]
    N --> O{"¿Hay cambios?"}
    O -->|Sí| O2["Aviso de cambio con la lista de cambios y reprogramar (7.16)"]
    O -->|No| P
    M -->|No| P
    I --> P
    J --> P
    K --> P
    O2 --> P["Guardar V como copia local"]
    P --> Q{"¿Quedan viajes?"}
    Q -->|Sí| C
    Q -->|No| R["última sincronización = hora del servidor de la respuesta"]
    R --> Z(["Fin"])
```

Se usa la **hora del servidor** y no la del teléfono, para no perder cambios si el reloj del teléfono está mal.

## 7.16 Programación de avisos de viaje de ida y de regreso (app)

Se ejecuta para cada viaje confirmado, una vez para el viaje de ida y otra para el de regreso.

```mermaid
flowchart TD
    A(["Inicio: viaje V, tipo (salida o regreso)"]) --> B{"¿Tengo una ausencia aprobada en la fecha de V y notify_during_absence es falso?"}
    B -->|Sí| Z0(["Fin: no se programa"])
    B -->|No| C["M = momento del evento: salida o regreso de V"]
    C --> D{"¿Modo del aviso?"}
    D -->|relative| E["T = M - minutos antes"]
    D -->|fixed| F["T = (fecha de M - días antes) a la hora fija"]
    F --> G{"¿T es posterior a M?"}
    G -->|No| H
    G -->|Sí| I{"¿fallback?"}
    I -->|default| J["T = M - 60 minutos"]
    I -->|none| Z0
    E --> H{"¿T ya pasó?"}
    J --> H
    H -->|Sí| Z0
    H -->|No| K["texto = plantilla con las variables sustituidas"]
    K --> L["Programar el aviso local con id = viaje + tipo (sustituye uno anterior con el mismo id)"]
    L --> Z(["Fin"])
```

## 7.17 Combinación de sensores

Se calcula cada vez que llega una posición y cuando alguien consulta la posición actual de un trayecto.

```mermaid
flowchart TD
    A(["Inicio: trayecto T"]) --> B["P = última posición de cada sensor de T, recibida hace menos de sensor_stale_seconds"]
    B --> C{"¿Cuántas hay?"}
    C -->|Ninguna| Z0(["Fin: sin posición, 0 sensores"])
    C -->|Una| D["posición = esa; sensores = 1"]
    C -->|"Dos o más"| E["m = mediana de las latitudes y mediana de las longitudes de P"]
    E --> F["Descartar de P los sensores a más de sensor_outlier_distance_m de m (distancia haversine)"]
    F --> G{"¿Queda alguno?"}
    G -->|No| H["posición = m; sensores = tamaño original de P (no hay grupo claro)"]
    G -->|Sí| I["posición = mediana de los que quedan; sensores = cuántos quedan"]
    D --> Z(["Fin: posición, sensores activos"])
    H --> Z
    I --> Z
```

Se usa la **mediana** y no la media porque un teléfono con mala señal no desplaza el resultado.

## 7.18 Paso por paradas, paradas no realizadas y fin del trayecto

Se ejecuta en la API cada vez que cambia la posición combinada p de un trayecto activo. Antes se calcula la **velocidad** v desde la última posición combinada guardada en el trayecto (`last_latitude`, `last_longitude`, `last_position_at`): distancia haversine / segundos × 3,6. Los umbrales son ajustes de la Entidad: N = `stop_min_dwell_seconds`, V = `stop_pass_speed_kmh`.

```mermaid
flowchart TD
    A(["Inicio: trayecto T activo, posición combinada p, velocidad v"]) --> B["Paradas del itinerario en el orden de T: ascendente en la ida, descendente en el regreso"]
    B --> C{"¿Hay un paso en estado arrived (está en una parada s)?"}
    C -->|No| G
    C -->|Sí| D{"¿p sigue a menos de stop_detection_radius_m de s?"}
    D -->|Sí| E["min_speed_kmh = mínimo entre el guardado y v"]
    E --> G
    D -->|No| F{"¿Estuvo al menos N segundos, o bajó de V km/h, o s es la parada de salida?"}
    F -->|Sí| F1["left_at = ahora; status = stopped"]
    F -->|No| F2["left_at = ahora; status = not_stopped"]
    F2 --> F3["Incidencia not_stopped y aviso trip_incident a los Jefes"]
    F1 --> G
    F3 --> G["Para cada parada s sin paso en T, en orden"]
    G --> H{"¿Distancia de p a s menor o igual que stop_detection_radius_m?"}
    H -->|No| I{"¿Quedan paradas sin paso?"}
    I -->|Sí| G
    I -->|No| Z(["Fin"])
    H -->|Sí| J["Crear trip_stop_passes (T, s, passed_at = ahora, min_speed_kmh = v, status = arrived; stopped si s es la última)"]
    J --> K["Para cada parada anterior a s sin paso, salvo la de salida"]
    K --> L["Crear paso con status = skipped e incidencia skipped, con aviso a los Jefes"]
    L --> M{"¿s es la última parada del trayecto?"}
    M -->|Sí| N["T.ended_at = ahora, end_reason = last_stop"]
    M -->|No| Z
    N --> Z
```

- Se recorren **todas** las paradas sin paso, no solo la siguiente: si el vehículo se salta una parada, se detecta la siguiente y la saltada queda marcada como `skipped`.
- **La parada de salida** no genera incidencias: se da por detenida aunque arranque sin parar, y nunca se marca como saltada. La última se da por detenida al llegar, porque ahí termina el trayecto.
- **Incidencia:** se crea una fila en `trip_leg_incidents` (tipo, parada, coordenadas, `started_at`) y un aviso `trip_incident` (con `payload` `direction`, `type` y `stop`) para los **Jefes del itinerario y los Jefes de Transporte de la Entidad**. A los pasajeros no se les avisa.
- Después se comprueba el desvío (7.33) y se guarda p como última posición del trayecto.
- **Finalizar a mano** (`PATCH /trip-legs/{id}` con `endedAt`) pone `end_reason = manual`. Gana lo que ocurra primero.

## 7.19 Eventos del recorrido: voz y lista de la próxima parada (app)

La app compara cada nueva posición combinada con la anterior y genera estos eventos. En la voz y en la lista, "ida" y "regreso" son el viaje de ida y el viaje de regreso.

```mermaid
flowchart TD
    A(["Inicio: nueva posición combinada"]) --> B{"¿El trayecto acaba de empezar?"}
    B -->|Sí| C["Decir: Comenzando viaje"]
    B -->|No| D{"¿Hay un paso nuevo por la parada Y?"}
    C --> D
    D -->|Sí| E["Decir: Llegando a parada Y"]
    D -->|No| F{"¿Se estaba dentro del radio de la parada X y ahora se está fuera?"}
    E --> F
    F -->|Sí| G["Y = siguiente parada del trayecto"]
    G --> H["Decir: Saliendo de parada X, próxima parada Y"]
    H --> I{"¿Trayecto?"}
    I -->|regreso| J["Mostrar quiénes suben en Y, por parada y alfabéticamente (7.21)"]
    I -->|salida| K["Mostrar quiénes se bajan en Y"]
    F -->|No| L
    J --> L{"¿El trayecto acaba de terminar?"}
    K --> L
    L -->|Sí| M["Decir: Terminando viaje"]
    L -->|No| Z(["Fin"])
    M --> Z
```

**La voz** solo se usa si el usuario es chofer, Jefe de itinerario, Jefe de Transporte o Administrador, y tiene `tts_enabled` activado. **La lista** solo la ven el chofer y los jefes.

## 7.20 Avisos de paso por paradas (app del trabajador)

```mermaid
flowchart TD
    A(["Inicio: paso del vehículo por la parada P en el trayecto T"]) --> B["orden = paradas de T en su sentido"]
    B --> C["iP = posición de P; iM = posición de mi parada"]
    C --> D{"¿stop_notice_scope = none?"}
    D -->|Sí| Z0(["Fin: no avisar"])
    D -->|No| E{"¿iP es menor que iM (la parada es anterior a la mía)?"}
    E -->|Sí| F{"¿scope = all, o scope = previous e iP = iM - 1?"}
    F -->|Sí| G["restantes = iM - iP"]
    F -->|No| Z0
    E -->|No| H{"¿Ya subí y stop_notice_after_boarding es verdadero?"}
    H -->|Sí| G2["restantes = 0"]
    H -->|No| Z0
    G --> I["Aviso con stop_notice_template"]
    G2 --> I
    I --> Z(["Fin"])
```

## 7.21 Lista de pasajeros

No hay orden de subida (docs/08-version-2.md §8.10).

```mermaid
flowchart TD
    A(["Inicio: viaje V, parada opcional"]) --> B["Pasajeros = M de 7.13, filtrados por parada si se indicó"]
    B --> C["Para cada pasajero: niños = hijos con derecho en la fecha de V (7.9)"]
    C --> D["Clave de orden: 1. posición de su parada en el itinerario"]
    D --> E["2. primer apellido, 3. segundo apellido, 4. primer nombre, 5. segundo nombre (alfabético, sin tildes y con la ñ después de la n)"]
    E --> F["Ordenar de menor a mayor por la clave"]
    F --> Z(["Fin: lista con su posición, niños y estado de subida"])
```

## 7.22 Registro de subida

```mermaid
flowchart TD
    A(["Inicio: trayecto T, trabajador W, método, niños n, quien registra U"]) --> B{"¿T está activo?"}
    B -->|No| X1["409: el trayecto no está en curso"]
    B -->|Sí| C{"¿Método?"}
    C -->|self| D{"¿U = W?"}
    D -->|No| X2["403 FORBIDDEN"]
    C -->|manual| E{"¿U es el chofer, un Jefe del itinerario, un Jefe de Transporte o el Administrador?"}
    E -->|No| X2
    C -->|qr| F{"¿U tiene uno de esos roles?"}
    F -->|No| X2
    F -->|Sí| G["Verificar la firma y la caducidad del token del QR"]
    G --> H{"¿Válido y emitido para T?"}
    H -->|No| X3["422 BOARDING_PASS_INVALID"]
    H -->|Sí| I["W = trabajador del token"]
    C -->|automatic| J["Lo genera el servidor (7.23)"]
    D -->|Sí| K
    E -->|Sí| K
    I --> K
    J --> K{"¿W es pasajero esperado del viaje?"}
    K -->|No| X4["422: no es miembro del itinerario"]
    K -->|Sí| L["máximo = hijos con derecho de W en la fecha del viaje (7.9)"]
    L --> M{"¿n es mayor que máximo?"}
    M -->|Sí| X5["422 CHILDREN_COUNT_EXCEEDED"]
    M -->|No| N["Crear trip_boardings (T, W, método, marked_by = U, n, ahora)"]
    N --> Z(["Fin"])
```

**Token del QR** (`POST /boarding-passes`): un JWT firmado con `sub` (trabajador), `leg` (trayecto) y `exp` = ahora + `boarding_pass_ttl_seconds`. No se guarda en la base de datos y no contiene datos personales. La app lo renueva antes de que caduque mientras se muestra el QR.

**Niños de la subida:** si hay varios registros del mismo trabajador en el mismo trayecto, vale `children_count` del más reciente.

## 7.23 Subida automática

Solo funciona si el trabajador comparte su ubicación.

```mermaid
flowchart TD
    A(["Inicio: llega una posición del sensor W en el trayecto T"]) --> B{"¿W ya tiene un registro de subida en T?"}
    B -->|Sí| Z0(["Fin"])
    B -->|No| C["Tomar las últimas auto_boarding_samples posiciones de W y la posición combinada en cada momento"]
    C --> D{"¿Hay suficientes muestras?"}
    D -->|No| Z0
    D -->|Sí| E{"¿Todas están a menos de auto_boarding_distance_m de la posición combinada?"}
    E -->|No| Z0
    E -->|Sí| F{"¿La posición combinada se movió más de auto_boarding_distance_m entre la primera y la última muestra?"}
    F -->|No| Z0
    F -->|Sí| G["Registrar subida automática (7.22) con niños = todos los que tiene con derecho"]
    G --> Z(["Fin"])
```

Exigir que el vehículo **se esté moviendo** evita marcar como subido a quien solo está esperando en la parada junto al vehículo detenido.

## 7.24 Parada automática del sensor (app)

```mermaid
flowchart TD
    A(["Inicio: el teléfono comparte ubicación en el trayecto T"]) --> B{"¿Soy el chofer del viaje?"}
    B -->|Sí| C{"¿Terminó el trayecto?"}
    B -->|No| D{"¿T es de salida y el vehículo ya pasó por mi parada?"}
    D -->|Sí| E["Dejar de compartir: me bajé"]
    D -->|No| C
    C -->|Sí| F["Dejar de compartir y quitar la notificación fija"]
    C -->|No| G["Seguir enviando cada location_interval_seconds"]
    E --> F
    F --> Z(["Fin"])
    G --> Z
```

## 7.25 Línea con hitos proporcional (app)

```mermaid
flowchart TD
    A(["Inicio: itinerario, sentido del trayecto, alto de la línea en pantalla H"]) --> B["Paradas s0, s1, … sn en el orden del trayecto"]
    B --> C["Para cada tramo de si a si+1"]
    C --> D{"¿Hay trayectos realizados de este itinerario en este sentido?"}
    D -->|Sí| E["d_i = media de la distancia recorrida entre si y si+1 en los últimos trayectos"]
    D -->|No| F["d_i = distancia haversine en línea recta entre si y si+1"]
    E --> G{"¿Quedan tramos?"}
    F --> G
    G -->|Sí| C
    G -->|No| H["acumulado_0 = 0; acumulado_i = suma de d hasta i; total = acumulado_n"]
    H --> I["Posición en pantalla de si = acumulado_i / total × H"]
    I --> J["Vehículo: k = última parada pasada; avance = distancia de sk a la posición actual, con máximo d_k"]
    J --> K["Posición en pantalla del vehículo = (acumulado_k + avance) / total × H"]
    K --> Z(["Fin"])
```

## 7.26 Baja automática por inactividad

**Tarea `workers:inactivity`**, una vez al día.

```mermaid
flowchart TD
    A(["Inicio: tarea diaria"]) --> B["Para cada trabajador activo W con itinerario I"]
    B --> C["N = inactivity_days y Av = inactivity_warning_days de la Entidad de W"]
    C --> D["desde = la más reciente entre: su última subida en un viaje realizado de I, el último viaje realizado que condujo, y la fecha en que entró en I"]
    D --> E["días contados = días entre desde y hoy en los que I tuvo al menos un viaje realizado, W no tenía ausencia aprobada y no condujo un viaje realizado"]
    E --> F{"¿días contados es mayor o igual que N?"}
    F -->|Sí| G["Crear solicitud itinerary_removal, ya aprobada, con el itinerario y la parada"]
    G --> H["W: itinerary_id y stop_id = vacíos"]
    H --> I2["notice inactivity_removal para W, y avisar a los Jefes de I"]
    F -->|No| J{"¿días contados = N - Av y no se le avisó ya en este periodo?"}
    J -->|Sí| K["notice inactivity_warning para W"]
    J -->|No| L
    I2 --> L{"¿Quedan trabajadores?"}
    K --> L
    L -->|Sí| C
    L -->|No| Z(["Fin"])
```

**"La fecha en que entró en I"** es la de resolución de la última solicitud aprobada (`itinerary_membership` o `itinerary_chief`) que lo llevó a ese itinerario. Así, un trabajador recién llegado no pierde la plaza por los días anteriores.

## 7.27 Borrado de chats y avisos

```mermaid
flowchart TD
    A(["Inicio"]) --> B{"¿Qué tarea?"}
    B -->|"chats:purge-trips, cada minuto"| C["Viajes en cancelled o completed cuyo regreso fue hace más de trip_chat_retention_days días"]
    C --> D["Borrar físicamente sus trip_messages"]
    B -->|"chats:purge-expired, diaria"| E["R = conversation_retention_days; Rs = guest_conversation_retention_days"]
    E --> F["Conversaciones con cuenta con el último mensaje de hace más de R días, y sin cuenta con el último de hace más de Rs"]
    F --> G["Borrar físicamente sus conversation_messages"]
    G --> H["Borrado lógico de la conversación"]
    H --> I["Borrado lógico de los avisos leídos hace más de read_notice_retention_days días"]
    D --> Z(["Fin"])
    I --> Z
```

Con `trip_chat_retention_days = 0` el borrado de `trip_messages` también se hace en el momento del cambio de estado (7.11); la tarea cada minuto es una red de seguridad. Todas las caducidades son ajustes de la app.

## 7.28 Periodo de una estadística

```mermaid
flowchart TD
    A(["Inicio: filtros de la petición"]) --> B{"¿Cuántos tipos de periodo vienen?"}
    B -->|"Más de uno"| X["400: solo un tipo de periodo"]
    B -->|Ninguno| C["Periodo = últimos 30 días"]
    B -->|Uno| D{"¿Cuál?"}
    D -->|"from y to"| E{"¿from es anterior o igual a to?"}
    E -->|No| X2["400: rango inválido"]
    E -->|Sí| F["Días = de from a to"]
    D -->|dates| G["Días = la lista, sin repetidos y ordenada"]
    D -->|"last = N + unidad"| H{"¿Unidad?"}
    H -->|d| H1["desde = hoy - N días + 1"]
    H -->|w| H2["desde = hoy - N semanas + 1 día"]
    H -->|m| H3["desde = hoy - N meses + 1 día"]
    H -->|y| H4["desde = hoy - N años + 1 día"]
    H1 --> I["Días = de desde a hoy"]
    H2 --> I
    H3 --> I
    H4 --> I
    C --> J
    F --> J
    G --> J
    I --> J["Aplicar las restricciones del rol: itinerarios, choferes o el propio trabajador"]
    J --> Z(["Fin: conjunto de días y filtros efectivos"])
```

## 7.29 Olvidé algo

```mermaid
flowchart TD
    A(["Inicio: instalación I, qué olvidó, abreviatura, Pase, teléfono"]) --> B{"¿I está bloqueada?"}
    B -->|Sí| X1["403 INSTALLATION_BLOCKED"]
    B -->|No| C{"¿I hizo access_recovery_max_per_hour solicitudes en la última hora?"}
    C -->|Sí| X2["429 TOO_MANY_REQUESTS"]
    C -->|No| D["Buscar el trabajador por Entidad y Pase (solo si su cuenta está activada)"]
    D --> E["Cerrar las solicitudes abiertas de I"]
    E --> F["Crear la solicitud pendiente: teléfono cifrado, trabajador encontrado o vacío, caduca en access_recovery_ttl_hours"]
    F --> G["Avisar al Administrador (access_recovery_requested)"]
    G --> Z1(["201: la misma respuesta coincidan o no los datos"])
    Z1 --> H(["El Administrador verifica a la persona por su cuenta"])
    H --> J{"¿Aprueba?"}
    J -->|No| K["rejected; se borra el teléfono"]
    J -->|Sí, y hay trabajador| L["approved"]
    L --> M{"¿Olvidó la contraseña?"}
    M -->|No| N["La instalación lee el usuario y la solicitud termina"]
    M -->|Sí| O["La instalación envía la contraseña nueva (7.1): se guarda, se cierran las demás sesiones, termina y se devuelven los tokens"]
```

La tarea `access-recoveries:expire` cierra cada hora las caducadas y borra su teléfono.

## 7.30 Compartimentación por Entidad

```mermaid
flowchart TD
    A(["Inicio: petición de la cuenta U sobre el recurso R"]) --> B{"¿U es Administrador?"}
    B -->|Sí| OK(["Ve y actúa sobre todas las Entidades; filter[entity] para limitar"])
    B -->|No| C{"¿U tiene trabajador?"}
    C -->|No| X1["403 ENTITY_REQUIRED (salvo perfil, avisos y conversaciones)"]
    C -->|Sí| D["Entidad de R: la de su tabla raíz (trabajador, itinerario, parada o vehículo)"]
    D --> E{"¿Es la Entidad de U?"}
    E -->|No| X2["404, como si no existiera"]
    E -->|Sí| F{"¿Al crear o modificar, lo relacionado es de la misma Entidad?"}
    F -->|No| X3["422 ENTITY_MISMATCH"]
    F -->|Sí| OK2(["Se aplican los permisos del rol"])
```

## 7.31 Viajes atrasados y aviso de comienzo

Servicio `TripTimeliness`. H = hora planificada del tramo (`departs_at` para la ida, `returns_at` para el regreso); tol = `trip_delay_tolerance_minutes` de la Entidad del itinerario.

```mermaid
flowchart TD
    A(["Inicio: viaje V, sentido S, ahora"]) --> B{"¿V está confirmed?"}
    B -->|No| N0(["No atrasado"])
    B -->|Sí| C{"¿Ya hay trip_legs de V en el sentido S (comenzó)?"}
    C -->|Sí| D["atraso = minutos entre H y started_at"]
    D --> E{"¿atraso > tol?"}
    E -->|Sí| F(["Comenzó con atraso: delayMinutes = atraso"])
    E -->|No| G(["Comenzó a tiempo: delayMinutes = NULL"])
    C -->|No| H{"¿ahora > H + tol?"}
    H -->|No| N0
    H -->|Sí| I(["Atrasado: delayed = verdadero, delayMinutes = minutos desde H hasta ahora"])
```

La API lo expone en cada viaje como `outboundDelayed`, `returnDelayed`, `outboundDelayMinutes` y `returnDelayMinutes`; no se guarda.

**Aviso de atraso** (tarea `trips:notify-delays`, cada minuto):

```mermaid
flowchart TD
    A(["Inicio: tarea cada minuto"]) --> B["Viajes confirmed con salida entre hace 2 días y ahora"]
    B --> C["Para cada viaje V y cada sentido S"]
    C --> D{"¿V está atrasado en S?"}
    D -->|No| K
    D -->|Sí| E{"¿Ya hay un notice trip_delayed de V con direction = S?"}
    E -->|Sí| K
    E -->|No| F["Destinatarios: pasajeros esperados, chofer y Jefes del itinerario"]
    F --> G["Quitar a quien tiene trip_delay_notice_enabled desactivado, y a quien tiene ausencia ese día sin notify_during_absence"]
    G --> H["notice trip_delayed con payload direction y scheduledAt"]
    H --> K{"¿Quedan?"}
    K -->|Sí| C
    K -->|No| Z(["Fin"])
```

**Aviso de comienzo:** al iniciar un trayecto (`POST /trip-legs`) se calcula su atraso y se envía `trip_started` (payload `direction` y `delayMinutes`) a los mismos destinatarios, filtrados por `trip_start_notice_enabled`, salvo a quien lo inició. Texto: *"Comenzó el viaje de ida de Ruta Este a tiempo."* o *"… (12 min de atraso)."*

## 7.32 Recordar contraseña (app)

Sustituye al PIN propio de la app. **La contraseña nunca se guarda**: solo la fecha en que se escribió por última vez en el teléfono.

```mermaid
flowchart TD
    A(["Inicio: se abre la app con una sesión guardada"]) --> B{"¿remember_password está activado?"}
    B -->|No| P["Pedir la contraseña (estado locked; la sesión sigue y los avisos llegan)"]
    B -->|Sí| C{"¿Hay fecha de la última vez que se escribió?"}
    C -->|No| D["Guardar ahora como fecha (sesiones de versiones anteriores)"]
    D --> OK(["Entrar sin pedirla"])
    C -->|Sí| E{"¿Pasaron más de remember_password_days días? (como mucho remember_password_max_days, 7.5)"}
    E -->|No| OK
    E -->|Sí| P
    P --> F{"¿La contraseña es correcta (POST /tokens)?"}
    F -->|Sí| G["Guardar ahora como fecha de la última vez"]
    G --> OK
    F -->|No| P
```

Al iniciar sesión también se guarda la fecha; al cerrar sesión se borra. Por defecto: activado, 7 días; el Administrador fija el máximo (30).

## 7.33 Desvío del recorrido de referencia

Se ejecuta en la API tras el paso por paradas (7.18), con cada posición combinada p de un trayecto activo T. La referencia R es el trayecto que el itinerario tiene como `reference_outbound_leg_id` o `reference_return_leg_id`, según el sentido de T.

```mermaid
flowchart TD
    A(["Inicio: trayecto T, posición combinada p"]) --> B{"¿El itinerario tiene recorrido de referencia R en ese sentido y R no es T?"}
    B -->|No| Z(["Fin"])
    B -->|Sí| C["L = posiciones de R en orden, reducidas a unos 1000 puntos (polilínea)"]
    C --> D{"¿L tiene al menos 2 puntos?"}
    D -->|No| Z
    D -->|Sí| E["d = distancia de p a la polilínea L"]
    E --> F{"¿d > route_deviation_m?"}
    F -->|Sí| G{"¿T.deviating?"}
    G -->|Sí| H["Incidencia abierta: distance_m = máximo entre la guardada y d"]
    G -->|No| I["T.deviating = verdadero; incidencia deviation (coordenadas de p, distance_m = d) y aviso trip_incident a los Jefes del itinerario y de Transporte"]
    F -->|No| J{"¿T.deviating?"}
    J -->|Sí| K["T.deviating = falso; ended_at de la incidencia abierta = ahora"]
    J -->|No| Z
    H --> Z
    I --> Z
    K --> Z
```

**Distancia a la polilínea** (`Geo::distanceToPolyline`): se proyectan los puntos en un plano local equirectangular centrado en p (x = Δlongitud · cos(latitud) · R⊕, y = Δlatitud · R⊕), y para cada segmento AB se calcula la distancia de p al punto más cercano del segmento (proyección t = −(A·AB)/|AB|², limitada a [0, 1]). El resultado es la menor de todas. Es suficiente a escala de ciudad.

**Marcar la referencia:** el Jefe del itinerario o un Jefe de Transporte elige un trayecto **terminado** de un viaje de ese itinerario y del mismo sentido; si no lo es, `422 INVALID_REFERENCE_LEG`. Mientras no haya referencia no se vigilan desvíos.

## 7.34 Lectura de la versión del APK y comprobación de actualizaciones

**En la API, al publicar una versión** (`POST /app-versions`), sin extensiones de PHP (`ApkInfo`):

```mermaid
flowchart TD
    A(["Inicio: APK subidos (64 bits, 32 bits, universal), versión escrita a mano (opcional)"]) --> B["Para cada APK"]
    B --> C["Buscar el fin del directorio central del ZIP (firma PK 05 06) y en él la entrada AndroidManifest.xml"]
    C --> D["Extraerla (almacenada o deflate)"]
    D --> E["Leer el XML binario de Android: tabla de cadenas y atributos versionName y versionCode del elemento manifest"]
    E --> F{"¿Se pudo leer?"}
    F -->|No| H
    F -->|Sí| G{"¿Coincide con lo leído de los APK anteriores y con lo escrito a mano?"}
    G -->|No| X1["422 APK_VERSION_MISMATCH"]
    G -->|Sí| H{"¿Quedan APK?"}
    H -->|Sí| B
    H -->|No| I{"¿Hay versión y código?"}
    I -->|No| X2["422 VALIDATION_ERROR: no se pudo leer la versión; escríbala a mano"]
    I -->|Sí| J{"¿versionCode es mayor que el de la última versión?"}
    J -->|No| X3["422 VERSION_CODE_TOO_LOW"]
    J -->|Sí| Z(["Fin: se guarda la versión"])
```

**En la app, comprobación periódica:** la sincronización en segundo plano (`workmanager`) consulta `GET /app-versions/latest` cada `update_check_hours` horas (24 por defecto). Si hay una versión con `versionCode` mayor que la instalada y aún no se avisó de ella, muestra una notificación; al tocarla se abre la pantalla de actualización. Si es obligatoria, al abrir la app no se puede seguir sin instalarla. Además se comprueba al abrir la app y desde Ajustes.

## 7.35 Aviso diario de caducidad de la contraseña

**Tarea `passwords:warn-expiry`**, una vez al día.

```mermaid
flowchart TD
    A(["Inicio: tarea diaria"]) --> B["Para cada cuenta U con password_changed_at"]
    B --> C["caduca = password_changed_at + password_expiry_days; N = password_expiry_notice_days de U (7.5)"]
    C --> D{"¿N > 0 y ahora < caduca ≤ ahora + N días?"}
    D -->|No| K
    D -->|Sí| E{"¿Ya tiene hoy un notice password_expiring?"}
    E -->|Sí| K
    E -->|No| F["Crear notice password_expiring: Su contraseña caduca el sáb. 14/03/26. Cámbiela en Mi perfil."]
    F --> K{"¿Quedan cuentas?"}
    K -->|Sí| B
    K -->|No| Z(["Fin"])
```

Antes era un único aviso a los 15 días (ajuste de la app `password_expiry_warning_days`); ahora es uno por día durante los últimos N días, y N es un ajuste de cada usuario (15 por defecto; 0 = sin avisos).
