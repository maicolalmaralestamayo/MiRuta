"""Genera docs/openapi.yaml (API de la próxima versión, Laravel 12).

Uso: python3 tools/openapi/generate.py docs/openapi.yaml
Requiere PyYAML. Editar este script y regenerar, en lugar de editar el YAML a mano.
El detalle de cada ruta (reglas, errores, ejemplos) está en docs/13-api-proxima-version.md.
"""
import sys

import yaml

JA = "application/vnd.api+json"
S = lambda t, **kw: dict(type=t, **kw)
STR = lambda **kw: S("string", **kw)
INT = lambda **kw: S("integer", **kw)
NUM = lambda **kw: S("number", **kw)
BOOL = lambda **kw: S("boolean", **kw)
DT = lambda **kw: STR(format="date-time", **kw)
DATE = lambda **kw: STR(format="date", **kw)
RO = dict(readOnly=True)
OBJ = lambda **kw: S("object", additionalProperties=True, **kw)

NAMES = {
    "firstName": STR(maxLength=50), "middleName": STR(maxLength=50, nullable=True), "firstSurname": STR(maxLength=50),
    "secondSurname": STR(maxLength=50),
}
NOMEN = {"name": STR(maxLength=100), "description": STR(nullable=True), "observation": STR(nullable=True), "active": BOOL()}
CARD = STR(pattern=r"^\d{11}$", description="Carné de identidad. Lo ven la persona, el Administrador y el Jefe de su itinerario.")
IMG = STR(format="uri", nullable=True, readOnly=True, description="Imagen subida (POST …/image); null = ícono")

# tipo -> (nombre del esquema, atributos, relaciones {nombre: tipo}, descripción)
R = {}


def res(rtype, name, attrs, rels=None, desc=""):
    R[rtype] = dict(name=name, attrs=attrs, rels=rels or {}, desc=desc)


res("users", "User", {**NAMES, "username": STR(), "fullName": STR(**RO), "sex": STR(enum=["F", "M"], **RO), "photoUrl": IMG,
    "isAdmin": BOOL(**RO), "entities": S("array", items=STR(), **RO), "identityCard": CARD, "birthDate": DATE(**RO),
    "password": STR(writeOnly=True), "mustChangePassword": BOOL(**RO), "currentPasswordRequired": BOOL(**RO),
    "passwordExpiresAt": DT(nullable=True, **RO), "appVersionCode": INT(nullable=True, **RO), "createdAt": DT(**RO)},
    desc="Persona. GET /me añade meta.role, meta.chiefItineraryId y meta.memberships.")
res("workers", "Worker", {"active": BOOL(), "createdAt": DT(**RO)},
    {"user": "users", "entity": "entities"}, "La persona en una Entidad. meta.itineraries: sus itinerarios en ella.")
res("worker-itineraries", "WorkerItinerary", {"isChief": BOOL(), "createdAt": DT(**RO)},
    {"user": "users", "worker": "workers", "itinerary": "itineraries", "stop": "stops"},
    "La persona en un itinerario de una de sus Entidades (varios por Entidad), con su parada y si es Jefe.")
res("management-summaries", "ManagementSummary", {"entities": INT(), "itineraries": INT(), "stops": INT(), "workers": INT(),
    "pendingEntityApplications": INT(), "pendingItineraryApplications": INT(), "nomenclators": OBJ()},
    desc="Cantidades de las tarjetas de Gestión.")
res("entities", "Entity", {"abbreviation": STR(maxLength=15), "number": STR(pattern=r"^\d{4}$", nullable=True), "name": STR(maxLength=150),
    "description": STR(nullable=True), "observation": STR(nullable=True), "imageUrl": IMG, "active": BOOL()})
res("itineraries", "Itinerary", {"name": STR(maxLength=100), "description": STR(nullable=True), "observation": STR(nullable=True),
    "imageUrl": IMG, "active": BOOL()}, {"entity": "entities"})
res("stops", "Stop", {"landmark": STR(), "street": STR(), "crossStreet1": STR(nullable=True), "crossStreet2": STR(nullable=True),
    "latitude": NUM(), "longitude": NUM(), "imageUrl": IMG, "active": BOOL()}, desc="Parada (compartida entre itinerarios). meta.itineraries.")
