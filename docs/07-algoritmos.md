# 7. Algoritmos

Diagramas de flujo de los algoritmos que van más allá de crear, leer, modificar o borrar filas. Están ordenados por área.

**Dónde se ejecuta cada uno:**

| Algoritmo | API | App | Tarea programada |
|---|:-:|:-:|:-:|
| 7.1 Validación del carné | ✔ | ✔ | |
| 7.2 Registro | ✔ | | |
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
| 7.13 Pasajeros esperados y sobresaturación | ✔ | | |
| 7.14 Marcar un viaje como realizado | ✔ | | ✔ |
| 7.15 Sincronización y detección de cambios | | ✔ | |
| 7.16 Programación de avisos de salida y regreso | | ✔ | |
| 7.17 Combinación de sensores | ✔ | | |
| 7.18 Paso por paradas y fin del trayecto | ✔ | | |
| 7.19 Eventos del recorrido: voz y lista de la próxima parada | | ✔ | |
| 7.20 Avisos de paso por paradas | | ✔ | |
| 7.21 Orden de subida | ✔ | | |
| 7.22 Registro de subida | ✔ | | |
| 7.23 Subida automática | ✔ | | |
| 7.24 Parada automática del sensor | | ✔ | |
| 7.25 Línea con hitos proporcional | | ✔ | |
| 7.26 Baja automática por inactividad | | | ✔ |
| 7.27 Borrado de chats | | | ✔ |
| 7.28 Periodo de una estadística | ✔ | ✔ | |

---

## 7.1 Validación del carné y datos derivados

Se usa en el registro y al declarar un hijo. Devuelve si el carné es válido, el sexo y la fecha de nacimiento.

```mermaid
flowchart TD
    A(["Inicio: carné"]) --> B{"¿Tiene exactamente 11 dígitos?"}
    B -->|No| X["Error CARD_NUMBER_INVALID"]
    B -->|Sí| C["AA = dígitos 1-2, MM = 3-4, DD = 5-6, S = dígito 7"]
    C --> D{"¿Valor de S?"}
    D -->|"9"| E1["siglo = 1800"]
    D -->|"0 a 5"| E2["siglo = 1900"]
    D -->|"6 a 8"| E3["siglo = 2000"]
    E1 --> F["año = siglo + AA"]
    E2 --> F
    E3 --> F
    F --> G{"¿AAAA-MM-DD es una fecha válida?"}
    G -->|No| X
    G -->|Sí| H{"¿La fecha es posterior a hoy?"}
    H -->|Sí| X
    H -->|No| I["fecha de nacimiento = AAAA-MM-DD"]
    I --> J{"¿El penúltimo dígito es par?"}
    J -->|Sí| K["sexo = M"]
    J -->|No| L["sexo = F"]
    K --> Z(["Fin: válido, sexo, fecha de nacimiento"])
    L --> Z
    X --> Y(["Fin: inválido"])
```

## 7.2 Registro

```mermaid
flowchart TD
    A(["Inicio: carné, nombre, apellidos, jerarquía, contraseña"]) --> B["Validar carné (7.1)"]
    B --> C{"¿Válido?"}
    C -->|No| X1["422 CARD_NUMBER_INVALID"]
    C -->|Sí| D["huella = HMAC-SHA256(carné, clave del servidor)"]
    D --> E{"¿Existe un trabajador con esa huella, aunque esté inactivo?"}
    E -->|Sí| X2["409 CARD_NUMBER_TAKEN"]
    E -->|No| F{"¿La jerarquía existe y está activa?"}
    F -->|No| X3["422 jerarquía inválida"]
    F -->|Sí| G["Abrir transacción y bloquear la tabla workers para lectura de conteo"]
    G --> H{"¿Hay algún trabajador registrado?"}
    H -->|No| I["is_admin = verdadero"]
    H -->|Sí| J["is_admin = falso"]
    I --> K["Guardar: carné cifrado, huella, sexo, contraseña con bcrypt"]
    J --> K
    K --> L["Confirmar transacción"]
    L --> Z(["Fin: 201 con el trabajador"])
```

El bloqueo garantiza que, si dos personas se registran a la vez en un sistema vacío, solo una sea Administrador.

## 7.3 Inicio de sesión

