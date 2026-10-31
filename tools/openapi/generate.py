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

NOMEN = {
    "name": STR(maxLength=100, description="Denominación"),
    "description": STR(nullable=True, description="Descripción"),
    "observation": STR(nullable=True, description="Observación"),
}

# type -> (schema name, tag, description, attributes, relationships{name: (type, many)}, meta)
R = {}


def res(rtype, name, tag, desc, attrs, rels=None, meta=None, required=None):
    R[rtype] = dict(name=name, tag=tag, desc=desc, attrs=attrs, rels=rels or {}, meta=meta or {}, required=required or [])


res("workers", "Worker", "Trabajadores", "Trabajador y usuario de la app.", {
    "username": STR(pattern=r"^[a-z][a-z0-9._]{2,29}$", description="Usuario para iniciar sesión, en minúsculas y único (también entre inactivos). Solo se devuelve al propio trabajador y al Administrador."),
    "cardNumber": STR(pattern=r"^\d{11}$", description="Carné de identidad. Se envía al registrarse; solo se devuelve al propio trabajador y al Administrador."),
    "firstName": STR(maxLength=100),
    "lastName": STR(maxLength=150, description="Apellidos"),
    "password": STR(format="password", minLength=8, writeOnly=True),
    "sex": STR(enum=["F", "M"], readOnly=True, description="Calculado a partir del carné"),
    "photoUrl": STR(format="uri", nullable=True, readOnly=True),
    "isAdmin": BOOL(readOnly=True),
    "active": BOOL(description="Falso = borrado lógico. Solo el Administrador puede cambiarlo."),
    "createdAt": DT(**RO),
}, {"rank": ("ranks", False), "itinerary": ("itineraries", False), "stop": ("stops", False)},
    {"childrenCount": INT(description="Hijos con derecho a viajar hoy"),
     "roles": {"type": "object", "properties": {"isTransportChief": BOOL(), "driverId": STR(nullable=True),
                                                "chiefOfItineraries": S("array", items=STR())}}},
    ["username", "cardNumber", "firstName", "lastName", "password"])
res("ranks", "Rank", "Nomencladores", "Jerarquía.", {**NOMEN, "precedence": INT(minimum=1, description="1 = la más alta"), "iconUrl": STR(format="uri", nullable=True, readOnly=True)}, required=["name", "precedence"])
res("vehicle-types", "VehicleType", "Nomencladores", "Tipo de vehículo.", dict(NOMEN), required=["name"])
res("absence-types", "AbsenceType", "Nomencladores", "Tipo de ausencia.", dict(NOMEN), required=["name"])
res("conversation-topics", "ConversationTopic", "Nomencladores", "Motivo de conversación.", {**NOMEN, "recipient": STR(enum=["itinerary_chiefs", "transport_chiefs", "developer"])}, required=["name", "recipient"])
res("itineraries", "Itinerary", "Itinerarios y paradas", "Itinerario.", dict(NOMEN), {"itineraryStops": ("itinerary-stops", True), "chiefs": ("itinerary-chiefs", True)},
    {"departurePoint": {"$ref": "#/components/schemas/ResourceIdentifier"}, "returnPoint": {"$ref": "#/components/schemas/ResourceIdentifier"}, "memberCount": INT()}, ["name"])
res("stops", "Stop", "Itinerarios y paradas", "Parada.", {
    "landmark": STR(maxLength=255, description="Punto de referencia"),
    "street": STR(maxLength=255),
    "crossStreet1": STR(maxLength=255, nullable=True),
    "crossStreet2": STR(maxLength=255, nullable=True),
    "latitude": NUM(minimum=-90, maximum=90),
    "longitude": NUM(minimum=-180, maximum=180),
}, required=["landmark", "street", "latitude", "longitude"])
res("itinerary-stops", "ItineraryStop", "Itinerarios y paradas", "Posición de una parada dentro de un itinerario.", {"position": INT(minimum=1)},
    {"itinerary": ("itineraries", False), "stop": ("stops", False)}, required=["position"])
