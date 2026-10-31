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
                    combinación de sensores, orden de subida, estadísticas
  Support/          Objetos de valor (CardNumber)
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
  - `sub` (id del trabajador);
  - `iat` y `exp` (30 min);
  - `jti`.

  El token de renovación lleva su propio `jti`. Se guarda solo su huella SHA-256 en `refresh_tokens`, y caduca a los 90 días.
- **HTTPS obligatorio.**

## 4.3 Autenticación

| Método | Ruta | Descripción | Acceso |
|---|---|---|---|
| `POST` | `/workers` | Registro (el primer usuario pasa a ser Administrador) | Público |
| `POST` | `/tokens` | Inicio de sesión con carné y contraseña | Público |
| `POST` | `/tokens/refresh` | Renovación con rotación | Con token de renovación |
| `DELETE` | `/tokens/current` | Cerrar sesión en este dispositivo | Autenticado |
| `DELETE` | `/tokens` | Cerrar sesión en todos los dispositivos | Autenticado |
| `POST` | `/password-resets` | Pedir restablecer la contraseña (carné y teléfono) | Público |
| `POST` | `/tokens/reset-code` | Entrar con el código de restablecimiento; obliga a cambiar la contraseña | Público |
| `GET`, `PATCH` | `/password-resets`, `/password-resets/{id}` | Ver las solicitudes (teléfono y código) y marcarlas como enviadas o canceladas | Administrador |

Las demás rutas exigen `Authorization: Bearer <token de acceso>`.

## 4.4 Recursos

| Recurso | Rutas | Notas |
|---|---|---|
| **Perfil propio** | `GET/PATCH /me`, `POST/DELETE /me/photo`, `GET/PATCH /me/settings` | Único lugar, junto con el acceso del Administrador, donde aparece el carné |
| `workers` | `GET /workers`, `GET /workers/{id}`, `PATCH /workers/{id}` | Desactivar o reactivar con el atributo `active` (Administrador). `meta`: `childrenCount` |
| `ranks` | CRUD + `POST /ranks/{id}/icon` | Gestión: Administrador |
| `vehicle-types`, `absence-types`, `conversation-topics` | CRUD | Gestión: Administrador y Jefes de Transporte |
| `itineraries` | CRUD | `meta`: `departurePoint`, `returnPoint`, `memberCount` |
| `stops` | CRUD | — |
| `itinerary-stops` | CRUD | `position` dentro del itinerario. Al cambiar las paradas extremas se tocan los viajes pendientes |
| `itinerary-chiefs`, `drivers`, `transport-chiefs` | `GET`, `DELETE` | Se crean al aprobar solicitudes. Darse de baja a uno mismo genera la solicitud `*_leave` correspondiente |
| `vehicles` | CRUD | `meta`: `totalCapacity` |
| `trips` | CRUD | `filter[updatedSince]` para sincronizar. `meta`: `expectedPassengers`, `overloaded`, `departurePoint`, `returnPoint`, `needsReassignment`, `expectedChildren` |
| `trip-completions` | `GET`, `POST` | Marcar como realizado |
| `trip-legs` | `GET`, `POST` (iniciar), `PATCH` (finalizar) | `meta`: `currentPosition`, `activeSensors` |
| `trip-positions` | `GET`, `POST` | Para enviar posiciones acumuladas sin conexión, usar `/operations` |
| `trip-stop-passes` | `GET` | Los genera el servidor |
| `trip-boardings` | `GET`, `POST` | `method`: `automatic`, `self`, `qr` o `manual` |
| `boarding-passes` | `POST` | Devuelve el token temporal para el QR |
| `trip-passengers` | `GET /trips/{id}/passengers` | Lista de pasajeros en **orden de subida**, con su parada y su estado de subida |
| `trip-messages` | `GET`, `POST` | Chat del viaje |
| `children` | `GET`, `GET /{id}` | Se crean y se quitan mediante solicitudes. `meta`: `eligibleUntil` (solo para el padre o madre y el Administrador) |
| `applications` | `GET`, `POST`, `GET /{id}`, `PATCH /{id}` | `PATCH` con `status`: `approved`, `rejected` o `cancelled` |
| `conversations`, `conversation-messages` | `GET`, `POST` | — |
| `notices` | `GET`, `PATCH` (marcar como leído) | — |
| `setting-definitions`, `settings` | `GET`, `PATCH /settings/{id}` | `editable_by` decide quién puede cambiar cada ajuste global |
| `statistics` | `GET /statistics/{name}` | Ver 4.6 |
| `app-versions` | `GET /app-versions/latest` (público), `GET`, `POST` (multipart), `DELETE /{id}` | Actualizaciones de la app; publica y retira solo el Administrador. La app envía su versión en la cabecera `X-App-Version-Code` |
| `app-versions` | `GET /app-versions/latest` (público), `GET`, `POST` (multipart), `DELETE /{id}` | Actualizaciones de la app; publica y retira solo el Administrador. La app envía su versión en la cabecera `X-App-Version-Code` |
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

