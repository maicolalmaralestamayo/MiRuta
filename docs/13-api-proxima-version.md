# 13. API de la próxima versión (servidor Laravel 12)

Referencia para construir la app contra el servidor nuevo (versión **4.1.0**). Implementa lo acordado en `docs/11`
§11.19–§11.60 y resumido en `docs/12`. Lo que no está aquí (pantallas, textos de la interfaz) sigue en esos documentos.

- **Base:** `https://<servidor>/api/v1` (en el hospedaje, `http://<dominio>/miruta/api/v1`).
- **Formato:** JSON:API 1.1, igual que en la versión 3.0: mismos documentos, errores, `include`, paginación y
  filtros. La especificación OpenAPI está en `docs/openapi.yaml` (generada con `tools/openapi/generate.py`).
- **Código:** `api/routes/api.php` (todas las rutas), `api/app/Http/Controllers`, `api/app/Services` (reglas).

## 13.1 Convenciones

### Cabeceras

| Cabecera | Cuándo | Valor |
|---|---|---|
| `Accept` | Siempre | `application/vnd.api+json` (si no se admite: 406) |
| `Content-Type` | Peticiones con cuerpo | `application/vnd.api+json` (si no: 415). Las subidas de archivos usan `multipart/form-data` |
| `Authorization` | Con sesión | `Bearer <accessToken>` |
| `X-App-Version` | **Siempre** (la app) | `versionCode` de Android de la app instalada (entero). Se usa para la actualización obligatoria (§13.3). Se acepta también `X-App-Version-Code` |
| `X-Installation` | Sin sesión («Olvidé algo») | `<id>.<secreto>` que devolvió `POST installations` |
| `X-Maintenance-Key` | Mantenimiento sin sesión | Clave de mantenimiento de `configuracion.php` |

### Documentos

- Un recurso: `{"data": {"type", "id", "attributes", "relationships", "meta", "links"}, "included": [...]}`.
- Los `id` son **cadenas**. Las relaciones a uno van como `{"data": {"type": "...", "id": "..."}}` o `{"data": null}`.
- Crear: `POST` con `{"data": {"type": "...", "attributes": {...}, "relationships": {...}}}` → `201` con `Location`.
- Modificar: `PATCH` solo con lo que cambia; `null` en una relación la quita (cuando se permite).
- Eliminar: `DELETE` → `204` sin cuerpo.
- Fechas y horas: ISO 8601 con zona (`2026-11-09T07:30:00-05:00`); días `AAAA-MM-DD`; horas `HH:MM` (24 h). La zona
  del servidor es `America/Havana` (ajuste `APP_TIMEZONE`).

### Listas

| Parámetro | Ejemplo | Notas |
|---|---|---|
| `page[number]`, `page[size]` | `page[number]=2&page[size]=5` | Por omisión 25; máximo 100. La app pagina de 5 en 5 |
| `sort` | `sort=-createdAt,name` | `-` = descendente. Campos admitidos por recurso |
| `filter[nombre]` | `filter[entity]=3` | Un solo valor por filtro; algunos admiten listas separadas por comas |
| `include` | `include=user,entity` | Relaciones a uno; se pueden encadenar con puntos |

Respuesta de lista: `data`, `links` (`self`, `first`, `prev`, `next`, `last`) y `meta` (`total`, `page`, `size`). Un
parámetro no admitido da `400 BAD_REQUEST` con `source.parameter`.

### Errores

```json
{"errors": [{"status": "422", "code": "VALIDATION_ERROR", "title": "Error de validación",
  "detail": "El campo nombre es obligatorio.", "source": {"pointer": "/data/attributes/name"}, "meta": {}}]}
```

| Estado | Códigos más comunes |
|---|---|
| 400 | `BAD_REQUEST` |
| 401 | `UNAUTHENTICATED`, `TOKEN_INVALID`, `TOKEN_EXPIRED` (renovar), `TOKEN_REVOKED` (sesión cerrada: volver a iniciar sesión), `INVALID_CREDENTIALS`, `INSTALLATION_REQUIRED` |
| 403 | `FORBIDDEN` (sin permiso, con el motivo en `detail`), `PASSWORD_CHANGE_REQUIRED`, `MAINTENANCE_KEY_INVALID`, `INSTALLATION_BLOCKED` |
| 404 | `NOT_FOUND` (también lo que existe pero no puede ver), `ENTITY_NOT_FOUND` |
| 405 / 406 / 415 | `METHOD_NOT_ALLOWED` / `NOT_ACCEPTABLE` / `UNSUPPORTED_MEDIA_TYPE` |
| 409 | `TYPE_MISMATCH`, `ID_MISMATCH`, `DUPLICATE` y los de cada recurso (`NOMENCLATOR_IN_USE`, `TRIP_NOT_EDITABLE`…) |
| 422 | `VALIDATION_ERROR` y los de cada recurso (`PASSWORD_POLICY`, `SETTING_INVALID`, `QR_EXPIRED`…) |
| 426 | `APP_UPDATE_REQUIRED` (actualización obligatoria, §13.3) |
| 429 | `TOO_MANY_REQUESTS` |
| 500 | `SERVER_ERROR` |

## 13.2 Roles y permisos

Tres roles fijos (docs/11 §11.30), con los permisos en el código (`App\Services\Access`). No hay tabla de roles.

| Rol | Cómo se sabe | Puede |
|---|---|---|
| **Administrador** | `users.isAdmin = true` (el primero que se registra) | Todo, en todas las Entidades: Entidades, itinerarios, paradas, personas, roles, solicitudes, viajes, nomencladores, ajustes, versiones, «Olvidé algo», mantenimiento, responder conversaciones |
| **Jefe de itinerario** | `worker-itineraries.isChief = true` en su itinerario (uno solo por persona) | Ve sus Entidades. En **su itinerario**: paradas (crear, editar aunque las usen otros, quitar, ordenar; eliminar solo si no las usa otro itinerario), personas (cambiar parada, sacar, poner en él a personas de su Entidad, activar/desactivar), solicitudes de itinerario, Incluir por QR, planificar y cambiar el estado de los viajes (cancelar solo los que planificó él) |
| **Trabajador** | Pertenece a una Entidad | Consulta sus Entidades (lo activo). Solicita Entidad e itinerario, sale de ellos, se cambia de parada en su itinerario, gestiona sus solicitudes, ausencias, hijos y perfil |

