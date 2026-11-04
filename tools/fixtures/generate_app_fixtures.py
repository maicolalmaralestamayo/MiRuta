"""Genera app/test/fixtures con respuestas reales de la API 3.0.

Monta un escenario completo contra una API recién migrada y sembrada:
Administradora (la primera en registrarse) sin Entidad, dos Entidades, un
itinerario con tres paradas, una trabajadora (Lucía) registrada por ella misma
que entra en las dos Entidades con solicitud, un chofer y una Jefa de
Transporte registrados por el Administrador (con usuario y contraseña
propuestos), roles asignados, un hijo, una ausencia, una solicitud de rol
pendiente, un viaje en marcha… y guarda las respuestas que usan las pruebas
de contrato de la app (app/test/api_contract_test.dart).

Uso: python3 tools/fixtures/generate_app_fixtures.py http://localhost:8000/api/v1 app/test/fixtures
"""
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta, timezone

API = sys.argv[1].rstrip("/")
OUT = sys.argv[2]
MEDIA = "application/vnd.api+json"
PASSWORD = "Viaje.2026x"

# Sin proxy para el servidor local.
urllib.request.install_opener(urllib.request.build_opener(urllib.request.ProxyHandler({})))


def call(method, path, body=None, token=None):
    request = urllib.request.Request(API + path, method=method, data=None if body is None else json.dumps(body).encode())
    request.add_header("Accept", MEDIA)
    if body is not None or method in ("POST", "PATCH"):
        request.add_header("Content-Type", MEDIA)
    if token:
        request.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        raise SystemExit(f"{method} {path} → {error.code}: {error.read().decode()}")


def data(rtype, attributes=None, rid=None, **relationships):
    document = {"type": rtype}
    if rid:
        document["id"] = str(rid)
    if attributes:
        document["attributes"] = attributes
    if relationships:
        document["relationships"] = {name: {"data": {"type": t, "id": str(i)}} for name, (t, i) in relationships.items()}
    return {"data": document}


def save(name, document):
    with open(f"{OUT}/{name}.json", "w") as f:
        json.dump(document, f, ensure_ascii=False, indent=1)


def login(username, password=PASSWORD):
    return call("POST", "/tokens", data("tokens", {"username": username, "password": password}))["data"]["attributes"]["accessToken"]


def names(first, middle, surname1, surname2):
    return {"firstName": first, "middleName": middle, "firstSurname": surname1, "secondSurname": surname2}


def card(born, female, seq="12"):
    """Carné válido: AAMMDD + siglo (0–5: 1900, 6–8: 2000) + 2 cifras + sexo (par M, impar F) + 1 cifra."""
    century = "6" if born.year >= 2000 else "0"
    return born.strftime("%y%m%d") + century + seq + ("3" if female else "4") + "0"


def register(full_names, identity_card):
    """Registro propio con el usuario y la contraseña que propone el sistema."""
    query = urllib.parse.urlencode({k: v for k, v in full_names.items() if v})
    username = call("GET", f"/username-suggestion?{query}")["data"]["attributes"]["username"]
    call("POST", "/users", data("users", {**full_names, "identityCard": identity_card, "username": username, "password": PASSWORD}))
    return username, login(username)


def approve(application, token):
    call("PATCH", f"/applications/{application}", data("applications", {"status": "approved"}, rid=application), token)


now = datetime.now(timezone.utc).replace(microsecond=0)
iso = lambda d: d.isoformat().replace("+00:00", "Z")

save("registration_status", call("GET", "/registration-status"))
save("username_suggestion", call("GET", "/username-suggestion?firstName=Ana&middleName=Isabel&firstSurname=G%C3%B3mez&secondSurname=Ruiz"))
save("password_suggestion", call("GET", "/password-suggestion"))

# Administradora (la primera en registrarse) y Entidades
_, admin = register(names("Ana", "Isabel", "Gómez", "Ruiz"), card(date(1980, 1, 1), True, "11"))
entity = call("POST", "/entities", data("entities", {"abbreviation": "PRUEBA", "name": "Empresa de prueba"}), admin)["data"]["id"]
second = call("POST", "/entities", data("entities", {"abbreviation": "DOS", "name": "Segunda Entidad"}), admin)["data"]["id"]
ent = {"entity": ("entities", entity)}

