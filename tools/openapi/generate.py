"""Genera docs/openapi.yaml.

Uso: python3 tools/openapi/generate.py docs/openapi.yaml
Requiere PyYAML. Editar este script y regenerar, en lugar de editar el YAML a mano.
"""
import sys

import yaml

S = lambda t, **kw: dict(type=t, **kw)
STR = lambda **kw: S("string", **kw)
INT = lambda **kw: S("integer", **kw)
BOOL = lambda **kw: S("boolean", **kw)
DT = lambda **kw: STR(format="date-time", **kw)
DATE = lambda **kw: STR(format="date", **kw)
NUM = lambda **kw: S("number", **kw)
RO = dict(readOnly=True)

NAMES = {f: STR(maxLength=50, **({"nullable": True, "description": "Opcional"} if f == "middleName" else {})) for f in ["firstName", "middleName", "firstSurname", "secondSurname"]}

NOMEN = {
    "name": STR(maxLength=100, description="Denominación"),
    "description": STR(nullable=True, description="Descripción"),
    "observation": STR(nullable=True, description="Observación"),
}

# type -> (schema name, tag, description, attributes, relationships{name: (type, many)}, meta)
R = {}


def res(rtype, name, tag, desc, attrs, rels=None, meta=None, required=None):
    R[rtype] = dict(name=name, tag=tag, desc=desc, attrs=attrs, rels=rels or {}, meta=meta or {}, required=required or [])


res("users", "User", "Cuentas", "Cuenta de la app. El Administrador es una cuenta sin trabajador. El usuario y los datos de la contraseña solo los ven la propia cuenta y el Administrador.", {
    "username": STR(pattern=r"^[a-z][a-z0-9._]{3,19}$", description="De 4 a 20 caracteres, empieza por letra, sin signos al final ni seguidos, al menos 3 letras, sin palabras reservadas. Único en toda la app; el anterior queda bloqueado `username_reuse_block_days` días."),
    "password": STR(format="password", writeOnly=True, description="Según la política de contraseñas (GET /password-policy)"),
    **NAMES,
    "fullName": STR(**RO),
    "photoUrl": STR(format="uri", nullable=True, readOnly=True),
    "isAdmin": BOOL(**RO),
    "active": BOOL(description="Falso = borrado lógico. Solo el Administrador puede cambiarlo."),
    "activated": BOOL(readOnly=True, description="Tiene usuario y contraseña (falso si la registró un superior y aún no la activó)"),
    "mustChangePassword": BOOL(readOnly=True, description="La contraseña caducó o se recuperó el acceso: solo se permite el perfil propio"),
    "currentPasswordRequired": BOOL(readOnly=True, description="Para cambiarla hay que dar la actual (falso tras recuperar el acceso)"),
    "passwordExpiresAt": DT(nullable=True, **RO),
    "appVersionCode": INT(nullable=True, readOnly=True, description="Solo para el Administrador"),
    "createdAt": DT(**RO),
}, {"worker": ("workers", False)}, required=["username", "password", "firstName", "firstSurname", "secondSurname"])
res("workers", "Worker", "Trabajadores", "Trabajador de una Entidad. Los nombres y la foto vienen de su cuenta. El Pase lo ven el propio trabajador, el Jefe de su itinerario, los Jefes de Transporte de su Entidad y el Administrador.", {
    **NAMES,
    "fullName": STR(**RO),
    "pass": INT(minimum=1, description="Pase: único dentro de la Entidad"),
    "sex": STR(enum=["F", "M"]),
    "photoUrl": STR(format="uri", nullable=True, readOnly=True),
    "active": BOOL(description="Falso = borrado lógico. Solo el Administrador puede cambiarlo."),
    "activated": BOOL(**RO),
    "createdAt": DT(**RO),
}, {"user": ("users", False), "entity": ("entities", False), "rank": ("ranks", False), "itinerary": ("itineraries", False), "stop": ("stops", False)},
    {"childrenCount": INT(description="Hijos con derecho a viajar hoy"),
     "roles": {"type": "object", "properties": {"isTransportChief": BOOL(), "driverId": STR(nullable=True),
                                                "chiefOfItineraries": S("array", items=STR())}},
     "activationCode": STR(description="Solo al registrarlo un superior o al generar uno nuevo"),
     "activationExpiresAt": DT(nullable=True)},
    ["firstName", "firstSurname", "secondSurname", "pass", "sex"])
res("entities", "Entity", "Entidades", "Entidad: empresa que usa la app. Solo el Administrador las gestiona; se muestra por su abreviatura.", {
    "abbreviation": STR(pattern=r"^[A-Z0-9]{2,15}$", description="Obligatoria y única (también entre inactivas); en mayúsculas"),
    "number": STR(pattern=r"^\d{4}$", nullable=True, description="Opcional; único si se pone"),
    "name": STR(maxLength=150),
    "description": STR(nullable=True), "observation": STR(nullable=True),
    "active": BOOL(description="En PATCH: desactivar o reactivar"),
}, required=["abbreviation", "name"])
res("installations", "Installation", "Sin cuenta", "Instalación de la app en un teléfono. Al crearla se devuelve su secreto (meta.header) para la cabecera X-Installation.", {
    "deviceModel": STR(nullable=True), "androidVersion": STR(nullable=True), "appVersionCode": INT(nullable=True),
    "blocked": BOOL(description="Solo el Administrador; bloqueada no puede escribir sin cuenta ni pedir recuperación"),
    "createdAt": DT(**RO),
}, {"user": ("users", False)}, {"header": STR(description="Solo al crearla: valor de X-Installation (<id>.<secreto>)")})
res("access-recoveries", "AccessRecovery", "Sin cuenta", "Solicitud \"No puedo entrar\". La crea y consulta la instalación; el Administrador la aprueba o rechaza.", {
    "forgotUsername": BOOL(), "forgotPassword": BOOL(),
    "entityAbbreviation": STR(), "pass": INT(minimum=1),
    "phone": STR(description="Al crearla; después solo lo ve el Administrador"),
    "status": STR(enum=["pending", "approved", "rejected", "completed", "expired"], description="En PATCH (Administrador): approved o rejected"),
    "username": STR(readOnly=True, description="Solo para la instalación, si se aprobó y olvidó el usuario"),
    "matched": BOOL(readOnly=True, description="Solo para el Administrador: los datos coinciden con un trabajador"),
    "expiresAt": DT(**RO), "resolvedAt": DT(nullable=True, **RO), "createdAt": DT(**RO),
}, {"worker": ("workers", False), "installation": ("installations", False), "resolvedBy": ("users", False)},
    required=["forgotUsername", "forgotPassword", "entityAbbreviation", "pass", "phone"])
