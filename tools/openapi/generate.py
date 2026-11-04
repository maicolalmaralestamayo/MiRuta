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


CARD = STR(pattern=r"^\d{11}$", description="Carné de identidad (11 dígitos). De él salen la fecha de nacimiento y el sexo. Solo lo ven la propia persona, el Administrador y quien tenga workers.view_identity_card en su ámbito.")
IMG = STR(format="uri", nullable=True, readOnly=True, description="Imagen subida (POST …/image, multipart); null = la app muestra un ícono")
SCOPE = STR(enum=["own", "itinerary", "entity", "all"])
PERM = {"type": "object", "properties": {"operation": STR(), "scope": SCOPE, "entityId": STR(nullable=True), "itineraryId": STR(nullable=True)}}
MEMBERSHIP = {"type": "object", "properties": {
    "workerId": STR(),
    "entity": {"type": "object", "properties": {"id": STR(), "abbreviation": STR(), "name": STR(), "imageUrl": STR(nullable=True), "workerCount": INT()}},
    "itinerary": {"type": "object", "nullable": True, "properties": {"id": STR(), "name": STR(), "imageUrl": STR(nullable=True), "memberCount": INT()}},
    "stop": {"type": "object", "nullable": True, "properties": {"id": STR(), "landmark": STR(), "street": STR(), "imageUrl": STR(nullable=True)}},
    "roles": S("array", items={"type": "object", "properties": {"id": STR(description="Id de worker-roles"), "roleId": STR(), "name": STR(), "icon": STR(nullable=True),
                                                                "isDefault": BOOL(), "itineraryId": STR(nullable=True), "itineraryName": STR(nullable=True)}})}}

res("users", "User", "Personas", "La persona (docs/11 §11.2 y §11.6): cuenta, nombres, carné, hijos y QR. Pertenece a 0..n Entidades (`workers`).", {
    "username": STR(description="De 2 a 50 caracteres, empieza por letra, al menos 2 letras, sin signos al final ni seguidos, sin palabras reservadas. Único. Solo la propia persona y el Administrador lo ven."),
    "password": STR(format="password", writeOnly=True, description="Según la política de contraseñas (GET /password-policy)"),
    **NAMES,
    "identityCard": CARD,
    "fullName": STR(**RO),
    "sex": STR(enum=["F", "M"], readOnly=True, description="Del carné (penúltimo dígito: par M, impar F)"),
    "birthDate": DATE(readOnly=True, description="Del carné. Con las mismas reglas de visibilidad que el carné"),
    "photoUrl": STR(format="uri", nullable=True, readOnly=True),
    "isAdmin": BOOL(**RO),
    "hasPhone": BOOL(readOnly=True, description="Falso = usa el QR impreso. Pasa a verdadero (y el impreso se anula) al entrar por primera vez en la app"),
    "active": BOOL(description="Falso = cuenta eliminada (borrado lógico). PATCH /users/{id}: workers.delete"),
    "entities": S("array", items=STR(), readOnly=True, description="Abreviaturas de sus Entidades (línea 2 de la tarjeta)"),
    "mustChangePassword": BOOL(readOnly=True, description="La puso otra persona o caducó: solo se permite el perfil propio"),
    "currentPasswordRequired": BOOL(**RO),
    "passwordExpiresAt": DT(nullable=True, **RO),
    "printedQrVersion": INT(readOnly=True, description="Versión del QR impreso (solo la propia persona y el Administrador)"),
    "appVersionCode": INT(nullable=True, readOnly=True, description="Solo para el Administrador"),
    "createdAt": DT(**RO),
}, meta={"permissions": S("array", items=PERM, description="Solo en GET /me: operaciones que puede hacer y dónde"),
         "memberships": S("array", items=MEMBERSHIP, description="Solo en GET /me: sus Entidades con itinerario, parada y roles")},
    required=["firstName", "firstSurname", "secondSurname", "identityCard", "username", "password"])
res("workers", "Worker", "Personas", "Pertenencia de una persona a una Entidad: itinerario y parada (siempre juntos) y roles. Los nombres vienen de la persona.", {
    **NAMES,
    "identityCard": CARD,
    "hasPhone": BOOL(description="Al registrar: si no tiene teléfono se le genera el QR impreso"),
    "username": STR(writeOnly=True, description="POST (registro por el Administrador): opcional, si falta se propone"),
    "password": STR(format="password", writeOnly=True, description="POST: opcional, si falta se propone"),
    "fullName": STR(**RO), "sex": STR(enum=["F", "M"], readOnly=True), "photoUrl": STR(format="uri", nullable=True, readOnly=True),
    "active": BOOL(description="PATCH con workers.deactivate: desactivar o reactivar la pertenencia"),
    "itineraryAssignedAt": DT(nullable=True, **RO),
    "createdAt": DT(**RO),
}, {"user": ("users", False), "entity": ("entities", False), "itinerary": ("itineraries", False), "stop": ("stops", False)},
    {"roles": S("array", items={"type": "object", "properties": {"id": STR(), "roleId": STR(), "name": STR(), "icon": STR(nullable=True), "itineraryId": STR(nullable=True)}}),
     "accountCreated": BOOL(description="Solo al registrar: falso si el carné ya existía (se añadió la Entidad)"),
     "username": STR(description="Solo al registrar y si se creó la cuenta"), "password": STR(description="Solo al registrar y si se creó la cuenta")})
res("entities", "Entity", "Entidades", "Entidad: empresa que usa la app. Se muestra por su abreviatura.", {
    "abbreviation": STR(pattern=r"^[A-Z0-9]{2,15}$", description="Obligatoria y única (también entre inactivas); en mayúsculas"),
    "number": STR(pattern=r"^\d{4}$", nullable=True, description="Opcional; único si se pone"),
    "name": STR(maxLength=150),
    "description": STR(nullable=True), "observation": STR(nullable=True),
    "imageUrl": IMG, "workerCount": INT(**RO),
    "active": BOOL(description="En PATCH: desactivar o reactivar"),
}, required=["abbreviation", "name"])
res("roles", "Role", "Roles", "Rol configurable (docs/11 §11.16). El primero de la lista es el Administrador virtual (`id: admin`, no editable).", {
    "name": STR(maxLength=100), "icon": STR(nullable=True, description="Nombre de ícono Material"),
    "requestable": BOOL(description="Se puede solicitar"), "isDefault": BOOL(description="Se asigna al aprobar la entrada en una Entidad (como mucho uno)"),
    "itineraryScoped": BOOL(description="Se asigna con un itinerario (Jefe de itinerario)"),
    "isAdministrator": BOOL(**RO), "editable": BOOL(**RO),
    "permissions": S("array", items={"type": "object", "properties": {"operation": STR(), "scope": SCOPE}}, description="Con roles.view o roles.manage"),
    "approverRoleIds": S("array", items=STR(), description="Roles que aprueban sus solicitudes (el Administrador siempre puede)"),
    "holderCount": INT(**RO),
}, required=["name"])
res("operations", "Operation", "Roles", "Operación del catálogo fijo (solo lectura).", {
    "key": STR(), "group": STR(), "name": STR(), "scopes": S("array", items=SCOPE)})
res("worker-roles", "WorkerRole", "Roles", "Rol de una persona en una Entidad (con itinerario si el rol es por itinerario).", {
    "roleName": STR(**RO), "icon": STR(nullable=True, readOnly=True), "createdAt": DT(**RO)},
    {"worker": ("workers", False), "role": ("roles", False), "itinerary": ("itineraries", False)})
res("applications", "Application", "Solicitudes", "Solicitud: entrar en una Entidad, itinerario y parada, o un rol.", {
    "type": STR(enum=["entity_membership", "itinerary_membership", "role"]),
    "status": STR(enum=["pending", "approved", "rejected", "cancelled"], description="En PATCH: approved, rejected (con resolutionNote) o cancelled (el solicitante)"),
    "entityAbbreviation": STR(description="entity_membership: en lugar de la relación entity"),
    "resolutionNote": STR(nullable=True, description="Obligatorio al rechazar"),
    "applicantName": STR(**RO), "itineraryName": STR(nullable=True, **RO), "stopLandmark": STR(nullable=True, **RO), "roleName": STR(nullable=True, **RO),
    "canResolve": BOOL(**RO), "resolvedAt": DT(nullable=True, **RO), "createdAt": DT(**RO),
}, {"user": ("users", False), "entity": ("entities", False), "itinerary": ("itineraries", False), "stop": ("stops", False), "role": ("roles", False),
    "createdBy": ("users", False), "resolvedBy": ("users", False)}, required=["type"])