# Paradas e itinerario
stops = []
for i, (landmark, street) in enumerate([("Empresa", "Calle 1"), ("Parque", "Calle 2"), ("Hospital", "Calle 3")]):
    attributes = {"landmark": landmark, "street": street, "latitude": 23.10 + i / 100, "longitude": -82.3}
    if i == 0:
        attributes.update({"crossStreet1": "A", "crossStreet2": "B"})
    stops.append(call("POST", "/stops", data("stops", attributes, **ent), admin)["data"]["id"])
itinerary = call("POST", "/itineraries", data("itineraries", {"name": "Ruta Este"}, **ent), admin)["data"]["id"]
for position, stop in enumerate(stops, 1):
    call("POST", "/itinerary-stops", data("itinerary-stops", {"position": position}, itinerary=("itineraries", itinerary), stop=("stops", stop)), admin)

# Lucía se registra ella misma y solicita entrar en las dos Entidades
lucia_username, lucia = register(names("Lucía", "María", "Pérez", "García"), card(date(1990, 5, 20), True, "21"))
for abbreviation in ("prueba", "DOS"):
    application = call("POST", "/applications", data("applications", {"type": "entity_membership", "entityAbbreviation": abbreviation}), lucia)["data"]["id"]
    approve(application, admin)

# Carlos y Teresa los registra el Administrador (usuario y contraseña propuestos)
people = {}
for key, full_names, born, female in [
    ("carlos", names("Carlos", "Luis", "Chofer", "Díaz"), date(1985, 3, 15), False),
    ("teresa", names("Teresa", "Ana", "Jefa", "López"), date(1978, 11, 2), True),
]:
    created = call("POST", "/workers", data("workers", {**full_names, "identityCard": card(born, female, "31"), "hasPhone": True}, **ent), admin)
    if key == "carlos":
        save("worker_registered", created)
    meta = created["data"]["meta"] if "meta" in created["data"] else created["meta"]
    token = login(meta["username"], meta["password"])
    # Contraseña puesta por otro: hay que cambiarla al entrar.
    call("PATCH", "/me", data("users", {"password": PASSWORD}), token)
    people[key] = (login(meta["username"]), created["data"]["id"])
carlos, carlos_worker = people["carlos"]
teresa, teresa_worker = people["teresa"]

me_lucia = call("GET", "/me", token=lucia)
lucia_worker = next(m["workerId"] for m in me_lucia["data"]["meta"]["memberships"] if m["entity"]["id"] == entity)

# Roles asignados directamente por el Administrador
roles = {r["attributes"]["name"]: r["id"] for r in call("GET", "/roles", token=admin)["data"]}
call("POST", "/worker-roles", data("worker-roles", worker=("workers", teresa_worker), role=("roles", roles["Jefe de Transporte"])), admin)
call("POST", "/worker-roles", data("worker-roles", worker=("workers", carlos_worker), role=("roles", roles["Chofer"])), admin)
call("POST", "/worker-roles", data("worker-roles", worker=("workers", teresa_worker), role=("roles", roles["Jefe de itinerario"]),
                                   itinerary=("itineraries", itinerary)), admin)

# Itinerario y parada: a Carlos se lo asigna el Administrador; Lucía lo pide y lo aprueba la Jefa de itinerario
call("PATCH", f"/workers/{carlos_worker}", data("workers", rid=carlos_worker, itinerary=("itineraries", itinerary), stop=("stops", stops[0])), admin)
application = call("POST", "/applications", data("applications", {"type": "itinerary_membership"}, itinerary=("itineraries", itinerary), stop=("stops", stops[1])), lucia)["data"]["id"]
approve(application, teresa)

# Lucía pide el rol de Chofer en PRUEBA (queda pendiente)
call("POST", "/applications", data("applications", {"type": "role"}, role=("roles", roles["Chofer"]), entity=("entities", entity)), lucia)

guagua = next(t["id"] for t in call("GET", "/vehicle-types", token=admin)["data"] if t["attributes"]["name"] == "Guagua")
vehicle = call("POST", "/vehicles", data("vehicles", {"plate": "B123456", "seats": 1, "standingCapacity": 0},
                                         vehicleType=("vehicle-types", guagua), driver=("workers", carlos_worker)), teresa)["data"]["id"]