res("activations", "Activation", "Cuentas", "\"Ya me registró un superior\": activar la cuenta con la Entidad, el Pase y el código.", {
    "entityAbbreviation": STR(), "pass": INT(minimum=1), "code": STR(description="8 caracteres; se admite con guion"),
    "username": STR(), "password": STR(format="password"), "deviceName": STR(nullable=True),
}, required=["entityAbbreviation", "pass", "code", "username", "password"])
res("password-policies", "PasswordPolicy", "Cuentas", "Requisitos actuales de la contraseña y del usuario.", {
    "minLength": INT(), "maxLength": INT(), "requiredClasses": INT(minimum=1, maximum=4), "historyCount": INT(), "expiryDays": INT(), "usernameMinLength": INT(), "usernameMaxLength": INT(),
})
res("server-statuses", "ServerStatus", "Mantenimiento", "Estado del servidor (PHP, base de datos, carpetas y tareas programadas).", {
    "apiVersion": STR(), "phpVersion": STR(), "phpSupported": BOOL(description="De 7.2.5 a 8.0"),
    "extensions": {"type": "object", "additionalProperties": BOOL()},
    "php": {"type": "object", "additionalProperties": True, "description": "Límites de PHP (subida, memoria, open_basedir…)"},
    "serverTime": STR(format="date-time"), "timezone": STR(),
    "database": {"type": "object", "properties": {"connected": BOOL(), "error": STR(nullable=True), "installed": BOOL(), "pendingMigrations": S("array", items=STR())}},
    "storage": {"type": "object", "properties": {"path": STR(), "exists": BOOL(), "writable": BOOL()}},
    "uploads": {"type": "object", "properties": {"path": STR(), "exists": BOOL(), "writable": BOOL()}},
    "tasks": {"type": "object", "additionalProperties": True, "description": "onRequests (sin cron), lastCheck y la lista con la última ejecución de cada tarea"},
    "commands": S("array", items=STR()),
})
res("maintenance-runs", "MaintenanceRun", "Mantenimiento", "Ejecución de una orden de mantenimiento de la lista (nunca una orden libre).", {
    "command": STR(enum=["install", "migrate", "run-tasks", "clear-cache", "log"], description="install: crea la base de datos (solo si está vacía); migrate: aplica los cambios de una versión nueva; run-tasks: tareas programadas pendientes; clear-cache; log: últimas líneas del registro de errores"),
    "ok": BOOL(readOnly=True), "output": STR(readOnly=True), "ranAt": STR(format="date-time", readOnly=True),
}, required=["command"])
res("ranks", "Rank", "Nomencladores", "Jerarquía, común a todas las Entidades. Solo sirve para las estadísticas.", {**NOMEN, "sortOrder": INT(minimum=0, description="Orden de presentación"), "iconUrl": STR(format="uri", nullable=True, readOnly=True)}, required=["name"])
res("vehicle-types", "VehicleType", "Nomencladores", "Tipo de vehículo.", dict(NOMEN), required=["name"])
res("absence-types", "AbsenceType", "Nomencladores", "Tipo de ausencia.", dict(NOMEN), required=["name"])
res("conversation-topics", "ConversationTopic", "Nomencladores", "Motivo de conversación.", {**NOMEN, "recipient": STR(enum=["itinerary_chiefs", "transport_chiefs", "developer"])}, required=["name", "recipient"])
res("itineraries", "Itinerary", "Itinerarios y paradas", "Itinerario de una Entidad (nombre único dentro de ella).", dict(NOMEN), {"entity": ("entities", False), "itineraryStops": ("itinerary-stops", True), "chiefs": ("itinerary-chiefs", True),
     "referenceOutboundLeg": ("trip-legs", False), "referenceReturnLeg": ("trip-legs", False)},
    {"departurePoint": {"$ref": "#/components/schemas/ResourceIdentifier"}, "returnPoint": {"$ref": "#/components/schemas/ResourceIdentifier"}, "memberCount": INT()}, ["name"])
res("stops", "Stop", "Itinerarios y paradas", "Parada de una Entidad. Dos Entidades pueden usar el mismo lugar, pero cada una registra la suya.", {
    "landmark": STR(maxLength=255, description="Punto de referencia"),
    "street": STR(maxLength=255),
    "crossStreet1": STR(maxLength=255, nullable=True),
    "crossStreet2": STR(maxLength=255, nullable=True),
    "latitude": NUM(minimum=-90, maximum=90),
    "longitude": NUM(minimum=-180, maximum=180),
}, {"entity": ("entities", False)}, required=["landmark", "street", "latitude", "longitude"])
res("itinerary-stops", "ItineraryStop", "Itinerarios y paradas", "Posición de una parada dentro de un itinerario.", {"position": INT(minimum=1)},
    {"itinerary": ("itineraries", False), "stop": ("stops", False)}, required=["position"])
res("itinerary-chiefs", "ItineraryChief", "Roles", "Jefe de un itinerario.", {"createdAt": DT(**RO)}, {"itinerary": ("itineraries", False), "worker": ("workers", False)})
res("drivers", "Driver", "Roles", "Chofer.", {"createdAt": DT(**RO)}, {"worker": ("workers", False)})
res("transport-chiefs", "TransportChief", "Roles", "Jefe de Transporte.", {"createdAt": DT(**RO)}, {"worker": ("workers", False)})
res("vehicles", "Vehicle", "Vehículos", "Vehículo de una Entidad (matrícula única dentro de ella).", {
    "plate": STR(maxLength=20, description="Matrícula"),
    "seats": INT(minimum=0, description="Asientos sin contar el del chofer"),
    "standingCapacity": INT(minimum=0),
}, {"entity": ("entities", False), "vehicleType": ("vehicle-types", False), "driver": ("drivers", False)}, {"totalCapacity": INT()}, ["plate", "seats", "standingCapacity"])
res("trips", "Trip", "Viajes", "Viaje planificado.", {
    "departsAt": DT(),
    "returnsAt": DT(description="Debe ser posterior a departsAt"),
    "status": STR(enum=["unconfirmed", "confirmed", "completed", "cancelled"]),
    "outboundDelayed": BOOL(readOnly=True, description="El viaje de ida no ha comenzado y ya pasó su hora más la tolerancia de la Entidad"),
    "returnDelayed": BOOL(readOnly=True, description="Igual para el viaje de regreso"),
    "outboundDelayMinutes": INT(nullable=True, readOnly=True, description="Minutos de atraso al comenzar (o hasta ahora si está atrasado)"),
    "returnDelayMinutes": INT(nullable=True, readOnly=True),
    "updatedAt": DT(**RO),
}, {"itinerary": ("itineraries", False), "vehicle": ("vehicles", False), "driver": ("drivers", False), "completions": ("trip-completions", True), "legs": ("trip-legs", True)},
    {"expectedPassengers": INT(description="Trabajadores esperados (los niños van cargados y no cuentan)"), "expectedChildren": INT(),
     "seats": INT(), "totalCapacity": INT(description="Asientos + capacidad de pie"),
     "occupancyLevel": STR(enum=["normal", "saturated", "overloaded"], description="saturated: más que asientos pero caben de pie; overloaded: no caben"),
     "saturated": BOOL(), "overloaded": BOOL(), "needsReassignment": BOOL(),
     "departurePoint": {"$ref": "#/components/schemas/ResourceIdentifier"}, "returnPoint": {"$ref": "#/components/schemas/ResourceIdentifier"}},
    ["departsAt", "returnsAt", "status"])
res("trip-completions", "TripCompletion", "Viajes", "Marca de viaje realizado.", {
    "role": STR(enum=["driver", "itinerary_chief", "transport_chief", "administrator", "system"], readOnly=True),
    "createdAt": DT(**RO),
}, {"trip": ("trips", False), "user": ("users", False)})
res("trip-legs", "TripLeg", "Recorrido", "Trayecto de un viaje (salida o regreso).", {
    "direction": STR(enum=["outbound", "return"]),
    "startedAt": DT(**RO),
    "endedAt": DT(nullable=True, description="Enviar en PATCH para finalizar el recorrido"),
    "endReason": STR(enum=["last_stop", "manual"], nullable=True, readOnly=True),
}, {"trip": ("trips", False), "startedBy": ("users", False)},
    {"currentPosition": {"$ref": "#/components/schemas/Position"}, "activeSensors": INT(),
     "stopPasses": S("array", items={"type": "object", "properties": {"stopId": STR(), "passedAt": DT(),
         "status": STR(enum=["arrived", "stopped", "not_stopped", "skipped"])}}),
     "deviating": BOOL(description="Ahora mismo fuera del recorrido de referencia"),
     "incidents": S("array", items={"type": "object", "properties": {
         "type": STR(enum=["not_stopped", "skipped", "deviation"]), "stopId": STR(nullable=True), "latitude": NUM(nullable=True),
         "longitude": NUM(nullable=True), "distanceM": INT(nullable=True), "startedAt": DT(), "endedAt": DT(nullable=True)}})}, ["direction"])