res("itinerary-chiefs", "ItineraryChief", "Roles", "Jefe de un itinerario.", {"createdAt": DT(**RO)}, {"itinerary": ("itineraries", False), "worker": ("workers", False)})
res("drivers", "Driver", "Roles", "Chofer.", {"createdAt": DT(**RO)}, {"worker": ("workers", False)})
res("transport-chiefs", "TransportChief", "Roles", "Jefe de Transporte.", {"createdAt": DT(**RO)}, {"worker": ("workers", False)})
res("vehicles", "Vehicle", "Vehículos", "Vehículo.", {
    "plate": STR(maxLength=20, description="Matrícula"),
    "seats": INT(minimum=0, description="Asientos sin contar el del chofer"),
    "standingCapacity": INT(minimum=0),
}, {"vehicleType": ("vehicle-types", False), "driver": ("drivers", False)}, {"totalCapacity": INT()}, ["plate", "seats", "standingCapacity"])
res("trips", "Trip", "Viajes", "Viaje planificado.", {
    "departsAt": DT(),
    "returnsAt": DT(description="Debe ser posterior a departsAt"),
    "status": STR(enum=["unconfirmed", "confirmed", "completed", "cancelled"]),
    "updatedAt": DT(**RO),
}, {"itinerary": ("itineraries", False), "vehicle": ("vehicles", False), "driver": ("drivers", False), "completions": ("trip-completions", True), "legs": ("trip-legs", True)},
    {"expectedPassengers": INT(), "expectedChildren": INT(), "totalCapacity": INT(), "overloaded": BOOL(), "needsReassignment": BOOL(),
     "departurePoint": {"$ref": "#/components/schemas/ResourceIdentifier"}, "returnPoint": {"$ref": "#/components/schemas/ResourceIdentifier"}},
    ["departsAt", "returnsAt", "status"])
res("trip-completions", "TripCompletion", "Viajes", "Marca de viaje realizado.", {
    "role": STR(enum=["driver", "itinerary_chief", "transport_chief", "administrator", "system"], readOnly=True),
    "createdAt": DT(**RO),
}, {"trip": ("trips", False), "worker": ("workers", False)})
res("trip-legs", "TripLeg", "Recorrido", "Trayecto de un viaje (salida o regreso).", {
    "direction": STR(enum=["outbound", "return"]),
    "startedAt": DT(**RO),
    "endedAt": DT(nullable=True, description="Enviar en PATCH para finalizar el recorrido"),
    "endReason": STR(enum=["last_stop", "manual"], nullable=True, readOnly=True),
}, {"trip": ("trips", False), "startedBy": ("workers", False)},
    {"currentPosition": {"$ref": "#/components/schemas/Position"}, "activeSensors": INT(),
     "stopPasses": S("array", items={"type": "object", "properties": {"stopId": STR(), "passedAt": DT()}})}, ["direction"])
res("trip-positions", "TripPosition", "Recorrido", "Posición enviada por un sensor.", {
    "latitude": NUM(), "longitude": NUM(), "accuracyM": NUM(nullable=True), "recordedAt": DT(),
}, {"tripLeg": ("trip-legs", False), "worker": ("workers", False)}, required=["latitude", "longitude", "recordedAt"])
res("trip-stop-passes", "TripStopPass", "Recorrido", "Paso del vehículo por una parada (lo genera el servidor).", {"passedAt": DT(**RO)},
    {"tripLeg": ("trip-legs", False), "stop": ("stops", False)})
res("trip-boardings", "TripBoarding", "Subida", "Registro de subida al vehículo.", {
    "method": STR(enum=["automatic", "self", "qr", "manual"]),
    "childrenCount": INT(minimum=0),
    "boardingPassToken": STR(writeOnly=True, description="Obligatorio si method = qr"),
    "boardedAt": DT(),
}, {"tripLeg": ("trip-legs", False), "worker": ("workers", False), "markedBy": ("workers", False)}, required=["method", "childrenCount"])
res("boarding-passes", "BoardingPass", "Subida", "Token temporal para el código QR del trabajador.", {
    "token": STR(readOnly=True), "expiresAt": DT(**RO),
}, {"tripLeg": ("trip-legs", False)})
res("trip-passengers", "TripPassenger", "Subida", "Pasajero esperado en un viaje, en orden de subida.", {
    "boardingOrder": INT(**RO), "eligibleChildren": INT(**RO), "boarded": BOOL(**RO), "boardedChildren": INT(nullable=True, **RO),
    "boardingMethod": STR(enum=["automatic", "self", "qr", "manual"], nullable=True, **RO),
}, {"worker": ("workers", False), "stop": ("stops", False)})
res("trip-messages", "TripMessage", "Chats", "Mensaje del chat de un viaje.", {"body": STR(maxLength=1000), "createdAt": DT(**RO)},
    {"trip": ("trips", False), "worker": ("workers", False)}, required=["body"])