res("itinerary-stops", "ItineraryStop", {"position": INT(minimum=1)}, {"itinerary": "itineraries", "stop": "stops"})
res("applications", "Application", {"type": STR(enum=["entidad", "itinerario"]), "status": STR(enum=["pendiente", "aprobada", "rechazada"]),
    "entityAbbreviation": STR(writeOnly=True), "resolutionNote": STR(nullable=True), "resolvedAt": DT(nullable=True, **RO),
    "seenAt": DT(nullable=True, **RO), "createdAt": DT(**RO)},
    {"user": "users", "entity": "entities", "itinerary": "itineraries", "stop": "stops", "denialReason": "denial-reasons", "resolvedBy": "users"})
res("absences", "Absence", {"startsOn": DATE(), "endsOn": DATE(nullable=True), "indefinite": BOOL(**RO), "note": STR(nullable=True)},
    {"worker": "workers", "absenceType": "absence-types"})
res("children", "Child", {**NAMES, "identityCard": CARD, "fullName": STR(**RO), "sex": STR(**RO), "birthDate": DATE(**RO),
    "eligibleUntil": DATE(**RO), "eligible": BOOL(**RO), "active": BOOL(), "photoUrl": IMG}, {"parent": "users"})
res("vehicle-types", "VehicleType", {**NOMEN, "seats": INT(minimum=0), "standing": INT(minimum=0), "total": INT(**RO)})
res("absence-types", "AbsenceType", dict(NOMEN))
res("conversation-topics", "ConversationTopic", dict(NOMEN))
res("denial-reasons", "DenialReason", {**NOMEN, "applicationType": STR(enum=["entidad", "itinerario"], nullable=True)})
res("detention-causes", "DetentionCause", dict(NOMEN))
res("trips", "Trip", {"direction": STR(enum=["ida", "regreso"]), "date": DATE(), "departureTime": STR(pattern=r"^\d{2}:\d{2}$"),
    "departsAt": DT(**RO), "status": STR(enum=["planificado", "en_ejecucion", "terminado", "cancelado"]), "statusChangedAt": DT(**RO),
    "finishReason": STR(nullable=True, **RO), "observation": STR(nullable=True), "vehicleState": STR(enum=["detenido", "en_movimiento"], nullable=True, **RO),
    "vehicleStateSince": DT(nullable=True, **RO), "vehicleAtStop": BOOL(**RO), "nextStopIndex": INT(**RO), "arrivedAt": DT(nullable=True, **RO),
    "editable": BOOL(**RO), "updatedAt": DT(**RO)},
    {"itinerary": "itineraries", "vehicleType": "vehicle-types", "detentionCause": "detention-causes", "createdBy": "users"})
res("conversations", "Conversation", {"body": STR(writeOnly=True), "lastMessageAt": DT(**RO), "lastMessage": STR(nullable=True, **RO),
    "unread": BOOL(**RO), "createdAt": DT(**RO)}, {"user": "users", "topic": "conversation-topics"})
res("conversation-messages", "ConversationMessage", {"body": STR(), "fromDeveloper": BOOL(**RO), "mine": BOOL(**RO), "createdAt": DT(**RO)},
    {"conversation": "conversations"})
res("settings", "Setting", {"name": STR(**RO), "group": STR(**RO), "groupName": STR(**RO),
    "type": STR(enum=["duracion", "distancia", "velocidad", "entero"], **RO),
    "value": STR(nullable=True, description="Texto con unidades: 10min, 12hor30min, 1km200m, 10km/hor; null = valor por omisión"),
    "base": NUM(**RO), "baseUnit": STR(nullable=True, **RO), "defaultValue": STR(**RO), "min": STR(**RO), "max": STR(**RO), "description": STR(**RO)})
res("app-versions", "AppVersion", {"versionName": STR(**RO), "versionCode": INT(**RO), "notes": STR(nullable=True), "mandatory": BOOL(),
    "files": S("array", items=OBJ(), **RO), "publishedAt": DT(**RO)})
res("access-recoveries", "AccessRecovery", {"forgotUsername": BOOL(), "forgotPassword": BOOL(), "identityCard": CARD,
    "phone": STR(), "status": STR(enum=["pending", "approved", "rejected", "completed", "expired"]), "matched": BOOL(**RO),
    "username": STR(**RO), "password": STR(**RO), "expiresAt": DT(**RO), "createdAt": DT(**RO), "resolvedAt": DT(nullable=True, **RO)},
    {"user": "users", "installation": "installations", "resolvedBy": "users"})