`GET me` devuelve `meta.role` (`administrador`, `jefe` o `trabajador`) y `meta.chiefItineraryId`.

- **Viajes:** cada uno ve los de **todos sus itinerarios** en los que tiene parada (el Jefe, el suyo aunque no tenga
  parada); el Administrador, todos.
- **Lo desactivado** (`active: false`) solo lo ven el Administrador y el Jefe (en su itinerario).
- **Carné** (`identityCard`): la propia persona, el Administrador y el Jefe (miembros y solicitantes de su itinerario).

## 13.3 Actualización obligatoria (docs/11 §11.54)

- Si existe una versión **obligatoria** con `versionCode` mayor que `X-App-Version`, **toda** petición responde
  `426 APP_UPDATE_REQUIRED` y, si traía un token, **se cierra esa sesión en el servidor** (el token deja de valer).
  `errors[0].meta`: `installedVersionCode`, `mandatoryVersionCode`, `latestVersionCode`, `latestVersionName`,
  `latestVersionUrl`.
- También se rechaza **`POST tokens`** (inicio de sesión) y `POST tokens/refresh`.
- **Se permiten:** `GET app-versions/latest`, `DELETE tokens/current`, `DELETE tokens`, `POST installations`,
  `guest/*` («Olvidé algo») y el mantenimiento. Las APK se descargan como archivos (`downloadUrl`), sin pasar por la API.
- Sin la cabecera `X-App-Version` no se comprueba nada.
- La app, al recibir 426: cierra la sesión local, vuelve a la pantalla de inicio de sesión, recuerda la obligación sin
  conexión y desde allí consulta `GET app-versions/latest?filter[currentVersionCode]=N&filter[abis]=arm64-v8a,armeabi-v7a`.

## 13.4 Cuenta y sesión

| Método y ruta | Quién | Qué |
|---|---|---|
| `GET registration-status` | Público | `attributes.adminExists` |
| `GET username-suggestion?firstName=&middleName=&firstSurname=&secondSurname=` | Público | `attributes.username` propuesto |
| `GET password-suggestion` | Público | `attributes.password` propuesta |
| `GET password-policy` | Público | `minLength`, `maxLength`, `requiredClasses`, `historyCount`, `expiryDays`, `usernameMinLength`, `usernameMaxLength` |
| `POST users` | Público | Registro: `firstName`, `middleName?`, `firstSurname`, `secondSurname`, `identityCard` (11 dígitos), `username`, `password`. El primero es Administrador. Con `X-Installation`, la instalación queda ligada. Carné repetido: `409 IDENTITY_CARD_TAKEN` |
| `POST tokens` | Público | `username`, `password`, `deviceName?` → `tokens`: `accessToken`, `refreshToken`, `tokenType`, `expiresIn`, `refreshExpiresIn`; `relationships.user` |
| `POST tokens/refresh` | Público | `refreshToken` → par nuevo (rotación; reutilizar uno ya usado cierra todas las sesiones) |
| `DELETE tokens/current` · `DELETE tokens` | Sesión | Cierra esta sesión · todas |
| `GET me` | Sesión | La persona (`users`) con `meta.role`, `meta.chiefItineraryId` y `meta.memberships` (abajo) |
| `PATCH me` | Sesión | Nombres, `identityCard`, `username`, `password` (con `meta.currentPassword`, salvo si la puso otra persona). Cambiarla cierra las demás sesiones |
| `POST me/photo` (multipart `photo`) · `DELETE me/photo` | Sesión | Foto (jpeg/png, ajuste «Tamaño foto») |
| `POST me/qr-devices` | Sesión | Certifica la clave del teléfono para Mi QR (§13.9) |
| `POST me/applications-seen` | Sesión | Marca vistas sus solicitudes resueltas (al abrir la sección Solicitudes) |

`meta.memberships` (una por Entidad): `workerId`, `active`, `entity {id, abbreviation, name, imageUrl, active,
workerCount}` e `itineraries` (sus itinerarios en esa Entidad, varios): `[{id, isChief, itinerary {id, name, imageUrl,
active, workerCount}, stop {id, landmark, street, imageUrl, latitude, longitude} | null}]` (`id` es el de
`worker-itineraries`). Sirve para Inicio (docs/11 §11.60); `GET users/{id}` devuelve lo mismo para el formulario del
Trabajador.

Recurso **`users`** (persona): `username`*, `firstName`, `middleName`, `firstSurname`, `secondSurname`, `fullName`,
`sex`, `photoUrl`, `isAdmin`, `entities` (abreviaturas; vacía = «Sin Entidad»), `identityCard`/`birthDate` (si puede
verlos), `mustChangePassword`*, `currentPasswordRequired`*, `passwordExpiresAt`*, `appVersionCode`*, `createdAt`*
(*solo ella misma y el Administrador).

Mientras `mustChangePassword` (contraseña caducada o puesta por otro), todo da `403 PASSWORD_CHANGE_REQUIRED` salvo
`GET/PATCH me`, `GET settings` y cerrar la sesión.

## 13.5 Gestión

### Entidades — `entities`

Atributos: `abbreviation` (única, en mayúsculas), `number?` (4 dígitos), `name`, `description?`, `observation?`,
`imageUrl` (solo lectura), `active`. `meta`: `workerCount`, `itineraryCount`, `pendingApplications` (solicitudes de
entrar pendientes).

| Ruta | Quién | Notas |
|---|---|---|
| `GET entities` | Todos (las suyas; Administrador todas) | Filtros `search`, `active`; orden `abbreviation`, `name`, `id`, `createdAt` |
| `GET entities/{id}` | Ídem | |
| `GET entities/lookup?filter[abbreviation]=UMIM` | Sesión o instalación | Comprueba una abreviatura (`entity-lookups`: `abbreviation`, `name`) sin ver la lista |
| `POST`, `PATCH`, `DELETE entities[/{id}]` | Administrador | Eliminar: sus itinerarios se conservan **sin Entidad**; las personas quedan sin esa Entidad (y sin sus itinerarios en ella); se borran sus solicitudes |
| `POST/DELETE entities/{id}/image` | Administrador | Imagen (multipart `image`) |