```mermaid
flowchart TD
    A(["Inicio: carné, contraseña, nombre del dispositivo"]) --> B["huella = HMAC-SHA256(carné)"]
    B --> C{"¿Existe un trabajador activo con esa huella?"}
    C -->|No| D["Verificar la contraseña contra un hash ficticio, para igualar el tiempo de respuesta"]
    D --> X["401 INVALID_CREDENTIALS"]
    C -->|Sí| E{"¿La contraseña coincide con bcrypt?"}
    E -->|No| X
    E -->|Sí| F["Token de acceso: JWT HS256 con sub, iat, exp = ahora + access_token_ttl_minutes, jti"]
    F --> G["Token de renovación: JWT con jti propio y exp = ahora + refresh_token_ttl_days"]
    G --> H["Guardar en refresh_tokens la huella SHA-256 del jti, el dispositivo y la caducidad"]
    H --> Z(["Fin: 201 con los dos tokens"])
```

## 7.4 Renovación de tokens con rotación

Si alguien reutiliza un token de renovación ya usado, es señal de que fue robado: se revocan **todos** los tokens del trabajador.

```mermaid
flowchart TD
    A(["Inicio: token de renovación"]) --> B{"¿Firma válida y no caducado?"}
    B -->|No| X1["401 TOKEN_EXPIRED"]
    B -->|Sí| C["Buscar en refresh_tokens por la huella del jti"]
    C --> D{"¿Existe?"}
    D -->|No| X2["401 TOKEN_REVOKED"]
    D -->|Sí| E{"¿Está revocado?"}
    E -->|Sí| F{"¿Tiene replaced_by_id, es decir, ya se usó?"}
    F -->|Sí| G["Reutilización detectada: revocar todos los tokens del trabajador"]
    G --> X2
    F -->|No| X2
    E -->|No| H{"¿El trabajador está activo?"}
    H -->|No| X2
    H -->|Sí| I["Emitir un nuevo par de tokens (7.3, pasos F a H)"]
    I --> J["Revocar el token usado y apuntar su replaced_by_id al nuevo"]
    J --> Z(["Fin: 201 con los dos tokens nuevos"])
```

## 7.5 Valor efectivo de un ajuste

```mermaid
flowchart TD
    A(["Inicio: clave del ajuste, trabajador"]) --> B["Leer setting_definitions por clave"]
    B --> C{"¿user_overridable y hay fila en user_settings para el trabajador?"}
    C -->|Sí| D["valor = user_settings.value"]
    C -->|No| E{"¿Hay fila en settings?"}
    E -->|Sí| F["valor = settings.value"]
    E -->|No| G["valor = default_value"]
    D --> H{"¿Existe un ajuste mínimo global asociado, p. ej. min_background_poll_minutes?"}
    F --> H
    G --> H
    H -->|Sí| I["valor = máximo entre valor y el mínimo global"]
    H -->|No| J["Convertir según value_type"]
    I --> J
    J --> Z(["Fin: valor"])
```

**Al guardar un ajuste** se valida que el valor sea del tipo correcto, que esté entre `min_value` y `max_value` (o en `setting_options`) y que quien lo cambia esté autorizado según `editable_by`. Si no, `SETTING_OUT_OF_RANGE` o `FORBIDDEN`.

## 7.6 Permiso para resolver una solicitud

```mermaid
flowchart TD
    A(["Inicio: usuario U, solicitud S"]) --> B{"¿S está pendiente?"}
    B -->|No| X1["409 APPLICATION_NOT_PENDING"]
    B -->|Sí| C{"¿U es el solicitante de S?"}
    C -->|Sí| X2["403 SELF_APPROVAL"]
    C -->|No| D{"¿U es Administrador?"}
    D -->|Sí| OK(["Fin: puede resolver"])
    D -->|No| E{"¿Tipo de S?"}
    E -->|transport_chief| X3["403 FORBIDDEN"]
    E -->|"itinerary_chief o driver"| F{"¿U es Jefe de Transporte?"}
    E -->|itinerary_membership| G{"¿U es Jefe de Transporte?"}
    E -->|"rank_change, child_addition, child_removal o absence"| H{"¿U es Jefe de Transporte?"}
    F -->|Sí| OK
    F -->|No| X3
    G -->|Sí| OK
    G -->|No| G2{"¿U es Jefe del itinerario pedido en S?"}
    G2 -->|Sí| OK
    G2 -->|No| X3
    H -->|Sí| OK
    H -->|No| H2{"¿U es Jefe del itinerario actual del solicitante?"}
    H2 -->|Sí| OK
    H2 -->|No| X3
```