res("installations", "Installation", {"deviceModel": STR(nullable=True), "androidVersion": STR(nullable=True),
    "appVersionCode": INT(nullable=True), "blocked": BOOL(), "createdAt": DT(**RO)}, {"user": "users"})
res("tokens", "Token", {"username": STR(writeOnly=True), "password": STR(writeOnly=True), "refreshToken": STR(), "deviceName": STR(nullable=True),
    "accessToken": STR(**RO), "tokenType": STR(**RO), "expiresIn": INT(**RO), "refreshExpiresIn": INT(**RO)}, {"user": "users"})
res("trip-reports", "TripReport", {"workerState": STR(enum=["de_camino", "en_parada", "viajando", "dejado", "recogido", "botado", "dormido", "no_voy"]),
    "stopId": INT(nullable=True), "childIds": S("array", items=INT()), "childrenCount": INT(minimum=0, maximum=20),
    "vehicleState": STR(enum=["detenido", "en_movimiento"]), "nextStopIndex": INT(minimum=0), "atStop": BOOL(), "reportedAt": DT()},
    desc="Informe del teléfono (solo cambios, con acuse).")
res("trip-lives", "TripLive", {"direction": STR(), "status": STR(), "departsAt": DT(), "vehicle": OBJ(), "sensors": INT(),
    "inVehicle": OBJ(), "expectedPassengers": INT(), "notGoing": INT(), "stops": S("array", items=OBJ()), "myState": OBJ(nullable=True),
    "serverTime": DT()}, {"trip": "trips"}, "Línea del recorrido.")
res("trip-workers", "TripWorker", {"fullName": STR(), "photoUrl": IMG, "expected": BOOL(), "state": STR(nullable=True),
    "stateAt": DT(nullable=True), "childrenCount": INT(), "isChief": BOOL()}, {"user": "users", "stop": "stops"})
res("notifications", "Notification", {"kind": STR(), "title": STR(), "body": STR(), "data": OBJ(), "createdAt": DT()},
    desc="Notificación para mostrar en el teléfono (GET /sync).")
res("qr-devices", "QrDevice", {"publicKey": STR(), "certificate": STR(**RO), "expiresAt": DT(**RO), "userId": STR(**RO), "serverPublicKey": STR(**RO)})
res("qr-scans", "QrScan", {"qr": STR(writeOnly=True), "scannedAt": DT(nullable=True), "fullName": STR(**RO), "photoUrl": IMG,
    "sex": STR(**RO), "memberships": S("array", items=OBJ(), **RO)}, {"user": "users"})
res("qr-inclusions", "QrInclusion", {"qr": STR(writeOnly=True), "scannedAt": DT(nullable=True), "fullName": STR(**RO), "previous": OBJ(**RO)},
    {"worker": "workers", "user": "users", "entity": "entities", "itinerary": "itineraries", "stop": "stops"})
res("maintenance-runs", "MaintenanceRun", {"command": STR(enum=["install", "migrate", "run-tasks", "clear-cache", "log"]),
    "ok": BOOL(**RO), "output": STR(**RO), "ranAt": DT(**RO)})
res("server-statuses", "ServerStatus", {"apiVersion": STR(), "phpVersion": STR(), "phpSupported": BOOL(), "extensions": OBJ(),
    "php": OBJ(), "serverTime": DT(), "timezone": STR(), "database": OBJ(), "storage": OBJ(), "uploads": OBJ(), "tasks": OBJ(),
    "commands": S("array", items=STR())})
res("entity-lookups", "EntityLookup", {"abbreviation": STR(), "name": STR()})
res("registration-status", "RegistrationStatus", {"adminExists": BOOL()})
res("username-suggestions", "UsernameSuggestion", {"username": STR()})
res("password-suggestions", "PasswordSuggestion", {"password": STR()})
res("password-policies", "PasswordPolicy", {"minLength": INT(), "maxLength": INT(), "requiredClasses": INT(), "historyCount": INT(),
    "expiryDays": INT(), "usernameMinLength": INT(), "usernameMaxLength": INT()})
res("qr-public-keys", "QrPublicKey", {"publicKey": STR(), "algorithm": STR(), "curve": STR(), "format": STR(), "signatureFormat": STR(),
    "clockSkewSeconds": INT(), "certificateDays": INT(), "refreshSeconds": INT()})