res("absences", "Absence", "Ausencias", "Ausencia declarada sin aprobación: no cuenta como pasajero esperado y pausa la baja por inactividad.", {
    "startsOn": DATE(description="Por defecto, hoy"), "endsOn": DATE(nullable=True, description="null = indefinida"), "indefinite": BOOL(),
    "note": STR(nullable=True), "createdAt": DT(**RO)}, {"worker": ("workers", False), "absenceType": ("absence-types", False)})
res("children", "Child", "Hijos", "Hijo de la persona (docs/11 §11.11), identificado por su carné. Lo pueden tener declarado varios padres.", {
    **NAMES, "identityCard": STR(pattern=r"^\d{11}$", description="Solo sus padres y children.manage all"),
    "fullName": STR(**RO), "sex": STR(enum=["F", "M"], readOnly=True), "birthDate": DATE(**RO),
    "eligibleUntil": DATE(readOnly=True, description="31/08 siguiente al cumpleaños en que alcanza child_max_age"),
    "eligible": BOOL(**RO), "active": BOOL(description="Desactivar / reactivar (reactivar exige derecho)"), "photoUrl": STR(format="uri", nullable=True, readOnly=True),
}, meta={"parents": S("array", items={"type": "object", "additionalProperties": True}, description="Solo sus padres"), "alreadyDeclared": BOOL(description="Al añadir: ya existía y se vinculó")},
    required=["firstName", "firstSurname", "secondSurname", "identityCard"])
res("access-recoveries", "AccessRecovery", "Sin cuenta", "«Olvidé algo»: carné y teléfono. Solo el Administrador la aprueba.", {
    "forgotUsername": BOOL(), "forgotPassword": BOOL(), "identityCard": STR(pattern=r"^\d{11}$", description="Al crearla; después solo el Administrador"),
    "phone": STR(description="Al crearla; después solo el Administrador"),
    "status": STR(enum=["pending", "approved", "rejected", "completed", "expired"], description="En PATCH (Administrador): approved o rejected"),
    "username": STR(readOnly=True, description="Si se aprobó y lo pidió (una vez)"), "password": STR(readOnly=True, description="Contraseña propuesta, si se aprobó y la pidió (una vez)"),
    "matched": BOOL(readOnly=True, description="Solo para el Administrador"),
    "expiresAt": DT(**RO), "resolvedAt": DT(nullable=True, **RO), "createdAt": DT(**RO),
}, {"user": ("users", False), "installation": ("installations", False), "resolvedBy": ("users", False)}, required=["forgotUsername", "forgotPassword", "identityCard", "phone"])
res("installations", "Installation", "Sin cuenta", "Instalación de la app en un teléfono. Al crearla se devuelve su secreto (meta.header) para X-Installation.", {
    "deviceModel": STR(nullable=True), "androidVersion": STR(nullable=True), "appVersionCode": INT(nullable=True),
    "blocked": BOOL(description="access_recoveries.manage"), "createdAt": DT(**RO),
}, {"user": ("users", False)}, {"header": STR(description="Solo al crearla: valor de X-Installation (<id>.<secreto>)")})
res("password-policies", "PasswordPolicy", "Cuentas", "Requisitos actuales de la contraseña y del usuario.", {
    "minLength": INT(), "maxLength": INT(), "requiredClasses": INT(minimum=1, maximum=4), "historyCount": INT(), "expiryDays": INT(), "usernameMinLength": INT(), "usernameMaxLength": INT()})
res("registration-status", "RegistrationStatus", "Cuentas", "Si ya hay Administrador (el primero que se registra lo es).", {"adminExists": BOOL()})
res("username-suggestions", "UsernameSuggestion", "Cuentas", "Usuario propuesto.", {"username": STR()})
res("password-suggestions", "PasswordSuggestion", "Cuentas", "Contraseña propuesta (cumple la política).", {"password": STR()})
res("server-statuses", "ServerStatus", "Mantenimiento", "Estado del servidor (PHP, base de datos, carpetas y tareas programadas).", {
    "apiVersion": STR(), "phpVersion": STR(), "phpSupported": BOOL(description="De 7.2.5 a 8.0"),
    "extensions": {"type": "object", "additionalProperties": BOOL()},
    "php": {"type": "object", "additionalProperties": True}, "serverTime": STR(format="date-time"), "timezone": STR(),
    "database": {"type": "object", "additionalProperties": True}, "storage": {"type": "object", "additionalProperties": True},
    "uploads": {"type": "object", "additionalProperties": True}, "tasks": {"type": "object", "additionalProperties": True}, "commands": S("array", items=STR()),
})
res("maintenance-runs", "MaintenanceRun", "Mantenimiento", "Ejecución de una orden de mantenimiento de la lista.", {
    "command": STR(enum=["install", "migrate", "run-tasks", "clear-cache", "log"]),
    "ok": BOOL(readOnly=True), "output": STR(readOnly=True), "ranAt": STR(format="date-time", readOnly=True)}, required=["command"])
res("vehicle-types", "VehicleType", "Nomencladores", "Tipo de vehículo.", dict(NOMEN), required=["name"])
res("absence-types", "AbsenceType", "Nomencladores", "Tipo de ausencia.", dict(NOMEN), required=["name"])
res("conversation-topics", "ConversationTopic", "Nomencladores", "Motivo de conversación: dirigido a un rol o al desarrollador.",
    {**NOMEN, "recipient": STR(enum=["role", "developer"]), "roleName": STR(nullable=True, **RO)}, {"role": ("roles", False)}, required=["name", "recipient"])
res("itineraries", "Itinerary", "Itinerarios y paradas", "Itinerario de una Entidad (nombre único dentro de ella).", {**NOMEN, "imageUrl": IMG},
    {"entity": ("entities", False), "referenceOutboundLeg": ("trip-legs", False), "referenceReturnLeg": ("trip-legs", False)},
    {"departurePoint": {"$ref": "#/components/schemas/ResourceIdentifier"}, "returnPoint": {"$ref": "#/components/schemas/ResourceIdentifier"},
     "stopIds": S("array", items=STR()), "memberCount": INT()}, ["name"])
res("stops", "Stop", "Itinerarios y paradas", "Parada de una Entidad. En las tarjetas se nombra por su punto de referencia.", {
    "landmark": STR(maxLength=255, description="Punto de referencia"), "street": STR(maxLength=255),
    "crossStreet1": STR(maxLength=255, nullable=True), "crossStreet2": STR(maxLength=255, nullable=True),
    "latitude": NUM(minimum=-90, maximum=90), "longitude": NUM(minimum=-180, maximum=180), "address": STR(**RO), "imageUrl": IMG,
}, {"entity": ("entities", False)}, required=["landmark", "street", "latitude", "longitude"])
res("itinerary-stops", "ItineraryStop", "Itinerarios y paradas", "Posición de una parada dentro de un itinerario.", {"position": INT(minimum=1)},
    {"itinerary": ("itineraries", False), "stop": ("stops", False)}, required=["position"])
res("vehicles", "Vehicle", "Vehículos", "Vehículo de una Entidad (matrícula única dentro de ella).", {
    "plate": STR(maxLength=20), "seats": INT(minimum=0, description="Asientos sin contar el del chofer"), "standingCapacity": INT(minimum=0),
}, {"entity": ("entities", False), "vehicleType": ("vehicle-types", False), "driver": ("workers", False)}, {"totalCapacity": INT()}, ["plate", "seats", "standingCapacity"])
res("trips", "Trip", "Viajes", "Viaje planificado.", {
    "departsAt": DT(), "returnsAt": DT(description="Posterior a departsAt"),
    "status": STR(enum=["unconfirmed", "confirmed", "completed", "cancelled"]),
    "outboundDelayed": BOOL(**RO), "returnDelayed": BOOL(**RO), "outboundDelayMinutes": INT(nullable=True, readOnly=True), "returnDelayMinutes": INT(nullable=True, readOnly=True),
    "updatedAt": DT(**RO),
}, {"itinerary": ("itineraries", False), "vehicle": ("vehicles", False), "driver": ("workers", False), "createdBy": ("users", False)},
    {"expectedPassengers": INT(description="Solo trabajadores: no se espera a ningún niño"),
     "seats": INT(), "totalCapacity": INT(), "occupancyLevel": STR(enum=["normal", "saturated", "overloaded"]),
     "saturated": BOOL(), "overloaded": BOOL(), "needsReassignment": BOOL(),
     "departurePoint": {"$ref": "#/components/schemas/ResourceIdentifier"}, "returnPoint": {"$ref": "#/components/schemas/ResourceIdentifier"}},
    ["departsAt", "returnsAt", "status"])
res("trip-completions", "TripCompletion", "Viajes", "Marca de viaje realizado.", {
    "role": STR(enum=["driver", "manager", "administrator", "system"], readOnly=True), "createdAt": DT(**RO)}, {"trip": ("trips", False), "user": ("users", False)})