res("trip-positions", "TripPosition", "Recorrido", "Posición enviada por un sensor.", {
    "latitude": NUM(), "longitude": NUM(), "accuracyM": NUM(nullable=True), "recordedAt": DT(),
}, {"tripLeg": ("trip-legs", False), "worker": ("workers", False)}, required=["latitude", "longitude", "recordedAt"])
res("trip-stop-passes", "TripStopPass", "Recorrido", "Paso del vehículo por una parada (lo genera el servidor).", {
    "passedAt": DT(**RO), "leftAt": DT(nullable=True, **RO),
    "status": STR(enum=["arrived", "stopped", "not_stopped", "skipped"], readOnly=True,
                  description="arrived: está en la parada; stopped: se detuvo; not_stopped: pasó de largo; skipped: se la saltó")},
    {"tripLeg": ("trip-legs", False), "stop": ("stops", False)})
res("trip-boardings", "TripBoarding", "Subida", "Registro de subida al vehículo.", {
    "method": STR(enum=["automatic", "self", "qr", "manual"]),
    "childrenCount": INT(minimum=0),
    "boardingPassToken": STR(writeOnly=True, description="Obligatorio si method = qr"),
    "boardedAt": DT(),
}, {"tripLeg": ("trip-legs", False), "worker": ("workers", False), "markedBy": ("users", False)}, required=["method", "childrenCount"])
res("boarding-passes", "BoardingPass", "Subida", "Token temporal para el código QR del trabajador.", {
    "token": STR(readOnly=True), "expiresAt": DT(**RO),
}, {"tripLeg": ("trip-legs", False)})
res("trip-passengers", "TripPassenger", "Subida", "Pasajero esperado en un viaje: por parada (en el orden del itinerario) y alfabéticamente.", {
    "position": INT(**RO), "eligibleChildren": INT(**RO), "boarded": BOOL(**RO), "boardedChildren": INT(nullable=True, **RO),
    "boardingMethod": STR(enum=["automatic", "self", "qr", "manual"], nullable=True, **RO),
}, {"worker": ("workers", False), "stop": ("stops", False)})
res("trip-messages", "TripMessage", "Chats", "Mensaje del chat de un viaje.", {"body": STR(maxLength=1000), "createdAt": DT(**RO)},
    {"trip": ("trips", False), "author": ("users", False)}, required=["body"])
res("children", "Child", "Hijos", "Hijo declarado.", {
    **NAMES, "fullName": STR(**RO),
    "birthDate": DATE(readOnly=True, description="Solo para el padre o madre, sus jefes y el Administrador"),
}, {"worker": ("workers", False)}, {"eligibleUntil": DATE(description="Solo para quien ve la fecha de nacimiento"), "eligible": BOOL(),
                                   "declared": BOOL(description="Falso mientras la solicitud está pendiente")})
res("applications", "Application", "Solicitudes", "Solicitud. Los atributos y relaciones extra dependen de `type`.", {
    "type": STR(enum=["itinerary_membership", "itinerary_chief", "driver", "transport_chief", "child_addition", "child_removal", "absence",
                      "itinerary_leave", "itinerary_chief_leave", "driver_leave", "transport_chief_leave", "itinerary_removal"]),
    "status": STR(enum=["pending", "approved", "rejected", "cancelled"], description="En PATCH: approved, rejected o cancelled"),
    "resolutionNote": STR(nullable=True, description="Obligatorio al rechazar"),
    "resolvedAt": DT(nullable=True, **RO),
    **{"child" + k[0].upper() + k[1:]: STR(maxLength=50, writeOnly=True, description="Solo child_addition") for k in NAMES},
    "childBirthDate": DATE(writeOnly=True, description="Solo child_addition"),
    "children": S("array", writeOnly=True, maxItems=10, description="Solo child_addition: varios hijos en una misma solicitud (una solicitud por hijo con el mismo groupId)",
                  items={"type": "object", "required": ["firstName", "firstSurname", "secondSurname", "birthDate"], "properties": {**NAMES, "birthDate": DATE()}}),
    "groupId": STR(nullable=True, readOnly=True, description="Solicitudes enviadas juntas: el id de la primera"),
    "indefinite": BOOL(description="Solo absence: ausencia indefinida, sin fechas"),
    "childFullName": STR(readOnly=True),
    "possibleDuplicate": BOOL(readOnly=True, description="Pendiente de un niño que coincide con otro de la Entidad en fecha, primer nombre y primer apellido"),
    "assigned": BOOL(readOnly=True, description="La creó un superior (asignación o retirada directa)"),
    "startsOn": DATE(nullable=True, description="Solo absence; NULL si es indefinida. El trabajador puede ponerlas después (PATCH sin status)"),
    "endsOn": DATE(nullable=True, description="Solo absence"),
    "observation": STR(nullable=True, description="Solo absence"),
    "createdAt": DT(**RO),
}, {"worker": ("workers", False), "createdBy": ("users", False), "resolvedBy": ("users", False), "itinerary": ("itineraries", False), "stop": ("stops", False),
    "child": ("children", False), "absenceType": ("absence-types", False)}, required=["type"])
res("conversations", "Conversation", "Chats", "Conversación con los jefes o con el desarrollador.",
    {"recipient": STR(enum=["itinerary_chiefs", "transport_chiefs", "developer"], **RO), "guest": BOOL(**RO, description="Abierta sin cuenta"),
     "closed": BOOL(description="En PATCH: cerrar o reabrir"), "guestName": STR(nullable=True), "guestPhone": STR(nullable=True, description="Solo para el Administrador"),
     "body": STR(writeOnly=True, description="Solo al abrirla sin cuenta: primer mensaje"),
     "createdAt": DT(**RO), "lastMessageAt": DT(nullable=True, **RO)},
    {"topic": ("conversation-topics", False), "openedBy": ("users", False), "itinerary": ("itineraries", False), "entity": ("entities", False), "installation": ("installations", False)})
res("conversation-messages", "ConversationMessage", "Chats", "Mensaje de una conversación.", {"body": STR(maxLength=1000), "createdAt": DT(**RO)},
    {"conversation": ("conversations", False), "author": ("users", False)}, required=["body"])
res("notices", "Notice", "Avisos", "Aviso del servidor.", {
    "type": STR(enum=["application_received", "application_resolved", "role_assigned", "role_removed", "resignation", "inactivity_warning", "inactivity_removal",
                      "trip_needs_reassignment", "access_recovery_requested", "password_expiring", "trip_started", "trip_delayed",
                      "trip_incident"], readOnly=True),
    "message": STR(readOnly=True, description="Texto del aviso: qué fue, quién lo hizo y, si se rechazó, el motivo"),
    "payload": {"type": "object", "nullable": True, "readOnly": True, "additionalProperties": True,
                "description": "Datos del aviso (p. ej. direction, delayMinutes, type, stop)"},
    "readAt": DT(nullable=True), "createdAt": DT(**RO),
}, {"application": ("applications", False), "trip": ("trips", False), "accessRecovery": ("access-recoveries", False)})
res("setting-definitions", "SettingDefinition", "Ajustes", "Definición de un ajuste.", {
    "key": STR(), "name": STR(), "description": STR(nullable=True),
    "valueType": STR(enum=["integer", "boolean", "string", "time", "option"]),
    "defaultValue": STR(), "minValue": INT(nullable=True), "maxValue": INT(nullable=True),
    "minSetting": STR(nullable=True, description="Clave del ajuste global que fija el mínimo"),
    "maxSetting": STR(nullable=True, description="Clave del ajuste global que fija el máximo"),
    "level": STR(enum=["app", "entity"], description="app: solo el Administrador; entity: el Administrador fija el de la app y cada Jefe de Transporte el de su Entidad"),
    "userOverridable": BOOL(),
    "options": S("array", items={"type": "object", "properties": {"value": STR(), "name": STR()}}),
})
res("settings", "Setting", "Ajustes", "Valor de un ajuste para toda la app. El id es la clave. Solo el Administrador lo cambia.", {"value": STR(), "editable": BOOL(**RO)}, {"definition": ("setting-definitions", False)}, required=["value"])
res("entity-settings", "EntitySetting", "Ajustes", "Valor de un ajuste de nivel Entidad para una Entidad. El id es la clave.", {
    "value": STR(), "appValue": STR(**RO), "isCustom": BOOL(**RO), "editable": BOOL(**RO)}, {"definition": ("setting-definitions", False)}, required=["value"])