schemas = {
    "Identifier": {"type": "object", "required": ["type", "id"], "properties": {"type": STR(), "id": STR()}},
    "Error": {"type": "object", "properties": {"status": STR(), "code": STR(), "title": STR(), "detail": STR(),
              "source": {"type": "object", "properties": {"pointer": STR(), "parameter": STR()}}, "meta": OBJ()}},
    "ErrorDocument": {"type": "object", "properties": {"errors": S("array", items={"$ref": "#/components/schemas/Error"})}},
    "Links": OBJ(),
}

for rtype, r in R.items():
    rels = {name: {"type": "object", "properties": {"data": {"allOf": [{"$ref": "#/components/schemas/Identifier"}], "nullable": True}}}
            for name in r["rels"]}
    resource = {"type": "object", "description": r["desc"] or r["name"], "required": ["type"], "properties": {
        "type": STR(enum=[rtype]), "id": STR(readOnly=True),
        "attributes": {"type": "object", "properties": r["attrs"]},
        "meta": OBJ(), "links": {"$ref": "#/components/schemas/Links"}}}
    if rels:
        resource["properties"]["relationships"] = {"type": "object", "properties": rels}
    schemas[r["name"]] = resource
    schemas[r["name"] + "Document"] = {"type": "object", "properties": {
        "data": {"$ref": "#/components/schemas/" + r["name"]}, "included": S("array", items=OBJ()), "meta": OBJ(),
        "links": {"$ref": "#/components/schemas/Links"}}}
    schemas[r["name"] + "Collection"] = {"type": "object", "properties": {
        "data": S("array", items={"$ref": "#/components/schemas/" + r["name"]}), "included": S("array", items=OBJ()),
        "meta": OBJ(), "links": {"$ref": "#/components/schemas/Links"}}}

ERR = {code: {"$ref": "#/components/responses/" + name} for code, name in {
    "400": "BadRequest", "401": "Unauthorized", "403": "Forbidden", "404": "NotFound", "409": "Conflict",
    "415": "UnsupportedMediaType", "422": "Unprocessable", "426": "UpdateRequired", "429": "TooManyRequests"}.items()}
ID = {"$ref": "#/components/parameters/Id"}
LIST = [{"$ref": "#/components/parameters/" + p} for p in ("PageNumber", "PageSize", "Sort", "Include")]
filt = lambda name, desc, schema=None: {"name": f"filter[{name}]", "in": "query", "required": False, "description": desc, "schema": schema or STR()}


def ok(status, schema=None, desc=None):
    if status == 204:
        return {"204": {"description": desc or "Hecho, sin contenido"}}
    return {str(status): {"description": desc or "Correcto", "content": {JA: {"schema": {"$ref": "#/components/schemas/" + schema}}}}}


def op(tag, summary, responses, desc="", params=None, body=None, errs=("401", "403", "404", "426"), public=False, multipart=None):
    o = {"tags": [tag], "summary": summary, "responses": {**responses, **{e: ERR[e] for e in errs}}}
    if desc:
        o["description"] = desc
    if params:
        o["parameters"] = params
    if body:
        o["requestBody"] = {"required": True, "content": {JA: {"schema": {"$ref": "#/components/schemas/" + body}}}}
    if multipart:
        o["requestBody"] = {"required": True, "content": {"multipart/form-data": {"schema": {"type": "object", "properties": multipart}}}}
    if public:
        o["security"] = []
    return o


paths = {}


def crud(rtype, tag, ops="LCRUD", filters=(), notes=None):
    name = R[rtype]["name"]
    notes = notes or {}
    base, item = "/" + rtype, "/" + rtype + "/{id}"
    if "L" in ops:
        paths.setdefault(base, {})["get"] = op(tag, "Listar " + rtype, ok(200, name + "Collection"), notes.get("L", ""), list(filters) + LIST,
                                               errs=("400", "401", "403", "426"))
    if "C" in ops:
        paths.setdefault(base, {})["post"] = op(tag, "Crear " + rtype, ok(201, name + "Document"), notes.get("C", ""), body=name + "Document",
                                                errs=("400", "401", "403", "404", "409", "415", "422", "426"))
    if "R" in ops:
        paths.setdefault(item, {})["get"] = op(tag, "Ver " + rtype, ok(200, name + "Document"), notes.get("R", ""), [ID], errs=("401", "403", "404", "426"))
    if "U" in ops:
        paths.setdefault(item, {})["patch"] = op(tag, "Modificar " + rtype, ok(200, name + "Document"), notes.get("U", ""), [ID], name + "Document",
                                                 errs=("400", "401", "403", "404", "409", "415", "422", "426"))
    if "D" in ops:
        paths.setdefault(item, {})["delete"] = op(tag, "Eliminar " + rtype, ok(204), notes.get("D", ""), [ID], errs=("401", "403", "404", "409", "426"))


