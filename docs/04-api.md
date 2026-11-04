# 4. API (versión 3.0)

La especificación completa, para importar en Swagger UI, Swagger Editor, Postman, Insomnia u otra herramienta compatible con OpenAPI, está en **[`openapi.yaml`](openapi.yaml)** (OpenAPI 3.0.3). Se genera con `python3 tools/openapi/generate.py docs/openapi.yaml`: se edita el script, no el YAML.

## 4.1 Generalidades

| Aspecto | Decisión |
|---|---|
| URL base | `/api/v1` |
| Formato | [JSON:API 1.1](https://jsonapi.org/format/) |
| Tipo de contenido | `application/vnd.api+json` en peticiones y respuestas (también en un `POST` sin cuerpo, como anular el QR impreso) |
| Operaciones en lote | Extensión [Atomic Operations](https://jsonapi.org/ext/atomic/) en `POST /operations`, con `Content-Type: application/vnd.api+json; ext="https://jsonapi.org/ext/atomic"` |
| Tipos de recurso | Plural y `kebab-case`: `workers`, `worker-roles`, `trip-legs`… |
| Atributos | `camelCase` (`firstName`, `departsAt`). El modelo los traduce a las columnas `snake_case` |
| Fechas | ISO 8601 con zona horaria (`2026-10-02T17:00:00-04:00`); fechas sin hora como `YYYY-MM-DD` |
| Paginación | `page[number]` y `page[size]` (25 por defecto, 100 como máximo), con `links` y `meta.total` |
| Orden, filtros, inclusión | `sort=campo,-otro`, `filter[campo]=valor`, `include=worker.user` |
| Excepción al formato | La subida de imágenes (foto de la persona y de los hijos; imagen de Entidad, itinerario y parada) y de APK usa `multipart/form-data`. La respuesta sí es JSON:API. `POST /offline-scans` recibe una **lista** en `data` |
| Mensajes | En español, con trato de usted |

## 4.2 Arquitectura del backend (modelo-controlador)

```
app/
  Models/           Modelos Eloquent (User = la persona, Worker = su pertenencia a una Entidad, Trip, …)
  Http/
    Controllers/    Un controlador por recurso: valida, comprueba permisos (App\Services\Permissions) y llama al servicio
    Middleware/     RequireJsonApi, Authenticate (JWT), AuthenticateInstallation, AuthenticateMaintenance
  JsonApi/          Documentos (data, included, links, meta), parámetros page/sort/filter/include, errores
  Serializers/      Capa de "vista": convierte modelos en recursos JSON:API
  Services/         Permissions (roles y ámbitos), Memberships, Roles, Applications, Accounts, Children,
                    Trips, Tracking, Boardings (subida), QrCodes y QrScans (QR), Statistics, Settings…
  Support/          Operations (catálogo fijo de operaciones), IdentityCard (carné), Username, Jwt, Geo,
                    NoticeText, ApkInfo, SpanishDate
  Console/Commands/ Tareas programadas (ver 02-procesos.md §2.13)
config/             mitransporte.php (versión 3.0.0), jsonapi.php (modelo → serializador)
database/           migrations/ (instalación limpia) seeders/
```

- **JWT** (HS256): token de acceso (`sub` = id de la persona, `exp`, `jti`, `sid`) y de renovación con rotación (se guarda su huella SHA-256 en `refresh_tokens`).
- **QR:** ECDSA P-256 con OpenSSL (ver [07-algoritmos.md §7.36](07-algoritmos.md#736-código-qr-de-la-persona)).
- **HTTPS recomendado.**

## 4.3 Permisos: roles configurables

- Cada persona tiene, **en cada Entidad a la que pertenece**, unos roles (`worker-roles`). Cada rol es un conjunto de **operaciones** del catálogo fijo (`GET /operations`), cada una con un **ámbito**: `own` (lo suyo), `itinerary` (el itinerario del rol si es por itinerario —Jefe de itinerario— o, si no, el itinerario del que es miembro), `entity` (la Entidad donde tiene el rol) o `all`.
- El **Administrador** (`users.isAdmin`) tiene todas las operaciones con `all`. Se muestra como rol virtual `id: "admin"` en `GET /roles`.
- `GET /me` devuelve `meta.permissions: [{operation, scope, entityId, itineraryId}]`: la app muestra solo lo permitido.
- Lo **propio** (perfil, hijos, ausencias, solicitudes, ajustes, QR) lo puede siempre cada persona.
- Sin permiso: `403 FORBIDDEN`. Lo que no puede ver: `404 NOT_FOUND`.
- Roles de partida (editables) y su reparto: [11-acuerdos-registro-qr.md §11.15](11-acuerdos-registro-qr.md).

## 4.4 Rutas

### Públicas y sin cuenta

| Método | Ruta | Descripción |
|---|---|---|
| `POST` | `/users` | Registrarse: nombres, apellidos, `identityCard`, `username`, `password`. Sin Entidad. El primero es el Administrador. `409 IDENTITY_CARD_TAKEN` |
| `GET` | `/registration-status` | `{adminExists}` |
| `GET` | `/username-suggestion?firstName=&middleName=&firstSurname=&secondSurname=` | Usuario propuesto |
| `GET` | `/password-suggestion` | Contraseña propuesta |
| `GET` | `/password-policy` | Requisitos (usuario de 2 a 50 caracteres) |
| `POST` | `/tokens`, `/tokens/refresh` | Iniciar sesión (si `hasPhone` era falso, pasa a verdadero y el QR impreso se anula) y renovar |
| `GET` | `/qr-public-key` | Clave pública del servidor para los QR |
| `POST` | `/installations` | Registrar la instalación (cabecera `X-Installation`) |
| `POST`, `GET` | `/guest/access-recoveries`, `/guest/access-recoveries/{id}` | «Olvidé algo»: carné + teléfono; al aprobarse, devuelve solo lo pedido (usuario y/o contraseña propuesta) una vez |
| `GET`, `POST` | `/guest/conversations`, `/guest/conversations/{id}/messages` | Hablar con el desarrollador sin cuenta |
| `GET` | `/entities/lookup?abbreviation=` | Con sesión o instalación |
| `GET` | `/app-versions/latest` | Última versión |

### Persona propia

| Método | Ruta | Descripción |
|---|---|---|
| `GET`, `PATCH` | `/me` | Su persona, con `meta.permissions` y `meta.memberships` (Entidades con itinerario, parada y roles) |
| `POST`, `DELETE` | `/me/photo` | Foto (multipart `photo`) |
| `POST` | `/me/entities` | Unirse a una Entidad sin solicitud (**solo el Administrador**) |
| `DELETE` | `/me/entities/{entityId}` | Darse de baja de una Entidad |
| `GET`, `PATCH`, `DELETE` | `/me/settings[/{key}]` | Sus ajustes |
| `POST` | `/me/qr-devices` | Certificado de la clave de su teléfono (QR dinámico) |
| `DELETE` | `/tokens/current`, `/tokens` | Cerrar sesión aquí o en todos los dispositivos |

### Recursos

| Recurso | Rutas | Permisos y notas |
|---|---|---|
| `users` | `GET`, `GET /{id}`, `PATCH /{id}` | Lista: la propia y las de su ámbito de `workers.view`. `PATCH active` = eliminar o reactivar la cuenta (`workers.delete`; `409 LAST_ADMIN`). `identityCard` y `birthDate` solo para ella misma, el Administrador y `workers.view_identity_card` |
| `users/{userId}/settings` | `GET`, `PATCH /{key}`, `DELETE /{key}` | Ajustes de un trabajador: `settings.worker` sobre alguna de sus pertenencias |
| `workers` | CRUD | Pertenencia persona–Entidad. `POST`: registro por el Administrador (`workers.register`; con `hasPhone`; devuelve `meta.username` y `meta.password` si creó la cuenta) o añadir a una persona ya registrada (`entities.assign_members`). `PATCH`: `active` (`workers.deactivate`), itinerario + parada (`members.assign`), nombres/carné/`hasPhone` (`workers.edit`). `DELETE`: baja de la Entidad |
| `workers/{id}/itinerary` | `DELETE` | Baja del itinerario (la propia persona o `members.assign`) |
| `workers/{id}/printed-qr` | `GET`, `POST /revoke` | QR impreso (`workers.printed_qr`). Ver §4.5 |
| `entities` | CRUD + `POST/DELETE /{id}/image` | `entities.view` / `entities.manage` |
| `roles` | CRUD | Ver: cualquiera; detalles: `roles.view`; gestionar: `roles.manage` (`isDefault`: `roles.set_default`) |
| `operations` | `GET` | Catálogo fijo (`roles.view`) |
| `worker-roles` | `GET`, `POST`, `DELETE` | Asignar o quitar: `roles.assign` y tener allí un rol aprobador de ese rol. Darse de baja: la propia persona |
| `applications` | `GET`, `POST`, `GET /{id}`, `PATCH /{id}` | `entity_membership`, `itinerary_membership`, `role`. Aprueban `entities.approve_membership`, `members.approve` o los roles aprobadores con `roles.approve`. Rechazar exige `resolutionNote` |
| `absences` | CRUD | Sin aprobación. La propia persona; de otros, `absences.view` / `absences.manage` |
| `children` | CRUD + `POST/DELETE /{id}/photo` | Por carné; si ya existe se vincula (`meta.alreadyDeclared`). Derecho: hasta el 31/08 siguiente al cumpleaños en que alcanza `child_max_age` |
| `vehicle-types`, `absence-types`, `conversation-topics` | CRUD | `nomenclators.manage`, `absence_types.manage`. Los motivos van dirigidos a un rol (`recipient: role`, relación `role`) o al desarrollador |
| `itineraries`, `stops`, `itinerary-stops` | CRUD + imagen | `itineraries.manage`, `stops.manage`, `itineraries.order_stops`, `itineraries.reference_route` |
| `vehicles` | CRUD | `vehicles.view`, `vehicles.manage`, `vehicles.assign_driver`. `driver` es una pertenencia (`workers`) con `tracking.drive` |
| `trips` | CRUD | `trips.view` (own = su itinerario), `trips.plan`, `trips.edit`, `trips.confirm_cancel`, `trips.complete`, `trips.delete`. `meta.expectedPassengers`: **solo trabajadores** (ningún niño) |
| `trips/{id}/passengers` | `GET` | Esperados por parada y alfabéticamente, con su subida (`boardedChildIds`); al final, quienes subieron sin ser esperados (`expected: false`, `outsider`) |
| `trip-completions` | `GET`, `POST` | Chofer del viaje o `trips.complete` |
| `trip-legs` | `GET`, `POST`, `PATCH` | Iniciar/finalizar: chofer del viaje, `tracking.drive` o `trips.complete` |
| `trip-positions`, `trip-stop-passes` | `GET`, `POST` / `GET` | Sensores: chofer del viaje y miembros del itinerario |
| `trip-boardings` | CRUD | Ver §4.6 |
| `qr-scans` | `POST` | Comprobar un QR (no lo gasta). Ver §4.5 |
| `itinerary-assignments` | `POST` | Alta directa en un itinerario con el QR (`members.assign_by_qr`) |
| `offline-scans` | `POST` | Sincronizar lo escaneado sin conexión (lista) |
| `entities/{id}/scan-roster` | `GET` | Lista para escanear sin conexión |
| `trip-messages` | `GET /trips/{id}/messages`, `POST`, `DELETE /{id}` | Chat del viaje. Borrar: el propio, o de otros con `chat.delete_messages` |
| `conversations`, `conversation-messages` | `GET`, `POST`, `PATCH /conversations/{id}`, `DELETE /conversation-messages/{id}` | Dirigidas a un rol: las ven quienes lo tienen con `chat.role_conversations`. Borrar mensajes de otros: `chat.delete_messages` |
| `notices` | `GET`, `PATCH` | Tipos nuevos: `entity_added`, `entity_removed`, `itinerary_assigned`, `itinerary_removed` |
| `setting-definitions`, `settings`, `entity-settings`, `itinerary-settings`, `itinerary-stop-settings` | | `settings.app`, `settings.entity`, `settings.itinerary`. Gana el más concreto: persona → parada del itinerario → itinerario → Entidad → app |
| `statistics` | `GET /statistics/{name}` | Ver §4.7 |
| `access-recoveries`, `installations` | | `access_recoveries.manage` |
| `app-versions` | | `app_versions.manage` |
| `server-status`, `maintenance-runs` | | `maintenance.run` o clave de mantenimiento |
| **Lote** | `POST /operations` | Viajes por rango, confirmar en masa, posiciones acumuladas |

**Eliminado en 3.0:** `/ranks`, `/activations`, `/me/worker`, `/drivers`, `/transport-chiefs`, `/itinerary-chiefs`, `/workers/{id}/activation-codes`, `/guest/access-recoveries/{id}/password`, `/boarding-passes` (el QR por trayecto lo sustituye el QR único de la persona), el atributo de entrada `childrenCount` de las subidas (ahora `childIds`) y el ajuste `boarding_pass_ttl_seconds`.

## 4.5 QR de la persona

El formato exacto, los bytes que se firman y la verificación sin conexión están en [07-algoritmos.md §7.36](07-algoritmos.md#736-código-qr-de-la-persona). Resumen:

| Paso | Ruta | Detalle |
|---|---|---|
| Clave del servidor | `GET /qr-public-key` | `{publicKey}`: ECDSA P-256, SPKI DER en base64. La app la guarda |
| Certificado del teléfono | `POST /me/qr-devices` `{publicKey}` | `{certificate, expiresAt}` (30 días). Si la persona no tenía teléfono, su impreso se anula |
| QR dinámico | (en el teléfono) | `MR1.<certificado>.<payload>.<firma>`, se renueva cada 15 s |
| QR impreso | `GET /workers/{id}/printed-qr` | `MRP1.<json>.<firma>` + nombres, apellidos y sexo. Solo sin teléfono (`409 PRINTED_QR_NOT_AVAILABLE`) |
| Anular el impreso | `POST /workers/{id}/printed-qr/revoke` | Sube la versión y devuelve el nuevo |
| Comprobar | `POST /qr-scans` `{qr, purpose, scannedAt?}` + `tripLeg?` | Tarjeta de la persona, sus pertenencias, `outsider`, `canAllowOutsider`, `alreadyBoarded`, `warning` e hijos con derecho. **No gasta el código** |
| Subir | `POST /trip-boardings` `{method: qr, qr, childIds, allowOutsider?, scannedAt?}` | Gasta el código (un solo uso) |
| Alta en un itinerario | `POST /itinerary-assignments` `{qr, scannedAt?}` + `itinerary`, `stop` | Gasta el código. La persona debe pertenecer a la Entidad (`422 NOT_A_MEMBER`); cambia su itinerario y parada; no pierde jefaturas |
| Sin conexión | `GET /entities/{id}/scan-roster` | Trabajadores (`userId`, nombre, foto, itinerario, parada, `printedQrVersion`) e hijos con derecho (`childId`, nombre, `parentUserIds`) |
| Sincronizar | `POST /offline-scans` (lista) | Cada escaneo con su `scannedAt`; respuesta por elemento: `accepted`, `repeated`, `discarded`, `rejected` |

Errores del QR (`422`): `QR_INVALID`, `QR_SIGNATURE_INVALID`, `QR_CERTIFICATE_INVALID` (no lo firmó el servidor o es de otra persona), `QR_CERTIFICATE_EXPIRED`, `QR_EXPIRED` (más de ±120 s entre la hora del QR y la del escaneo), `QR_REVOKED` (impreso anulado), `QR_USER_INACTIVE`, `QR_SCAN_TIME_INVALID` (hora del escaneo en el futuro), `QR_SCAN_TOO_OLD` (más de 7 días); `409 QR_ALREADY_USED` (código dinámico ya gastado).

### Subida con QR: ejemplo

```http
POST /api/v1/qr-scans
{ "data": { "type": "qr-scans",
    "attributes": { "qr": "MR1.eyJ1Ijo…", "purpose": "boarding" },
    "relationships": { "tripLeg": { "data": { "type": "trip-legs", "id": "81" } } } } }

→ 200 { "data": { "type": "qr-scans", "attributes": { "kind": "dynamic", "userId": "12", "fullName": "Maicol Almarales Tamayo",
        "outsider": "itinerary", "canAllowOutsider": true, "alreadyBoarded": false,
        "warning": "Esta persona no pertenece al itinerario de este viaje.",
        "children": [ { "id": "4", "fullName": "Ana Almarales", "alreadyBoarded": false } ] } } }

POST /api/v1/trip-boardings
{ "data": { "type": "trip-boardings",
    "attributes": { "method": "qr", "qr": "MR1.eyJ1Ijo…", "childIds": ["4"], "allowOutsider": true },
    "relationships": { "tripLeg": { "data": { "type": "trip-legs", "id": "81" } } } } }

→ 201 { "data": { "type": "trip-boardings", "attributes": { "method": "qr", "qrKind": "dynamic",
        "childIds": ["4"], "childrenCount": 1, "outsider": "itinerary" } } }
```

### Sincronización: ejemplo

```http
POST /api/v1/offline-scans
{ "data": [
  { "type": "offline-scans", "lid": "b-17", "attributes": { "purpose": "boarding", "qr": "MR1.…",
      "scannedAt": "2026-11-03T17:10:04-05:00", "childIds": [] },
    "relationships": { "tripLeg": { "data": { "type": "trip-legs", "id": "81" } } } },
  { "type": "offline-scans", "lid": "a-3", "attributes": { "purpose": "itinerary_assignment", "qr": "MRP1.…",
      "scannedAt": "2026-11-03T17:12:00-05:00" },
    "relationships": { "itinerary": { "data": { "type": "itineraries", "id": "3" } }, "stop": { "data": { "type": "stops", "id": "17" } } } } ] }

→ 200 { "data": [
  { "type": "offline-scans", "id": "b-17", "attributes": { "status": "accepted", "code": null, "detail": null },
    "relationships": { "tripBoarding": { "data": { "type": "trip-boardings", "id": "501" } } } },
  { "type": "offline-scans", "id": "a-3", "attributes": { "status": "rejected", "code": "QR_REVOKED", "detail": "Este QR impreso fue anulado…" } } ],
  "meta": { "accepted": 1, "total": 2 } }
```

## 4.6 Subida (`trip-boardings`)

- **Una sola subida por persona y trayecto.** Un segundo escaneo (`qr` o `manual`) de quien ya subió: `409 ALREADY_BOARDED` (con QR impreso, el detalle avisa de que puede ser una copia). Una subida automática o «Ya subí» previa se convierte en escaneada.
- `method`: `self` («Ya subí», solo miembros del itinerario), `qr`, `manual` (`relationships.worker`) o `automatic` (la genera el servidor, sin hijos).
- **Hijos:** `childIds` = hijos activos con derecho de esa persona (`422 CHILD_NOT_ELIGIBLE`). Cada niño cuenta **una vez por trayecto** (`409 CHILD_ALREADY_BOARDED`, aunque lo tengan declarado los dos padres).
- **De fuera:** si la persona no es del itinerario (`outsider: itinerary`) o de la Entidad del viaje (`outsider: entity`), quien escanea necesita `tracking.allow_outsiders` (`403 OUTSIDER_NOT_ALLOWED`) y confirmarlo con `allowOutsider: true` (si no, `409 OUTSIDER_CONFIRMATION_REQUIRED` con `meta.outsider`). Cuenta como pasajero. Sin ninguna Entidad: `422 NOT_A_WORKER`.
- **Corrección** (`tracking.fix_passengers`): `PATCH /trip-boardings/{id}` con `childIds` (mientras el trayecto está en curso, también quien escanea y la propia persona), `DELETE /trip-boardings/{id}` y registrar subidas con el trayecto ya terminado.
- **Sin conexión:** `scannedAt` = hora local del escaneo. Se acepta si cae dentro del trayecto (±2 min) aunque ya haya terminado. Reintento con el mismo código: `200` con `meta.repeated`.

## 4.7 Estadísticas

`GET /statistics/{name}` devuelve un recurso `statistics` con `attributes.columns` y `attributes.rows`.

**Periodo** (uno de los tres): `filter[from]` + `filter[to]`, `filter[dates]` o `filter[last]=7d` (`d`, `w`, `m`, `y`). Por defecto, los últimos 30 días.

**Otros filtros:** `filter[entity]`, `filter[itinerary]`, `filter[vehicle]`, `filter[driver]`, `filter[stop]`, `filter[worker]`, `filter[trip]`, `filter[level]`, `filter[by]`.

**Quién:** `statistics.view` en su ámbito (itinerario, Entidad o todas). Sin él, quien conduce ve las de sus viajes y cualquiera las suyas (`worker-trips`, `live-trip`).

| `name` | Contenido |
|---|---|
| `trips-by-status`, `punctuality`, `duration`, `trips-by-driver`, `trips-by-vehicle` | Viajes |
| `overloaded-trips`, `occupancy` | Ocupación (solo trabajadores) |
| `attendance` | Subidos frente a esperados, por itinerario y parada |
| `children-transported` | **Niños que viajan realmente** (los marcados al subir; cada uno una vez por viaje): `children`, `distinctChildren` y `eligibleChildren` (hijos con derecho declarados por los miembros del itinerario) |
| `outsider-travellers` | **Nueva.** Trabajadores que viajan fuera de su itinerario o de su Entidad: trabajador, su Entidad, su itinerario, itinerario en que viajó, tipo, viajes, subidas y niños |
| `workers-distribution` | Trabajadores por `itinerary`, `stop` o `sex` (ya no hay jerarquía) |
| `worker-trips`, `applications-summary`, `stop-activity`, `stop-pass-times`, `distance`, `live-trip`, `trip-incidents` | Como en 2.x |

## 4.8 Errores

Siempre con el formato `errors[]` de JSON:API: `status`, `code`, `title`, `detail`, `source.pointer` o `source.parameter` y, a veces, `meta`.

| `code` | HTTP | Cuándo |
|---|---|---|
| `BAD_REQUEST`, `OPERATION_NOT_SUPPORTED` | 400 | Documento o parámetro mal formado; operación atómica no admitida |
| `UNAUTHENTICATED`, `INVALID_CREDENTIALS`, `INSTALLATION_REQUIRED`, `TOKEN_INVALID`, `TOKEN_EXPIRED`, `TOKEN_REVOKED` | 401 | Autenticación |
| `FORBIDDEN` | 403 | Sin la operación en ese ámbito |
| `PASSWORD_CHANGE_REQUIRED` | 403 | Contraseña puesta por otro o caducada |
| `SELF_APPROVAL`, `ROLE_NOT_EDITABLE`, `INSTALLATION_BLOCKED`, `MAINTENANCE_KEY_INVALID` | 403 | |
| `OUTSIDER_NOT_ALLOWED` | 403 | Dejar subir a alguien de fuera sin `tracking.allow_outsiders` |
| `NOT_FOUND`, `ENTITY_NOT_FOUND` | 404 | No existe o no puede verlo |
| `METHOD_NOT_ALLOWED`, `NOT_ACCEPTABLE`, `UNSUPPORTED_MEDIA_TYPE` | 405, 406, 415 | |
| `TYPE_MISMATCH`, `ID_MISMATCH`, `DUPLICATE` | 409 | |
| `IDENTITY_CARD_TAKEN` | 409 | Carné ya registrado (texto de docs/11 §11.5) |
| `USERNAME_TAKEN`, `ACCOUNT_INACTIVE`, `LAST_ADMIN` | 409 | |
| `ALREADY_MEMBER`, `NOT_A_MEMBER`, `NO_ITINERARY`, `ALREADY_HAS_ROLE`, `ROLE_IN_USE`, `APPLICATION_ALREADY_PENDING`, `APPLICATION_NOT_PENDING` | 409 | Pertenencias, roles y solicitudes |
| `CHILD_ALREADY_DECLARED` | 409 | Ya lo tiene declarado |
| `RECOVERY_NOT_PENDING`, `RECOVERY_NOT_MATCHED`, `CONVERSATION_CLOSED`, `CHAT_NOT_AVAILABLE` | 409 | |
| `STOP_ALREADY_IN_ITINERARY`, `STOP_HAS_MEMBERS`, `STOP_IN_USE`, `ITINERARY_HAS_MEMBERS`, `ITINERARY_HAS_ROLES` | 409 | |
| `TRIP_OVERLAP`, `TRIP_TRANSITION_NOT_ALLOWED`, `TRIP_NOT_CONFIRMED`, `TRIP_STARTED`, `LEG_ALREADY_STARTED`, `LEG_NOT_ACTIVE` | 409 | Viajes y recorrido |
| `ALREADY_BOARDED` | 409 | Ya subió en este trayecto (con QR impreso: posible copia) |
| `CHILD_ALREADY_BOARDED` | 409 | El niño ya subió en este trayecto con otra persona |
| `OUTSIDER_CONFIRMATION_REQUIRED` | 409 | Es de otro itinerario o Entidad: falta `allowOutsider` (`meta.outsider`) |
| `QR_ALREADY_USED` | 409 | Código dinámico ya gastado |
| `PRINTED_QR_NOT_AVAILABLE` | 409 | La persona usa la app en su teléfono |
| `ALREADY_INSTALLED` | 409 | Mantenimiento |
| `VALIDATION_ERROR` | 422 | Campo no válido (`source.pointer`) |
| `IDENTITY_CARD_INVALID`, `USERNAME_INVALID`, `PASSWORD_POLICY`, `CURRENT_PASSWORD_INVALID` | 422 | Cuenta |
| `ENTITY_MISMATCH`, `ENTITY_REQUIRED`, `STOP_NOT_IN_ITINERARY`, `ROLE_NOT_REQUESTABLE`, `OPERATION_UNKNOWN`, `SCOPE_NOT_ALLOWED` | 422 | |
| `CHILD_NOT_ELIGIBLE` | 422 | Sin derecho a viajar (al añadir) o no es hijo con derecho de quien sube |
| `TRIP_DATES_INVALID`, `INVALID_REFERENCE_LEG`, `NOT_A_DRIVER`, `NOT_A_PASSENGER`, `NOT_A_SENSOR`, `NOT_A_WORKER` | 422 | Viajes y recorrido |
| `QR_INVALID`, `QR_SIGNATURE_INVALID`, `QR_CERTIFICATE_INVALID`, `QR_CERTIFICATE_EXPIRED`, `QR_EXPIRED`, `QR_REVOKED`, `QR_USER_INACTIVE`, `QR_SCAN_TIME_INVALID`, `QR_SCAN_TOO_OLD`, `QR_DEVICE_KEY_INVALID` | 422 | QR (§4.5) |
| `SETTING_OUT_OF_RANGE`, `APK_INVALID`, `APK_REQUIRED`, `APK_VERSION_MISMATCH`, `VERSION_CODE_TOO_LOW` | 422 | |
| `TOO_MANY_REQUESTS` | 429 | Demasiadas solicitudes o mensajes sin cuenta |
| `SERVER_ERROR` | 500 | Error interno |