Leyenda: **A** Administrador · **JT** Jefe de Transporte · **JI** Jefe de itinerario (solo en sus itinerarios) · **C** Chofer (solo sus viajes) · **T** cualquier trabajador · **Propio** solo lo suyo

| Acción | A | JT | JI | C | T |
|---|:-:|:-:|:-:|:-:|:-:|
| Ver nombre, apellidos, foto, jerarquía y cantidad de hijos de cualquiera | ✔ | ✔ | ✔ | ✔ | ✔ |
| Ver carné y fechas de nacimiento | ✔ | | | | Propio |
| Gestionar jerarquías e iconos, motivos de conversación | ✔ | | | | |
| Gestionar tipos de vehículo y tipos de ausencia | ✔ | ✔ | | | |
| Gestionar vehículos, itinerarios y paradas | ✔ | ✔ | | | |
| Planificar viajes (crear, copiar a un rango, confirmar, cancelar) | ✔ | ✔ | Solo su itinerario | | |
| Ver viajes | ✔ | ✔ | ✔ | ✔ | De su itinerario |
| Aprobar `transport_chief` | ✔ | | | | |
| Aprobar `itinerary_chief` y `driver` | ✔ | ✔ | | | |
| Aprobar `itinerary_membership`, `rank_change`, `child_*` y `absence` | ✔ | ✔ | ✔ | | |
| Marcar viaje como realizado | ✔ | ✔ | ✔ | ✔ | |
| Iniciar o finalizar trayecto, registrar subidas de otros, escanear QR | ✔ | ✔ | ✔ | ✔ | |
| Enviar posición como sensor (solo el chofer del viaje o miembros de ese itinerario, sea cual sea su rol) | | | | ✔ | Si es de ese itinerario |
| Voz durante el recorrido | ✔ | ✔ | ✔ | ✔ | |
| Ajustes globales | Según `editable_by` | Según `editable_by` | | | |
| Estadísticas | Todas | Todas | Sus itinerarios | Las suyas | Las propias |

**Nadie aprueba sus propias solicitudes.**

## 4.6 Estadísticas

`GET /statistics/{name}` devuelve un recurso `statistics` con `attributes.columns` (definición de columnas) y `attributes.rows` (filas). La app dibuja los gráficos y genera el Excel o el PDF a partir de esos datos.

**Filtros de periodo** (uno de los tres):

| Forma | Ejemplo |
|---|---|
| Rango | `filter[from]=2026-10-01&filter[to]=2026-10-31` |
| Fechas explícitas | `filter[dates]=2026-10-02,2026-10-09,2026-10-16` |
| Relativo | `filter[last]=7d` (también `w`, `m`, `y`: días, semanas, meses, años) |

**Otros filtros:** `filter[itinerary]`, `filter[vehicle]`, `filter[driver]`, `filter[stop]`. La API los restringe según el rol.

**Nombres disponibles:**