res("trip-legs", "TripLeg", "Recorrido", "Trayecto de un viaje (salida o regreso).", {
    "direction": STR(enum=["outbound", "return"]), "startedAt": DT(**RO),
    "endedAt": DT(nullable=True, description="Enviar en PATCH para finalizar el recorrido"),
    "endReason": STR(enum=["last_stop", "manual"], nullable=True, readOnly=True),
}, {"trip": ("trips", False), "startedBy": ("users", False)},
    {"currentPosition": {"$ref": "#/components/schemas/Position"}, "activeSensors": INT(), "deviating": BOOL(),
     "stopPasses": S("array", items={"type": "object", "additionalProperties": True}), "incidents": S("array", items={"type": "object", "additionalProperties": True})}, ["direction"])
res("trip-positions", "TripPosition", "Recorrido", "Posición enviada por un sensor.", {
    "latitude": NUM(), "longitude": NUM(), "accuracyM": NUM(nullable=True), "recordedAt": DT()}, {"tripLeg": ("trip-legs", False), "worker": ("workers", False)},
    required=["latitude", "longitude", "recordedAt"])
res("trip-stop-passes", "TripStopPass", "Recorrido", "Paso del vehículo por una parada (lo genera el servidor).", {
    "passedAt": DT(**RO), "leftAt": DT(nullable=True, **RO), "status": STR(enum=["arrived", "stopped", "not_stopped", "skipped"], readOnly=True)},
    {"tripLeg": ("trip-legs", False), "stop": ("stops", False)})
res("trip-boardings", "TripBoarding", "Subida", "Subida al vehículo: una por persona y trayecto, con los hijos que suben (cada niño, una vez por trayecto).", {
    "method": STR(enum=["automatic", "self", "qr", "manual"], description="automatic solo lo genera el servidor"),
    "qr": STR(writeOnly=True, description="method = qr: texto del QR (MR1… o MRP1…)"),
    "scannedAt": DT(writeOnly=True, description="Hora del escaneo en el teléfono (sincronización sin conexión). Por defecto, ahora"),
    "childIds": S("array", items=STR(), maxItems=20, description="Hijos que suben con la persona (activos y con derecho). En PATCH: corrección"),
    "allowOutsider": BOOL(writeOnly=True, description="Confirmación de quien escanea para dejar subir a alguien de otro itinerario o Entidad (tracking.allow_outsiders)"),
    "childrenCount": INT(**RO),
    "outsider": STR(enum=["itinerary", "entity"], nullable=True, readOnly=True),
    "qrKind": STR(enum=["dynamic", "printed"], nullable=True, readOnly=True),
    "boardedAt": DT(**RO),
}, {"tripLeg": ("trip-legs", False), "worker": ("workers", False), "markedBy": ("users", False)}, {"repeated": BOOL(description="Reintento: el mismo QR ya registró esta subida (200)")}, ["method"])
res("trip-passengers", "TripPassenger", "Subida", "Pasajero de un viaje: los esperados por parada y alfabéticamente; al final, quienes subieron sin ser esperados.", {
    "position": INT(**RO), "expected": BOOL(**RO), "eligibleChildren": INT(nullable=True, readOnly=True, description="Informativo; los niños no se esperan"),
    "boarded": BOOL(**RO), "boardedChildren": INT(nullable=True, **RO), "boardedChildIds": S("array", items=STR(), readOnly=True),
    "boardingMethod": STR(enum=["automatic", "self", "qr", "manual"], nullable=True, **RO), "outsider": STR(enum=["itinerary", "entity"], nullable=True, readOnly=True),
}, {"worker": ("workers", False), "stop": ("stops", False), "tripBoarding": ("trip-boardings", False)})
res("trip-messages", "TripMessage", "Chats", "Mensaje del chat de un viaje.", {"body": STR(maxLength=1000), "createdAt": DT(**RO)},
    {"trip": ("trips", False), "author": ("users", False)}, required=["body"])
res("conversations", "Conversation", "Chats", "Conversación dirigida a un rol o al desarrollador.", {
    "recipient": STR(enum=["role", "developer"], **RO), "guest": BOOL(**RO), "closed": BOOL(description="En PATCH: cerrar o reabrir"),
    "guestName": STR(nullable=True), "guestPhone": STR(nullable=True), "body": STR(writeOnly=True, description="Solo sin cuenta: primer mensaje"),
    "createdAt": DT(**RO), "lastMessageAt": DT(nullable=True, **RO)},
    {"topic": ("conversation-topics", False), "openedBy": ("users", False), "itinerary": ("itineraries", False), "entity": ("entities", False), "installation": ("installations", False)})
res("conversation-messages", "ConversationMessage", "Chats", "Mensaje de una conversación.", {"body": STR(maxLength=1000), "createdAt": DT(**RO)},
    {"conversation": ("conversations", False), "author": ("users", False)}, required=["body"])
res("notices", "Notice", "Avisos", "Aviso del servidor.", {
    "type": STR(enum=["application_received", "application_resolved", "role_assigned", "role_removed", "resignation", "inactivity_warning", "inactivity_removal",
                      "trip_needs_reassignment", "access_recovery_requested", "password_expiring", "trip_started", "trip_delayed", "trip_incident",
                      "entity_added", "entity_removed", "itinerary_assigned", "itinerary_removed"], readOnly=True),
    "message": STR(readOnly=True), "payload": {"type": "object", "nullable": True, "readOnly": True, "additionalProperties": True},
    "readAt": DT(nullable=True), "createdAt": DT(**RO),
}, {"application": ("applications", False), "trip": ("trips", False), "accessRecovery": ("access-recoveries", False)})
res("setting-definitions", "SettingDefinition", "Ajustes", "Definición de un ajuste.", {
    "key": STR(), "name": STR(), "description": STR(nullable=True), "valueType": STR(enum=["integer", "boolean", "string", "time", "option"]),
    "defaultValue": STR(), "minValue": INT(nullable=True), "maxValue": INT(nullable=True), "minSetting": STR(nullable=True), "maxSetting": STR(nullable=True),
    "level": STR(enum=["app", "entity"]), "userOverridable": BOOL(), "itineraryLevel": BOOL(description="Se puede cambiar por itinerario"),
    "stopLevel": BOOL(description="Se puede cambiar por parada de un itinerario"),
    "options": S("array", items={"type": "object", "properties": {"value": STR(), "name": STR()}}),
})
res("settings", "Setting", "Ajustes", "Valor de un ajuste para toda la app. El id es la clave (settings.app).", {"value": STR(), "editable": BOOL(**RO)}, {"definition": ("setting-definitions", False)}, required=["value"])
for t, n, d in [("entity-settings", "EntitySetting", "de una Entidad (settings.entity)"), ("itinerary-settings", "ItinerarySetting", "de un itinerario (settings.itinerary)"),
                ("itinerary-stop-settings", "ItineraryStopSetting", "de una parada de un itinerario (settings.itinerary)")]:
    res(t, n, "Ajustes", f"Valor de un ajuste {d}. El id es la clave.", {
        "value": STR(), "inheritedValue": STR(**RO), "appValue": STR(**RO), "isCustom": BOOL(**RO), "editable": BOOL(**RO)}, {"definition": ("setting-definitions", False)}, required=["value"])
res("user-settings", "UserSetting", "Ajustes", "Valor efectivo de un ajuste de una persona (la propia o, con settings.worker, la de otro). El id es la clave.", {
    "value": STR(), "inheritedValue": STR(readOnly=True), "isCustom": BOOL(**RO)}, {"definition": ("setting-definitions", False), "user": ("users", False)}, required=["value"])
res("statistics", "Statistic", "Estadísticas", "Resultado de una estadística.", {
    "columns": S("array", items={"type": "object", "properties": {"key": STR(), "label": STR(), "type": STR(enum=["string", "integer", "number", "date", "datetime", "percent"])}}),
    "rows": S("array", items={"type": "object", "additionalProperties": True}),
})
res("app-versions", "AppVersion", "Actualizaciones", "Versión de la app publicada.", {
    "versionName": STR(), "versionCode": INT(), "notes": STR(nullable=True), "mandatory": BOOL(),
    "files": S("array", readOnly=True, items={"type": "object", "additionalProperties": True}), "publishedAt": DT(),
}, meta={"installedCount": INT()})
res("tokens", "Token", "Autenticación", "Par de tokens JWT.", {
    "username": STR(writeOnly=True), "password": STR(format="password", writeOnly=True), "deviceName": STR(nullable=True),
    "refreshToken": STR(description="En /tokens/refresh se envía; en las respuestas se devuelve el nuevo"),
    "accessToken": STR(**RO), "tokenType": STR(enum=["Bearer"], **RO), "expiresIn": INT(**RO), "refreshExpiresIn": INT(**RO),
})
# QR (docs/07-algoritmos.md §7.31)
QRTXT = STR(maxLength=2000, description="Texto del QR: `MR1.<cert>.<cert-firma>.<payload>.<firma>` (dinámico) o `MRP1.<json>.<firma>` (impreso)")
res("qr-public-keys", "QrPublicKey", "QR", "Clave pública del servidor (ECDSA P-256) para comprobar certificados y QR impresos sin conexión.", {
    "publicKey": STR(description="SPKI DER en base64 estándar"), "algorithm": STR(enum=["ES256"]), "curve": STR(enum=["P-256"]),
    "format": STR(), "signatureFormat": STR(enum=["DER"]), "clockSkewSeconds": INT(), "certificateDays": INT()})