res("user-settings", "UserSetting", "Ajustes", "Valor efectivo de un ajuste para el usuario autenticado. El id es la clave.", {
    "value": STR(), "inheritedValue": STR(readOnly=True, description="El de su Entidad o el de la app"), "isCustom": BOOL(**RO)}, {"definition": ("setting-definitions", False)}, required=["value"])
res("statistics", "Statistic", "Estadísticas", "Resultado de una estadística.", {
    "columns": S("array", items={"type": "object", "properties": {"key": STR(), "label": STR(), "type": STR(enum=["string", "integer", "number", "date", "datetime", "percent"])}}),
    "rows": S("array", items={"type": "object", "additionalProperties": True}),
})
res("app-versions", "AppVersion", "Actualizaciones", "Versión de la app publicada por el Administrador.", {
    "versionName": STR(), "versionCode": INT(), "notes": STR(nullable=True), "mandatory": BOOL(),
    "files": S("array", readOnly=True, items={"type": "object", "properties": {
        "abi": STR(enum=["arm64-v8a", "armeabi-v7a", "universal"]), "downloadUrl": STR(format="uri"), "sizeBytes": INT(), "sha256": STR()}}),
    "publishedAt": DT(),
}, meta={"installedCount": INT(description="Solo para el Administrador")})
res("tokens", "Token", "Autenticación", "Par de tokens JWT.", {
    "username": STR(writeOnly=True),
    "password": STR(format="password", writeOnly=True),
    "deviceName": STR(nullable=True),
    "refreshToken": STR(description="En /tokens/refresh se envía; en las respuestas se devuelve el nuevo"),
    "accessToken": STR(**RO),
    "tokenType": STR(enum=["Bearer"], **RO),
    "expiresIn": INT(description="Segundos de validez del token de acceso (1800)", **RO),
    "refreshExpiresIn": INT(description="Segundos de validez del token de renovación (7776000)", **RO),
})

schemas = {
    "ResourceIdentifier": {"type": "object", "required": ["type", "id"], "properties": {"type": STR(), "id": STR()}},
    "Links": {"type": "object", "properties": {k: STR(format="uri", nullable=True) for k in ["self", "first", "prev", "next", "last"]}},
    "PageMeta": {"type": "object", "properties": {"total": INT(), "page": INT(), "size": INT()}},
    "Position": {"type": "object", "nullable": True, "properties": {"latitude": NUM(), "longitude": NUM(), "at": DT()}},
    "BoundingBox": {"type": "object", "properties": {"south": NUM(), "west": NUM(), "north": NUM(), "east": NUM()}},
    "Error": {"type": "object", "properties": {
        "status": STR(), "code": STR(), "title": STR(), "detail": STR(),
        "source": {"type": "object", "properties": {"pointer": STR(), "parameter": STR()}},
        "meta": {"type": "object", "additionalProperties": True}}},
    "ErrorDocument": {"type": "object", "required": ["errors"], "properties": {"errors": S("array", items={"$ref": "#/components/schemas/Error"})}},
    "AtomicOperation": {"type": "object", "required": ["op"], "properties": {
        "op": STR(enum=["add", "update", "remove"]),
        "ref": {"type": "object", "properties": {"type": STR(), "id": STR(), "relationship": STR()}},
        "data": {"type": "object", "additionalProperties": True}}},
    "AtomicRequest": {"type": "object", "required": ["atomic:operations"], "properties": {
        "atomic:operations": S("array", minItems=1, items={"$ref": "#/components/schemas/AtomicOperation"})}},
    "AtomicResponse": {"type": "object", "properties": {
        "atomic:results": S("array", items={"type": "object", "properties": {"data": {"type": "object", "additionalProperties": True}}})}},
}

for rtype, r in R.items():
    n = r["name"]
    rel_props = {}
    for rel, (t, many) in r["rels"].items():
        ident = {"allOf": [{"$ref": "#/components/schemas/ResourceIdentifier"}], "nullable": True}
        rel_props[rel] = {"type": "object", "properties": {"data": S("array", items={"$ref": "#/components/schemas/ResourceIdentifier"}) if many else ident}}
    res_schema = {"type": "object", "description": r["desc"], "required": ["type"], "properties": {
        "type": STR(enum=[rtype]),
        "id": STR(),
        "attributes": {"type": "object", "properties": r["attrs"]},
    }}
    if r["required"]:
        res_schema["properties"]["attributes"]["required"] = r["required"]
    if rel_props:
        res_schema["properties"]["relationships"] = {"type": "object", "properties": rel_props}
    if r["meta"]:
        res_schema["properties"]["meta"] = {"type": "object", "readOnly": True, "properties": r["meta"]}
    res_schema["properties"]["links"] = {"$ref": "#/components/schemas/Links"}
    schemas[n] = res_schema
    schemas[n + "Document"] = {"type": "object", "required": ["data"], "properties": {
        "data": {"$ref": f"#/components/schemas/{n}"},
        "included": S("array", items={"type": "object", "additionalProperties": True})}}
    schemas[n + "Collection"] = {"type": "object", "required": ["data"], "properties": {
        "data": S("array", items={"$ref": f"#/components/schemas/{n}"}),
        "included": S("array", items={"type": "object", "additionalProperties": True}),
        "links": {"$ref": "#/components/schemas/Links"},
        "meta": {"$ref": "#/components/schemas/PageMeta"}}}

JA = "application/vnd.api+json"


def body(schema):
    return {"required": True, "content": {JA: {"schema": {"$ref": f"#/components/schemas/{schema}"}}}}


def resp(code, schema=None, desc=None):
    d = {"description": desc or {200: "Correcto", 201: "Creado", 204: "Sin contenido"}.get(code, "Respuesta")}
    if schema:
        d["content"] = {JA: {"schema": {"$ref": f"#/components/schemas/{schema}"}}}
    return {str(code): d}


ERR = {
    "400": {"$ref": "#/components/responses/BadRequest"},
    "401": {"$ref": "#/components/responses/Unauthorized"},
    "403": {"$ref": "#/components/responses/Forbidden"},
    "404": {"$ref": "#/components/responses/NotFound"},
    "409": {"$ref": "#/components/responses/Conflict"},
    "415": {"$ref": "#/components/responses/UnsupportedMediaType"},
    "422": {"$ref": "#/components/responses/Unprocessable"},
    "429": {"$ref": "#/components/responses/TooManyRequests"},
}
LIST_PARAMS = [{"$ref": f"#/components/parameters/{p}"} for p in ["PageNumber", "PageSize", "Sort", "Include"]]
ID = {"$ref": "#/components/parameters/Id"}


def op(tag, summary, responses, desc=None, params=None, reqbody=None, public=False, errs=("400", "401", "403", "404", "415", "422")):
    o = {"tags": [tag], "summary": summary}
    if desc:
        o["description"] = desc
    if params:
        o["parameters"] = params
    if reqbody:
        o["requestBody"] = reqbody
    rs = dict(responses)
    for e in errs:
        if public and e in ("401", "403"):
            continue
        rs[e] = ERR[e]
    o["responses"] = rs
    if public:
        o["security"] = []
    return o


def filt(name, desc, schema=None):
    return {"name": f"filter[{name}]", "in": "query", "required": False, "description": desc, "schema": schema or STR()}


paths = {}


