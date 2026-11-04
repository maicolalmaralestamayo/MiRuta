import '../../core/api_client.dart';
import '../../models/models.dart';
import '../../services/sync.dart';

/// Un viaje con las paradas de su itinerario (en orden) y sus trayectos.
class TripContext {
  final Trip trip;
  final List<Stop> stops;
  final List<TripLeg> legs;

  /// Itinerario del viaje (con sus recorridos de referencia), si se pudo leer.
  final Itinerary? itinerary;

  TripContext(this.trip, this.stops, this.legs, [this.itinerary]);

  static Future<TripContext> load(ApiClient api, String tripId) async {
    final trip = Trip.from((await api.get('/trips/$tripId', query: {'include': SyncService.tripInclude})).resource);
    final links = await api.getAll('/itinerary-stops', query: {'filter[itinerary]': trip.itineraryId, 'include': 'stop', 'sort': 'position'});
    final stops = links.map(ItineraryStop.from).map((link) => link.stop!).toList();
    final legs = (await api.getAll('/trip-legs', query: {'filter[trip]': tripId})).map(TripLeg.from).toList();
    Itinerary? itinerary;
    try {
      itinerary = Itinerary.from((await api.get('/itineraries/${trip.itineraryId}')).resource);
    } catch (_) {
      // Sin acceso al itinerario: se sigue sin el recorrido de referencia.
    }
    return TripContext(trip, stops, legs, itinerary);
  }

  /// Tramos (viaje de ida / de regreso) de los viajes que pueden estar en
  /// curso o haber terminado hace poco, para el estado de las tarjetas.
  /// Los demás viajes se quedan sin tramos (la tarjeta usa el atraso).
  static Future<Map<String, List<TripLeg>>> legsOf(ApiClient api, Iterable<Trip> trips) async {
    final now = DateTime.now();
    final candidates = trips
        .where((trip) => trip.status != TripStatus.cancelled && trip.departsAt.isBefore(now.add(const Duration(hours: 2))) && trip.returnsAt.isAfter(now.subtract(const Duration(hours: 24))))
        .take(10)
        .toList();
    final result = <String, List<TripLeg>>{};
    await Future.wait(candidates.map((trip) async {
      try {
        result[trip.id] = (await api.getAll('/trip-legs', query: {'filter[trip]': trip.id})).map(TripLeg.from).toList();
      } catch (_) {
        // Sin conexión: la tarjeta se muestra sin el estado del recorrido.
      }
    }));
    return result;
  }

  TripLeg? leg(String direction) {
    for (final leg in legs) {
      if (leg.direction == direction) return leg;
    }
    return null;
  }

  /// Recorrido de referencia del itinerario para ese sentido.
  String? referenceLegId(String direction) => direction == 'return' ? itinerary?.referenceReturnLegId : itinerary?.referenceOutboundLegId;

  TripLeg? get activeLeg {
    for (final leg in legs) {
      if (leg.isActive) return leg;
    }
    return null;
  }

  /// Paradas en el orden del trayecto: salida en orden, regreso al revés.
  List<Stop> orderedStops(String direction) => direction == 'return' ? stops.reversed.toList() : stops;

  Stop? stop(String? id) {
    for (final stop in stops) {
      if (stop.id == id) return stop;
    }
    return null;
  }

  /// Puede hacer [operation] sobre este viaje (su Entidad y su itinerario).
  bool can(Me me, String operation) => me.can(operation, entityId: trip.entityId ?? itinerary?.entityId, itineraryId: trip.itineraryId);

  /// Es el chofer del viaje (una de sus pertenencias).
  bool isDriver(Me me) => me.workerIds.contains(trip.driverId);

  /// Puede iniciar/finalizar el recorrido y registrar subidas de otros
  /// (docs/04-api.md: chofer del viaje, tracking.drive o trips.complete).
  bool canOperate(Me me) => isDriver(me) || can(me, Op.trackingDrive) || can(me, Op.tripsComplete) || can(me, Op.trackingScanBoarding);

  bool isPassenger(Me me) => me.isMemberOf(trip.itineraryId) && !isDriver(me);
}