res("qr-devices", "QrDevice", "QR", "Certificado de la clave del teléfono (30 días). Al pedirlo, si la persona no tenía teléfono, su QR impreso se anula.", {
    "publicKey": STR(description="Clave pública EC P-256 del teléfono, SPKI DER en base64 estándar"),
    "certificate": STR(readOnly=True, description="base64url(json) + \".\" + base64url(firma DER del servidor); json = {\"u\",\"k\",\"e\",\"v\":1}"),
    "expiresAt": DT(**RO), "userId": STR(**RO), "serverPublicKey": STR(**RO)}, required=["publicKey"])
res("printed-qrs", "PrintedQr", "QR", "QR impreso de una persona sin teléfono (no caduca; se anula subiendo la versión).", {
    "qr": STR(readOnly=True, description="MRP1.base64url({\"u\",\"v\"}).base64url(firma DER del servidor)"), "version": INT(**RO),
    **{k: dict(v, readOnly=True) for k, v in NAMES.items()}, "fullName": STR(**RO), "sex": STR(enum=["F", "M"], readOnly=True)}, {"user": ("users", False)})
CHILD_SCAN = {"type": "object", "properties": {"id": STR(), "fullName": STR(), "sex": STR(), "photoUrl": STR(nullable=True),
                                                "alreadyBoarded": BOOL(description="Ya subió con otra persona en este trayecto"), "boardedWithThisPerson": BOOL()}}
SCAN_MEMBERSHIP = {"type": "object", "properties": {"workerId": STR(), "entityId": STR(), "entityAbbreviation": STR(), "itineraryId": STR(nullable=True),
                                                     "itineraryName": STR(nullable=True), "stopId": STR(nullable=True), "stopLandmark": STR(nullable=True), "assignableByQr": BOOL()}}
res("qr-scans", "QrScan", "QR", "Comprobación de un QR escaneado (no gasta el código): tarjeta de la persona y avisos.", {
    "qr": dict(QRTXT, writeOnly=True), "purpose": STR(enum=["boarding", "itinerary_assignment"]), "scannedAt": DT(writeOnly=True),
    "kind": STR(enum=["dynamic", "printed"], readOnly=True), "userId": STR(**RO), **{k: dict(v, readOnly=True) for k, v in NAMES.items()},
    "fullName": STR(**RO), "sex": STR(readOnly=True), "photoUrl": STR(nullable=True, readOnly=True), "entities": S("array", items=STR(), readOnly=True),
    "alreadyUsed": BOOL(readOnly=True, description="El código dinámico ya se usó"),
    "memberships": S("array", items=SCAN_MEMBERSHIP, readOnly=True),
    "outsider": STR(enum=["itinerary", "entity"], nullable=True, readOnly=True, description="Con tripLeg: no es del itinerario o de la Entidad del viaje"),
    "canAllowOutsider": BOOL(nullable=True, readOnly=True), "alreadyBoarded": BOOL(nullable=True, readOnly=True),
    "warning": STR(nullable=True, readOnly=True), "children": S("array", items=CHILD_SCAN, readOnly=True, description="Hijos con derecho (purpose = boarding)"),
}, {"tripLeg": ("trip-legs", False), "user": ("users", False)}, required=["qr", "purpose"])
res("scan-rosters", "ScanRoster", "QR", "Lista para escanear sin conexión en una Entidad.", {
    "generatedAt": DT(), "serverPublicKey": STR(),
    "workers": S("array", items={"type": "object", "properties": {"workerId": STR(), "userId": STR(), "fullName": STR(), "sex": STR(), "photoUrl": STR(nullable=True),
        "itineraryId": STR(nullable=True), "itineraryName": STR(nullable=True), "stopId": STR(nullable=True), "stopLandmark": STR(nullable=True),
        "printedQrVersion": INT(nullable=True, description="null = no tiene QR impreso válido")}}),
    "children": S("array", items={"type": "object", "properties": {"childId": STR(), "fullName": STR(), "sex": STR(), "photoUrl": STR(nullable=True),
        "eligibleUntil": DATE(), "parentUserIds": S("array", items=STR())}}),
}, {"entity": ("entities", False)})
res("itinerary-assignments", "ItineraryAssignment", "QR", "Alta directa en un itinerario con el QR (members.assign_by_qr). El id es el de la pertenencia.", {
    "qr": dict(QRTXT, writeOnly=True), "scannedAt": DT(writeOnly=True), "fullName": STR(**RO),
    "previousItineraryId": STR(nullable=True, readOnly=True), "previousStopId": STR(nullable=True, readOnly=True), "assignedAt": DT(nullable=True, readOnly=True),
}, {"itinerary": ("itineraries", False), "stop": ("stops", False), "worker": ("workers", False), "user": ("users", False)}, {"repeated": BOOL()}, required=["qr"])
res("offline-scans", "OfflineScan", "QR", "Escaneo hecho sin conexión que se sincroniza. Cada uno se procesa por separado.", {
    "purpose": STR(enum=["boarding", "itinerary_assignment"]), "qr": dict(QRTXT, writeOnly=True), "scannedAt": DT(writeOnly=True, description="Hora local del escaneo (obligatoria)"),
    "childIds": S("array", items=STR(), writeOnly=True), "allowOutsider": BOOL(writeOnly=True),
    "status": STR(enum=["accepted", "repeated", "discarded", "rejected"], readOnly=True,
                  description="accepted: registrado; repeated: ya estaba (reintento); discarded: código o subida repetidos; rejected: no válido (ver code)"),
    "code": STR(nullable=True, readOnly=True), "detail": STR(nullable=True, readOnly=True),
}, {"tripLeg": ("trip-legs", False), "itinerary": ("itineraries", False), "stop": ("stops", False), "tripBoarding": ("trip-boardings", False), "worker": ("workers", False)})


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
        item["delete"] = op(tag, f"Eliminar {rtype}", resp(204), notes.get("D"), [ID], errs=("401", "403", "404", "409"))
    if coll:
        paths[f"/{rtype}"] = coll
    if item:
        paths[f"/{rtype}/{{id}}"] = item


# Autenticación
INSTALLATION = {"name": "X-Installation", "in": "header", "required": True, "schema": STR(), "description": "<id>.<secreto> de la instalación (POST /installations)"}
TOKENS_401 = {"responses": {**resp(201, "TokenDocument"), "401": {"$ref": "#/components/responses/Unauthorized"}, "415": ERR["415"], "422": ERR["422"]}}
paths["/tokens"] = {
    "post": op("Autenticación", "Iniciar sesión", resp(201, "TokenDocument"),
               "Usuario + contraseña. Devuelve token de acceso y de renovación. Si la persona no tenía teléfono (`hasPhone` falso), pasa a tenerlo y su QR impreso se anula. "
               "Con X-Installation, la instalación y sus conversaciones sin cuenta pasan a la cuenta.",
               reqbody=body("TokenDocument"), public=True, errs=("400", "415", "422")) | TOKENS_401,
    "delete": op("Autenticación", "Cerrar sesión en todos los dispositivos", resp(204), errs=("401",)),
}
paths["/tokens/refresh"] = {"post": op("Autenticación", "Renovar tokens", resp(201, "TokenDocument"), "Envía `attributes.refreshToken` (rotación).",
                                       reqbody=body("TokenDocument"), public=True, errs=("400", "415", "422")) | TOKENS_401}
paths["/tokens/current"] = {"delete": op("Autenticación", "Cerrar sesión en este dispositivo", resp(204), errs=("401",))}
paths["/password-policy"] = {"get": op("Cuentas", "Requisitos de la contraseña y del usuario", resp(200, "PasswordPolicyDocument"), "Público.", public=True, errs=())}
paths["/registration-status"] = {"get": op("Cuentas", "¿Ya hay Administrador?", resp(200, "RegistrationStatusDocument"), "Público. Solo responde sí o no.", public=True, errs=())}
paths["/username-suggestion"] = {"get": op("Cuentas", "Usuario propuesto", resp(200, "UsernameSuggestionDocument"),
    "Público. primer nombre → +.segundo nombre → +.primer apellido → +.segundo apellido → +.2, .3… (minúsculas, sin tildes, ñ→n), mientras esté ocupado o no sea válido.",
    [{"name": n, "in": "query", "required": n in ("firstName", "firstSurname"), "schema": STR()} for n in ["firstName", "middleName", "firstSurname", "secondSurname"]], public=True, errs=("400",))}