def crud(rtype, ops="LCRUD", list_filters=None, notes=None):
    r = R[rtype]
    n, tag = r["name"], r["tag"]
    notes = notes or {}
    coll, item = {}, {}
    if "L" in ops:
        coll["get"] = op(tag, f"Listar {rtype}", resp(200, n + "Collection"), notes.get("L"), LIST_PARAMS + (list_filters or []), errs=("400", "401", "403"))
    if "C" in ops:
        coll["post"] = op(tag, f"Crear {rtype}", resp(201, n + "Document"), notes.get("C"), reqbody=body(n + "Document"), errs=("400", "401", "403", "409", "415", "422"))
    if "R" in ops:
        item["get"] = op(tag, f"Obtener {rtype}", resp(200, n + "Document"), notes.get("R"), [ID, {"$ref": "#/components/parameters/Include"}], errs=("401", "403", "404"))
    if "U" in ops:
        item["patch"] = op(tag, f"Modificar {rtype}", resp(200, n + "Document"), notes.get("U"), [ID], body(n + "Document"), errs=("400", "401", "403", "404", "409", "415", "422"))
    if "D" in ops:
        item["delete"] = op(tag, f"Eliminar {rtype} (borrado lógico)", resp(204), notes.get("D"), [ID], errs=("401", "403", "404", "409"))
    if coll:
        paths[f"/{rtype}"] = coll
    if item:
        paths[f"/{rtype}/{{id}}"] = item


# Autenticación
INSTALLATION = {"name": "X-Installation", "in": "header", "required": True, "schema": STR(), "description": "<id>.<secreto> de la instalación (POST /installations)"}
TOKENS_401 = {"responses": {**resp(201, "TokenDocument"), "401": {"$ref": "#/components/responses/Unauthorized"}, "415": ERR["415"], "422": ERR["422"]}}
paths["/tokens"] = {
    "post": op("Autenticación", "Iniciar sesión", resp(201, "TokenDocument"),
               "Usuario + contraseña. Devuelve token de acceso (30 min) y de renovación (90 días). Con X-Installation, la instalación y sus conversaciones sin cuenta pasan a la cuenta.",
               reqbody=body("TokenDocument"), public=True, errs=("400", "415", "422")) | TOKENS_401,
    "delete": op("Autenticación", "Cerrar sesión en todos los dispositivos", resp(204), "Revoca todos los tokens de renovación de la cuenta.", errs=("401",)),
}
paths["/tokens/refresh"] = {"post": op("Autenticación", "Renovar tokens", resp(201, "TokenDocument"),
                                       "Envía `attributes.refreshToken`. Devuelve un par nuevo y revoca el token de renovación usado (rotación).",
                                       reqbody=body("TokenDocument"), public=True, errs=("400", "415", "422")) | TOKENS_401}
paths["/tokens/current"] = {"delete": op("Autenticación", "Cerrar sesión en este dispositivo", resp(204), errs=("401",))}
paths["/password-policy"] = {"get": op("Cuentas", "Requisitos de la contraseña y del usuario", resp(200, "PasswordPolicyDocument"), "Público.", public=True, errs=())}

# Cuentas
paths["/users"] = {
    "post": op("Cuentas", "Crear la cuenta (paso 1 del registro)", resp(201, "UserDocument"),
               "Público. Cuatro nombres (obligatorios), usuario y contraseña. La primera cuenta es la del Administrador (sin trabajador). "
               "Errores: USERNAME_INVALID, USERNAME_TAKEN, PASSWORD_POLICY.", reqbody=body("UserDocument"), public=True, errs=("400", "409", "415", "422")),
    "get": op("Cuentas", "Listar cuentas", resp(200, "UserCollection"), "Solo el Administrador; incluye las que no se unieron a ninguna Entidad.",
              LIST_PARAMS + [filt("search", "Usuario o nombres"), filt("hasWorker", "true/false", BOOL()), filt("active", "true, false o all")], errs=("400", "401", "403")),
}
paths["/users/{id}"] = {
    "get": op("Cuentas", "Obtener cuenta", resp(200, "UserDocument"), "Solo el Administrador.", [ID], errs=("401", "403", "404")),
    "patch": op("Cuentas", "Activar o desactivar cuenta", resp(200, "UserDocument"), "Solo el Administrador. Atributo `active`.", [ID], body("UserDocument"), errs=("400", "401", "403", "404", "415", "422")),
}
paths["/activations"] = {"post": op("Cuentas", "Activar una cuenta creada por un superior", resp(201, "TokenDocument"),
    "Público. \"Ya me registró un superior\": abreviatura de la Entidad, Pase, código, usuario y contraseña. Devuelve los tokens. "
    "Datos o código incorrectos: 422 ACTIVATION_INVALID (5 intentos por código).", reqbody=body("ActivationDocument"), public=True, errs=("400", "409", "415", "422"))}

# Sin cuenta (instalación)
paths["/installations"] = {"post": op("Sin cuenta", "Registrar la instalación de la app", resp(201, "InstallationDocument"),
    "Público. Devuelve en meta.header el valor de X-Installation (solo esta vez).", reqbody=body("InstallationDocument"), public=True, errs=("400", "415", "422"))}
paths["/installations/{id}"] = {
    "get": op("Sin cuenta", "Obtener instalación", resp(200, "InstallationDocument"), "Solo el Administrador.", [ID], errs=("401", "403", "404")),
    "patch": op("Sin cuenta", "Bloquear o desbloquear una instalación", resp(200, "InstallationDocument"), "Solo el Administrador. Atributo `blocked`.", [ID], body("InstallationDocument"), errs=("400", "401", "403", "404", "415", "422")),
}
paths["/guest/access-recoveries"] = {"post": op("Sin cuenta", "No puedo entrar: pedir ayuda", resp(201, "AccessRecoveryDocument"),
    "Con X-Installation. Usuario olvidado, contraseña o los dos; Entidad, Pase y teléfono. La respuesta no dice si los datos coinciden. Límite por hora (429).",
    [INSTALLATION], body("AccessRecoveryDocument"), public=True, errs=("400", "401", "403", "415", "422", "429"))}
paths["/guest/access-recoveries/{id}"] = {"get": op("Sin cuenta", "Estado de mi solicitud", resp(200, "AccessRecoveryDocument"),
    "Con X-Installation. Si se aprobó y olvidó el usuario, trae `username` (y la solicitud termina).", [ID, INSTALLATION], public=True, errs=("401", "404"))}
paths["/guest/access-recoveries/{id}/password"] = {"post": op("Sin cuenta", "Elegir contraseña nueva tras la aprobación", resp(201, "TokenDocument"),
    "Con X-Installation. Cierra las demás sesiones y devuelve los tokens.", [ID, INSTALLATION], body("AccessRecoveryDocument"), public=True, errs=("400", "401", "404", "409", "415", "422"))}
paths["/access-recoveries"] = {"get": op("Sin cuenta", "Solicitudes \"No puedo entrar\"", resp(200, "AccessRecoveryCollection"),
    "Solo el Administrador. Por defecto, pendientes y aprobadas.", LIST_PARAMS + [filt("status", "Estados separados por comas")], errs=("400", "401", "403"))}
paths["/access-recoveries/{id}"] = {
    "get": op("Sin cuenta", "Obtener solicitud", resp(200, "AccessRecoveryDocument"), "Solo el Administrador.", [ID], errs=("401", "403", "404")),
    "patch": op("Sin cuenta", "Aprobar o rechazar", resp(200, "AccessRecoveryDocument"),
                "Solo el Administrador, tras verificar a la persona por su cuenta. `status`: approved o rejected.", [ID], body("AccessRecoveryDocument"), errs=("400", "401", "403", "404", "409", "415", "422")),
}
paths["/guest/conversations"] = {
    "get": op("Sin cuenta", "Mis conversaciones sin cuenta", resp(200, "ConversationCollection"), "Con X-Installation.", [INSTALLATION], public=True, errs=("401",)),
    "post": op("Sin cuenta", "Escribir al desarrollador sin cuenta", resp(201, "ConversationDocument"),
               "Con X-Installation. `guestName`, `guestPhone`, `body` y la relación `topic` (de destinatario developer). Límite de mensajes por hora (429).",
               [INSTALLATION], body("ConversationDocument"), public=True, errs=("400", "401", "403", "415", "422", "429")),
}
paths["/guest/conversations/{id}/messages"] = {
    "get": op("Sin cuenta", "Mensajes de una conversación sin cuenta", resp(200, "ConversationMessageCollection"), "Con X-Installation.", [ID, INSTALLATION, filt("since", "Posteriores a", DT())], public=True, errs=("401", "404")),
    "post": op("Sin cuenta", "Escribir en una conversación sin cuenta", resp(201, "ConversationMessageDocument"), "Con X-Installation. Falla con CONVERSATION_CLOSED si está cerrada.",
               [ID, INSTALLATION], body("ConversationMessageDocument"), public=True, errs=("400", "401", "403", "404", "409", "415", "422", "429")),
}