### Itinerarios — `itineraries`

Atributos: `name` (único en su Entidad), `description?`, `observation?`, `imageUrl`, `active`. Relación `entity`
(**opcional**: un itinerario está como mucho en una Entidad; `null` = «Sin Entidad», docs/11 §11.58). `meta`:
`stopCount`, `workerCount`, `pendingApplications`.

| Ruta | Quién | Notas |
|---|---|---|
| `GET itineraries` | Todos (de sus Entidades) | Filtros `entity` (id o `none` = sin Entidad, solo Administrador), `search`, `active`; `include=entity` |
| `POST`, `PATCH`, `DELETE itineraries[/{id}]` | Administrador | `relationships.entity` (id o `null`). Cambiar de Entidad: sus personas pasan con él a la nueva (entran en ella si no estaban) y sus solicitudes le siguen; sin Entidad: sus personas salen de él y se borran sus solicitudes pendientes. Eliminar: sus personas salen de él (pierden parada y jefatura en él), se eliminan sus viajes y solicitudes; **las paradas se conservan**, aunque queden sin itinerario |
| `PATCH itineraries/{id}/relationships/stops` | Administrador o Jefe | Orden completo (arrastrar): `{"data": [{"type": "stops", "id": "7"}, …]}` de la 1.ª a la última; deben ser todas las paradas (`422 STOP_ORDER_INVALID`) |

### Paradas — `stops` (compartidas entre itinerarios y Entidades)

Atributos: `landmark` (punto de referencia), `street`, `crossStreet1?`, `crossStreet2?`, `latitude`, `longitude`,
`imageUrl`, `active`. `meta.itineraries`: `[{itineraryStopId, itineraryId, name, entityId, entityAbbreviation,
position}]` (vacía = «Sin itinerario»: una parada puede estar en varios itinerarios o en ninguno); `meta.workerCount`
(personas que la tienen en alguno de sus itinerarios).

| Ruta | Quién | Notas |
|---|---|---|
| `GET stops` | Administrador y Jefes: todas (para «Añadir parada existente», con `filter[search]`); trabajador: las de sus Entidades | Filtros `itinerary` (id o `none`), `entity`, `search`, `active`. Con `filter[itinerary]=id` salen en su orden (`sort=position`) |
| `POST stops` | Administrador; Jefe con `relationships.itinerary` = el suyo | Con `relationships.itinerary` se añade al itinerario (al final o en `meta.position`) |
| `PATCH stops/{id}` | Administrador; Jefe si está en su itinerario | Ubicación con «Usar mi ubicación actual» o compartida desde otra app: solo `latitude`/`longitude` |
| `DELETE stops/{id}` | Administrador; Jefe si solo la usa su itinerario (si no, `409 STOP_SHARED`) | Quien la tenía queda sin parada |
| `POST/DELETE stops/{id}/image` | Administrador; Jefe (las de su itinerario) | |

### Paradas de un itinerario — `itinerary-stops`

Atributo `position` (1 = primera). Relaciones `itinerary`, `stop`.

| Ruta | Quién | Notas |
|---|---|---|
| `GET itinerary-stops?filter[itinerary]=` | Todos | |
| `POST itinerary-stops` | Administrador o Jefe del itinerario | «Añadir parada existente» (`position?`; por omisión, al final). Repetida: `409 STOP_ALREADY_IN_ITINERARY` |
| `PATCH itinerary-stops/{id}` | Ídem | Mover a `position` |
| `DELETE itinerary-stops/{id}` | Ídem | «Quitar del itinerario»: la parada se conserva (aunque fuera su último itinerario); quien la tenía en ese itinerario queda sin parada |

### Personas — `users`, `workers` y `worker-itineraries`

`users` es la persona; **`workers`** es la persona en una Entidad; **`worker-itineraries`** es la persona en un
itinerario de una de sus Entidades. Una persona puede estar en **varias Entidades** y, en cada una, en **varios
itinerarios**, cada uno con su **parada** (opcional). Puede estar suelta (sin Entidad o sin itinerario). Es Jefe de un
solo itinerario (docs/11 §11.58).

`workers`: atributos `active`, `createdAt`; relaciones `user`, `entity`; `meta.itineraries` (sus itinerarios en esa
Entidad, como en `meta.memberships`).

`worker-itineraries`: atributo `isChief`, `createdAt`; relaciones `user`, `worker`, `itinerary`, `stop` (opcional);
`meta`: `userName`, `photoUrl`, `active`, `itineraryName`, `entityId`, `entityAbbreviation`, `stopLandmark` (para las
tarjetas sin `include`).