paths["/password-suggestion"] = {"get": op("Cuentas", "Contraseña propuesta", resp(200, "PasswordSuggestionDocument"), "Público. Cumple la política.", public=True, errs=())}

# Personas
paths["/users"] = {
    "post": op("Cuentas", "Registrarse", resp(201, "UserDocument"),
               "Público. Nombres, apellidos, carné, usuario y contraseña; sin Entidad. Si no hay Administrador, el primero lo es (con bloqueo). "
               "Errores: 409 IDENTITY_CARD_TAKEN (texto de docs/11 §11.5), 422 IDENTITY_CARD_INVALID, USERNAME_INVALID, 409 USERNAME_TAKEN, 422 PASSWORD_POLICY.",
               reqbody=body("UserDocument"), public=True, errs=("400", "409", "415", "422")),
    "get": op("Personas", "Listar personas", resp(200, "UserCollection"), "La propia, las de su ámbito de workers.view y los solicitantes visibles (con «all»: todas).",
              LIST_PARAMS + [filt("search", "Nombres, usuario o carné exacto"), filt("active", "true, false o all")], errs=("400", "401", "403")),
}
paths["/users/{id}"] = {
    "get": op("Personas", "Obtener persona", resp(200, "UserDocument"), params=[ID], errs=("401", "403", "404")),
    "patch": op("Personas", "Eliminar o reactivar la cuenta", resp(200, "UserDocument"), "workers.delete. Atributo `active`. 409 LAST_ADMIN.", [ID], body("UserDocument"), errs=("400", "401", "403", "404", "409", "415", "422")),
}
UID = {"name": "userId", "in": "path", "required": True, "schema": STR()}
paths["/users/{userId}/settings"] = {"get": op("Ajustes", "Ajustes de un trabajador", resp(200, "UserSettingCollection"),
    "settings.worker sobre alguna de sus pertenencias (Entidad o itinerario); también la propia persona.", [UID], errs=("401", "403", "404"))}
paths["/users/{userId}/settings/{id}"] = {
    "patch": op("Ajustes", "Cambiar un ajuste de un trabajador", resp(200, "UserSettingDocument"), "settings.worker. `id` = clave.", [UID, ID], body("UserSettingDocument"), errs=("400", "401", "403", "404", "415", "422")),
    "delete": op("Ajustes", "Volver al valor heredado", resp(204), "settings.worker.", [UID, ID], errs=("401", "403", "404")),
}
paths["/me"] = {
    "get": op("Perfil", "Mi persona", resp(200, "UserDocument"), "Con `meta.permissions` y `meta.memberships`.", errs=("401",)),
    "patch": op("Perfil", "Modificar mi persona", resp(200, "UserDocument"),
                "Nombres, carné, usuario y contraseña (con `meta.currentPassword`, salvo must_change_password).", reqbody=body("UserDocument"), errs=("400", "401", "409", "415", "422")),
}
paths["/me/entities"] = {"post": op("Perfil", "Unirme a una Entidad (Administrador)", resp(201, "WorkerDocument"),
    "Solo el Administrador entra sin solicitud: relationships.entity o attributes.entityAbbreviation. Los demás lo solicitan (applications).", reqbody=body("WorkerDocument"), errs=("400", "401", "403", "409", "415", "422"))}
paths["/me/entities/{entityId}"] = {"delete": op("Perfil", "Darme de baja de una Entidad", resp(204), "Borra itinerario, parada y roles en esa Entidad.",
    [{"name": "entityId", "in": "path", "required": True, "schema": STR()}], errs=("401", "404"))}
paths["/me/photo"] = {
    "post": {"tags": ["Perfil"], "summary": "Subir foto de perfil", "description": "`multipart/form-data` (campo `photo`), máx. `photo_max_kb`.",
             "requestBody": {"required": True, "content": {"multipart/form-data": {"schema": {"type": "object", "required": ["photo"], "properties": {"photo": STR(format="binary")}}}}},
             "responses": {**resp(200, "UserDocument"), "401": ERR["401"], "422": ERR["422"]}},
    "delete": op("Perfil", "Quitar foto de perfil", resp(204), errs=("401",)),
}
paths["/me/settings"] = {"get": op("Ajustes", "Mis ajustes", resp(200, "UserSettingCollection"), "Valor efectivo y heredado de cada ajuste personalizable.", errs=("401",))}
paths["/me/settings/{id}"] = {
    "patch": op("Ajustes", "Cambiar un ajuste propio", resp(200, "UserSettingDocument"), "`id` = clave.", [ID], body("UserSettingDocument"), errs=("400", "401", "404", "415", "422")),
    "delete": op("Ajustes", "Volver al valor heredado", resp(204), params=[ID], errs=("401", "404")),
}

# Sin cuenta (instalación)
paths["/installations"] = {"post": op("Sin cuenta", "Registrar la instalación de la app", resp(201, "InstallationDocument"),
    "Público. Devuelve en meta.header el valor de X-Installation (solo esta vez).", reqbody=body("InstallationDocument"), public=True, errs=("400", "415", "422"))}
paths["/installations/{id}"] = {
    "get": op("Sin cuenta", "Obtener instalación", resp(200, "InstallationDocument"), "access_recoveries.manage.", [ID], errs=("401", "403", "404")),
    "patch": op("Sin cuenta", "Bloquear o desbloquear una instalación", resp(200, "InstallationDocument"), "access_recoveries.manage.", [ID], body("InstallationDocument"), errs=("400", "401", "403", "404", "415", "422")),
}
paths["/guest/access-recoveries"] = {"post": op("Sin cuenta", "Olvidé algo", resp(201, "AccessRecoveryDocument"),
    "Con X-Installation. Usuario, contraseña o los dos; carné y teléfono. Límite por hora (429).", [INSTALLATION], body("AccessRecoveryDocument"), public=True, errs=("400", "401", "403", "415", "422", "429"))}
paths["/guest/access-recoveries/{id}"] = {"get": op("Sin cuenta", "Estado de mi solicitud", resp(200, "AccessRecoveryDocument"),
    "Con X-Installation. Si se aprobó: `username` y/o `password` (solo lo pedido) y la solicitud termina.", [ID, INSTALLATION], public=True, errs=("401", "404"))}
paths["/access-recoveries"] = {"get": op("Sin cuenta", "Solicitudes «Olvidé algo»", resp(200, "AccessRecoveryCollection"), "access_recoveries.manage.",
    LIST_PARAMS + [filt("status", "Estados separados por comas")], errs=("400", "401", "403"))}
paths["/access-recoveries/{id}"] = {
    "get": op("Sin cuenta", "Obtener solicitud", resp(200, "AccessRecoveryDocument"), "access_recoveries.manage.", [ID], errs=("401", "403", "404")),
    "patch": op("Sin cuenta", "Aprobar o rechazar", resp(200, "AccessRecoveryDocument"), "access_recoveries.manage. Al aprobar se propone contraseña (must_change_password).",
                [ID], body("AccessRecoveryDocument"), errs=("400", "401", "403", "404", "409", "415", "422")),
}
paths["/guest/conversations"] = {
    "get": op("Sin cuenta", "Mis conversaciones sin cuenta", resp(200, "ConversationCollection"), "Con X-Installation.", [INSTALLATION], public=True, errs=("401",)),
    "post": op("Sin cuenta", "Escribir al desarrollador sin cuenta", resp(201, "ConversationDocument"), "Con X-Installation.", [INSTALLATION], body("ConversationDocument"), public=True, errs=("400", "401", "403", "415", "422", "429")),
}
paths["/guest/conversations/{id}/messages"] = {
    "get": op("Sin cuenta", "Mensajes de una conversación sin cuenta", resp(200, "ConversationMessageCollection"), "Con X-Installation.", [ID, INSTALLATION, filt("since", "Posteriores a", DT())], public=True, errs=("401", "404")),
    "post": op("Sin cuenta", "Escribir en una conversación sin cuenta", resp(201, "ConversationMessageDocument"), "Con X-Installation.", [ID, INSTALLATION], body("ConversationMessageDocument"), public=True, errs=("400", "401", "403", "404", "409", "415", "422", "429")),
}

