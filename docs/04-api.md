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
    Middleware/     JwtAuthenticate, RequireJsonApi (comprueba Content-Type/Accept)
  Serializers/      Capa de "vista": convierte modelos en documentos JSON:API
  Policies/         Permisos por recurso y rol (el Administrador siempre tiene permiso)
  Services/         Lógica que abarca varios modelos: aprobación de solicitudes, solapamiento,
                    combinación de sensores, orden de subida, estadísticas
  Console/Commands/ Tareas programadas (ver 02-procesos.md §2.12)
database/
  migrations/  seeders/  factories/
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
| Gestionar vehículos, itinerarios, paradas y viajes | ✔ | ✔ | | | |
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
| `CARD_NUMBER_INVALID` | 422 | El carné no tiene 11 dígitos, la fecha no es válida o el siglo no corresponde |
| `CARD_NUMBER_TAKEN` | 409 | El carné ya está registrado |
| `INVALID_CREDENTIALS` | 401 | Carné o contraseña incorrectos |
| `TOKEN_EXPIRED`, `TOKEN_REVOKED` | 401 | Token de acceso caducado, o token de renovación revocado o ya usado |
| `FORBIDDEN` | 403 | El rol no permite la acción |
| `SELF_APPROVAL` | 403 | Intento de resolver una solicitud propia |
| `APPLICATION_NOT_PENDING` | 409 | Resolver o cancelar una solicitud que ya no está pendiente |
| `STOP_NOT_IN_ITINERARY` | 422 | La parada no pertenece al itinerario |
| `STOP_HAS_MEMBERS` | 409 | Quitar del itinerario una parada en la que hay miembros |
| `CHILD_NOT_ELIGIBLE` | 422 | El niño ya no tiene derecho a viajar |
| `CHILD_ALREADY_DECLARED` | 409 | Ese niño ya está declarado |
| `TRIP_OVERLAP` | 409 | Solapamiento de vehículo o chofer al confirmar. `meta.conflictingTripId` indica con qué viaje |
| `TRIP_TRANSITION_NOT_ALLOWED` | 409 | Cancelar un viaje realizado, o marcar como realizado uno cancelado |
| `TRIP_DATES_INVALID` | 422 | El regreso no es posterior a la salida |
| `BOARDING_PASS_INVALID` | 422 | QR caducado o de otro trayecto |
| `CHILDREN_COUNT_EXCEEDED` | 422 | Suben más niños de los que tiene con derecho |
| `SETTING_OUT_OF_RANGE` | 422 | Valor fuera de los límites del ajuste |
| `UNSUPPORTED_MEDIA_TYPE` | 415 | Falta el tipo de contenido JSON:API |