| Ruta | Quién | Notas |
|---|---|---|
| `GET users` | Todos (los de sus Entidades) | Filtros `entity` (id o `none` = «Sin Entidad», solo Administrador), `itinerary` (id o `none` = en ningún itinerario), `stop` (id o `none` = algún itinerario sin parada), `search` (nombre, usuario o carné) |
| `GET users/{id}` | Ídem | Con `meta.memberships` (sus Entidades que ve quien consulta, con itinerarios y paradas): formulario del Trabajador |
| `PATCH users/{id}` · `DELETE users/{id}` | Administrador | Nombres, carné, usuario · eliminar (no al Administrador) |
| `GET workers` | Todos | Filtros `entity`, `itinerary` (id o `none` = sin ningún itinerario en esa Entidad: «Trabajadores sin itinerario»), `stop` (id o `none`), `user`, `search`, `active`, `chief`; `include=user,entity`; orden `name`, `surname`, `id`, `createdAt` |
| `POST workers` | Administrador | Persona existente: `relationships.user` + `entity` («Asociar Entidad», «Adicionar persona»; también él mismo). Persona nueva («Registrar trabajador»): `firstName`, `middleName?`, `firstSurname`, `secondSurname`, `identityCard`, `username?`, `password?` + `entity`; responde `meta.created`, `meta.username`, `meta.password`. La app pide usuario y contraseña (no los propone); si faltan, los genera el servidor. Si el carné ya existe, solo se le añade la Entidad (`meta.created=false`). Con `itinerary` (de esa Entidad) y `stop` se le añade además ese itinerario |
| `PATCH workers/{id}` | Administrador; Jefe (si está en su itinerario) | `active` |
| `DELETE workers/{id}` | Administrador; la propia persona («Salir de la Entidad») | Se borran sus itinerarios allí (con parada y jefatura), sus ausencias allí y sus solicitudes pendientes |
| `GET worker-itineraries` | Todos (los de sus Entidades) | Filtros `user`, `itinerary`, `entity`, `stop` (id o `none` = «Trabajadores sin parada»), `chief`, `search`; `include=user,worker,itinerary,stop` |
| `POST worker-itineraries` | Administrador (a cualquiera; si no estaba en la Entidad del itinerario, entra en ella); Jefe (en su itinerario, a personas de su Entidad) | `relationships.user`, `itinerary`, `stop?`; `isChief?` (Administrador). **Añade** el itinerario a los que ya tiene. Errores: `409 ALREADY_IN_ITINERARY`, `409 ITINERARY_WITHOUT_ENTITY`, `422 STOP_NOT_IN_ITINERARY`. El trabajador lo solicita |
| `PATCH worker-itineraries/{id}` | `relationships.stop` («Cambiar de parada»): Administrador, Jefe del itinerario o la propia persona. `isChief` («Asignar rol» / «Quitar rol de Jefe»): Administrador | Al nombrarlo Jefe deja de serlo de cualquier otro itinerario |
| `DELETE worker-itineraries/{id}` | Administrador, Jefe del itinerario o la propia persona («Salir del itinerario») | Pierde la parada y la jefatura en él; sigue en la Entidad |

### Gestión — `management-summary`

`GET management-summary` (sesión): cantidades de las tarjetas de Gestión (docs/11 §11.59) que ve quien consulta:
`entities`, `itineraries`, `stops`, `workers`, `pendingEntityApplications`, `pendingItineraryApplications` (las que le
toca resolver) y, para el Administrador, `nomenclators {vehicle-types, absence-types, conversation-topics,
denial-reasons, detention-causes}`.

### Solicitudes — `applications`

Atributos: `type` (`entidad` o `itinerario`), `status` (`pendiente`, `aprobada`, `rechazada`), `resolutionNote`,
`resolvedAt`, `seenAt`, `createdAt`. Relaciones: `user`, `entity`, `itinerary`, `stop`, `denialReason`, `resolvedBy`.

| Ruta | Quién | Notas |
|---|---|---|
| `GET applications` | Las suyas; el Jefe además las de su itinerario; el Administrador todas | Filtros `status` (lista: `pendiente,aprobada`), `type`, `entity`, `itinerary`, `mine` (`true`/`false`). «Mostrar/Ocultar aprobadas y rechazadas» = filtro `status` |
| `POST applications` | Cualquiera | `type: entidad` con `relationships.entity` o `attributes.entityAbbreviation`; `type: itinerario` con `relationships.itinerary` y `stop?` (hay que pertenecer a su Entidad). Errores `409`: `ALREADY_MEMBER`, `APPLICATION_PENDING`, `NOT_MEMBER`, `ALREADY_IN_ITINERARY`, `ENTITY_INACTIVE`, `ITINERARY_INACTIVE` |
| `PATCH applications/{id}` | Entidad: Administrador. Itinerario: Administrador o Jefe de ese itinerario | `status: aprobada`, o `status: rechazada` con `relationships.denialReason` (obligatorio, del tipo de la solicitud) y `resolutionNote?` |
| `DELETE applications/{id}` | Quien la hizo | Cancelar (pendiente) o eliminar (resuelta) |

Al aprobar: Entidad → entra en ella; itinerario → se le **añade** ese itinerario (y la parada, si la indicó), sin
quitarle los que tenía. Un itinerario sin Entidad no admite solicitudes (`409 ITINERARY_WITHOUT_ENTITY`).

### Ausencias — `absences`

`startsOn`, `endsOn?` (`null` = indefinida), `indefinite` (solo lectura), `note?`; relaciones `worker` (su pertenencia)
y `absenceType`. Las declara la propia persona (también el Administrador o el Jefe de su itinerario). Mientras dura, no
es pasajero esperado en los viajes de los itinerarios de esa Entidad. Filtros `worker`, `current=true`.

### Hijos — `children`

`firstName`, `middleName?`, `firstSurname`, `secondSurname`, `fullName`, `sex`, `birthDate`, `eligibleUntil`,
`eligible`, `active`, `photoUrl`, `identityCard` (padres y Administrador). `meta.parents` (quién más lo tiene
declarado). `POST children` con el carné: si ya existe se vincula (`meta.alreadyDeclared`); sin derecho a viajar,
`422 CHILD_NOT_ELIGIBLE`. `DELETE` lo desvincula de quien lo pide. Foto: `POST/DELETE children/{id}/photo`.
Filtros `parent`, `active`, `eligible`.

## 13.6 Nomencladores

`vehicle-types`, `absence-types`, `conversation-topics`, `denial-reasons`, `detention-causes`. Atributos comunes:
`name` (único), `description?`, `observation?`, `active`; `meta.usageCount`.

- `vehicle-types`: además `seats`, `standing` y `total` (calculado, solo lectura).
- `denial-reasons`: además `applicationType` (`entidad`, `itinerario` o `null` = las dos). Filtro
  `filter[applicationType]=itinerario` para el diálogo de rechazar.
- Todos los consultan (los desactivados, solo el Administrador); solo el Administrador los cambia.
- **En uso no se elimina:** `409 NOMENCLATOR_IN_USE` con `meta.usageCount`; la app propone desactivarlo
  (`PATCH … {active: false}`).

## 13.7 Viajes — `trips`

