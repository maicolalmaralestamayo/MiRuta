import '../../core/api_client.dart';
import '../../models/models.dart';
import '../../services/sync.dart';

/// Un viaje con las paradas de su itinerario (en orden) y sus trayectos.
class TripContext {
  final Trip trip;
  final List<Stop> stops;
  final List<TripLeg> legs;

  TripContext(this.trip, this.stops, this.legs);

  static Future<TripContext> load(ApiClient api, String tripId) async {
    final trip = Trip.from((await api.get('/trips/$tripId', query: {'include': SyncService.tripInclude})).resource);
    final links = await api.getAll('/itinerary-stops', query: {'filter[itinerary]': trip.itineraryId, 'include': 'stop', 'sort': 'position'});
    final stops = links.map(ItineraryStop.from).map((link) => link.stop!).toList();
    final legs = (await api.getAll('/trip-legs', query: {'filter[trip]': tripId})).map(TripLeg.from).toList();
    return TripContext(trip, stops, legs);
  }

  TripLeg? leg(String direction) {
    for (final leg in legs) {
      if (leg.direction == direction) return leg;
    }
    return null;
  }

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

  /// Puede iniciar/finalizar el recorrido y registrar subidas de otros.
  bool canOperate(Worker me) => me.managesTransport || me.roles.driverId == trip.driverId || me.isChiefOf(trip.itineraryId);

  bool isPassenger(Worker me) => me.itineraryId == trip.itineraryId && me.roles.driverId != trip.driverId;
}