# Cuenta y sesión
paths["/registration-status"] = {"get": op("Cuenta", "¿Ya hay Administrador?", ok(200, "RegistrationStatusDocument"), public=True, errs=("426",))}
paths["/username-suggestion"] = {"get": op("Cuenta", "Usuario propuesto", ok(200, "UsernameSuggestionDocument"), params=[
    {"name": n, "in": "query", "required": n == "firstName", "schema": STR()} for n in ("firstName", "middleName", "firstSurname", "secondSurname")],
    public=True, errs=("422", "426"))}
paths["/password-suggestion"] = {"get": op("Cuenta", "Contraseña propuesta", ok(200, "PasswordSuggestionDocument"), public=True, errs=("426",))}
paths["/password-policy"] = {"get": op("Cuenta", "Política de contraseñas", ok(200, "PasswordPolicyDocument"), public=True, errs=("426",))}
paths["/users"] = {"post": op("Cuenta", "Registrarse", ok(201, "UserDocument"), "Público. El primero que se registra es el Administrador.",
                              body="UserDocument", public=True, errs=("400", "409", "415", "422", "426"))}
paths["/tokens"] = {
    "post": op("Cuenta", "Iniciar sesión", ok(201, "TokenDocument"), "Con una actualización obligatoria pendiente: 426.", body="TokenDocument",
               public=True, errs=("400", "401", "415", "422", "426")),
    "delete": op("Cuenta", "Cerrar todas las sesiones", ok(204), errs=("401",)),
}
paths["/tokens/refresh"] = {"post": op("Cuenta", "Renovar los tokens", ok(201, "TokenDocument"), "Rotación: reutilizar uno usado cierra todas las sesiones.",
                                       body="TokenDocument", public=True, errs=("400", "401", "415", "426"))}
paths["/tokens/current"] = {"delete": op("Cuenta", "Cerrar esta sesión", ok(204), errs=("401",))}
paths["/me"] = {
    "get": op("Cuenta", "Mi persona", ok(200, "UserDocument"), "meta.role, meta.chiefItineraryId y meta.memberships.", errs=("401", "426")),
    "patch": op("Cuenta", "Cambiar mis datos o mi contraseña", ok(200, "UserDocument"), "Para la contraseña, meta.currentPassword.", body="UserDocument",
                errs=("400", "401", "409", "415", "422", "426")),
}
paths["/me/photo"] = {
    "post": op("Cuenta", "Subir mi foto", ok(200, "UserDocument"), multipart={"photo": STR(format="binary")}, errs=("401", "422", "426")),
    "delete": op("Cuenta", "Quitar mi foto", ok(204), errs=("401", "426")),
}
paths["/me/applications-seen"] = {"post": op("Cuenta", "Marcar vistas mis solicitudes resueltas", ok(204), errs=("401", "426"))}

# Gestión
crud("entities", "Gestión", filters=[filt("search", "Abreviatura o nombre"), filt("active", "true o false")],
     notes={"C": "Administrador.", "U": "Administrador.", "D": "Administrador. Sus itinerarios quedan sin Entidad; las personas quedan sin esa Entidad."})
paths["/entities/lookup"] = {"get": op("Gestión", "Comprobar una abreviatura", ok(200, "EntityLookupDocument"), "Con sesión o X-Installation.",
                                       [filt("abbreviation", "Abreviatura")], errs=("400", "401", "404", "426"))}
crud("itineraries", "Gestión", filters=[filt("entity", "Id de Entidad o none"), filt("search", "Nombre"), filt("active", "true o false")],
     notes={"C": "Administrador. relationships.entity opcional.", "U": "Administrador. relationships.entity (id o null): sus personas pasan con él (o salen de él).",
            "D": "Administrador. Sus personas salen de él; las paradas se conservan."})
paths["/itineraries/{id}/relationships/stops"] = {"patch": op("Gestión", "Ordenar las paradas del itinerario",
    {"200": {"description": "Nuevo orden", "content": {JA: {"schema": {"type": "object", "properties": {"data": S("array", items={"$ref": "#/components/schemas/Identifier"})}}}}}},
    "Administrador o Jefe del itinerario. data = todas sus paradas en orden.", [ID],
    errs=("400", "401", "403", "404", "409", "415", "422", "426"))}