Un viaje es de **ida** o de **regreso** de un itinerario, un día, con su hora y su tipo de vehículo. Uno por itinerario,
sentido y día.

Atributos: `direction` (`ida`, `regreso`), `date`, `departureTime` (`HH:MM`), `departsAt`, `status`
(`planificado`, `en_ejecucion`, `terminado`, `cancelado`), `statusChangedAt`, `finishReason` (`manual`, `llegada`,
`espera_cierre`, `duracion_maxima`), `observation?`, `vehicleState` (`detenido`, `en_movimiento`, `null`),
`vehicleStateSince`, `vehicleAtStop`, `nextStopIndex`, `arrivedAt`, `editable`, `updatedAt`. Relaciones `itinerary`,
`vehicleType`, `detentionCause`, `createdBy`. `meta`: `expectedPassengers`, `capacity`, `myState`.

| Ruta | Quién | Notas |
|---|---|---|
| `GET trips` | Ver §13.2 | Secciones: `filter[status]=planificado` / `en_ejecucion` / `terminado` / `cancelado` (lista). Otros: `itinerary`, `direction`, `date`, `from`, `to`; orden `departsAt` |
| `POST trips` | Administrador o Jefe del itinerario | `direction`, `date`, `departureTime`, `observation?`; `itinerary`, `vehicleType`. Ida y regreso del mismo día = dos peticiones. Errores: `409 TRIP_EXISTS`, `ITINERARY_WITHOUT_STOPS`, `ITINERARY_INACTIVE`; `422 TRIP_IN_PAST`, `VEHICLE_TYPE_INVALID` |
| `PATCH trips/{id}` | Ídem | Datos (`date`, `departureTime`, `observation`, `vehicleType`) solo en `planificado` (si no, `409 TRIP_NOT_EDITABLE`). `status` para el cambio a mano. `relationships.detentionCause` (o `null`) con el vehículo detenido |
| `DELETE trips/{id}` | Ídem | No en ejecución (`409 TRIP_RUNNING`) |
| `GET trips/{id}/passengers` | Quien ve el viaje | «Trabajadores»: `trip-workers` con `fullName`, `photoUrl`, `expected`, `state`, `stateAt`, `childrenCount`, `isChief`; relaciones `user`, `stop`; `meta.total` |
| `GET trips/{id}/live` | Quien ve el viaje | Línea del recorrido (§13.8) |
| `POST trips/{id}/reports` | Trabajadores del itinerario | Informe del teléfono (§13.8) |

**Cambios de estado a mano** (Administrador o Jefe del itinerario): `planificado → en_ejecucion`,
`planificado → cancelado` (solo el Administrador o el Jefe que lo planificó), `en_ejecucion → terminado`. Otro:
`409 TRIP_TRANSITION_INVALID`.

**Pasajeros esperados:** los activos del itinerario con parada y sin ausencia ese día. Los niños cuentan como
pasajeros pero no ocupan plaza (`inVehicle.children` aparte).

## 13.8 Tiempo real

Todo lo calcula el **teléfono**; envía al servidor **solo los cambios**, con acuse, y reintenta hasta recibirlo.

### Informe del teléfono: `POST trips/{id}/reports`

```json
{"data": {"type": "trip-reports", "attributes": {
  "workerState": "viajando", "childIds": ["12"], "reportedAt": "2026-11-09T07:02:10-05:00",
  "vehicleState": "en_movimiento", "nextStopIndex": 2, "atStop": false}}}
```

| Atributo | Cuándo | Notas |
|---|---|---|
| `workerState` | Cambia el estado del trabajador | Ver tablas de abajo |
| `stopId` | Con `dejado` | Parada del recorrido donde se bajó (si no es la suya) |
| `childIds` / `childrenCount` | Al subir | Hijos que suben con él (con derecho y activos); o solo cuántos |
| `vehicleState`, `nextStopIndex`, `atStop` | Si es **sensor** (Viajando en la ida, Recogido en el regreso) | Estado del vehículo, posición en el recorrido de la próxima parada (0 = salida) y si está detenido en su radio |
| `reportedAt` | Siempre | Hora del teléfono. Un informe más viejo que el último aplicado se ignora (con acuse) |

Respuesta `200`: la línea del recorrido (`trip-lives`, abajo) con `meta`:
`{"ack": true, "applied": true|false, "reason": null|"INFORME_ANTERIOR"|"ESTADO_FINAL"|"TRANSICION_NO_PERMITIDA"|"VIAJE_CERRADO", "sensor": true|false}`.
Con `ack` la app no reenvía ese cambio. Un estado que no corresponde al sentido: `422 WORKER_STATE_INVALID`.

Cada informe (aunque no traiga cambios) cuenta como «el teléfono envió algo»: un **sensor** deja de contar si no envía
nada en 3 × «Frecuencia cálculo» (30 s). Durante el viaje la app envía cada «Frecuencia cálculo» en esta misma petición.

**Estados del trabajador** (docs/11 §11.43):

| Ida | Significa |
|---|---|
| `de_camino` | De camino a la primera parada |
| `en_parada` | En la primera parada (todos suben ahí) |
| `viajando` | En el vehículo (sensor). Semidefinitivo: solo pasa a `dejado` |
| `dejado` | Se bajó (definitivo) |
| `no_voy` | No va a viajar |

| Regreso | Significa |
|---|---|
| `de_camino` | De camino a su parada |
| `en_parada` | En su parada |
| `recogido` | En el vehículo (sensor, definitivo) |
| `botado` | Estaba en la parada cuando pasó el vehículo y no lo recogió |
| `dormido` | Llegó a la parada después de que pasara el vehículo |
| `no_voy` | No va a viajar |

### Reglas del servidor

- **Mayoría de sensores** (docs/11 §11.43): con `n` sensores activos, un valor se acepta si lo indican al menos
  «Mínimo confirmaciones» (3) cuando `n ≥ 3`, o la mayoría si hay menos; siempre más de la mitad. Se aplica al estado
  del vehículo, a `atStop` y al avance de la próxima parada (la más lejana confirmada; las saltadas quedan pasadas a esa hora).