# Viaje en marcha
trip = call("POST", "/trips", data("trips", {"departsAt": iso(now - timedelta(hours=2)), "returnsAt": iso(now - timedelta(minutes=10)), "status": "confirmed"},
                                   itinerary=("itineraries", itinerary), vehicle=("vehicles", vehicle), driver=("workers", carlos_worker)), teresa)["data"]["id"]

# Hijo de Lucía (por carné, sin solicitud) y una ausencia
child = call("POST", "/children", data("children", {**names("Pepito", "Juan", "Pérez", "García"), "identityCard": card(date(2018, 3, 5), False, "41")}), lucia)["data"]["id"]
absence_type = call("GET", "/absence-types", token=lucia)["data"][0]["id"]
call("POST", "/absences", data("absences", {"startsOn": (now + timedelta(days=10)).date().isoformat(), "endsOn": (now + timedelta(days=14)).date().isoformat(), "note": "Vacaciones"},
                               worker=("workers", lucia_worker), absenceType=("absence-types", absence_type)), lucia)

# Recorrido de regreso: el chofer comparte su ubicación junto al Hospital
leg = call("POST", "/trip-legs", data("trip-legs", {"direction": "return"}, trip=("trips", trip)), carlos)["data"]["id"]
call("POST", "/trip-positions", data("trip-positions", {"latitude": 23.1199, "longitude": -82.3, "accuracyM": 10, "recordedAt": iso(datetime.now(timezone.utc))},
                                     tripLeg=("trip-legs", leg)), carlos)
call("POST", "/trip-boardings", data("trip-boardings", {"method": "self"}, tripLeg=("trip-legs", leg)), lucia)
call("POST", "/trip-messages", data("trip-messages", {"body": "Voy con el niño"}, trip=("trips", trip)), lucia)

topic = next(t["id"] for t in call("GET", "/conversation-topics?page[size]=100")["data"]
             if t["attributes"]["name"] == "Reportar un problema" and t["attributes"].get("roleName") == "Jefe de itinerario")
conversation = call("POST", "/conversations", data("conversations", topic=("conversation-topics", topic), entity=("entities", entity)), lucia)["data"]["id"]
call("POST", "/conversation-messages", data("conversation-messages", {"body": "La guagua llegó tarde"}, conversation=("conversations", conversation)), lucia)

# Respuestas que usan las pruebas
save("me", call("GET", "/me", token=lucia))
save("me_admin", call("GET", "/me", token=admin))
save("me_chief", call("GET", "/me", token=teresa))
save("trip", call("GET", f"/trips/{trip}?include=itinerary,vehicle.vehicleType,driver", token=lucia))
save("itinerary", call("GET", f"/itineraries/{itinerary}", token=lucia))
save("itinerary_stops", call("GET", f"/itinerary-stops?filter[itinerary]={itinerary}&include=stop&sort=position", token=lucia))
save("trip_leg", call("GET", f"/trip-legs/{leg}", token=carlos))
save("passengers", call("GET", f"/trips/{trip}/passengers?filter[direction]=return", token=carlos))
save("applications", call("GET", "/applications?filter[mine]=true&include=entity,itinerary,stop,role", token=lucia))
save("children", call("GET", f"/children/{child}", token=lucia))
save("absences", call("GET", "/absences?filter[mine]=true&include=absenceType", token=lucia))
save("roles", call("GET", "/roles", token=admin))
save("worker_roles", call("GET", f"/worker-roles?filter[worker]={teresa_worker}&include=role,itinerary", token=teresa))
save("notices", call("GET", "/notices", token=lucia))
save("trip_messages", call("GET", f"/trips/{trip}/messages?include=author", token=lucia))
save("conversations", call("GET", "/conversations?include=topic,openedBy", token=lucia))
save("setting_definitions", call("GET", "/setting-definitions", token=lucia))
save("user_settings", call("GET", "/me/settings", token=lucia))
save("statistic", call("GET", "/statistics/trips-by-status?filter[last]=7d", token=admin))
save("live_trip", call("GET", f"/statistics/live-trip?filter[trip]={trip}", token=carlos))
save("vehicle", call("GET", f"/vehicles/{vehicle}?include=vehicleType", token=teresa))
save("workers", call("GET", f"/workers?filter[entity]={entity}&include=entity", token=admin))
save("entity_lookup", call("GET", "/entities/lookup?abbreviation=prueba", token=lucia))
print("Fixtures guardados en", OUT)
