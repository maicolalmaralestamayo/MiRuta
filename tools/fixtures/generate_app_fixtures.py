"""Genera app/test/fixtures con respuestas reales de la API.

Monta un escenario completo (Administrador, una Entidad, un itinerario con
tres paradas, una Jefa de Transporte, un chofer, una trabajadora con un hijo,
un viaje en marcha…) contra una API recién migrada y sembrada, y guarda las
respuestas que usan las pruebas de contrato de la app (app/test/api_contract_test.dart).

Uso: python3 tools/fixtures/generate_app_fixtures.py http://localhost:8000/api/v1 app/test/fixtures
"""
import json
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

API = sys.argv[1].rstrip("/")
OUT = sys.argv[2]
MEDIA = "application/vnd.api+json"
PASSWORD = "Viaje.2026x"


def call(method, path, body=None, token=None):
    request = urllib.request.Request(API + path, method=method, data=None if body is None else json.dumps(body).encode())
    request.add_header("Accept", MEDIA)
    if body is not None:
        request.add_header("Content-Type", MEDIA)
    if token:
        request.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        raise SystemExit(f"{method} {path} → {error.code}: {error.read().decode()}")


def data(rtype, attributes=None, **relationships):
    document = {"type": rtype}
    if attributes:
        document["attributes"] = attributes
    if relationships:
        document["relationships"] = {name: {"data": {"type": t, "id": str(i)}} for name, (t, i) in relationships.items()}
    return {"data": document}


def save(name, document):
    with open(f"{OUT}/{name}.json", "w") as f:
        json.dump(document, f, ensure_ascii=False, indent=1)


def login(username):
    return call("POST", "/tokens", data("tokens", {"username": username, "password": PASSWORD}))["data"]["attributes"]["accessToken"]


def names(first, middle, surname1, surname2):
    return {"firstName": first, "middleName": middle, "firstSurname": surname1, "secondSurname": surname2}


def register(username, full_names):
    call("POST", "/users", data("users", {**full_names, "username": username, "password": PASSWORD}))
    return login(username)


now = datetime.now(timezone.utc).replace(microsecond=0)
iso = lambda d: d.isoformat().replace("+00:00", "Z")

# Administrador y Entidad
admin = register("direccion", names("Ana", "Isabel", "Gómez", "Ruiz"))
entity = call("POST", "/entities", data("entities", {"abbreviation": "PRUEBA", "name": "Empresa de prueba"}), admin)["data"]["id"]
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

# Trabajadores
rank = next(r["id"] for r in call("GET", "/ranks?page[size]=100")["data"] if r["attributes"]["name"] == "Trabajador civil")
people = {}
for pass_number, (username, full_names, sex) in enumerate([
    ("lucia.perez", names("Lucía", "María", "Pérez", "García"), "F"),
    ("carlos.chofer", names("Carlos", "Luis", "Chofer", "Díaz"), "M"),
    ("teresa.jefa", names("Teresa", "Ana", "Jefa", "López"), "F"),
], 101):
    token = register(username, full_names)
    worker = call("POST", "/me/worker", data("workers", {"entityAbbreviation": "prueba", "pass": pass_number, "sex": sex}, rank=("ranks", rank)), token)["data"]["id"]
    people[username] = (token, worker)
lucia, lucia_worker = people["lucia.perez"]
carlos, carlos_worker = people["carlos.chofer"]
teresa, teresa_worker = people["teresa.jefa"]

# Roles y miembros, asignados directamente por el Administrador
call("POST", "/applications", data("applications", {"type": "transport_chief"}, worker=("workers", teresa_worker)), admin)
call("POST", "/applications", data("applications", {"type": "driver"}, worker=("workers", carlos_worker)), admin)
call("POST", "/applications", data("applications", {"type": "itinerary_membership"}, worker=("workers", carlos_worker),
                                   itinerary=("itineraries", itinerary), stop=("stops", stops[0])), admin)
# Lucía lo pide ella y lo aprueba la Jefa de Transporte
application = call("POST", "/applications", data("applications", {"type": "itinerary_membership"}, itinerary=("itineraries", itinerary), stop=("stops", stops[1])), lucia)["data"]["id"]
call("PATCH", f"/applications/{application}", {"data": {"type": "applications", "id": application, "attributes": {"status": "approved"}}}, teresa)