| `name` | Contenido |
|---|---|
| `trips-by-status` | Viajes por estado |
| `punctuality` | Diferencia entre lo planificado y lo real, en salida y llegada |
| `duration` | Duración real frente a planificada |
| `trips-by-driver`, `trips-by-vehicle` | Carga de trabajo |
| `overloaded-trips` | Viajes sobresaturados |
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
| `INVALID_CREDENTIALS` | 401 | Carné o contraseña incorrectos |
| `TOKEN_INVALID` | 401 | Token mal formado, con firma no válida o de otro tipo |
| `TOKEN_EXPIRED` | 401 | Token caducado |
| `TOKEN_REVOKED` | 401 | Token de renovación revocado o reutilizado, o cuenta desactivada |
| `FORBIDDEN` | 403 | El rol no permite la acción |
| `SELF_APPROVAL` | 403 | Intento de resolver una solicitud propia |
| `NOT_FOUND` | 404 | No existe o el usuario no puede verlo |
| `METHOD_NOT_ALLOWED` | 405 | Método HTTP no admitido en esa ruta |
| `NOT_ACCEPTABLE` | 406 | La cabecera `Accept` solo admite JSON:API con parámetros no permitidos |
| `TYPE_MISMATCH` | 409 | `data.type` no corresponde al recurso |
| `ID_MISMATCH` | 409 | `data.id` no coincide con el de la URL |
| `DUPLICATE` | 409 | Ya existe un registro con esos datos (clave única) |
| `CARD_NUMBER_TAKEN` | 409 | El carné ya está registrado |
| `APPLICATION_NOT_PENDING` | 409 | Resolver o cancelar una solicitud que ya no está pendiente |
| `APPLICATION_ALREADY_PENDING` | 409 | Ya hay una solicitud pendiente de ese tipo |
| `ALREADY_MEMBER` | 409 | Ya viaja en ese itinerario y esa parada |
| `ALREADY_HAS_ROLE` | 409 | Ya tiene el rol que pide |
| `ALREADY_CHIEF_OF_OTHER` | 409 | Pide ser Jefe de un itinerario siendo ya Jefe de otro |
| `STOP_ALREADY_IN_ITINERARY` | 409 | La parada ya está en el itinerario |
| `STOP_HAS_MEMBERS` | 409 | Quitar del itinerario una parada en la que hay miembros |
| `STOP_IN_USE` | 409 | Borrar una parada que está en algún itinerario |
| `ITINERARY_HAS_MEMBERS` | 409 | Borrar un itinerario con miembros |
| `CHILD_ALREADY_DECLARED` | 409 | Ese niño ya está declarado o pendiente |
| `TRIP_OVERLAP` | 409 | Solapamiento de vehículo o chofer al confirmar. `meta.conflictingTripId` y `meta.reason` (`vehicle` o `driver`) |
| `TRIP_TRANSITION_NOT_ALLOWED` | 409 | Cancelar un viaje realizado, o marcar como realizado uno cancelado |
| `TRIP_NOT_CONFIRMED` | 409 | Iniciar el recorrido de un viaje no confirmado |
| `LEG_ALREADY_STARTED` | 409 | Ese trayecto ya se inició |
| `LEG_NOT_ACTIVE` | 409 | El trayecto no está en curso |
| `CHAT_NOT_AVAILABLE` | 409 | El chat de un viaje no confirmado |
| `UNSUPPORTED_MEDIA_TYPE` | 415 | Falta el tipo de contenido JSON:API (o la extensión atómica en `/operations`) |
| `VALIDATION_ERROR` | 422 | Error de validación de un campo (`source.pointer` indica cuál) |
| `CARD_NUMBER_INVALID` | 422 | El carné no tiene 11 dígitos, la fecha no es válida o el siglo no corresponde |
| `CURRENT_PASSWORD_INVALID` | 422 | Falta la contraseña actual o no es correcta |
| `STOP_NOT_IN_ITINERARY` | 422 | La parada no pertenece al itinerario |
| `CHILD_NOT_ELIGIBLE` | 422 | El niño ya no tiene derecho a viajar |
| `TRIP_DATES_INVALID` | 422 | El regreso no es posterior a la salida |
| `NOT_A_PASSENGER` | 422 | El trabajador no es pasajero esperado del viaje |
| `BOARDING_PASS_INVALID` | 422 | QR caducado, manipulado o de otro trayecto |
| `CHILDREN_COUNT_EXCEEDED` | 422 | Suben más niños de los que tiene con derecho |
| `NO_ITINERARY` | 422 | Escribir a los Jefes de itinerario sin ser miembro de ninguno |
| `RESET_CODE_INVALID` | 401 | Código de restablecimiento incorrecto, usado, caducado o con demasiados intentos |
| `PASSWORD_CHANGE_REQUIRED` | 403 | Entró con un código de restablecimiento y aún no cambió la contraseña |
| `RESET_NOT_OPEN` | 409 | Marcar como enviada una solicitud ya cerrada |
| `APK_INVALID` | 422 | El archivo publicado no es un APK |
| `VERSION_CODE_TOO_LOW` | 422 | El versionCode no es mayor que el de la última versión publicada |
| `SETTING_OUT_OF_RANGE` | 422 | Valor fuera de los límites del ajuste |
| `OPERATION_NOT_SUPPORTED` | 400 | Operación atómica no admitida |
| `SERVER_ERROR` | 500 | Error interno (el detalle solo aparece con `APP_DEBUG=true`) |