paths["/itineraries/{id}/relationships/stops"]["patch"]["requestBody"] = {"required": True, "content": {JA: {"schema": {
    "type": "object", "properties": {"data": S("array", items={"$ref": "#/components/schemas/Identifier"})}}}}}
crud("stops", "Gestión", filters=[filt("itinerary", "Id de itinerario o none"), filt("entity", "Id de Entidad"), filt("search", "Punto de referencia o calle"),
     filt("active", "true o false")], notes={"C": "Administrador; Jefe con relationships.itinerary = el suyo.", "D": "Jefe: solo si no la usa otro itinerario (409 STOP_SHARED)."})
crud("itinerary-stops", "Gestión", "LCUD", [filt("itinerary", "Id de itinerario"), filt("stop", "Id de parada")],
     notes={"C": "Añadir parada existente.", "U": "Mover (position).", "D": "Quitar del itinerario (la parada se conserva)."})
for resource in ("entities", "itineraries", "stops"):
    paths[f"/{resource}/{{id}}/image"] = {
        "post": op("Gestión", "Subir la imagen", ok(200, R[resource]["name"] + "Document"), params=[ID], multipart={"image": STR(format="binary")},
                   errs=("401", "403", "404", "422", "426")),
        "delete": op("Gestión", "Quitar la imagen", ok(204), params=[ID]),
    }
crud("users", "Gestión", "LRUD", [filt("entity", "Id de Entidad o none"), filt("itinerary", "Id o none"), filt("stop", "Id o none"),
     filt("search", "Nombre, usuario o carné")], notes={"U": "Administrador.", "D": "Administrador."})
crud("workers", "Gestión", filters=[filt("entity", "Id de Entidad"), filt("itinerary", "Id o none"), filt("stop", "Id o none"), filt("user", "Id de persona"),
     filt("search", "Nombre, usuario o carné"), filt("active", "true o false"), filt("chief", "true o false")],
     notes={"C": "Administrador: persona existente (relationships.user) o nueva (nombres y carné; meta.username y meta.password).",
            "U": "active (Administrador o Jefe de su itinerario).", "D": "Administrador o la propia persona."})
crud("worker-itineraries", "Gestión", filters=[filt("user", "Id de persona"), filt("itinerary", "Id de itinerario"), filt("entity", "Id de Entidad"),
     filt("stop", "Id o none"), filt("chief", "true o false"), filt("search", "Nombre, usuario o carné")],
     notes={"C": "Administrador, o Jefe en su itinerario a personas de su Entidad. Añade el itinerario a los que ya tiene.",
            "U": "relationships.stop (Administrador, Jefe o la propia persona); isChief (Administrador).",
            "D": "Salir del itinerario (Administrador, Jefe o la propia persona)."})
paths["/management-summary"] = {"get": op("Gestión", "Cantidades de las tarjetas de Gestión", ok(200, "ManagementSummaryDocument"), errs=("401", "426"))}
crud("applications", "Gestión", filters=[filt("status", "Lista: pendiente,aprobada,rechazada"), filt("type", "entidad o itinerario"),
     filt("entity", "Id"), filt("itinerary", "Id"), filt("mine", "true o false")],
     notes={"U": "status aprobada, o rechazada con relationships.denialReason.", "D": "Quien la hizo."})
crud("absences", "Gestión", filters=[filt("worker", "Id de pertenencia"), filt("current", "true")])
crud("children", "Hijos", filters=[filt("parent", "Id de persona"), filt("active", "true o false"), filt("eligible", "true o false")])
paths["/children/{id}/photo"] = {
    "post": op("Hijos", "Subir la foto", ok(200, "ChildDocument"), params=[ID], multipart={"photo": STR(format="binary")}),
    "delete": op("Hijos", "Quitar la foto", ok(204), params=[ID]),
}

for rtype in ("vehicle-types", "absence-types", "conversation-topics", "denial-reasons", "detention-causes"):
    crud(rtype, "Nomencladores", filters=[filt("active", "true o false (solo Administrador)"), filt("search", "Nombre")]
         + ([filt("applicationType", "entidad o itinerario")] if rtype == "denial-reasons" else []),
         notes={"C": "Administrador.", "U": "Administrador.", "D": "Administrador. En uso: 409 NOMENCLATOR_IN_USE (desactivarlo)."})