La **bandeja de solicitudes** (`filter[toResolve]=true`) aplica este mismo algoritmo como filtro de la consulta.

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
    C -->|rank_change| H["Trabajador: rank_id = el de S"]
    C -->|child_addition| I["El niño queda declarado (se deriva de la solicitud aprobada)"]
    C -->|child_removal| J["Borrado lógico del niño"]
    C -->|absence| K["Sin cambios en tablas: la ausencia aprobada se consulta por fechas"]
    D --> N["Crear notice application_resolved para el solicitante"]
    E5 --> N
    F --> N
    G --> N
    H --> N
    I --> N
    J --> N
    K --> N
    N --> Z(["Fin"])
```

**Al rechazar:** solo se cambia el estado y se avisa al solicitante. **Al cancelar:** solo se cambia el estado. Una solicitud `child_addition` rechazada o cancelada aplica además borrado lógico al niño, para que pueda volver a declararse.

**Al crear una solicitud** se buscan todos los usuarios que podrían resolverla (7.6) y se crea un `notice` `application_received` para cada uno.

## 7.8 Bajas voluntarias

```mermaid
flowchart TD
    A(["Inicio: trabajador T pide una baja de tipo B"]) --> B["Crear solicitud B, ya aprobada, con resolved_by vacío"]
    B --> C{"¿Tipo B?"}
    C -->|itinerary_leave| D["Guardar el itinerario y la parada actuales en itinerary_applications"]
    D --> D2["T: itinerary_id y stop_id = vacíos"]
    D2 --> D3["Avisar a los Jefes de ese itinerario"]
    C -->|itinerary_chief_leave| E["Borrado lógico de itinerary_chiefs de ese itinerario"]
    E --> E2["Avisar a los Jefes de Transporte"]
    C -->|driver_leave| F["Borrado lógico de drivers"]
    F --> F2["Quitar a T como chofer habitual de los vehículos"]
    F2 --> F3["Buscar viajes futuros no cancelados con T de chofer"]
    F3 --> F4["Avisar a los Jefes de Transporte: trip_needs_reassignment por cada viaje"]
    F4 --> F5["Avisar a los Jefes de Transporte: resignation"]
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
    A(["Inicio: carné del niño, fecha D a evaluar"]) --> B["Fecha de nacimiento N a partir del carné (7.1)"]
    B --> C["E = child_max_age (7.5)"]
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
1. Se valida el carné (7.1).
2. Se comprueba el derecho con D = hoy. Si no lo tiene: `CHILD_NOT_ELIGIBLE`.
3. Se busca la huella del carné en `children`:
   - si existe un niño **declarado**: `CHILD_ALREADY_DECLARED`;
   - si existe uno **borrado**: se restaura y se asigna a este trabajador.

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

## 7.13 Pasajeros esperados y sobresaturación

```mermaid
flowchart TD
    A(["Inicio: viaje V"]) --> B["M = trabajadores activos con itinerary_id = V.itinerario"]
    B --> C["Quitar de M a quienes tienen una ausencia aprobada que incluye la fecha de salida de V"]
    C --> D{"¿El chofer de V está en M?"}
    D -->|Sí| E["Quitar al chofer de M"]
    D -->|No| F
    E --> F["esperados = tamaño de M"]
    F --> G["niños esperados = suma de hijos con derecho en la fecha de V (7.9) de cada miembro de M"]
    G --> H["capacidad = asientos + capacidad de pie del vehículo"]
    H --> I{"¿esperados es mayor que capacidad?"}
    I -->|Sí| J["sobresaturado = verdadero"]
    I -->|No| K["sobresaturado = falso"]
    J --> Z(["Fin: esperados, niños esperados, sobresaturado"])
    K --> Z
```

Los niños no cuentan para la capacidad, porque viajan en las piernas.

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

## 7.16 Programación de avisos de salida y regreso (app)