# Entidades
crud("entities", notes={"L": "Las suyas y las de entities.view.", "C": "entities.manage.", "U": "entities.manage. `active` desactiva o reactiva.", "D": "entities.manage."},
     list_filters=[filt("search", "Abreviatura o nombre"), filt("active", "true, false o all")])
paths["/entities/lookup"] = {"get": op("Entidades", "Buscar una Entidad por su abreviatura", resp(200, "EntityDocument"),
    "Con sesión o con X-Installation. Abreviatura exacta; solo abreviatura y nombre. 404 ENTITY_NOT_FOUND.", [{"name": "abbreviation", "in": "query", "required": True, "schema": STR()}], errs=("401", "404"))}
RESOURCE = {"name": "resource", "in": "path", "required": True, "schema": STR(enum=["entities", "itineraries", "stops"])}
paths["/{resource}/{id}/image"] = {
    "post": {"tags": ["Entidades"], "summary": "Subir imagen (Entidad, itinerario o parada)", "description": "`multipart/form-data` (campo `image`). entities.manage / itineraries.manage / stops.manage.",
             "parameters": [RESOURCE, ID], "requestBody": {"required": True, "content": {"multipart/form-data": {"schema": {"type": "object", "required": ["image"], "properties": {"image": STR(format="binary")}}}}},
             "responses": {"200": {"description": "Correcto"}, "401": ERR["401"], "403": ERR["403"], "404": ERR["404"], "422": ERR["422"]}},
    "delete": op("Entidades", "Quitar imagen", resp(204), params=[RESOURCE, ID], errs=("401", "403", "404")),
}

# Pertenencias
crud("workers", "LCRUD", [filt("entity", "Id de Entidad"), filt("itinerary", "Id de itinerario"), filt("stop", "Id de parada"), filt("user", "Id de persona"),
                          filt("active", "false o all"), filt("search", "Nombres, usuario o carné exacto")],
     {"L": "Las suyas y las de workers.view en su ámbito.",
      "C": "Registro por el Administrador (workers.register): nombres, identityCard, hasPhone, username/password opcionales y relationships.entity (+ itinerary y stop). "
           "Si el carné ya existe, añade la Entidad (`meta.accountCreated` falso). Con relationships.user + entity: entities.assign_members. 409 ALREADY_MEMBER.",
      "U": "`active` (workers.deactivate), relationships itinerary + stop (members.assign) o nombres/identityCard/hasPhone (workers.edit).",
      "D": "Baja de la Entidad: la propia persona o entities.assign_members."})
paths["/workers/{id}/itinerary"] = {"delete": op("Personas", "Baja del itinerario", resp(204), "La propia persona o members.assign. 409 NO_ITINERARY.", [ID], errs=("401", "403", "404", "409"))}
paths["/workers/{id}/printed-qr"] = {"get": op("QR", "QR impreso de un trabajador", resp(200, "PrintedQrDocument"),
    "workers.printed_qr sobre su Entidad o itinerario. Lleva solo el texto del QR y, para imprimir al lado, nombres, apellidos y sexo. "
    "409 PRINTED_QR_NOT_AVAILABLE si la persona usa la app en su teléfono.", [ID], errs=("401", "403", "404", "409"))}
paths["/workers/{id}/printed-qr/revoke"] = {"post": op("QR", "Anular el QR impreso y generar uno nuevo", resp(200, "PrintedQrDocument"),
    "workers.printed_qr. Sube printed_qr_version: las copias anteriores dejan de valer (sin conexión, al sincronizar la lista). Cuerpo opcional; Content-Type JSON:API.", [ID], errs=("401", "403", "404", "409", "415"))}

# Roles
crud("roles", notes={"L": "Cualquiera con sesión (para solicitar roles). Detalles con roles.view.", "C": "roles.manage.", "U": "roles.manage (isDefault: roles.set_default). 403 ROLE_NOT_EDITABLE para `admin`.",
                     "D": "roles.manage. Lo quita a quien lo tenga (aviso role_removed)."})
paths["/operations"] = {"get": op("Roles", "Catálogo de operaciones", resp(200, "OperationCollection"), "roles.view o roles.manage. Fijo: solo consulta.", errs=("401", "403")),
                        "post": {"tags": ["Lote"], "summary": "Operaciones atómicas (JSON:API Atomic Operations)",
                                 "description": "Crear viajes por rango, confirmar o desconfirmar en masa, enviar posiciones acumuladas. O se aplican todas o ninguna.",
                                 "requestBody": {"required": True, "content": {'application/vnd.api+json; ext="https://jsonapi.org/ext/atomic"': {"schema": {"$ref": "#/components/schemas/AtomicRequest"}}}},
                                 "responses": {"200": {"description": "Todas aplicadas", "content": {'application/vnd.api+json; ext="https://jsonapi.org/ext/atomic"': {"schema": {"$ref": "#/components/schemas/AtomicResponse"}}}},
                                               **{k: ERR[k] for k in ("400", "401", "403", "409", "415", "422")}}}}
crud("worker-roles", "LCRD", [filt("worker", "Id de pertenencia"), filt("entity", "Id de Entidad"), filt("role", "Id de rol"), filt("itinerary", "Id de itinerario"), filt("user", "Id de persona")],
     {"C": "roles.assign en la Entidad y tener allí un rol aprobador de ese rol (Administrador: todos). 409 ALREADY_HAS_ROLE.",
      "D": "Darse de baja (la propia persona) o quitarlo (mismo permiso que asignar)."})

# Solicitudes, ausencias e hijos
crud("applications", "LCRU", [filt("status", "Estado"), filt("type", "Tipo"), filt("mine", "Solo las propias", BOOL()), filt("toResolve", "Solo las que puedo resolver", BOOL()),
                              filt("user", "Id de persona"), filt("entity", "Id de Entidad"), filt("itinerary", "Id de itinerario"), filt("role", "Id de rol")],
     {"C": "entity_membership (entity o entityAbbreviation), itinerary_membership (itinerary + stop) o role (role [+ entity] [+ itinerary]).",
      "U": "approved / rejected (resolutionNote) por quien puede resolver; cancelled por el solicitante. 403 SELF_APPROVAL."})
crud("absences", "LCRUD", [filt("worker", "Id de pertenencia"), filt("entity", "Id de Entidad"), filt("itinerary", "Id de itinerario"), filt("user", "Id de persona"),
                           filt("mine", "Solo las propias", BOOL()), filt("on", "Vigentes ese día", DATE())],
     {"C": "La propia persona (relationships.worker si pertenece a varias Entidades) o absences.manage. Sin aprobación."})
crud("children", "LCRUD", [filt("parent", "Id de persona"), filt("active", "true/false"), filt("eligible", "true/false"), filt("entity", "Id de Entidad"), filt("itinerary", "Id de itinerario")],
     {"C": "Por carné. Si ya existe se vincula (`meta.alreadyDeclared`). 409 CHILD_ALREADY_DECLARED, 422 CHILD_NOT_ELIGIBLE.",
      "D": "Desvincula al padre que lo pide; sin padres, borrado lógico."})
paths["/children/{id}/photo"] = {
    "post": {"tags": ["Hijos"], "summary": "Subir foto del hijo", "parameters": [ID], "description": "`multipart/form-data` (campo `photo`).",
             "requestBody": {"required": True, "content": {"multipart/form-data": {"schema": {"type": "object", "required": ["photo"], "properties": {"photo": STR(format="binary")}}}}},
             "responses": {**resp(200, "ChildDocument"), "401": ERR["401"], "403": ERR["403"], "404": ERR["404"], "422": ERR["422"]}},
    "delete": op("Hijos", "Quitar foto del hijo", resp(204), params=[ID], errs=("401", "403", "404")),
}

# Nomencladores, itinerarios, vehículos
crud("vehicle-types", notes={"C": "nomenclators.manage.", "U": "nomenclators.manage.", "D": "nomenclators.manage."})
crud("absence-types", notes={"C": "absence_types.manage.", "U": "absence_types.manage.", "D": "absence_types.manage."})
crud("conversation-topics", list_filters=[filt("recipient", "role o developer"), filt("role", "Id de rol")])
crud("itineraries", list_filters=[filt("entity", "Id de Entidad")], notes={"C": "itineraries.manage.", "U": "itineraries.manage (recorrido de referencia: itineraries.reference_route).", "D": "itineraries.manage."})
crud("stops", list_filters=[filt("itinerary", "Paradas de un itinerario"), filt("entity", "Id de Entidad")], notes={"C": "stops.manage.", "U": "stops.manage.", "D": "stops.manage."})
crud("itinerary-stops", list_filters=[filt("itinerary", "Id de itinerario")], notes={"U": "Ordenar: itineraries.order_stops.", "D": "409 STOP_HAS_MEMBERS si hay miembros en esa parada."})
crud("vehicles", list_filters=[filt("vehicleType", "Id de tipo"), filt("driver", "Id de pertenencia del chofer"), filt("entity", "Id de Entidad")],
     notes={"L": "vehicles.view.", "C": "vehicles.manage.", "U": "vehicles.manage (solo el chofer habitual: vehicles.assign_driver).", "D": "vehicles.manage."})