res("children", "Child", "Hijos", "Hijo declarado.", {
    "firstName": STR(), "lastName": STR(),
    "cardNumber": STR(pattern=r"^\d{11}$", readOnly=True, description="Solo para el padre o madre y el Administrador"),
}, {"worker": ("workers", False)}, {"eligibleUntil": DATE(description="Solo para el padre o madre y el Administrador"), "eligible": BOOL(),
                                   "declared": BOOL(description="Falso mientras la solicitud está pendiente")})
res("applications", "Application", "Solicitudes", "Solicitud. Los atributos y relaciones extra dependen de `type`.", {
    "type": STR(enum=["itinerary_membership", "itinerary_chief", "driver", "transport_chief", "rank_change", "child_addition", "child_removal", "absence",
                      "itinerary_leave", "itinerary_chief_leave", "driver_leave", "transport_chief_leave", "itinerary_removal"]),
    "status": STR(enum=["pending", "approved", "rejected", "cancelled"], description="En PATCH: approved, rejected o cancelled"),
    "resolutionNote": STR(nullable=True),
    "resolvedAt": DT(nullable=True, **RO),
    "childFirstName": STR(description="Solo child_addition"),
    "childLastName": STR(description="Solo child_addition"),
    "childCardNumber": STR(pattern=r"^\d{11}$", writeOnly=True, description="Solo child_addition"),
    "startsOn": DATE(description="Solo absence"),
    "endsOn": DATE(description="Solo absence"),
    "observation": STR(nullable=True, description="Solo absence"),
    "createdAt": DT(**RO),
}, {"worker": ("workers", False), "resolvedBy": ("workers", False), "itinerary": ("itineraries", False), "stop": ("stops", False),
    "rank": ("ranks", False), "child": ("children", False), "absenceType": ("absence-types", False)}, required=["type"])
res("conversations", "Conversation", "Chats", "Conversación con los jefes o con el desarrollador.",
    {"recipient": STR(enum=["itinerary_chiefs", "transport_chiefs", "developer"], **RO), "createdAt": DT(**RO), "lastMessageAt": DT(nullable=True, **RO)},
    {"topic": ("conversation-topics", False), "openedBy": ("workers", False), "itinerary": ("itineraries", False)})
res("conversation-messages", "ConversationMessage", "Chats", "Mensaje de una conversación.", {"body": STR(maxLength=1000), "createdAt": DT(**RO)},
    {"conversation": ("conversations", False), "worker": ("workers", False)}, required=["body"])