driver = call("GET", f"/drivers?filter[worker]={carlos_worker}", token=admin)["data"][0]["id"]
guagua = next(t["id"] for t in call("GET", "/vehicle-types", token=admin)["data"] if t["attributes"]["name"] == "Guagua")
vehicle = call("POST", "/vehicles", data("vehicles", {"plate": "B123456", "seats": 1, "standingCapacity": 0},
                                         vehicleType=("vehicle-types", guagua), driver=("drivers", driver)), teresa)["data"]["id"]

# Viaje en marcha
trip = call("POST", "/trips", data("trips", {"departsAt": iso(now - timedelta(hours=2)), "returnsAt": iso(now - timedelta(minutes=10)), "status": "confirmed"},
                                   itinerary=("itineraries", itinerary), vehicle=("vehicles", vehicle), driver=("drivers", driver)), teresa)["data"]["id"]

# Hijo de Lucía
child_application = call("POST", "/applications", data("applications", {
    "type": "child_addition", "childFirstName": "Pepito", "childMiddleName": "Juan", "childFirstSurname": "Pérez", "childSecondSurname": "García",
    "childBirthDate": "2015-03-05"}), lucia)["data"]["id"]
call("PATCH", f"/applications/{child_application}", {"data": {"type": "applications", "id": child_application, "attributes": {"status": "approved"}}}, teresa)

# Recorrido de regreso: el chofer comparte su ubicación junto al Hospital
leg = call("POST", "/trip-legs", data("trip-legs", {"direction": "return"}, trip=("trips", trip)), carlos)["data"]["id"]
call("POST", "/trip-positions", data("trip-positions", {"latitude": 23.1199, "longitude": -82.3, "accuracyM": 10, "recordedAt": iso(datetime.now(timezone.utc))},
                                     tripLeg=("trip-legs", leg)), carlos)
call("POST", "/trip-boardings", data("trip-boardings", {"method": "self", "childrenCount": 1}, tripLeg=("trip-legs", leg)), lucia)
boarding_pass = call("POST", "/boarding-passes", data("boarding-passes", tripLeg=("trip-legs", leg)), lucia)
call("POST", "/trip-messages", data("trip-messages", {"body": "Voy con el niño"}, trip=("trips", trip)), lucia)

topic = next(t["id"] for t in call("GET", "/conversation-topics?page[size]=100")["data"]
             if t["attributes"]["name"] == "Reportar un problema" and t["attributes"]["recipient"] == "itinerary_chiefs")
conversation = call("POST", "/conversations", data("conversations", topic=("conversation-topics", topic)), lucia)["data"]["id"]
call("POST", "/conversation-messages", data("conversation-messages", {"body": "La guagua llegó tarde"}, conversation=("conversations", conversation)), lucia)

children = call("GET", f"/children?filter[worker]={lucia_worker}", token=lucia)["data"]

# Respuestas que usan las pruebas
save("me", call("GET", "/me?include=worker,worker.entity,worker.rank", token=lucia))
save("trip", call("GET", f"/trips/{trip}?include=itinerary,vehicle.vehicleType,driver.worker", token=lucia))
save("itinerary", call("GET", f"/itineraries/{itinerary}", token=lucia))
save("itinerary_stops", call("GET", f"/itinerary-stops?filter[itinerary]={itinerary}&include=stop&sort=position", token=lucia))
save("trip_leg", call("GET", f"/trip-legs/{leg}", token=carlos))
save("passengers", call("GET", f"/trips/{trip}/passengers?filter[direction]=return", token=carlos))
save("applications", call("GET", "/applications?filter[mine]=true&include=worker,resolvedBy,itinerary,stop,absenceType", token=lucia))
save("children", call("GET", f"/children/{children[0]['id']}", token=lucia))
save("notices", call("GET", "/notices", token=lucia))
save("trip_messages", call("GET", f"/trips/{trip}/messages?include=author", token=lucia))
save("conversations", call("GET", "/conversations?include=topic,openedBy", token=lucia))
save("setting_definitions", call("GET", "/setting-definitions", token=lucia))
save("user_settings", call("GET", "/me/settings", token=lucia))
save("statistic", call("GET", "/statistics/trips-by-status?filter[last]=7d", token=admin))
save("live_trip", call("GET", f"/statistics/live-trip?filter[trip]={trip}", token=carlos))
save("vehicle", call("GET", f"/vehicles/{vehicle}?include=vehicleType", token=teresa))
save("workers", call("GET", "/workers?include=rank,entity", token=admin))
save("boarding_pass", boarding_pass)
save("entity_lookup", call("GET", "/entities/lookup?abbreviation=prueba", token=lucia))
print("Fixtures guardados en", OUT)