# Viajes
crud("trips", "LCRUD", [filt("itinerary", "Id de itinerario"), filt("vehicle", "Id de vehículo"), filt("driver", "Id de pertenencia del chofer"),
                        filt("status", "Estados separados por comas"), filt("from", "Salida desde", DATE()), filt("to", "Salida hasta", DATE()),
                        filt("updatedSince", "Modificados después de", DT()), filt("overloaded", "Solo sobresaturados", BOOL())],
     {"L": "trips.view (own = su itinerario) y siempre los que conduce.", "C": "trips.plan. Para un rango de fechas, usar POST /operations.",
      "U": "trips.edit (vehículo, chofer, horas), trips.confirm_cancel, trips.complete.", "D": "trips.delete. 409 TRIP_STARTED si ya empezó."})
paths["/trips/{id}/passengers"] = {"get": op("Subida", "Pasajeros del viaje", resp(200, "TripPassengerCollection"),
    "Esperados por parada y alfabéticamente, con su subida y los hijos que subieron; al final, quienes subieron sin ser esperados (`expected` falso, `outsider`).",
    [ID, filt("stop", "Solo los de una parada"), filt("direction", "outbound o return (por defecto)")], errs=("400", "401", "403", "404"))}
paths["/trips/{id}/messages"] = {"get": op("Chats", "Mensajes del chat del viaje", resp(200, "TripMessageCollection"), "Solo mientras el viaje está confirmado.",
                                           [ID, filt("since", "Posteriores a", DT())] + LIST_PARAMS[:2], errs=("401", "403", "404", "409"))}
crud("trip-completions", "LC", [filt("trip", "Id de viaje")], {"C": "Chofer del viaje o trips.complete."})
crud("trip-legs", "LCRU", [filt("trip", "Id de viaje"), filt("active", "Solo en curso", BOOL())],
     {"C": "Iniciar recorrido: chofer del viaje, tracking.drive o trips.complete.", "U": "Finalizar: enviar `endedAt`."})
crud("trip-positions", "LC", [filt("tripLeg", "Id de trayecto"), filt("since", "Posteriores a", DT()), filt("worker", "Id del sensor")],
     {"C": "Posición como sensor. Para varias acumuladas sin conexión, POST /operations."})
crud("trip-stop-passes", "L", [filt("tripLeg", "Id de trayecto")])
crud("trip-boardings", "LCRUD", [filt("tripLeg", "Id de trayecto"), filt("worker", "Id de pertenencia"), filt("outsider", "itinerary, entity o true")],
     {"C": "Una sola subida por persona y trayecto. `self` («Ya subí», miembros del itinerario), `qr` (texto del QR; chofer o tracking.scan_boarding) o `manual` "
           "(relationships.worker). `childIds`: hijos que suben (cada niño, una vez por trayecto: 409 CHILD_ALREADY_BOARDED). "
           "De otro itinerario o Entidad: hace falta tracking.allow_outsiders (403 OUTSIDER_NOT_ALLOWED) y `allowOutsider: true` (si no, 409 OUTSIDER_CONFIRMATION_REQUIRED con meta.outsider). "
           "Ya subió: 409 ALREADY_BOARDED (con QR impreso, aviso de posible copia). Sincronización: `scannedAt`; si el código ya registró esta subida, 200 con meta.repeated. "
           "Trayecto terminado: 409 LEG_NOT_ACTIVE salvo que `scannedAt` caiga dentro del trayecto o se tenga tracking.fix_passengers. Errores del QR: ver POST /qr-scans.",
      "U": "Corregir los hijos (`childIds`): tracking.fix_passengers; mientras el trayecto está en curso, también quien escanea y la propia persona.",
      "D": "Quitar una subida: tracking.fix_passengers."})
crud("trip-messages", "CD", notes={"D": "El propio mensaje, o el de otro con chat.delete_messages sobre el itinerario del viaje."})

# QR
paths["/qr-public-key"] = {"get": op("QR", "Clave pública del servidor", resp(200, "QrPublicKeyDocument"),
    "Público. ECDSA P-256 (SPKI DER en base64). La app la guarda para comprobar sin conexión certificados y QR impresos.", public=True, errs=())}
paths["/me/qr-devices"] = {"post": op("QR", "Certificar la clave de mi teléfono", resp(201, "QrDeviceDocument"),
    "`publicKey`: clave EC P-256 del almacén seguro (SPKI DER en base64). Devuelve el certificado (30 días; la app lo renueva antes). 422 QR_DEVICE_KEY_INVALID.",
    reqbody=body("QrDeviceDocument"), errs=("400", "401", "415", "422"))}
paths["/qr-scans"] = {"post": op("QR", "Comprobar un QR", resp(200, "QrScanDocument"),
    "No gasta el código. `purpose`: boarding (chofer, tracking.scan_boarding; con relationships.tripLeg dice si es de fuera, si ya subió y qué hijos puede subir) "
    "o itinerary_assignment (members.assign_by_qr). Errores 422: QR_INVALID, QR_SIGNATURE_INVALID, QR_CERTIFICATE_INVALID (no lo firmó el servidor o es de otra persona), "
    "QR_CERTIFICATE_EXPIRED, QR_EXPIRED (|t − hora del escaneo| > 120 s), QR_REVOKED (impreso anulado), QR_USER_INACTIVE, QR_SCAN_TIME_INVALID, QR_SCAN_TOO_OLD (> 7 días).",
    reqbody=body("QrScanDocument"), errs=("400", "401", "403", "404", "415", "422"))}
paths["/itinerary-assignments"] = {"post": op("QR", "Alta directa en un itinerario con el QR", resp(201, "ItineraryAssignmentDocument"),
    "members.assign_by_qr sobre ese itinerario (por defecto, solo el Administrador). La persona debe pertenecer a la Entidad (422 NOT_A_MEMBER). "
    "Cambia itinerario y parada en esa Entidad (pierde el anterior; no pierde jefaturas) y le avisa (itinerary_assigned). "
    "El código se gasta: reintento del mismo alta → 200 con meta.repeated; otro uso → 409 QR_ALREADY_USED.",
    reqbody=body("ItineraryAssignmentDocument"), errs=("400", "401", "403", "404", "409", "415", "422"))}
paths["/offline-scans"] = {"post": {"tags": ["QR"], "summary": "Sincronizar escaneos hechos sin conexión",
    "description": "`data` es una LISTA (máx. 200) de `offline-scans` con `lid` (id local), `purpose`, `qr`, `scannedAt` (hora local del escaneo) y, según el uso, "
                   "relationships.tripLeg (+ childIds, allowOutsider) o itinerary + stop. Cada uno se procesa por separado y la respuesta trae su `status`: "
                   "accepted, repeated (ya estaba: reintento), discarded (QR_ALREADY_USED o ALREADY_BOARDED) o rejected (`code` y `detail`). Nunca falla todo el lote.",
    "requestBody": {"required": True, "content": {JA: {"schema": {"type": "object", "required": ["data"], "properties": {"data": S("array", maxItems=200, items={"$ref": "#/components/schemas/OfflineScan"})}}}}},
    "responses": {**resp(200, "OfflineScanCollection"), **{k: ERR[k] for k in ("400", "401", "415")}}}}
paths["/entities/{id}/scan-roster"] = {"get": op("QR", "Lista para escanear sin conexión", resp(200, "ScanRosterDocument"),
    "tracking.scan_boarding, members.assign_by_qr o tracking.drive en esa Entidad. Trabajadores (con printedQrVersion para comprobar el impreso) e hijos con derecho, y la clave del servidor.",
    [ID], errs=("401", "403", "404"))}

# Hijos, chats
crud("conversations", "LCRU", [filt("topic", "Id de motivo"), filt("recipient", "role o developer"), filt("mine", "Solo las que abrí", BOOL())],
     {"C": "Elegir `topic` (+ relationships.entity si pertenece a varias). Dirigida a un rol: la ven quienes lo tienen en la Entidad (y el itinerario) con chat.role_conversations.",
      "U": "Cerrar o reabrir (`closed`)."})
paths["/conversations/{id}/messages"] = {"get": op("Chats", "Mensajes de una conversación", resp(200, "ConversationMessageCollection"),
                                                   params=[ID, filt("since", "Posteriores a", DT())] + LIST_PARAMS[:2], errs=("401", "403", "404"))}