# QR
paths["/qr-public-key"] = {"get": op("QR", "Clave pública del servidor", ok(200, "QrPublicKeyDocument"), public=True, errs=("426",))}
paths["/me/qr-devices"] = {"post": op("QR", "Certificar la clave de mi teléfono", ok(201, "QrDeviceDocument"), body="QrDeviceDocument",
                                      errs=("400", "401", "415", "422", "426"))}
paths["/qr-scans"] = {"post": op("QR", "Comprobar un QR", ok(200, "QrScanDocument"), "Administrador y Jefes. No gasta el código.",
                                 body="QrScanDocument", errs=("400", "401", "403", "415", "422", "426"))}
paths["/qr-inclusions"] = {"post": op("QR", "Incluir por QR", ok(201, "QrInclusionDocument"),
    "En una Entidad, un itinerario (con parada opcional) o una parada (con su itinerario). Reintento: 200 con meta.repeated.",
    body="QrInclusionDocument", errs=("400", "401", "403", "404", "409", "415", "422", "426"))}

# Viajes
crud("trips", "Viajes", filters=[filt("status", "Lista: planificado,en_ejecucion,terminado,cancelado"), filt("itinerary", "Id"),
     filt("direction", "ida o regreso"), filt("date", "Día", DATE()), filt("from", "Desde", DATE()), filt("to", "Hasta", DATE())],
     notes={"C": "Administrador o Jefe del itinerario.", "U": "Datos solo en planificado; status para el cambio a mano; relationships.detentionCause.",
            "D": "No en ejecución."})
paths["/trips/{id}/live"] = {"get": op("Viajes", "Línea del recorrido", ok(200, "TripLiveDocument"), params=[ID])}
paths["/trips/{id}/passengers"] = {"get": op("Viajes", "Trabajadores del viaje", ok(200, "TripWorkerCollection"), params=[ID])}
paths["/trips/{id}/reports"] = {"post": op("Viajes", "Informe del teléfono", ok(200, "TripLiveDocument", "Acuse (meta.ack, meta.applied, meta.reason) y línea del recorrido"),
    "Estado del trabajador y, si es sensor, del vehículo. Idempotente.", [ID], "TripReportDocument", errs=("400", "401", "403", "404", "415", "422", "426"))}

# Sincronización, conversaciones y ajustes
paths["/sync"] = {"get": op("Sincronización", "Novedades desde el cursor", ok(200, "NotificationCollection"),
    "Sin cursor: solo meta.cursor. meta: cursor, more, changed, counters, latestAppVersion, nextTrip, settingsVersion, serverTime.",
    [{"name": "cursor", "in": "query", "required": False, "schema": STR(pattern=r"^\d+$")}], errs=("400", "401", "426"))}
crud("conversations", "Conversaciones", "LCR", [filt("mine", "true"), filt("unread", "true")])
paths["/conversations/{id}/messages"] = {
    "get": op("Conversaciones", "Mensajes", ok(200, "ConversationMessageCollection"), "Los da por leídos.", [ID, filt("after", "Id de mensaje")]),
    "post": op("Conversaciones", "Escribir", ok(201, "ConversationMessageDocument"), params=[ID], body="ConversationMessageDocument",
               errs=("400", "401", "404", "415", "422", "426")),
}
crud("settings", "Ajustes", "LRU", [filt("group", "Grupo")], notes={"U": "Administrador. value con unidades o null."})

# Administración del servidor
paths["/app-versions/latest"] = {"get": op("Actualizaciones", "Última versión de la app", ok(200, "AppVersionDocument"),
    "Público; permitido con una actualización obligatoria pendiente.",
    [filt("currentVersionCode", "versionCode instalado", INT()), filt("abis", "p. ej. arm64-v8a,armeabi-v7a")], public=True, errs=("400",))}