- **Planificado → En ejecución** (además de a mano): ida, al menos «Mínimo confirmaciones» trabajadores `viajando`;
  regreso, al menos ese número `recogido` en la última parada (si se esperan menos, todos los esperados). Al empezar,
  la parada de salida queda pasada y `nextStopIndex = 1`.
- **En ejecución → Terminado** (además de a mano): ida, el vehículo **pasó la última parada**
  (`nextStopIndex` = número de paradas); regreso, **detenido en el radio de la primera parada** (la última del
  recorrido). `finishReason = llegada`.
- **Revisión periódica** (tarea `viajes:revisar`, cada minuto, §13.13): un `planificado` se **elimina** pasado «Plazo
  eliminación» (5 h) desde su salida; un `en_ejecucion` **termina** pasada «Duración máxima» (5 h) desde que empezó
  o pasada «Espera cierre» (2 h) desde el último `dejado` (ida) o `recogido` (regreso) sin llegar a la parada final.
- **Vehículo detenido** fuera de una parada: sin causa hasta que la indiquen el Administrador o el Jefe
  (`PATCH trips/{id}` con `relationships.detentionCause`); al volver a moverse se borra la causa.

### Línea del recorrido: `GET trips/{id}/live`

```json
{"data": {"type": "trip-lives", "id": "15", "attributes": {
  "direction": "regreso", "status": "en_ejecucion", "departsAt": "…",
  "vehicle": {"state": "detenido", "since": "…", "atStop": true, "nextStopIndex": 1, "nextStopId": "7",
              "longDetention": false, "detentionCause": null},
  "sensors": 3,
  "inVehicle": {"workers": 12, "children": 2, "total": 14, "capacity": 60, "seats": 40},
  "expectedPassengers": 38, "notGoing": 1,
  "stops": [{"index": 0, "stopId": "9", "landmark": "Parqueo del trabajo", "street": "…", "passed": true,
             "passedAt": "…", "expected": 5, "counts": {"botado": 1}, "mine": false}, …],
  "myState": {"state": "en_parada", "stateAt": "…", "stopId": "7", "childrenCount": 0, "sensor": false},
  "serverTime": "…"}}}
```

- `stops` va en el **orden del recorrido** (ida: 1.ª → última; regreso: última → 1.ª).
- `counts`: cantidades por estado en cada parada (la app no muestra los ceros). En la ida, `de_camino` y `en_parada`
  se cuentan en la primera parada («N esperando en [primera parada]»); `dejado`, en la parada donde se bajó. En el
  regreso, `de_camino`, `en_parada`, `botado` y `dormido` en la parada de cada uno.
- Los `viajando` (ida) o `recogido` (regreso) van en `inVehicle`. `sensors` se muestra destacado.

## 13.9 Mi QR e Incluir por QR

- `GET qr-public-key` (público): `publicKey` (SPKI DER base64, ES256/P-256), `clockSkewSeconds` (120),
  `certificateDays` (30), `refreshSeconds` (15).
- `POST me/qr-devices` con `publicKey` (clave del Android Keystore) → `certificate` (30 días), `serverPublicKey`.
- El QR es `MR1.<certificado>.<base64url(payload)>.<base64url(firma)>`, payload `{"u": userId, "t": unix, "n":
  "<16 hex>"}`, firmado con la clave del teléfono; cambia cada 15 s; un solo uso. Igual que en la versión 3.0.
- `POST qr-scans` (Administrador y Jefes) con `qr`, `scannedAt?` → `qr-scans`: `fullName`, `photoUrl`, `sex`,
  `memberships` (dónde está ya: como `meta.memberships` de `GET me`). No gasta el código.
- `POST qr-inclusions` con `qr`, `scannedAt?` y **dónde**: `relationships.entity`, o `itinerary` (con `stop?`), o `stop`
  (con su `itinerary`, bloqueado en la interfaz). Responde `201` (`qr-inclusions`: `fullName`, `previous {inEntity,
  inItinerary, stopId}`; relaciones `worker`, `user`, `entity`, `itinerary`, `stop`). El Jefe solo en su itinerario.
  Incluir **añade** la Entidad o el itinerario a los que ya tiene; si ya estaba en el itinerario, solo le pone la parada.
- **Sin conexión:** la app guarda el QR leído con su `scannedAt` y lo envía al volver la conexión (hasta 7 días). Un
  reintento de la misma inclusión responde `200` con `meta.repeated: true`.
- Errores: `422 QR_INVALID`, `QR_EXPIRED`, `QR_SIGNATURE_INVALID`, `QR_CERTIFICATE_INVALID`, `QR_CERTIFICATE_EXPIRED`,
  `QR_SCAN_TIME_INVALID`, `QR_SCAN_TOO_OLD`, `QR_USER_INACTIVE`; `409 QR_ALREADY_USED`.

## 13.10 Sincronización y notificaciones del teléfono

No hay servicio de envío (sin Firebase): la app consulta **`GET sync?cursor=N`** y muestra como notificaciones locales
lo que llega. Frecuencias (ajustes): «Frecuencia reposo» (sin viajes ese día), «Frecuencia día viaje» (hay un viaje
ese día), «Frecuencia cálculo» (durante el viaje, con `POST trips/{id}/reports`), «Frecuencia chat» (con la
conversación abierta), y el botón Actualizar.

```json
{"data": [{"type": "notifications", "id": "131", "attributes": {"kind": "viaje_creado", "title": "Viaje planificado",
   "body": "viaje de ida de Ruta 1 del lun. 09-11-26 a las 07:30.", "data": {"tripId": "15", "status": "planificado",
   "direction": "ida"}, "createdAt": "…"}}],
 "meta": {"cursor": "131", "more": false, "changed": ["trips"],
   "counters": {"applicationsToResolve": 0, "applicationsResolvedUnseen": 1, "conversationsUnread": 0},
   "latestAppVersion": {"id": "4", "versionCode": 42, "versionName": "4.2.0", "updateAvailable": true, "mandatory": false},
   "nextTrip": {"id": "15", "direction": "ida", "status": "planificado", "departsAt": "…", "today": true},
   "settingsVersion": "…", "serverTime": "…"}}
```