# Entidades
crud("entities", notes={"L": "Solo el Administrador ve todas; los demás, la suya.", "C": "Solo el Administrador.", "U": "Solo el Administrador. `active` desactiva o reactiva.", "D": "Solo el Administrador."},
     list_filters=[filt("search", "Abreviatura o nombre"), filt("active", "true, false o all")])
paths["/entities/lookup"] = {"get": op("Entidades", "Buscar una Entidad por su abreviatura", resp(200, "EntityDocument"),
    "Con sesión o con X-Installation. Abreviatura exacta, sin distinguir mayúsculas; devuelve solo abreviatura y nombre. 404 ENTITY_NOT_FOUND.",
    [{"name": "abbreviation", "in": "query", "required": True, "schema": STR()}], errs=("401", "404"))}

# Trabajadores
paths["/workers"] = {
    "post": op("Trabajadores", "Registrar a un trabajador sin teléfono", resp(201, "WorkerDocument"),
               "Jefe de Transporte (en su Entidad), Jefe de itinerario (en su itinerario) o Administrador (con la relación `entity`). Cuatro nombres, Pase, sexo, jerarquía e, "
               "opcionalmente, itinerario y parada. La cuenta queda sin usuario ni contraseña; meta.activationCode trae el código (solo esta vez). 409 PASS_TAKEN.",
               reqbody=body("WorkerDocument"), errs=("400", "401", "403", "409", "415", "422")),
    "get": op("Trabajadores", "Listar trabajadores", resp(200, "WorkerCollection"), "Los de la propia Entidad (todas para el Administrador).",
              LIST_PARAMS + [filt("entity", "Id de Entidad (Administrador)"), filt("itinerary", "Id de itinerario"), filt("stop", "Id de parada"), filt("rank", "Id de jerarquía"),
                             filt("pass", "Pase"), filt("activated", "true/false", BOOL()), filt("active", "true, false o all (Administrador)"),
                             filt("search", "Nombres, usuario o Pase")], errs=("400", "401", "403")),
}
paths["/workers/{id}"] = {
    "get": op("Trabajadores", "Obtener trabajador", resp(200, "WorkerDocument"), params=[ID, {"$ref": "#/components/parameters/Include"}], errs=("401", "403", "404")),
    "patch": op("Trabajadores", "Activar o desactivar trabajador", resp(200, "WorkerDocument"), "Solo el Administrador. Atributo `active` (también la cuenta).", [ID], body("WorkerDocument"),
                errs=("400", "401", "403", "404", "415", "422")),
}
paths["/workers/{id}/activation-codes"] = {"post": op("Trabajadores", "Generar un código de activación nuevo", resp(201, "WorkerDocument"),
    "Los mismos superiores que pueden registrarlo. Anula los anteriores. 409 ALREADY_ACTIVATED.", [ID], errs=("401", "403", "404", "409"))}
paths["/me"] = {
    "get": op("Perfil", "Mi cuenta", resp(200, "UserDocument"), "Incluye `username`. Con include=worker,worker.entity,worker.rank trae el trabajador.", [{"$ref": "#/components/parameters/Include"}], errs=("401",)),
    "patch": op("Perfil", "Modificar mi cuenta", resp(200, "UserDocument"),
                "Usuario, nombres, contraseña y la relación `rank` (jerarquía, sin solicitud). Para cambiar la contraseña hay que enviar `meta.currentPassword` "
                "(salvo tras recuperar el acceso); se cierran las demás sesiones.", reqbody=body("UserDocument"), errs=("400", "401", "409", "415", "422")),
}
paths["/me/worker"] = {"post": op("Perfil", "Unirme a mi Entidad (paso 2 del registro)", resp(201, "WorkerDocument"),
    "`entityAbbreviation`, `pass`, `sex` y la relación `rank`. Obligatorio salvo para el Administrador: hasta entonces la API responde 403 ENTITY_REQUIRED. "
    "Errores: ENTITY_NOT_FOUND, PASS_TAKEN, ALREADY_IN_ENTITY.", reqbody=body("WorkerDocument"), errs=("400", "401", "409", "415", "422"))}
paths["/me/photo"] = {
    "post": {"tags": ["Perfil"], "summary": "Subir foto de perfil",
             "description": "Excepción al formato JSON:API: `multipart/form-data`. JPG o PNG, tamaño máximo según el ajuste `photo_max_kb`.",
             "requestBody": {"required": True, "content": {"multipart/form-data": {"schema": {"type": "object", "required": ["photo"], "properties": {"photo": STR(format="binary")}}}}},
             "responses": {**resp(200, "UserDocument"), "401": ERR["401"], "422": ERR["422"]}},
    "delete": op("Perfil", "Quitar foto de perfil", resp(204), errs=("401",)),
}
paths["/me/settings"] = {
    "get": op("Ajustes", "Mis ajustes", resp(200, "UserSettingCollection"), "Valor efectivo de cada ajuste que el usuario puede personalizar, y el heredado (Entidad o app).", errs=("401",)),
}
paths["/me/settings/{id}"] = {
    "patch": op("Ajustes", "Cambiar un ajuste propio", resp(200, "UserSettingDocument"), "`id` = clave del ajuste.", [ID], body("UserSettingDocument"), errs=("400", "401", "404", "415", "422")),
    "delete": op("Ajustes", "Volver al valor de mi Entidad", resp(204), params=[ID], errs=("401", "404")),
}

# Nomencladores
crud("ranks", notes={"L": "Público: la pantalla de registro la necesita antes de iniciar sesión.", "C": "Solo el Administrador.", "U": "Solo el Administrador.", "D": "Solo el Administrador."},
     list_filters=[filt("name", "Texto contenido en la denominación")])
paths["/ranks"]["get"]["security"] = []
paths["/ranks/{id}"]["get"]["security"] = []
paths["/ranks/{id}/icon"] = {"post": {"tags": ["Nomencladores"], "summary": "Subir icono de jerarquía",
                                      "description": "Solo el Administrador. `multipart/form-data` (PNG o SVG).", "parameters": [ID],
                                      "requestBody": {"required": True, "content": {"multipart/form-data": {"schema": {"type": "object", "required": ["icon"], "properties": {"icon": STR(format="binary")}}}}},
                                      "responses": {**resp(200, "RankDocument"), "401": ERR["401"], "403": ERR["403"], "404": ERR["404"], "422": ERR["422"]}}}
crud("vehicle-types")
crud("absence-types")
crud("conversation-topics", list_filters=[filt("recipient", "itinerary_chiefs, transport_chiefs o developer")])

# Itinerarios
crud("itineraries")
crud("stops", list_filters=[filt("itinerary", "Paradas de un itinerario")])
crud("itinerary-stops", list_filters=[filt("itinerary", "Id de itinerario")], notes={"D": "Falla con STOP_HAS_MEMBERS si hay miembros en esa parada."})
crud("itinerary-chiefs", "LRD", [filt("itinerary", "Id de itinerario"), filt("worker", "Id de trabajador")],
     {"D": "Si lo hace el propio jefe, se registra la solicitud `itinerary_chief_leave` y se avisa a los Jefes de Transporte."})
