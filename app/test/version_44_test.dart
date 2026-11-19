import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitransporte/core/local_cache.dart';
import 'package:mitransporte/services/app_settings.dart';
import 'package:mitransporte/services/shared_location.dart';
import 'package:mitransporte/services/tracking/tracking_service.dart';
import 'package:mitransporte/services/tracking/worker_tracker.dart';
import 'package:mitransporte/ui/trips/trip_form_screen.dart';
import 'package:mitransporte/ui/widgets/busy.dart';

/// Versión 4.4.0 (docs/11 §11.65). La máquina de estados está en
/// worker_tracker_test.dart.
void main() {
  group('Frecuencias corta y larga', () {
    test('corta con la app abierta (dentro o fuera de la ventana) y cerrada dentro; larga solo cerrada fuera', () {
      const s = AppSettings({'frecuencia_corta': '10seg', 'frecuencia_larga': '20min'});
      expect(s.every(appOpen: true, inWindow: false), const Duration(seconds: 10), reason: 'el contador de la captura marcaba ~15 min');
      expect(s.every(appOpen: true, inWindow: true), const Duration(seconds: 10));
      expect(s.every(appOpen: false, inWindow: true), const Duration(seconds: 10));
      expect(s.every(appOpen: false, inWindow: false), const Duration(minutes: 20));
    });

    test('mínimos y valores guardados con los nombres viejos', () {
      expect(const AppSettings({'frecuencia_corta': '1seg'}).shortEvery, const Duration(seconds: 5));
      expect(const AppSettings({'frecuencia_larga': '5min'}).longEvery, const Duration(minutes: 15));
      expect(const AppSettings({'frecuencia_calculo': '20seg'}).shortEvery, const Duration(seconds: 20));
      expect(const AppSettings({}).longEvery, const Duration(minutes: 15));
    });
  });

  group('Cola con hora de captura', () {
    test('cambios del trabajador con la parada detectada; observaciones del vehículo solo si cambian', () {
      final at = DateTime(2026, 11, 16, 10, 40, 5);
      final worker = workerEvent('en_parada', '7', at, childIds: ['3']);
      // La hora de captura va en UTC (docs/11 §11.67).
      expect(worker, {'kind': 'worker', 'state': 'en_parada', 'stopId': 7, 'childIds': [3], 'capturedAt': at.toUtc().toIso8601String()});
      expect(workerEvent('no_viajare', null, at).containsKey('stopId'), isFalse);
      final a = vehicleEvent(const TrackerStep(vehicleState: 'en_movimiento', nextStopIndex: 2, atStop: false), at);
      final b = vehicleEvent(const TrackerStep(vehicleState: 'en_movimiento', nextStopIndex: 2, atStop: false), at.add(const Duration(seconds: 10)));
      final c = vehicleEvent(const TrackerStep(vehicleState: 'detenido', nextStopIndex: 2, atStop: true), at.add(const Duration(seconds: 20)));
      expect(sameObservation(a, b), isTrue);
      expect(sameObservation(b, c), isFalse);
    });

    test('sin conexión se guardan todos los cambios del trabajador y las últimas observaciones', () {
      final at = DateTime(2026, 11, 16);
      final queue = [
        workerEvent('en_parada', '1', at),
        for (var i = 0; i < 5; i++) {'kind': 'vehicle', 'nextStopIndex': i, 'capturedAt': '$i'},
        workerEvent('viajando', '1', at),
      ];
      final trimmed = trimQueue(queue, maxVehicle: 2);
      expect(trimmed.where((e) => e['kind'] == 'worker'), hasLength(2));
      expect([for (final e in trimmed) if (e['kind'] == 'vehicle') e['nextStopIndex']], [3, 4]);
    });

    test('lo guardado del viaje para el cálculo: estados de las paradas y vehículo', () {
      final info = tripInfoFrom({'status': 'en_ejecucion', 'states': {'0': 'recogida', '1': 'volada'}, 'left': [0, 1], 'next': 2, 'vehicle': 'en_movimiento', 'sensors': 2});
      expect(info.stopStates, {0: 'recogida', 1: 'volada'});
      expect(info.left, {0, 1});
      expect(info.waiting(2), isTrue);
      expect(info.nextStopIndex, 2);
      expect(info.vehicleState, 'en_movimiento');
      expect(info.sensors, 2);
      expect(tripInfoFrom(const {}).status, 'planificado');
    });
  });

  group('Registro de cambios en la caché', () {
    final body = {
      'data': [
        {'type': 'stops', 'id': '1', 'attributes': {'landmark': 'La llama'}},
        {'type': 'stops', 'id': '2', 'attributes': {'landmark': 'Banco'}},
      ],
      'included': [
        {'type': 'itineraries', 'id': '9', 'attributes': {'name': 'XX'}},
      ],
    };

    test('cambia los registros, quita los borrados y marca la lista de un tipo con cambios', () {
      final changes = CacheChanges.fromJson({
        'data': [
          {'type': 'stops', 'id': '1', 'attributes': {'landmark': 'Coppelia'}},
          {'type': 'itineraries', 'id': '9', 'attributes': {'name': 'XX Aniversario'}},
        ],
        'deleted': {'stops': ['2']},
        'changed': ['stops'],
      });
      final (patched, stale) = changes.applyTo('/stops?filter[itinerary]=9', body);
      final data = patched!['data'] as List;
      expect(data, hasLength(1));
      expect((data.first as Map)['attributes'], {'landmark': 'Coppelia'});
      expect(((patched['included'] as List).first as Map)['attributes'], {'name': 'XX Aniversario'});
      expect(stale, isTrue);
    });

    test('un registro borrado se quita; lo que no cambió queda igual', () {
      final single = {'data': {'type': 'stops', 'id': '2', 'attributes': {}}};
      final gone = CacheChanges.fromJson({'deleted': {'stops': ['2']}});
      expect(gone.applyTo('/stops/2', single).$1, isNull);
      final other = CacheChanges.fromJson({'data': [{'type': 'trips', 'id': '5', 'attributes': {}}], 'changed': ['trips']});
      final (same, stale) = other.applyTo('/stops?filter[itinerary]=9', body);
      expect(identical(same, body), isTrue);
      expect(stale, isFalse);
    });

    test('tipo de cada consulta (lo que cubre el registro)', () {
      expect(LocalCache.typeOf('/stops?filter[itinerary]=9'), 'stops');
      expect(LocalCache.typeOf('/trips/4'), 'trips');
      expect(LocalCache.typeOf('/trips/4/live'), isNull);
      expect(LocalCache.typeOf('/management-summary'), isNull);
      expect(LocalCache.typeOf('/me'), isNull);
    });
  });

  group('Formularios', () {
    test('«Crear Viaje»: Ida hoy 05:00 p. m. y Regreso mañana 06:00 a. m.', () {
      final d = planDefaults(DateTime(2026, 11, 16, 9, 30));
      expect(d.outboundDate, DateTime(2026, 11, 16));
      expect(d.outboundTime, const TimeOfDay(hour: 17, minute: 0));
      expect(d.returnDate, DateTime(2026, 11, 17));
      expect(d.returnTime, const TimeOfDay(hour: 6, minute: 0));
    });

    test('«Pegar ubicación»: lat, lng y enlaces de Google Maps, OsmAnd, OpenStreetMap y geo:', () {
      GeoPoint? p(String s) => parseLocation(s);
      expect(p('23.1136, -82.3666')!.latitude, closeTo(23.1136, 1e-6));
      expect(p('https://www.google.com/maps/@23.1136,-82.3666,17z')!.longitude, closeTo(-82.3666, 1e-6));
      expect(p('https://osmand.net/map?pin=23.1136,-82.3666#17/23.1136/-82.3666')!.latitude, closeTo(23.1136, 1e-6));
      expect(p('https://www.openstreetmap.org/?mlat=23.1136&mlon=-82.3666#map=17/23.1136/-82.3666')!.longitude, closeTo(-82.3666, 1e-6));
      expect(p('geo:23.1136,-82.3666')!.latitude, closeTo(23.1136, 1e-6));
      expect(p('hola mundo'), isNull);
    });

    testWidgets('spinner: texto arriba, círculo en el color de acento y «✕ Cancelar» gris debajo', (tester) async {
      var cancelled = false;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: BusyPanel(text: 'Consultando Paradas', onCancel: () => cancelled = true))));
      final text = tester.getRect(find.text('Consultando Paradas'));
      final circle = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      final button = tester.getRect(find.text('Cancelar'));
      expect(circle.color, const Color(0xFFFFA500));
      expect(text.top < tester.getRect(find.byType(CircularProgressIndicator)).top, isTrue);
      expect(button.top > text.top, isTrue);
      expect(find.byIcon(Icons.close), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      expect(cancelled, isTrue);
    });
  });
}