paths["/app-versions"] = {
    "get": op("Actualizaciones", "Versiones publicadas", ok(200, "AppVersionCollection"), "Administrador."),
    "post": op("Actualizaciones", "Publicar una versión", ok(201, "AppVersionDocument"), "Administrador.", multipart={
        "apkArm64": STR(format="binary"), "apkArm32": STR(format="binary"), "apkUniversal": STR(format="binary"),
        "versionName": STR(), "versionCode": INT(), "notes": STR(), "mandatory": STR(enum=["0", "1"])}, errs=("401", "403", "422", "426")),
}
paths["/app-versions/{id}"] = {
    "patch": op("Actualizaciones", "Cambiar obligatoria o novedades", ok(200, "AppVersionDocument"), params=[ID], body="AppVersionDocument"),
    "delete": op("Actualizaciones", "Retirar una versión", ok(204), params=[ID]),
}
paths["/installations"] = {"post": op("Olvidé algo", "Registrar la instalación", ok(201, "InstallationDocument"), "Público. meta.header para X-Installation.",
                                      body="InstallationDocument", public=True, errs=("400", "415", "422"))}
paths["/installations/{id}"] = {
    "get": op("Olvidé algo", "Ver una instalación", ok(200, "InstallationDocument"), "Administrador.", [ID]),
    "patch": op("Olvidé algo", "Bloquear o desbloquear", ok(200, "InstallationDocument"), "Administrador.", [ID], "InstallationDocument"),
}
INSTALLATION = {"name": "X-Installation", "in": "header", "required": True, "schema": STR()}
paths["/guest/access-recoveries"] = {"post": op("Olvidé algo", "Pedir «Olvidé algo»", ok(201, "AccessRecoveryDocument"), params=[INSTALLATION],
    body="AccessRecoveryDocument", public=True, errs=("400", "401", "403", "415", "422", "429"))}
paths["/guest/access-recoveries/{id}"] = {"get": op("Olvidé algo", "Consultar mi solicitud", ok(200, "AccessRecoveryDocument"),
    "Aprobada: solo lo pedido, una vez.", [ID, INSTALLATION], public=True, errs=("401", "404"))}
crud("access-recoveries", "Olvidé algo", "LRU", [filt("status", "Lista de estados")], notes={"U": "Administrador: status approved o rejected."})
MAINT = {"name": "X-Maintenance-Key", "in": "header", "required": False, "schema": STR(), "description": "Sin ella, la sesión del Administrador."}
paths["/server-status"] = {"get": op("Mantenimiento", "Estado del servidor", ok(200, "ServerStatusDocument"), params=[MAINT], errs=("401", "403"))}
paths["/maintenance-runs"] = {"post": op("Mantenimiento", "Ejecutar una orden", ok(201, "MaintenanceRunDocument"),
    "install, migrate, run-tasks, clear-cache o log.", [MAINT], "MaintenanceRunDocument", errs=("401", "403", "409", "415", "422"))}

errresp = lambda d: {"description": d, "content": {JA: {"schema": {"$ref": "#/components/schemas/ErrorDocument"}}}}
spec = {
    "openapi": "3.0.3",
    "info": {
        "title": "MiRuta API",
        "version": "4.1.0",
        "description": "API de MiRuta (Laravel 12): gestión del transporte de trabajadores.\n\n"
                       "- Formato [JSON:API 1.1](https://jsonapi.org/format/) (`application/vnd.api+json`).\n"
                       "- Autenticación JWT (RFC 7519) con token de renovación y rotación.\n"
                       "- Tres roles fijos: Administrador, Jefe de itinerario y Trabajador.\n"
                       "- Cabecera `X-App-Version` en cada petición: con una actualización obligatoria pendiente, 426 APP_UPDATE_REQUIRED.\n"
                       "- Detalle de reglas y errores: `docs/13-api-proxima-version.md`.",
    },
    "servers": [{"url": "https://{host}/api/v1", "variables": {"host": {"default": "localhost"}}}],
    "security": [{"bearerAuth": []}],
    "tags": [{"name": t} for t in ["Cuenta", "Gestión", "Hijos", "Nomencladores", "QR", "Viajes", "Sincronización", "Conversaciones", "Ajustes",
                                   "Actualizaciones", "Olvidé algo", "Mantenimiento"]],
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
            "Unauthorized": errresp("No autenticado, token no válido o sesión cerrada"),
            "Forbidden": errresp("Sin permiso"),
            "NotFound": errresp("No encontrado (o no lo puede ver)"),
            "Conflict": errresp("Conflicto (duplicado, en uso, transición no permitida…)"),
            "UnsupportedMediaType": errresp("Falta el tipo de contenido JSON:API"),
            "Unprocessable": errresp("Error de validación"),
            "UpdateRequired": errresp("Actualización obligatoria pendiente (APP_UPDATE_REQUIRED)"),
            "TooManyRequests": errresp("Demasiadas solicitudes desde ese teléfono"),
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