res("notices", "Notice", "Avisos", "Aviso del servidor.", {
    "type": STR(enum=["application_received", "application_resolved", "resignation", "inactivity_warning", "inactivity_removal", "trip_needs_reassignment", "password_reset_requested"], readOnly=True),
    "readAt": DT(nullable=True), "createdAt": DT(**RO),
}, {"application": ("applications", False), "trip": ("trips", False), "passwordReset": ("password-resets", False)})
res("setting-definitions", "SettingDefinition", "Ajustes", "Definición de un ajuste.", {
    "key": STR(), "name": STR(), "description": STR(nullable=True),
    "valueType": STR(enum=["integer", "boolean", "string", "time", "option"]),
    "defaultValue": STR(), "minValue": INT(nullable=True), "maxValue": INT(nullable=True),
    "minSetting": STR(nullable=True, description="Clave del ajuste global que fija el mínimo"),
    "editableBy": STR(enum=["administrator", "transport_chief"], nullable=True), "userOverridable": BOOL(),
    "options": S("array", items={"type": "object", "properties": {"value": STR(), "name": STR()}}),
})
res("settings", "Setting", "Ajustes", "Valor global de un ajuste. El id es la clave.", {"value": STR(), "editable": BOOL(**RO)}, {"definition": ("setting-definitions", False)}, required=["value"])
res("user-settings", "UserSetting", "Ajustes", "Valor efectivo de un ajuste para el usuario autenticado. El id es la clave.", {"value": STR(), "isCustom": BOOL(**RO)}, {"definition": ("setting-definitions", False)}, required=["value"])
res("statistics", "Statistic", "Estadísticas", "Resultado de una estadística.", {
    "columns": S("array", items={"type": "object", "properties": {"key": STR(), "label": STR(), "type": STR(enum=["string", "integer", "number", "date", "datetime", "percent"])}}),
    "rows": S("array", items={"type": "object", "additionalProperties": True}),
})
res("app-versions", "AppVersion", "Actualizaciones", "Versión de la app publicada por el Administrador.", {
    "versionName": STR(), "versionCode": INT(), "notes": STR(nullable=True), "mandatory": BOOL(),
    "downloadUrl": STR(format="uri"), "sizeBytes": INT(), "sha256": STR(), "publishedAt": DT(),
}, meta={"installedCount": INT(description="Solo para el Administrador")})
res("password-resets", "PasswordReset", "Autenticación", "Solicitud de restablecimiento de contraseña. El teléfono y el código solo los ve el Administrador.", {
    "username": STR(writeOnly=True, description="Solo al solicitarlo. Usuario o carné"),
    "cardNumber": STR(pattern=r"^\d{11}$", writeOnly=True, description="Obsoleto: usar `username`. Lo envían las versiones de la app anteriores al usuario"),
    "phone": STR(description="Teléfono para enviar el código por WhatsApp"),
    "code": STR(readOnly=True), "status": STR(enum=["pending", "sent", "used", "expired", "cancelled"]),
    "failedAttempts": INT(**RO), "expiresAt": DT(**RO), "sentAt": DT(nullable=True, **RO), "usedAt": DT(nullable=True, **RO), "createdAt": DT(**RO),
}, {"worker": ("workers", False)})
res("tokens", "Token", "Autenticación", "Par de tokens JWT.", {
    "username": STR(writeOnly=True, description="Usuario o, como alternativa, carné (11 dígitos)"),
    "cardNumber": STR(pattern=r"^\d{11}$", writeOnly=True, description="Obsoleto: usar `username`. Lo envían las versiones de la app anteriores al usuario"),
    "password": STR(format="password", writeOnly=True),
    "deviceName": STR(nullable=True),
    "refreshToken": STR(description="En /tokens/refresh se envía; en las respuestas se devuelve el nuevo"),
    "resetCode": STR(writeOnly=True, description="Solo en /tokens/reset-code"),
    "mustChangePassword": BOOL(**RO),
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
paths["/tokens"] = {
    "post": op("Autenticación", "Iniciar sesión", resp(201, "TokenDocument"), "Usuario (o carné) + contraseña. Devuelve token de acceso (30 min) y de renovación (90 días).",
               reqbody=body("TokenDocument"), public=True, errs=("400", "415", "422")) | {"responses": {**resp(201, "TokenDocument"), "401": {"$ref": "#/components/responses/Unauthorized"}, "415": ERR["415"], "422": ERR["422"]}},
    "delete": op("Autenticación", "Cerrar sesión en todos los dispositivos", resp(204), "Revoca todos los tokens de renovación del usuario.", errs=("401",)),
}
paths["/tokens/refresh"] = {"post": op("Autenticación", "Renovar tokens", resp(201, "TokenDocument"),
                                       "Envía `attributes.refreshToken`. Devuelve un par nuevo y revoca el token de renovación usado (rotación).",
                                       reqbody=body("TokenDocument"), public=True, errs=("400", "415", "422")) | {"responses": {**resp(201, "TokenDocument"), "401": {"$ref": "#/components/responses/Unauthorized"}, "415": ERR["415"], "422": ERR["422"]}}}
paths["/tokens/reset-code"] = {"post": op("Autenticación", "Entrar con un código de restablecimiento", resp(201, "TokenDocument"),
    "Público. Usuario (o carné) + `resetCode`. El código sirve una vez, caduca (`password_reset_ttl_hours`) y admite 5 intentos. "
    "Cierra las demás sesiones y obliga a cambiar la contraseña: hasta entonces la API responde 403 PASSWORD_CHANGE_REQUIRED salvo en /me.",
    reqbody=body("TokenDocument"), public=True, errs=("400", "415", "422")) | {"responses": {**resp(201, "TokenDocument"), "401": {"$ref": "#/components/responses/Unauthorized"}, "415": ERR["415"], "422": ERR["422"]}}}
paths["/password-resets"] = {
    "post": op("Autenticación", "Pedir restablecer la contraseña", {"202": {"description": "Recibida (la misma respuesta exista o no el usuario)"}},
               "Público. Usuario (o carné) y teléfono. Se genera un código y se avisa al Administrador, que lo envía por WhatsApp.",
               reqbody=body("PasswordResetDocument"), public=True, errs=("400", "415", "422")),
    "get": op("Autenticación", "Solicitudes de restablecimiento", resp(200, "PasswordResetCollection"), "Solo el Administrador. Por defecto, las abiertas.",
              LIST_PARAMS + [filt("status", "Estados separados por comas (por defecto pending,sent)")], errs=("400", "401", "403")),
}
paths["/password-resets/{id}"] = {"patch": op("Autenticación", "Marcar como enviado o cancelar", resp(200, "PasswordResetDocument"),
    "Solo el Administrador. `status`: sent o cancelled.", [ID], body("PasswordResetDocument"), errs=("400", "401", "403", "404", "409", "415", "422"))}
paths["/tokens/current"] = {"delete": op("Autenticación", "Cerrar sesión en este dispositivo", resp(204), errs=("401",))}

# Trabajadores
paths["/workers"] = {
    "post": op("Trabajadores", "Registrarse", resp(201, "WorkerDocument"),
               "Público. Carné, usuario, nombre, apellidos, jerarquía (relación `rank`) y contraseña. El primer usuario registrado pasa a ser Administrador.",
               reqbody=body("WorkerDocument"), public=True, errs=("400", "409", "415", "422")),
    "get": op("Trabajadores", "Listar trabajadores", resp(200, "WorkerCollection"), "Solo datos públicos, salvo para el Administrador.",
              LIST_PARAMS + [filt("itinerary", "Id de itinerario"), filt("stop", "Id de parada"), filt("rank", "Id de jerarquía"),
                             filt("active", "true/false (solo Administrador)", BOOL()), filt("search", "Texto en nombre, apellidos o usuario")], errs=("400", "401", "403")),
}
paths["/workers/{id}"] = {
    "get": op("Trabajadores", "Obtener trabajador", resp(200, "WorkerDocument"), params=[ID, {"$ref": "#/components/parameters/Include"}], errs=("401", "403", "404")),
    "patch": op("Trabajadores", "Activar o desactivar trabajador", resp(200, "WorkerDocument"), "Solo el Administrador. Atributo `active`.", [ID], body("WorkerDocument"),
                errs=("400", "401", "403", "404", "415", "422")),
}
paths["/me"] = {
    "get": op("Perfil", "Mi perfil", resp(200, "WorkerDocument"), "Incluye `username` y `cardNumber`.", [{"$ref": "#/components/parameters/Include"}], errs=("401",)),
    "patch": op("Perfil", "Modificar mi perfil", resp(200, "WorkerDocument"),
                "Usuario, nombre, apellidos o contraseña. El usuario tiene que estar libre (409 USERNAME_TAKEN). Para cambiar la contraseña hay que enviar también `meta.currentPassword`; al cambiarla se revocan todos los tokens de renovación.",
                reqbody=body("WorkerDocument"), errs=("400", "401", "409", "415", "422")),
}
paths["/me/photo"] = {
    "post": {"tags": ["Perfil"], "summary": "Subir foto de perfil",
             "description": "Excepción al formato JSON:API: `multipart/form-data`. JPG o PNG, tamaño máximo según el ajuste `photo_max_kb`.",
             "requestBody": {"required": True, "content": {"multipart/form-data": {"schema": {"type": "object", "required": ["photo"], "properties": {"photo": STR(format="binary")}}}}},
             "responses": {**resp(200, "WorkerDocument"), "401": ERR["401"], "422": ERR["422"]}},
    "delete": op("Perfil", "Quitar foto de perfil", resp(204), errs=("401",)),
}
paths["/me/settings"] = {
    "get": op("Ajustes", "Mis ajustes", resp(200, "UserSettingCollection"), "Valor efectivo de cada ajuste que el usuario puede personalizar.", errs=("401",)),
}
paths["/me/settings/{id}"] = {
    "patch": op("Ajustes", "Cambiar un ajuste propio", resp(200, "UserSettingDocument"), "`id` = clave del ajuste.", [ID], body("UserSettingDocument"), errs=("400", "401", "404", "415", "422")),
    "delete": op("Ajustes", "Volver al valor global", resp(204), params=[ID], errs=("401", "404")),
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
paths["/trips/{id}/passengers"] = {"get": op("Subida", "Pasajeros en orden de subida", resp(200, "TripPassengerCollection"),
                                             "Primero los que suben con niños; luego mujeres y después hombres; dentro de cada grupo, por jerarquía y alfabético.",
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
crud("settings", "LRU", notes={"U": "Solo quien indique `editableBy` en la definición (y siempre el Administrador). Se valida contra min, max y opciones."})

# Estadísticas
paths["/statistics/{name}"] = {"get": op("Estadísticas", "Obtener una estadística", resp(200, "StatisticDocument"),
                                         "Un solo tipo de periodo: `from`+`to`, `dates` o `last`. Los filtros se restringen según el rol.",
                                         [{"name": "name", "in": "path", "required": True, "schema": STR(enum=[
                                             "trips-by-status", "punctuality", "duration", "trips-by-driver", "trips-by-vehicle", "overloaded-trips", "occupancy",
                                             "attendance", "children-transported", "workers-distribution", "worker-trips", "applications-summary", "stop-activity",
                                             "stop-pass-times", "distance", "live-trip"])},
                                          filt("from", "Desde", DATE()), filt("to", "Hasta", DATE()),
                                          filt("dates", "Fechas explícitas separadas por comas"),
                                          filt("last", "Relativo: número + d/w/m/y (p. ej. 7d, 3m)", STR(pattern=r"^\d+[dwmy]$")),
                                          filt("itinerary", "Id de itinerario"), filt("vehicle", "Id de vehículo"), filt("driver", "Id de chofer"),
                                          filt("stop", "Id de parada"), filt("worker", "Id de trabajador"), filt("trip", "Id de viaje (live-trip)"),
                                          filt("by", "Agrupación: itinerary, vehicle, driver (punctuality, occupancy) o itinerary, stop, rank, sex (workers-distribution)")],
                                         errs=("400", "401", "403", "404"))}

# Actualizaciones de la app
paths["/app-versions/latest"] = {"get": op("Actualizaciones", "Última versión de la app", resp(200, "AppVersionDocument"),
    "Público. `data` es null si no hay ninguna. Con `filter[currentVersionCode]`, `meta.updateAvailable` y `meta.mandatory`.",
    [filt("currentVersionCode", "versionCode instalado", INT())], public=True, errs=("400",))}
paths["/app-versions"] = {
    "get": op("Actualizaciones", "Versiones publicadas", resp(200, "AppVersionCollection"), "Solo el Administrador. `meta.workersWithoutVersion`.", errs=("401", "403")),
    "post": {"tags": ["Actualizaciones"], "summary": "Publicar una versión",
             "description": "Solo el Administrador. `multipart/form-data`. El versionCode debe ser mayor que el de cualquier versión anterior.",
             "requestBody": {"required": True, "content": {"multipart/form-data": {"schema": {"type": "object", "required": ["apk", "versionName", "versionCode"], "properties": {
                 "apk": STR(format="binary"), "versionName": STR(), "versionCode": INT(), "notes": STR(), "mandatory": BOOL()}}}}},
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
        "version": "1.0.0",
        "description": "API de MiTransporte: gestión del transporte de trabajadores.\n\n"
                       "- Formato [JSON:API 1.1](https://jsonapi.org/format/) (`application/vnd.api+json`).\n"
                       "- Autenticación JWT (RFC 7519): token de acceso de 30 min y de renovación de 90 días con rotación.\n"
                       "- Documentación funcional en `docs/`.",
    },
    "servers": [{"url": "https://{host}/api/v1", "variables": {"host": {"default": "localhost"}}}],
    "security": [{"bearerAuth": []}],
    "tags": [{"name": t} for t in ["Autenticación", "Trabajadores", "Perfil", "Nomencladores", "Itinerarios y paradas", "Roles", "Vehículos", "Viajes",
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