- **La primera vez** (sin `cursor`) no devuelve notificaciones antiguas: solo `meta.cursor`. Después se envía siempre
  el último `meta.cursor`. Sin novedades: `data: []` con el mismo cursor. Con `more: true`, pedir otra vez.
- `changed`: qué recargar (`trips`, `applications`, `conversations`, `access-recoveries`).
- `counters`: número de la pestaña Gestión (por resolver para Administrador y Jefe; resueltas sin ver para el
  trabajador) y conversaciones sin leer.
- `latestAppVersion`: notificación «actualización disponible» (`updateAvailable`) y obligatoria (`mandatory`).
- `nextTrip`: el viaje en ejecución o el próximo planificado (frecuencia de consulta y recordatorio de activar la
  ubicación «Anticipación viaje» antes).
- `settingsVersion`: si cambia, recargar `GET settings`.

| `kind` | Para | Cuándo |
|---|---|---|
| `viaje_creado` | Trabajadores del itinerario | Se planifica un viaje |
| `viaje_modificado` | Ídem | Cambian sus datos mientras está Planificado |
| `viaje_estado` | Ídem | Pasa a En ejecución o se cancela (no la terminación ni la eliminación) |
| `vehiculo_detencion_larga` | Quienes están `en_parada` | Detenido más de «Detención larga» |
| `vehiculo_reanuda` | Ídem | Vuelve a moverse tras una detención larga |
| `vehiculo_en_parada` | Ídem | Llega (detenido) a una parada: «Recogiendo/Dejando en la parada …» |
| `solicitud_recibida` | Administrador; Jefes del itinerario | Nueva solicitud que les toca resolver |
| `solicitud_resuelta` | Quien la hizo | Aprobada o rechazada (con el motivo) |
| `respuesta_desarrollador` | Quien abrió la conversación | Responde el desarrollador |
| `olvide_recibida` | Administrador | Nueva solicitud «Olvidé algo» |

Los estados propios del trabajador, el recordatorio de activar la ubicación y el de quitar el GPS los genera el propio
teléfono.

## 13.11 Conversaciones con el desarrollador

- `GET conversations` (las suyas; el Administrador, todas; `filter[mine]`, `filter[unread]`), `GET conversations/{id}`
  (`include=topic,user`).
- `POST conversations`: `attributes.body` (primer mensaje) y `relationships.topic` (motivo activo).
- `GET conversations/{id}/messages` (`filter[after]=<id>` para los nuevos; los da por leídos) y
  `POST conversations/{id}/messages` con `body`. Mensajes: `body`, `fromDeveloper`, `mine` (burbuja propia a la
  derecha), `createdAt`. Solo texto, hasta «Longitud mensaje». Responde el Administrador.
- Se borran pasada «Conservación conversaciones» desde el último mensaje.

## 13.12 Ajustes de la app — `settings`

Un solo nivel (toda la app). Todos los leen; solo el Administrador los cambia. `id` = clave.

Atributos: `name`, `group`, `groupName`, `type` (`duracion`, `distancia`, `velocidad`, `entero`), `value` (texto con
unidades), `base` (segundos, metros, metros por segundo o entero), `baseUnit`, `defaultValue`, `min`, `max`,
`description`. `GET settings` (filtro `group`) trae `meta.groups` y `meta.version`. `PATCH settings/{clave}` con
`attributes.value` (`null` = valor por omisión). Error: `422 SETTING_INVALID`.

Unidades: tiempos `seg min hor dia sem mes ano` (mes = 30 días, año = 365), combinables y cada una una vez
(`12hor30min`, `1ano6mes`); distancias `m km` (`1km200m`); velocidades distancia/tiempo (`10km/hor`, `200m/min`).

| Clave | Grupo | Nombre | Por omisión |
|---|---|---|---|
| `radio_parada` | Generales | Radio parada | `100m` |
| `anticipacion_viaje` | Generales | Anticipación viaje | `10min` |
| `minimo_confirmaciones` | Generales | Mínimo confirmaciones | `3` |
| `velocidad_humana` | Estado trabajador | Velocidad humana | `10km/hor` |
| `tolerancia_gps` | Estado trabajador | Tolerancia GPS | `20m` |
| `distancia_abandono` | Estado trabajador | Distancia abandono | `1km` |
| `frecuencia_calculo` | Estado trabajador | Frecuencia cálculo | `10seg` |
| `calculos_consecutivos` | Estado trabajador | Cálculos consecutivos | `6` |
| `espera_final` | Estado trabajador | Espera final | `10min` |
| `plazo_eliminacion` | Estado viaje | Plazo eliminación | `5hor` |
| `duracion_maxima` | Estado viaje | Duración máxima | `5hor` |
| `espera_cierre` | Estado viaje | Espera cierre | `2hor` |
| `detencion_larga` | Notificaciones | Detención larga | `5min` |
| `frecuencia_reposo` | Sincronización | Frecuencia reposo | `1hor` |
| `frecuencia_dia_viaje` | Sincronización | Frecuencia día viaje | `15min` |
| `frecuencia_chat` | Sincronización | Frecuencia chat | `5seg` |
| `longitud_contrasena` | Contraseñas | Longitud contraseña | `8` |
| `tipos_caracteres` | Contraseñas | Tipos caracteres | `3` |
| `caducidad_contrasena` | Contraseñas | Caducidad contraseña | `1ano` |
| `historial_contrasenas` | Contraseñas | Historial contraseñas | `5` |
| `validez_acceso` | Acceso | Validez acceso | `30min` |
| `validez_sesion` | Acceso | Validez sesión | `90dia` |
| `reserva_usuario` | Acceso | Reserva usuario | `30dia` |
| `validez_olvide` | Olvidé algo | Validez solicitud | `3dia` |
| `limite_olvide` | Olvidé algo | Solicitudes hora | `3` |
| `conservacion_conversaciones` | Conversaciones | Conservación conversaciones | `1mes` |
| `longitud_mensaje` | Conversaciones | Longitud mensaje | `1000` |
| `tamano_foto` | Archivos | Tamaño foto (KB) | `2048` |
| `tamano_apk` | Archivos | Tamaño APK (MB) | `150` |
| `edad_hijos` | Hijos | Edad hijos | `16` |