crud("drivers", "LRD", notes={"D": "Si lo hace el propio chofer, se registra `driver_leave`: se le quita el vehículo y sus viajes futuros quedan para reasignar."})
crud("transport-chiefs", "LRD", notes={"D": "Si lo hace el propio jefe, se registra `transport_chief_leave` y se avisa al Administrador."})
crud("vehicles", list_filters=[filt("vehicleType", "Id de tipo"), filt("driver", "Id de chofer")])

# Viajes
crud("trips", "LCRU", [filt("itinerary", "Id de itinerario"), filt("vehicle", "Id de vehículo"), filt("driver", "Id de chofer"),
                       filt("status", "Uno o varios estados separados por comas"), filt("from", "Salida desde (fecha)", DATE()),
                       filt("to", "Salida hasta (fecha)", DATE()), filt("updatedSince", "Para sincronizar: modificados después de esta fecha", DT()),
                       filt("overloaded", "Solo sobresaturados", BOOL())],
     {"C": "Al crear como `confirmed` se comprueba el solapamiento de vehículo y chofer (TRIP_OVERLAP). Para crear un rango, usar /operations.",
      "U": "Cambios de estado: no se puede cancelar un viaje realizado ni marcar como realizado uno cancelado (TRIP_TRANSITION_NOT_ALLOWED). Al pasar a `confirmed` se comprueba el solapamiento."})
paths["/trips/{id}/passengers"] = {"get": op("Subida", "Pasajeros esperados", resp(200, "TripPassengerCollection"),
                                             "Por parada (en el orden del itinerario) y, dentro de cada una, alfabéticamente por apellidos y nombres.",
                                             [ID, filt("stop", "Solo los de una parada"), filt("direction", "outbound o return")], errs=("401", "403", "404"))}
paths["/trips/{id}/messages"] = {"get": op("Chats", "Mensajes del chat del viaje", resp(200, "TripMessageCollection"),
                                           "Solo mientras el viaje está confirmado.", [ID, filt("since", "Mensajes posteriores a", DT())] + LIST_PARAMS[:2], errs=("401", "403", "404"))}
crud("trip-completions", "LC", [filt("trip", "Id de viaje")], {"C": "Marca el viaje como realizado. Chofer del viaje, Jefes de su itinerario, Jefes de Transporte o Administrador."})
crud("trip-legs", "LCRU", [filt("trip", "Id de viaje"), filt("active", "Solo los que están en curso", BOOL())],
     {"C": "Iniciar recorrido (chofer del viaje, Jefes de su itinerario o Jefes de Transporte; viaje confirmado).",
      "U": "Finalizar recorrido: enviar `endedAt` (se usa la hora del servidor)."})
crud("trip-positions", "LC", [filt("tripLeg", "Id de trayecto (obligatorio)"), filt("since", "Posiciones posteriores a", DT()), filt("worker", "Id del sensor")],
     {"C": "Envía una posición como sensor. Para enviar varias acumuladas sin conexión, usar /operations."})
crud("trip-stop-passes", "L", [filt("tripLeg", "Id de trayecto")])
crud("trip-boardings", "LC", [filt("tripLeg", "Id de trayecto"), filt("worker", "Id de trabajador")])
crud("boarding-passes", "C", notes={"C": "Genera el token para el QR del trabajador autenticado en el trayecto indicado (relación `tripLeg`)."})
crud("trip-messages", "C")

# Hijos y solicitudes
crud("children", "LR", [filt("worker", "Id de trabajador")])
crud("applications", "LCRU", [filt("status", "Estado"), filt("type", "Tipo"), filt("mine", "Solo las propias", BOOL()),
                              filt("toResolve", "Solo las que puedo resolver", BOOL()), filt("worker", "Id de trabajador")],
     {"C": "Los tipos `*_leave` se aprueban automáticamente. `itinerary_removal` solo lo genera el sistema.",
      "U": "Enviar `status`: `approved` o `rejected` (quien puede resolver; nunca el propio solicitante) o `cancelled` (solo el solicitante, mientras esté pendiente)."})

# Chats
crud("conversations", "LCR", [filt("topic", "Id de motivo"), filt("recipient", "itinerary_chiefs, transport_chiefs o developer"), filt("mine", "Solo las que abrí", BOOL())],
     {"C": "Elegir `topic`. Si el motivo es para los Jefes de itinerario, la conversación se asocia al itinerario del trabajador."})
paths["/conversations/{id}/messages"] = {"get": op("Chats", "Mensajes de una conversación", resp(200, "ConversationMessageCollection"),
                                                   params=[ID, filt("since", "Mensajes posteriores a", DT())] + LIST_PARAMS[:2], errs=("401", "403", "404"))}
crud("conversation-messages", "C")

# Avisos y ajustes
crud("notices", "LU", [filt("unread", "Solo no leídos", BOOL()), filt("since", "Creados después de", DT())], {"U": "Marcar como leído (`readAt` con fecha) o como no leído (`null`)."})
crud("setting-definitions", "LR")
crud("settings", "LRU", notes={"U": "Solo el Administrador (valores de toda la app). Se valida contra min, max y opciones."})
paths["/entity-settings"] = {"get": op("Ajustes", "Ajustes de nivel Entidad", resp(200, "EntitySettingCollection"),
    "Los de la propia Entidad; el Administrador indica filter[entity].", [filt("entity", "Id de Entidad (Administrador)")], errs=("400", "401"))}
paths["/entity-settings/{id}"] = {
    "patch": op("Ajustes", "Cambiar un ajuste de la Entidad", resp(200, "EntitySettingDocument"), "Jefe de Transporte de la Entidad o Administrador. `id` = clave.", [ID, filt("entity", "Id de Entidad (Administrador)")], body("EntitySettingDocument"), errs=("400", "401", "403", "404", "415", "422")),
    "delete": op("Ajustes", "Volver al valor de la app", resp(204), params=[ID, filt("entity", "Id de Entidad (Administrador)")], errs=("401", "403", "404")),
}

# Estadísticas
paths["/statistics/{name}"] = {"get": op("Estadísticas", "Obtener una estadística", resp(200, "StatisticDocument"),
                                         "Un solo tipo de periodo: `from`+`to`, `dates` o `last`. Cada uno ve lo de su Entidad (el Administrador, todas o una con `entity`); los filtros se restringen según el rol.",
                                         [{"name": "name", "in": "path", "required": True, "schema": STR(enum=[
                                             "trips-by-status", "punctuality", "duration", "trips-by-driver", "trips-by-vehicle", "overloaded-trips", "occupancy",
                                             "attendance", "children-transported", "workers-distribution", "worker-trips", "applications-summary", "stop-activity",
                                             "stop-pass-times", "distance", "live-trip", "trip-incidents"])},
                                          filt("from", "Desde", DATE()), filt("to", "Hasta", DATE()),
                                          filt("dates", "Fechas explícitas separadas por comas"),
                                          filt("last", "Relativo: número + d/w/m/y (p. ej. 7d, 3m)", STR(pattern=r"^\d+[dwmy]$")),
                                          filt("entity", "Id de Entidad (Administrador)"), filt("level", "overloaded-trips: saturated (por defecto) u overloaded"),
                                          filt("itinerary", "Id de itinerario"), filt("vehicle", "Id de vehículo"), filt("driver", "Id de chofer"),
                                          filt("stop", "Id de parada"), filt("worker", "Id de trabajador"), filt("trip", "Id de viaje (live-trip)"),
                                          filt("by", "Agrupación: itinerary, vehicle, driver (punctuality, occupancy) o itinerary, stop, rank, sex (workers-distribution)")],
                                         errs=("400", "401", "403", "404"))}