Se ejecuta para cada viaje confirmado, una vez para la salida y otra para el regreso.

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

## 7.18 Paso por paradas y fin del trayecto

Se ejecuta en la API cada vez que cambia la posición combinada de un trayecto activo.

```mermaid
flowchart TD
    A(["Inicio: trayecto T activo, posición combinada p"]) --> B["Paradas del itinerario en orden de T: ascendente en la salida, descendente en el regreso"]
    B --> C["Pendientes = paradas sin trip_stop_passes en T, en ese orden"]
    C --> D["Para cada parada pendiente s, en orden"]
    D --> E{"¿Distancia de p a s es menor o igual que stop_detection_radius_m?"}
    E -->|Sí| F["Crear trip_stop_passes (T, s, ahora)"]
    F --> G{"¿s es la última parada del trayecto?"}
    G -->|Sí| H["T.ended_at = ahora, end_reason = last_stop"]
    H --> Z(["Fin"])
    G -->|No| Z
    E -->|No| I{"¿Quedan pendientes?"}
    I -->|Sí| D
    I -->|No| Z
```

- Se recorren **todas** las pendientes, no solo la siguiente. Así, si el vehículo se salta una parada (por ejemplo, porque nadie sube), se detecta igualmente la siguiente.
- **Finalizar a mano** (`PATCH /trip-legs/{id}` con `endedAt`) pone `end_reason = manual`. Gana lo que ocurra primero.

## 7.19 Eventos del recorrido: voz y lista de la próxima parada (app)

La app compara cada nueva posición combinada con la anterior y genera estos eventos.

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
    I -->|regreso| J["Mostrar quiénes suben en Y, en orden de subida (7.21)"]
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

## 7.21 Orden de subida

```mermaid
flowchart TD
    A(["Inicio: viaje V, parada opcional"]) --> B["Pasajeros = M de 7.13, filtrados por parada si se indicó"]
    B --> C["Para cada pasajero: niños = hijos con derecho en la fecha de V (7.9)"]
    C --> D["Clave de orden de cada pasajero, en este orden de prioridad:"]
    D --> E["1. 0 si niños es mayor que 0, si no 1"]
    E --> F["2. 0 si sexo = F, 1 si sexo = M"]
    F --> G["3. precedence de su jerarquía (1 = la más alta)"]
    G --> H["4. apellidos, alfabético"]
    H --> I["5. nombre, alfabético"]
    I --> J["Ordenar de menor a mayor por la clave"]
    J --> K["boardingOrder = posición en la lista"]
    K --> Z(["Fin: lista ordenada"])
```

El orden alfabético usa la intercalación `utf8mb4_unicode_ci`, que ordena bien las tildes y la ñ.

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

**Token del QR** (`POST /boarding-passes`): un JWT firmado con `sub` (trabajador), `leg` (trayecto) y `exp` = ahora + `boarding_pass_ttl_seconds`. No se guarda en la base de datos y no contiene el carné. La app lo renueva antes de que caduque mientras se muestra el QR.

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
    A(["Inicio: tarea diaria"]) --> B["N = inactivity_days; Av = inactivity_warning_days"]
    B --> C["Para cada trabajador activo W con itinerario I"]
    C --> D["desde = la más reciente entre: su última subida en un viaje realizado de I, y la fecha en que entró en I"]
    D --> E["días contados = días entre desde y hoy en los que I tuvo al menos un viaje realizado y W no tenía ausencia aprobada"]
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

## 7.27 Borrado de chats

```mermaid
flowchart TD
    A(["Inicio"]) --> B{"¿Qué tarea?"}
    B -->|"chats:purge-trips, cada minuto"| C["Viajes en cancelled o completed que aún tienen mensajes"]
    C --> D["Borrar físicamente sus trip_messages"]
    B -->|"chats:purge-expired, diaria"| E["R = conversation_retention_days"]
    E --> F["Conversaciones cuyo último mensaje (o su creación, si no tiene) es de hace más de R días"]
    F --> G["Borrar físicamente sus conversation_messages"]
    G --> H["Borrado lógico de la conversación"]
    D --> Z(["Fin"])
    H --> Z
```

El borrado de `trip_messages` también se hace en el momento del cambio de estado (7.11). La tarea cada minuto es una red de seguridad.

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