crud("conversation-messages", "CD", notes={"D": "El propio mensaje, o el de otro con chat.delete_messages sobre la Entidad (o el itinerario) de la conversación."})

# Avisos y ajustes
crud("notices", "LU", [filt("unread", "Solo no leídos", BOOL()), filt("since", "Creados después de", DT())], {"U": "Marcar como leído (`readAt`) o no leído (`null`)."})
crud("setting-definitions", "LR")
crud("settings", "LRU", notes={"U": "settings.app."})
ENT = filt("entity", "Id de Entidad (si pertenece a varias o con «all»)")
paths["/entity-settings"] = {"get": op("Ajustes", "Ajustes de una Entidad", resp(200, "EntitySettingCollection"), params=[ENT], errs=("400", "401", "403"))}
paths["/entity-settings/{id}"] = {
    "patch": op("Ajustes", "Cambiar un ajuste de la Entidad", resp(200, "EntitySettingDocument"), "settings.entity. `id` = clave.", [ID, ENT], body("EntitySettingDocument"), errs=("400", "401", "403", "404", "415", "422")),
    "delete": op("Ajustes", "Volver al valor de la app", resp(204), params=[ID, ENT], errs=("401", "403", "404")),
}
ITF = filt("itinerary", "Id de itinerario (obligatorio)")
paths["/itinerary-settings"] = {"get": op("Ajustes", "Ajustes de un itinerario", resp(200, "ItinerarySettingCollection"), "Los de nivel itinerario. Miembros de la Entidad o itineraries.view.", [ITF], errs=("400", "401", "403", "404"))}
paths["/itinerary-settings/{id}"] = {
    "patch": op("Ajustes", "Cambiar un ajuste del itinerario", resp(200, "ItinerarySettingDocument"), "settings.itinerary.", [ID, ITF], body("ItinerarySettingDocument"), errs=("400", "401", "403", "404", "415", "422")),
    "delete": op("Ajustes", "Volver al heredado", resp(204), params=[ID, ITF], errs=("401", "403", "404")),
}
ISF = filt("itineraryStop", "Id de itinerary-stops (obligatorio)")
paths["/itinerary-stop-settings"] = {"get": op("Ajustes", "Ajustes de una parada del itinerario", resp(200, "ItineraryStopSettingCollection"), params=[ISF], errs=("400", "401", "403", "404"))}
paths["/itinerary-stop-settings/{id}"] = {
    "patch": op("Ajustes", "Cambiar un ajuste de la parada", resp(200, "ItineraryStopSettingDocument"), "settings.itinerary.", [ID, ISF], body("ItineraryStopSettingDocument"), errs=("400", "401", "403", "404", "415", "422")),
    "delete": op("Ajustes", "Volver al heredado", resp(204), params=[ID, ISF], errs=("401", "403", "404")),
}

# Estadísticas
paths["/statistics/{name}"] = {"get": op("Estadísticas", "Obtener una estadística", resp(200, "StatisticDocument"),
    "Un solo tipo de periodo: `from`+`to`, `dates` o `last`. statistics.view por ámbito; sin él, quien conduce las de sus viajes y cualquiera las suyas (worker-trips, live-trip). "
    "`outsider-travellers`: trabajadores que viajan fuera de su itinerario o de su Entidad. `children-transported`: niños que viajan realmente (marcados al subir), distintos y con derecho declarados.",
    [{"name": "name", "in": "path", "required": True, "schema": STR(enum=[
        "trips-by-status", "punctuality", "duration", "trips-by-driver", "trips-by-vehicle", "overloaded-trips", "occupancy", "attendance", "children-transported",
        "workers-distribution", "worker-trips", "applications-summary", "stop-activity", "stop-pass-times", "distance", "live-trip", "trip-incidents", "outsider-travellers"])},
     filt("from", "Desde", DATE()), filt("to", "Hasta", DATE()), filt("dates", "Fechas separadas por comas"),
     filt("last", "Número + d/w/m/y (p. ej. 7d)", STR(pattern=r"^\d+[dwmy]$")), filt("entity", "Id de Entidad"), filt("level", "overloaded-trips: saturated u overloaded"),
     filt("itinerary", "Id de itinerario"), filt("vehicle", "Id de vehículo"), filt("driver", "Id de pertenencia del chofer"), filt("stop", "Id de parada"),
     filt("worker", "Id de pertenencia"), filt("trip", "Id de viaje (live-trip)"),
     filt("by", "itinerary, vehicle, driver (punctuality, occupancy) o itinerary, stop, sex (workers-distribution)")],
    errs=("400", "401", "403", "404"))}

# Mapa, mantenimiento y actualizaciones
paths["/map"] = {"get": op("Mapas", "Configuración del mapa", {"200": {"description": "Configuración", "content": {JA: {"schema": {"type": "object", "additionalProperties": True}}}}},
    "Límites de Cuba y zona de la Entidad para usar el mapa sin conexión.", [filt("entity", "Entidad")], errs=("401", "403"))}
MAINT_KEY = {"name": "X-Maintenance-Key", "in": "header", "required": False, "schema": STR(), "description": "Clave de mantenimiento (MAINTENANCE_KEY). Sin ella, maintenance.run."}
paths["/server-status"] = {"get": op("Mantenimiento", "Estado del servidor", resp(200, "ServerStatusDocument"), "maintenance.run o clave de mantenimiento.", params=[MAINT_KEY], errs=("401", "403"))}
paths["/maintenance-runs"] = {"post": op("Mantenimiento", "Ejecutar una orden de mantenimiento", resp(201, "MaintenanceRunDocument"), "maintenance.run o clave de mantenimiento.",
                                         params=[MAINT_KEY], reqbody=body("MaintenanceRunDocument"), errs=("401", "403", "409", "415", "422"))}
paths["/app-versions/latest"] = {"get": op("Actualizaciones", "Última versión de la app", resp(200, "AppVersionDocument"), "Público.",
    [filt("currentVersionCode", "versionCode instalado", INT()), filt("abis", "p. ej. arm64-v8a,armeabi-v7a")], public=True, errs=("400",))}
paths["/app-versions"] = {
    "get": op("Actualizaciones", "Versiones publicadas", resp(200, "AppVersionCollection"), "app_versions.manage.", errs=("401", "403")),
    "post": {"tags": ["Actualizaciones"], "summary": "Publicar una versión", "description": "app_versions.manage. `multipart/form-data`.",
             "requestBody": {"required": True, "content": {"multipart/form-data": {"schema": {"type": "object", "properties": {
                 "apkArm64": STR(format="binary"), "apkArm32": STR(format="binary"), "apkUniversal": STR(format="binary"), "notes": STR(), "mandatory": BOOL()}}}}},
             "responses": {**resp(201, "AppVersionDocument"), "401": ERR["401"], "403": ERR["403"], "422": ERR["422"]}},
}
paths["/app-versions/{id}"] = {"delete": op("Actualizaciones", "Retirar una versión", resp(204), "app_versions.manage.", [ID], errs=("401", "403", "404"))}


errresp = lambda d: {"description": d, "content": {JA: {"schema": {"$ref": "#/components/schemas/ErrorDocument"}}}}
spec = {
    "openapi": "3.0.3",
    "info": {
        "title": "MiRuta API",
        "version": "3.0.0",
        "description": "API de MiRuta: gestión del transporte de trabajadores.\n\n"
                       "- Formato [JSON:API 1.1](https://jsonapi.org/format/) (`application/vnd.api+json`).\n"
                       "- Autenticación JWT (RFC 7519): token de acceso de 30 min y de renovación de 90 días con rotación.\n"
                       "- La persona pertenece a 0..n Entidades. Lo que puede hacer lo dan sus roles configurables (operación + ámbito: own, itinerary, entity, all; GET /me → meta.permissions). El Administrador puede todo.\n"
                       "- QR de la persona (dinámico MR1 y impreso MRP1): ver la etiqueta QR y docs/07-algoritmos.md §7.31.\n"
                       "- Sin cuenta, la app se identifica con la cabecera X-Installation (POST /installations).\n"
                       "- Documentación funcional en `docs/`.",
    },
    "servers": [{"url": "https://{host}/api/v1", "variables": {"host": {"default": "localhost"}}}],
    "security": [{"bearerAuth": []}],
    "tags": [{"name": t} for t in ["Autenticación", "Cuentas", "Sin cuenta", "Personas", "Perfil", "Entidades", "Roles", "Solicitudes", "Ausencias", "Hijos", "Nomencladores", "Itinerarios y paradas", "Mapas", "Vehículos", "Viajes",
                                   "Recorrido", "Subida", "QR", "Chats", "Avisos", "Ajustes", "Estadísticas", "Mantenimiento", "Actualizaciones", "Lote"]],
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
