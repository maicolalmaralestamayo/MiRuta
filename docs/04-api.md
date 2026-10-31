# 4. API

La especificación completa, para importar en Swagger UI, Swagger Editor, Postman, Insomnia u otra herramienta compatible con OpenAPI, está en **[`openapi.yaml`](openapi.yaml)** (OpenAPI 3.0.3).

## 4.1 Generalidades

| Aspecto | Decisión |
|---|---|
| URL base | `/api/v1` |
| Formato | [JSON:API 1.1](https://jsonapi.org/format/) |
| Tipo de contenido | `application/vnd.api+json` en peticiones y respuestas |
| Operaciones en lote | Extensión [Atomic Operations](https://jsonapi.org/ext/atomic/) en `POST /operations`, con `Content-Type: application/vnd.api+json; ext="https://jsonapi.org/ext/atomic"` |
| Tipos de recurso | Plural y `kebab-case`: `workers`, `itinerary-stops`, `trip-legs`… |
| Atributos | `camelCase` (`firstName`, `departsAt`). El modelo los traduce a las columnas `snake_case` |
| Fechas | ISO 8601 con zona horaria (`2026-10-02T17:00:00-04:00`); fechas sin hora como `YYYY-MM-DD` |
| Paginación | `page[number]` y `page[size]` (25 por defecto, 100 como máximo), con `links.first`, `prev`, `next` y `last`, y `meta.total` |
| Orden | `sort=campo,-otroCampo` |
| Filtros | `filter[campo]=valor` |
| Relaciones incluidas | `include=vehicle,driver.worker` |
| Excepción al formato | La subida de imágenes (foto de perfil e iconos de jerarquía) usa `multipart/form-data`, porque JSON:API no está pensado para archivos. La respuesta sí es JSON:API |

## 4.2 Arquitectura del backend (modelo-controlador)

```
app/
  Models/           Modelos Eloquent (Worker, Trip, …): datos, relaciones, reglas propias de cada entidad
  Http/
    Controllers/    Un controlador por recurso: valida, comprueba permisos y llama al modelo o al servicio
    Middleware/     RequireJsonApi (Content-Type y Accept), JwtAuthenticate (sprint 2)
  JsonApi/          Documentos (data, included, links, meta), parámetros page/sort/filter/include, errores
  Serializers/      Capa de "vista": convierte modelos en recursos JSON:API
  Policies/         Permisos por recurso y rol (el Administrador siempre tiene permiso)
  Services/         Lógica que abarca varios modelos: registro, aprobación de solicitudes, solapamiento,
                    combinación de sensores, ocupación, estadísticas
  Support/          Reglas comunes (Username, Tenancy para la compartimentación por Entidad, contraseñas comunes, JWT)
  Rules/            Reglas de validación propias
  Console/Commands/ Tareas programadas (ver 02-procesos.md §2.13)
config/             mitransporte.php, jsonapi.php (modelo → serializador)
database/
  migrations/  seeds/  factories/
```
- **Librerías previstas** (compatibles con Lumen 7 y PHP 7.2.5):
  - `firebase/php-jwt` para firmar y verificar JWT;
  - serialización JSON:API propia y ligera.
- **JWT:** se firma con HS256. Claims del token de acceso:
  - `iss`, `aud`;
  - `sub` (id de la cuenta, `users`);
  - `iat` y `exp` (30 min);
  - `jti`.

  El token de renovación lleva su propio `jti`. Se guarda solo su huella SHA-256 en `refresh_tokens`, y caduca a los 90 días.
- **HTTPS obligatorio.**

## 4.3 Autenticación, cuentas y acceso sin cuenta

| Método | Ruta | Descripción | Acceso |
|---|---|---|---|
| `POST` | `/users` | Crear la cuenta (paso 1 del registro). La primera es la del Administrador | Público |
| `POST` | `/tokens` | Inicio de sesión con usuario y contraseña | Público |
| `POST` | `/tokens/refresh` | Renovación con rotación | Con token de renovación |
| `DELETE` | `/tokens/current` | Cerrar sesión en este dispositivo | Autenticado |
| `DELETE` | `/tokens` | Cerrar sesión en todos los dispositivos | Autenticado |
| `GET` | `/password-policy` | Requisitos de la contraseña y del usuario | Público |
| `POST` | `/me/worker` | Unirse a la Entidad (paso 2 del registro): abreviatura, Pase, sexo y jerarquía | Autenticado |
| `POST` | `/activations` | "Ya me registró un superior": Entidad, Pase, código, usuario y contraseña; devuelve los tokens | Público |
| `POST` | `/installations` | Registrar la instalación de la app; devuelve el valor de la cabecera `X-Installation` | Público |
| `GET` | `/entities/lookup?abbreviation=` | Buscar una Entidad por su abreviatura exacta (abreviatura y nombre) | Con sesión o instalación |
| `POST`, `GET` | `/guest/access-recoveries`, `/guest/access-recoveries/{id}` | "No puedo entrar": pedir ayuda y consultar el estado (con el usuario, si se aprobó) | Instalación |
| `POST` | `/guest/access-recoveries/{id}/password` | Contraseña nueva tras la aprobación; devuelve los tokens | Instalación |
| `GET`, `PATCH` | `/access-recoveries`, `/access-recoveries/{id}` | Ver las solicitudes y aprobarlas o rechazarlas | Administrador |
| `GET`, `POST` | `/guest/conversations`, `/guest/conversations/{id}/messages` | Hablar con el desarrollador sin cuenta | Instalación |
| `GET`, `PATCH` | `/installations/{id}` | Ver una instalación y bloquearla o desbloquearla | Administrador |

- **Con sesión:** `Authorization: Bearer <token de acceso>`.
- **Sin cuenta:** `X-Installation: <id>.<secreto>`. Una instalación bloqueada solo puede leer.
- **Compartimentación:** cada usuario ve y actúa solo sobre su Entidad; lo de otra responde `404`, como si no existiera. El Administrador ve todo; en las listas puede filtrar con `filter[entity]` y, al crear itinerarios, paradas, vehículos o trabajadores, indica la relación `entity`.
- **Hasta unirse a una Entidad** (salvo el Administrador), solo se permiten el perfil, los avisos y las conversaciones: el resto responde `403 ENTITY_REQUIRED`.
- **Contraseña caducada o acceso recuperado:** solo se permiten el perfil propio y cerrar la sesión (`403 PASSWORD_CHANGE_REQUIRED`).

## 4.4 Recursos

| Recurso | Rutas | Notas |
|---|---|---|
| **Cuenta propia** | `GET/PATCH /me`, `POST/DELETE /me/photo`, `GET/PATCH/DELETE /me/settings/{id}` | `GET /me` devuelve un recurso `users`; con `include=worker,worker.entity,worker.rank` trae su trabajador. `PATCH /me` cambia usuario, nombres, contraseña y jerarquía (relación `rank`) |
| `users` | `GET`, `GET /{id}`, `PATCH /{id}` | Solo el Administrador: cuentas (también las que no se unieron a una Entidad); activar y desactivar |
| `entities` | CRUD | Solo el Administrador. Los demás ven la suya |
| `workers` | `GET`, `GET /{id}`, `POST`, `PATCH /{id}`, `POST /{id}/activation-codes` | `POST`: un superior registra a un trabajador sin teléfono (devuelve `meta.activationCode`). `PATCH`: activar o desactivar (Administrador). `meta`: `childrenCount`, `roles` |
| `ranks` | CRUD + `POST /ranks/{id}/icon` | Comunes. Gestión: Administrador. `sortOrder` = orden de presentación |
| `vehicle-types`, `absence-types`, `conversation-topics`, `forbidden-words` | CRUD | Comunes. Gestión: Administrador |
| `itineraries` | CRUD | De una Entidad. `meta`: `departurePoint`, `returnPoint`, `memberCount` |
| `stops` | CRUD | De una Entidad |
| `itinerary-stops` | CRUD | `position` dentro del itinerario. La parada tiene que ser de la misma Entidad |
| `itinerary-chiefs`, `drivers`, `transport-chiefs` | `GET`, `DELETE` | `DELETE` lo hace el propio trabajador (baja) o un superior (retirada) |
| `vehicles` | CRUD | De una Entidad. `meta`: `totalCapacity` |
| `trips` | CRUD | `filter[updatedSince]` para sincronizar. `meta`: `expectedPassengers`, `expectedChildren`, `seats`, `totalCapacity`, `occupancyLevel` (`normal`, `saturated`, `overloaded`), `saturated`, `overloaded`, `departurePoint`, `returnPoint`, `needsReassignment` |
| `trip-completions` | `GET`, `POST` | Marcar como realizado |
| `trip-legs` | `GET`, `POST` (iniciar), `PATCH` (finalizar) | `meta`: `currentPosition`, `activeSensors` |
| `trip-positions` | `GET`, `POST` | Para enviar posiciones acumuladas sin conexión, usar `/operations` |
| `trip-stop-passes` | `GET` | Los genera el servidor |
| `trip-boardings` | `GET`, `POST` | `method`: `automatic`, `self`, `qr` o `manual` |
| `boarding-passes` | `POST` | Devuelve el token temporal para el QR |
| `trip-passengers` | `GET /trips/{id}/passengers` | Pasajeros por parada (en el orden del itinerario) y alfabéticamente, con su estado de subida |
| `trip-messages` | `GET`, `POST` | Chat del viaje |
| `children` | `GET`, `GET /{id}` | Se crean y se quitan mediante solicitudes. `birthDate` y `meta.eligibleUntil` solo para el padre o la madre, sus jefes y el Administrador |
| `applications` | `GET`, `POST`, `GET /{id}`, `PATCH /{id}` | `PATCH` con `status`: `approved`, `rejected` o `cancelled`. Con la relación `worker` de otro trabajador, un superior **asigna** (queda aprobada) o **retira** (tipos `*_leave`) |
| `conversations`, `conversation-messages` | `GET`, `POST`, `PATCH /conversations/{id}` (cerrar o reabrir) | Las abiertas sin cuenta aparecen con `guest = true` |
| `notices` | `GET`, `PATCH` (marcar como leído) | — |
| `setting-definitions`, `settings` | `GET`, `PATCH /settings/{id}` | `level`: `app` (solo el Administrador) o `entity`. `settings` son los valores de la app |
| `entity-settings` | `GET`, `PATCH /{id}`, `DELETE /{id}` | Valores de nivel Entidad: los cambia su Jefe de Transporte (el Administrador con `filter[entity]`) |
| `statistics` | `GET /statistics/{name}` | Ver 4.6 |
| `app-versions` | `GET /app-versions/latest` (público), `GET`, `POST` (multipart), `DELETE /{id}` | Un APK por tipo de procesador (`apkArm64`, `apkArm32`, `apkUniversal`). `latest` con `filter[abis]` indica en `meta.file` el APK del teléfono. La app envía su versión en la cabecera `X-App-Version-Code` |
| **Lote** | `POST /operations` | Atomic Operations: crear viajes por rango, confirmar o desconfirmar en masa, enviar posiciones acumuladas |

### Solicitudes: ejemplo

```http
POST /api/v1/applications
Content-Type: application/vnd.api+json

{
  "data": {
    "type": "applications",
    "attributes": { "type": "itinerary_membership" },
    "relationships": {
      "itinerary": { "data": { "type": "itineraries", "id": "3" } },
      "stop":      { "data": { "type": "stops", "id": "17" } }
    }
  }
}
```

Los datos propios de cada tipo de solicitud (ver [03-datos.md §3.5](03-datos.md#35-valores-de-los-campos-enum)) se envían como atributos o relaciones del mismo recurso `applications`. La API los guarda en la tabla de subtipo que corresponda.

### Viajes por rango: ejemplo

```http
POST /api/v1/operations
Content-Type: application/vnd.api+json; ext="https://jsonapi.org/ext/atomic"

{
  "atomic:operations": [
    { "op": "add", "data": { "type": "trips", "attributes": {
        "departsAt": "2026-10-02T17:00:00-04:00", "returnsAt": "2026-10-03T06:30:00-04:00", "status": "confirmed" },
        "relationships": { "itinerary": {"data": {"type": "itineraries", "id": "3"}},
                           "vehicle":   {"data": {"type": "vehicles", "id": "5"}},
                           "driver":    {"data": {"type": "drivers", "id": "2"}} } } },
    { "op": "add", "data": { "type": "trips", "attributes": {
        "departsAt": "2026-10-03T17:00:00-04:00", "returnsAt": "2026-10-04T06:30:00-04:00", "status": "confirmed" },
        "relationships": { "...": "igual que la anterior" } } }
  ]
}
```

La app genera las copias del rango y las envía juntas. Si alguna falla (por ejemplo, por solapamiento), no se crea ninguna.

## 4.5 Permisos

Leyenda: **A** Administrador (todas las Entidades) · **JT** Jefe de Transporte (su Entidad) · **JI** Jefe de itinerario (solo su itinerario) · **C** Chofer (solo sus viajes) · **T** cualquier trabajador · **Propio** solo lo suyo

| Acción | A | JT | JI | C | T |
|---|:-:|:-:|:-:|:-:|:-:|
| Ver nombres, foto, jerarquía y cantidad de hijos (de su Entidad) | ✔ | ✔ | ✔ | ✔ | ✔ |
| Ver el usuario | ✔ | | | | Propio |
| Ver el Pase | ✔ | ✔ | Los de su itinerario | | Propio |
| Ver fechas de nacimiento de los hijos | ✔ | ✔ | Los de su itinerario | | Propio |
| Gestionar Entidades, nomencladores, palabras no permitidas y ajustes de la app | ✔ | | | | |
| Gestionar vehículos, itinerarios, paradas y ajustes de la Entidad | ✔ | ✔ | | | |
| Registrar trabajadores sin teléfono y generar su código | ✔ | ✔ | En su itinerario | | |
| Planificar viajes (crear, copiar a un rango, confirmar, cancelar) | ✔ | ✔ | Solo su itinerario | | |
| Ver viajes | ✔ | ✔ | ✔ | ✔ | De su itinerario |
| Aprobar, asignar o retirar `transport_chief` | ✔ | | | | |
| Aprobar, asignar o retirar `itinerary_chief` y `driver` | ✔ | ✔ | | | |
| Aprobar `itinerary_membership`, `child_*` y `absence`; asignar o quitar itinerario y parada | ✔ | ✔ | ✔ | | |
| Cambiar la jerarquía | | | | | Propio |
| Aprobar o rechazar "No puedo entrar"; bloquear instalaciones | ✔ | | | | |
| Marcar viaje como realizado | ✔ | ✔ | ✔ | ✔ | |
| Iniciar o finalizar trayecto, registrar subidas de otros, escanear QR | ✔ | ✔ | ✔ | ✔ | |
| Enviar posición como sensor (solo el chofer del viaje o miembros de ese itinerario, sea cual sea su rol) | | | | ✔ | Si es de ese itinerario |
| Voz durante el recorrido | ✔ | ✔ | ✔ | ✔ | |
| Estadísticas | Todas | Su Entidad | Su itinerario | Las suyas | Las propias |

**Nadie aprueba sus propias solicitudes.**

## 4.6 Estadísticas

`GET /statistics/{name}` devuelve un recurso `statistics` con `attributes.columns` (definición de columnas) y `attributes.rows` (filas). La app dibuja los gráficos y las tablas a partir de esos datos (no se exportan).

**Filtros de periodo** (uno de los tres):

| Forma | Ejemplo |
|---|---|
| Rango | `filter[from]=2026-10-01&filter[to]=2026-10-31` |
| Fechas explícitas | `filter[dates]=2026-10-02,2026-10-09,2026-10-16` |
| Relativo | `filter[last]=7d` (también `w`, `m`, `y`: días, semanas, meses, años) |

**Otros filtros:** `filter[entity]` (solo el Administrador), `filter[itinerary]`, `filter[vehicle]`, `filter[driver]`, `filter[stop]`, `filter[level]` (en `overloaded-trips`: `saturated` u `overloaded`). La API los restringe según el rol y la Entidad.

**Nombres disponibles:**

| `name` | Contenido |
|---|---|
| `trips-by-status` | Viajes por estado |
| `punctuality` | Diferencia entre lo planificado y lo real, en salida y llegada |
| `duration` | Duración real frente a planificada |
| `trips-by-driver`, `trips-by-vehicle` | Carga de trabajo |
| `overloaded-trips` | Viajes saturados y sobresaturados |
| `occupancy` | Ocupación media frente a capacidad |
| `attendance` | Subidos frente a esperados, por itinerario y por parada |
| `children-transported` | Niños transportados |
| `workers-distribution` | Trabajadores por itinerario, parada, jerarquía y sexo |
| `worker-trips` | Historial de viajes de un trabajador |
| `applications-summary` | Solicitudes por tipo y estado, y tiempo medio de resolución |
| `stop-activity` | Subidas y bajadas por parada |
| `stop-pass-times` | Hora real de paso por cada parada |
| `distance` | Distancia recorrida por vehículo |
| `live-trip` | Estadísticas del viaje en marcha (`filter[trip]`) |

## 4.7 Errores

Siempre con el formato `errors[]` de JSON:API: `status`, `code`, `title`, `detail` y `source.pointer` o `source.parameter`.

| `code` | HTTP | Cuándo |
|---|---|---|
| `BAD_REQUEST` | 400 | Documento o parámetro de consulta mal formado (`source.parameter` indica cuál) |
| `UNAUTHENTICATED` | 401 | Falta la cabecera `Authorization: Bearer` |
| `INVALID_CREDENTIALS` | 401 | Usuario o contraseña incorrectos |
| `INSTALLATION_REQUIRED` | 401 | Falta la cabecera `X-Installation` o no es válida |
| `TOKEN_INVALID` | 401 | Token mal formado, con firma no válida o de otro tipo |
| `TOKEN_EXPIRED` | 401 | Token caducado |
| `TOKEN_REVOKED` | 401 | Token de renovación revocado o reutilizado, o cuenta desactivada |
| `FORBIDDEN` | 403 | El rol no permite la acción |
| `ENTITY_REQUIRED` | 403 | La cuenta aún no se unió a una Entidad |
| `INSTALLATION_BLOCKED` | 403 | El Administrador bloqueó ese teléfono |
| `SELF_APPROVAL` | 403 | Intento de resolver una solicitud propia |
| `NOT_FOUND` | 404 | No existe o el usuario no puede verlo |
| `METHOD_NOT_ALLOWED` | 405 | Método HTTP no admitido en esa ruta |
| `NOT_ACCEPTABLE` | 406 | La cabecera `Accept` solo admite JSON:API con parámetros no permitidos |
| `TYPE_MISMATCH` | 409 | `data.type` no corresponde al recurso |
| `ID_MISMATCH` | 409 | `data.id` no coincide con el de la URL |
| `DUPLICATE` | 409 | Ya existe un registro con esos datos (clave única) |
| `USERNAME_TAKEN` | 409 | El usuario ya existe (también si es de una cuenta inactiva) o se dejó de usar hace menos de `username_reuse_block_days` días |
| `PASS_TAKEN` | 409 | Ya hay un trabajador con ese Pase en la Entidad |
| `ALREADY_IN_ENTITY` | 409 | La cuenta ya pertenece a una Entidad |
| `ADMIN_HAS_NO_ENTITY` | 409 | El Administrador no se une a ninguna Entidad |
| `ALREADY_ACTIVATED` | 409 | Pedir un código de activación para una cuenta ya activada |
| `RECOVERY_NOT_PENDING` | 409 | Aprobar o rechazar una solicitud "No puedo entrar" que ya no está pendiente |
| `RECOVERY_NOT_MATCHED` | 409 | Aprobar una solicitud cuyos datos no coinciden con ningún trabajador |
| `RECOVERY_NOT_APPROVED` | 409 | Elegir contraseña con una solicitud no aprobada |
| `CONVERSATION_CLOSED` | 409 | Escribir en una conversación cerrada |
| `APPLICATION_NOT_PENDING` | 409 | Resolver o cancelar una solicitud que ya no está pendiente |
| `APPLICATION_ALREADY_PENDING` | 409 | Ya hay una solicitud pendiente de ese tipo |
| `ALREADY_MEMBER` | 409 | Ya viaja en ese itinerario y esa parada |
| `ALREADY_HAS_ROLE` | 409 | Ya tiene el rol que pide |
| `ALREADY_CHIEF_OF_OTHER` | 409 | Pide ser Jefe de un itinerario siendo ya Jefe de otro |
| `STOP_ALREADY_IN_ITINERARY` | 409 | La parada ya está en el itinerario |
| `STOP_HAS_MEMBERS` | 409 | Quitar del itinerario una parada en la que hay miembros |
| `STOP_IN_USE` | 409 | Borrar una parada que está en algún itinerario |
| `ITINERARY_HAS_MEMBERS` | 409 | Borrar un itinerario con miembros |
| `TRIP_OVERLAP` | 409 | Solapamiento de vehículo o chofer al confirmar. `meta.conflictingTripId` y `meta.reason` (`vehicle` o `driver`) |
| `TRIP_TRANSITION_NOT_ALLOWED` | 409 | Cancelar un viaje realizado, o marcar como realizado uno cancelado |
| `TRIP_NOT_CONFIRMED` | 409 | Iniciar el recorrido de un viaje no confirmado |
| `LEG_ALREADY_STARTED` | 409 | Ese trayecto ya se inició |
| `LEG_NOT_ACTIVE` | 409 | El trayecto no está en curso |
| `CHAT_NOT_AVAILABLE` | 409 | El chat de un viaje no confirmado |
| `UNSUPPORTED_MEDIA_TYPE` | 415 | Falta el tipo de contenido JSON:API (o la extensión atómica en `/operations`) |
| `VALIDATION_ERROR` | 422 | Error de validación de un campo (`source.pointer` indica cuál) |
| `USERNAME_INVALID` | 422 | El usuario no cumple las reglas (longitud, caracteres, palabras reservadas o no permitidas) |
| `PASSWORD_POLICY` | 422 | La contraseña no cumple la política (detalle con todos los motivos) |
| `ENTITY_NOT_FOUND` | 422 / 404 | No hay ninguna Entidad con esa abreviatura |
| `ENTITY_MISMATCH` | 422 | Lo relacionado (itinerario, parada, vehículo, chofer…) es de otra Entidad |
| `ACTIVATION_INVALID` | 422 | Entidad, Pase o código de activación incorrectos, o código caducado |
| `CURRENT_PASSWORD_INVALID` | 422 | Falta la contraseña actual o no es correcta |
| `STOP_NOT_IN_ITINERARY` | 422 | La parada no pertenece al itinerario |
| `CHILD_NOT_ELIGIBLE` | 422 | El niño ya no tiene derecho a viajar |
| `TRIP_DATES_INVALID` | 422 | El regreso no es posterior a la salida |
| `NOT_A_PASSENGER` | 422 | El trabajador no es pasajero esperado del viaje |
| `BOARDING_PASS_INVALID` | 422 | QR caducado, manipulado o de otro trayecto |
| `CHILDREN_COUNT_EXCEEDED` | 422 | Suben más niños de los que tiene con derecho |
| `NO_ITINERARY` | 422 | Escribir a los Jefes de itinerario sin ser miembro de ninguno |
| `NOT_A_SENSOR` | 422 | Enviar posición sin ser trabajador |
| `PASSWORD_CHANGE_REQUIRED` | 403 | La contraseña caducó o se recuperó el acceso, y aún no se eligió una nueva |
| `TOO_MANY_REQUESTS` | 429 | Demasiadas solicitudes "No puedo entrar" o mensajes sin cuenta desde ese teléfono en la última hora |
| `APK_INVALID` | 422 | El archivo publicado no es un APK |
| `APK_REQUIRED` | 422 | No se subió ningún APK |
| `VERSION_CODE_TOO_LOW` | 422 | El versionCode no es mayor que el de la última versión publicada |
| `SETTING_OUT_OF_RANGE` | 422 | Valor fuera de los límites del ajuste |
| `OPERATION_NOT_SUPPORTED` | 400 | Operación atómica no admitida |
| `SERVER_ERROR` | 500 | Error interno (el detalle solo aparece con `APP_DEBUG=true`) |