# Actualizaciones de la app
paths["/map"] = {"get": op("Mapas", "Configuración del mapa propio", {"200": {"description": "Configuración", "content": {"application/vnd.api+json": {"schema": {
    "type": "object", "properties": {"data": {"type": "object", "properties": {"type": STR(enum=["map-configs"]), "id": STR(), "attributes": {"type": "object", "properties": {
        "tilesUrl": STR(description="Plantilla de las imágenes del mapa ({z}/{x}/{y}); relativa a la dirección del servidor"),
        "minZoom": INT(), "maxZoom": INT(), "downloadMinZoom": INT(), "downloadMaxZoom": INT(),
        "bounds": {"$ref": "#/components/schemas/BoundingBox"},
        "area": {"allOf": [{"$ref": "#/components/schemas/BoundingBox"}], "nullable": True, "description": "Zona de las paradas de la Entidad con margen, para descargarla"}}}}}}}}}}},
    "Límites de Cuba y zona de la Entidad para usar el mapa sin conexión. El Administrador puede indicar `filter[entity]`.", [filt("entity", "Entidad (solo el Administrador)")], errs=("401", "403"))}
MAINT_KEY = {"name": "X-Maintenance-Key", "in": "header", "required": False, "schema": STR(), "description": "Clave de mantenimiento (MAINTENANCE_KEY). Sin ella, hace falta la sesión del Administrador."}
paths["/server-status"] = {"get": op("Mantenimiento", "Estado del servidor", resp(200, "ServerStatusDocument"),
                                     "Administrador o clave de mantenimiento. Funciona aunque la base de datos no esté instalada.", params=[MAINT_KEY], errs=("401", "403"))}
paths["/maintenance-runs"] = {"post": op("Mantenimiento", "Ejecutar una orden de mantenimiento", resp(201, "MaintenanceRunDocument"),
                                         "Administrador o clave de mantenimiento. Para hospedajes sin SSH. Errores: MAINTENANCE_KEY_INVALID, ALREADY_INSTALLED (409).",
                                         params=[MAINT_KEY], reqbody=body("MaintenanceRunDocument"), errs=("401", "403", "409", "415", "422"))}
paths["/app-versions/latest"] = {"get": op("Actualizaciones", "Última versión de la app", resp(200, "AppVersionDocument"),
    "Público. `data` es null si no hay ninguna. Con `filter[currentVersionCode]`, `meta.updateAvailable` y `meta.mandatory`. "
    "Con `filter[abis]` (los que admite el teléfono, por preferencia), `meta.file` trae el APK que le corresponde: el suyo, si no el universal, si no el único publicado.",
    [filt("currentVersionCode", "versionCode instalado", INT()), filt("abis", "p. ej. arm64-v8a,armeabi-v7a")], public=True, errs=("400",))}
paths["/app-versions"] = {
    "get": op("Actualizaciones", "Versiones publicadas", resp(200, "AppVersionCollection"), "Solo el Administrador. `meta.usersWithoutVersion`.", errs=("401", "403")),
    "post": {"tags": ["Actualizaciones"], "summary": "Publicar una versión",
             "description": "Solo el Administrador. `multipart/form-data`. Un APK por tipo de procesador (al menos uno). La versión y el código se leen del propio APK (todos deben coincidir); el versionCode debe ser mayor que el de cualquier versión anterior.",
             "requestBody": {"required": True, "content": {"multipart/form-data": {"schema": {"type": "object", "properties": {
                 "apkArm64": STR(format="binary", description="64 bits"), "apkArm32": STR(format="binary", description="32 bits"), "apkUniversal": STR(format="binary"),
                 "versionName": STR(description="Solo si no se puede leer del APK"), "versionCode": INT(description="Solo si no se puede leer del APK"), "notes": STR(), "mandatory": BOOL()}}}}},
             "responses": {**resp(201, "AppVersionDocument"), "401": ERR["401"], "403": ERR["403"], "422": ERR["422"]}},
}
paths["/app-versions/{id}"] = {"delete": op("Actualizaciones", "Retirar una versión", resp(204), "Solo el Administrador. Borra también el archivo.", [ID], errs=("401", "403", "404"))}

# Atomic
paths["/operations"] = {"post": {"tags": ["Lote"], "summary": "Operaciones atómicas (JSON:API Atomic Operations)",
                                 "description": "Crear viajes por rango, confirmar o desconfirmar en masa, enviar posiciones acumuladas. O se aplican todas o ninguna.",
                                 "requestBody": {"required": True, "content": {'application/vnd.api+json; ext="https://jsonapi.org/ext/atomic"': {"schema": {"$ref": "#/components/schemas/AtomicRequest"}}}},
                                 "responses": {"200": {"description": "Todas aplicadas", "content": {'application/vnd.api+json; ext="https://jsonapi.org/ext/atomic"': {"schema": {"$ref": "#/components/schemas/AtomicResponse"}}}},
                                               "204": {"description": "Todas aplicadas, sin resultados"},
                                               **{k: ERR[k] for k in ("400", "401", "403", "409", "415", "422")}}}}

errresp = lambda d: {"description": d, "content": {JA: {"schema": {"$ref": "#/components/schemas/ErrorDocument"}}}}
spec = {
    "openapi": "3.0.3",
    "info": {
        "title": "MiTransporte API",
        "version": "2.0.0",
        "description": "API de MiTransporte: gestión del transporte de trabajadores.\n\n"
                       "- Formato [JSON:API 1.1](https://jsonapi.org/format/) (`application/vnd.api+json`).\n"
                       "- Autenticación JWT (RFC 7519): token de acceso de 30 min y de renovación de 90 días con rotación.\n"
                       "- Varias Entidades: cada usuario ve y actúa solo sobre la suya; el Administrador, sobre todas. Lo ajeno responde 404.\n"
                       "- Sin cuenta, la app se identifica con la cabecera X-Installation (POST /installations).\n"
                       "- Documentación funcional en `docs/`.",
    },
    "servers": [{"url": "https://{host}/api/v1", "variables": {"host": {"default": "localhost"}}}],
    "security": [{"bearerAuth": []}],
    "tags": [{"name": t} for t in ["Autenticación", "Cuentas", "Sin cuenta", "Entidades", "Trabajadores", "Perfil", "Nomencladores", "Itinerarios y paradas", "Mapas", "Roles", "Vehículos", "Viajes",
                                   "Recorrido", "Subida", "Hijos", "Solicitudes", "Chats", "Avisos", "Ajustes", "Estadísticas", "Actualizaciones", "Lote"]],
    "paths": paths,
    "components": {
        "securitySchemes": {"bearerAuth": {"type": "http", "scheme": "bearer", "bearerFormat": "JWT"}},
        "parameters": {
            "Id": {"name": "id", "in": "path", "required": True, "schema": STR()},
            "PageNumber": {"name": "page[number]", "in": "query", "schema": INT(minimum=1, default=1)},
            "PageSize": {"name": "page[size]", "in": "query", "schema": INT(minimum=1, maximum=100, default=25)},
            "Sort": {"name": "sort", "in": "query", "description": "Campos separados por comas; `-` delante para orden descendente", "schema": STR()},
            "Include": {"name": "include", "in": "query", "description": "Relaciones a incluir, separadas por comas", "schema": STR()},
        },
        "responses": {
            "BadRequest": errresp("Petición mal formada"),
            "Unauthorized": errresp("No autenticado o token inválido"),
            "Forbidden": errresp("Sin permiso"),
            "NotFound": errresp("No encontrado"),
            "Conflict": errresp("Conflicto (duplicado, solapamiento, transición no permitida…)"),
            "UnsupportedMediaType": errresp("Falta el tipo de contenido JSON:API"),
            "Unprocessable": errresp("Error de validación"),
            "TooManyRequests": errresp("Demasiadas solicitudes o mensajes desde ese teléfono en la última hora"),
        },
        "schemas": schemas,
    },
}


class NoAlias(yaml.SafeDumper):
    def ignore_aliases(self, data):
        return True


with open(sys.argv[1], "w") as f:
    yaml.dump(spec, f, Dumper=NoAlias, sort_keys=False, allow_unicode=True, width=120)
print(len(paths), "paths,", len(schemas), "schemas")