Mínimos y máximos: ver `GET settings` o `api/app/Support/SettingCatalog.php`.

## 13.13 Administración del servidor

### Actualizaciones de la app — `app-versions`

- `GET app-versions/latest` (público): última versión; con `filter[currentVersionCode]=N` → `meta.updateAvailable`,
  `meta.mandatory`; con `filter[abis]=arm64-v8a,armeabi-v7a` → `meta.file {abi, downloadUrl, sizeBytes, sha256}`.
- `GET app-versions` (Administrador): `versionName`, `versionCode`, `notes`, `mandatory`, `files[]`, `publishedAt`;
  `meta.installedCount` (cuántos la tienen, por `X-App-Version`).
- `POST app-versions` (Administrador, **multipart**): `apkArm64` (64 bits), `apkArm32` (32 bits) y/o `apkUniversal`,
  `mandatory` (`1`/`0`), `notes?`, `versionName?`/`versionCode?` (se leen del APK). Errores `APK_INVALID`,
  `APK_REQUIRED`, `APK_VERSION_MISMATCH`, `VERSION_CODE_TOO_LOW`.
- `PATCH app-versions/{id}` (`mandatory`, `notes`) y `DELETE app-versions/{id}` (retira y borra los APK).

### «Olvidé algo» — instalaciones y `access-recoveries`

- `POST installations` (público): `deviceModel?`, `androidVersion?`, `appVersionCode?` → `meta.header` para la cabecera
  `X-Installation` (guardarlo; el secreto no se vuelve a mostrar).
- `POST guest/access-recoveries` (con `X-Installation`): `forgotUsername`, `forgotPassword`, `identityCard`, `phone`.
  Como mucho «Solicitudes hora» por hora (`429`). `GET guest/access-recoveries/{id}`: estado (`pending`, `approved`,
  `rejected`, `completed`, `expired`) y, aprobada, solo lo pedido (`username`, `password`), una vez.
- Administrador: `GET access-recoveries` (`filter[status]`), `GET access-recoveries/{id}` (carné, teléfono, `matched`),
  `PATCH access-recoveries/{id}` con `status: approved` (propone contraseña, que se debe cambiar al entrar; cierra sus
  sesiones) o `rejected`. `GET/PATCH installations/{id}` (`blocked`).

### Mantenimiento del servidor (sin SSH ni cron)

Con la sesión del Administrador o con `X-Maintenance-Key`:

- `GET server-status`: versión de la API y de PHP (`phpSupported`: 8.2 o superior), extensiones, límites de PHP, hora,
  base de datos (`connected`, `installed`, `pendingMigrations`), carpetas, tareas (`onRequests`, `lastCheck`, `list`).
- `POST maintenance-runs` con `attributes.command`:

  | Orden | Hace |
  |---|---|
  | `install` | Crea las tablas y los nomencladores de partida (solo si no están: si no, `409 ALREADY_INSTALLED`) |
  | `migrate` | Aplica las migraciones pendientes de una versión nueva |
  | `run-tasks` | Ejecuta las tareas pendientes (`viajes:revisar` cada minuto; `olvide:caducar` y `qr:limpiar` cada hora; `conversaciones:limpiar` y `notificaciones:limpiar` cada día) |
  | `clear-cache` | Limpia la caché |
  | `log` | Últimas líneas del registro de errores |

  Respuesta `maintenance-runs`: `command`, `ok`, `output`, `ranAt`.
- Con `TASKS_ON_REQUESTS=true` (configuración del hospedaje) las tareas se ejecutan solas al terminar las peticiones,
  como mucho una vez por minuto.

## 13.14 Qué cambió respecto a la versión 3.0 (para la app)

- Se quitan: `vehicles`, `roles`, `worker-roles`, `operations`, `trip-legs`, `trip-boardings`, `trip-positions`,
  `trip-completions`, `trip-stop-passes`, `trip-messages`, `notices`, `statistics`, `map`, `setting-definitions`,
  `entity-settings`, `itinerary-settings`, `itinerary-stop-settings`, `me/settings`, `users/{id}/settings`,
  `printed-qr`, `qr-scans` de subida, `offline-scans`, `itinerary-assignments`, `entities/{id}/scan-roster`,
  `guest/conversations`, `me/entities`.
- Nuevos: `sync`, `trips/{id}/live`, `trips/{id}/reports`, `trips/{id}/passengers`, `qr-inclusions`,
  `itineraries/{id}/relationships/stops`, `denial-reasons`, `detention-causes`, `me/applications-seen`,
  `conversations/{id}/messages` (POST).
- `stops` ya no tiene Entidad; `workers` lleva `isChief` y `active`; `applications` usa `type`/`status` en español;
  `trips` es un solo sentido con `vehicleType`; los ajustes son `settings` con texto con unidades.
- Cabecera nueva `X-App-Version` y error `426 APP_UPDATE_REQUIRED`.

## 13.15 Qué cambió en la 4.1.0 (docs/11 §11.56–§11.60)

- `itineraries.entity` es opcional (`filter[entity]=none`); eliminar una Entidad deja sus itinerarios sin Entidad.
- Una persona puede estar en varios itinerarios de cada Entidad: nuevo recurso `worker-itineraries` (parada y
  jefatura por itinerario). `workers` pierde `isChief` y las relaciones `itinerary` y `stop` (lleva `meta.itineraries`);
  `PATCH workers/{id}` solo cambia `active`; ya no hay «Cambiar de Entidad» (se asocia otra Entidad con `POST workers`).
- `meta.memberships` (`GET me`, `GET users/{id}`, `qr-scans`) lleva `itineraries` por Entidad.
- Aprobar una solicitud o incluir por QR **añade** el itinerario en vez de cambiarlo.
- Nuevo `GET management-summary`; `meta.pendingApplications` en Entidades e itinerarios; `meta.workerCount` en paradas.
